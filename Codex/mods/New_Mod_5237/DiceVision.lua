--[[
    DiceVision Integration for MCDM Codex

    Integrates physical dice rolling via DiceVision with the Codex VTT.

    Modes:
    - chat: Physical dice rolls from DiceVision appear in Codex chat
    - replace: Physical dice replace virtual dice (intercepts dmhub.Roll)
              User sees the roll dialog, configures modifiers, clicks "Roll Dice",
              then waits for physical dice. Results fire game callbacks properly.

    Commands:
    - /dv connect <code>  - Connect to DiceVision session
    - /dv disconnect      - Disconnect from session
    - /dv status          - Show connection status
    - /dv mode <mode>     - Set mode: "off", "chat", or "replace"
    - /dv test            - Test API connection
]]

local mod = dmhub.GetModLoading()

-- ============================================================================
-- Forward Declarations
-- ============================================================================

local stopPolling
local removeRollInterceptor

-- ============================================================================
-- Configuration & State
-- ============================================================================

local DiceVision = {
    -- Connection settings
    baseUrl = "https://dicevision.dirtyowlbear.com",  -- Production
    -- baseUrl = "http://localhost:8000",  -- Local development
    sessionCode = nil,
    connected = false,

    -- Mode: "off", "chat" (Level 1), or "replace" (Level 2)
    mode = "off",

    -- Polling state
    isPolling = false,
    pollIntervalMs = 500,
    lastPollTime = 0,

    -- Level 2: Pending roll state (when using RollDialog hook)
    pendingRoll = nil,  -- Stores the roll context when waiting for physical dice
    waitingForRoll = false,
    rollTimeout = 30000,  -- 30 second timeout
    rollStartTime = 0,

    -- Request ID for polling (prevents race condition with continuous mode)
    currentRequestId = nil,
}

-- Default dice rules (applied on load and after "rules clear")
local DEFAULT_RULES = {
    valueMappings = {
        ["d10"] = {[0] = 10},  -- Standard d10: 0 reads as 10
    },
    diceSelection = nil,
}

-- Dice rule configuration (initialized from defaults)
DiceVision.rules = {
    -- Value mappings: {dieType = {fromValue = toValue}}
    -- Example: {["d10"] = {[1] = 0}} makes 1s count as 0
    valueMappings = {},

    -- Dice selection override (nil = auto-detect from roll context)
    -- Example: {keep = "highest", count = 2}
    diceSelection = nil,

    -- Clamp values outside 0-10 range to 1 (for misread dice)
    clampOutOfRange = false,
}

-- Apply default rules on load
for dieType, mappings in pairs(DEFAULT_RULES.valueMappings) do
    DiceVision.rules.valueMappings[dieType] = {}
    for from, to in pairs(mappings) do
        DiceVision.rules.valueMappings[dieType][from] = to
    end
end

-- ============================================================================
-- Utility Functions
-- ============================================================================

local function generateRequestId()
    -- Generate unique ID (timestamp + random suffix) for tracking poll requests
    -- This prevents the race condition where continuous mode re-triggers after a roll is captured
    return tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
end

local function formatDice(dice)
    local parts = {}
    for _, die in ipairs(dice) do
        table.insert(parts, string.format("%s:%d", die.type, die.value))
    end
    return table.concat(parts, ", ")
end

local function formatRollForChat(rollData)
    local diceStr = formatDice(rollData.dice)
    return string.format("[DiceVision] %s = %d", diceStr, rollData.total)
end

local function extractModifierFromRoll(rollStr)
    -- Extract modifier from roll string (e.g., "2d10+5" -> 5, "2d10 + 2" -> 2, "2d10-2" -> -2)
    if not rollStr then return 0 end

    -- Strip edge/bane suffix first: "2d10+2 1 edge" or "2d10+2 2 edges" -> "2d10+2"
    local strippedStr = rollStr:gsub("%s+%d+%s+edges?%s*$", "")
    strippedStr = strippedStr:gsub("%s+%d+%s+banes?%s*$", "")

    -- Now extract modifier from end: "2d10+2" -> +2
    local sign, num = strippedStr:match("([%+%-])%s*(%d+)%s*$")
    if sign and num then
        local modifier = tonumber(num) or 0
        if sign == "-" then
            modifier = -modifier
        end
        return modifier
    end
    return 0
end

local function getDiceFaces(dieType)
    -- Extract number of faces from die type string (e.g., "d10" -> 10)
    local faces = dieType:match("d(%d+)")
    return tonumber(faces) or 10
end

local function calculateTier(total)
    -- Draw Steel tier thresholds
    if total >= 17 then
        return 3
    elseif total >= 12 then
        return 2
    else
        return 1
    end
end

-- Split combined m_boons (-2 to +2) into separate edge/bane counts
local function SplitBoons(combinedBoons)
    combinedBoons = combinedBoons or 0
    if combinedBoons >= 0 then
        return combinedBoons, 0  -- edges, banes
    else
        return 0, -combinedBoons  -- edges, banes
    end
end

-- Calculate roll modifier from edges/banes (NOT tier shift)
-- Returns 0 for double edge/bane cases (tier shift handled by DiceResultToTier)
local function GetRollModFromEdgesAndBanes(edges, banes)
    edges = edges or 0
    banes = banes or 0

    local bonus = 0
    if banes == 0 then
        if edges == 1 then
            bonus = 2
        end
        -- 2+ edges: bonus = 0, tier shift happens in DiceResultToTier
    elseif edges == 0 then
        if banes == 1 then
            bonus = -2
        end
        -- 2+ banes: bonus = 0, tier shift happens in DiceResultToTier
    elseif edges > banes then
        bonus = 2
    elseif edges < banes then
        bonus = -2
    else
        bonus = 0
    end

    return bonus
end

-- Calculate tier with edge/bane effects (for double edge/bane tier shifts)
local function CalculateTierWithEdges(total, edges, banes)
    local tier = 1
    if total >= 17 then
        tier = 3
    elseif total >= 12 then
        tier = 2
    end

    -- Double edge/bane tier shifts (only when one side is 0)
    if edges >= 2 and banes == 0 then
        tier = tier + 1
    elseif banes >= 2 and edges == 0 then
        tier = tier - 1
    end

    -- Clamp to valid range
    if tier > 3 then tier = 3 end
    if tier < 1 then tier = 1 end

    return tier
end

-- Parse edge/bane from roll string (e.g., "2d10 1 edge" or "2d10 2 bane")
-- Returns edges, banes counts
-- This is a FALLBACK for when context.boons is 0 due to DSRollDialog's boonBar prepare reset
local function ParseBoonsFromRollString(rollString)
    if not rollString then return 0, 0 end

    local edges = 0
    local banes = 0

    -- Look for "N edge" pattern (e.g., "2d10 1 edge" -> 1)
    local edgeMatch = string.match(rollString, "(%d+)%s+edge")
    if edgeMatch then
        edges = tonumber(edgeMatch) or 0
    end

    -- Look for "N bane" pattern (e.g., "2d10 2 bane" -> 2)
    local baneMatch = string.match(rollString, "(%d+)%s+bane")
    if baneMatch then
        banes = tonumber(baneMatch) or 0
    end

    return edges, banes
end

local function getTierRanges()
    -- Returns the tier threshold ranges for display
    return {
        { tier = 1, label = "1-11", min = nil, max = 11 },
        { tier = 2, label = "12-16", min = 12, max = 16 },
        { tier = 3, label = "17+", min = 17, max = nil },
    }
end

-- ============================================================================
-- Dice Rule Processing
-- ============================================================================

-- Apply value mappings to dice
local function applyValueMappings(dice, mappings)
    if not mappings or next(mappings) == nil then
        return dice
    end

    local result = {}
    for i, die in ipairs(dice) do
        local dieType = die.type
        local typeMapping = mappings[dieType] or mappings["*"] or {}
        local newValue = typeMapping[die.value] or die.value

        result[i] = {
            type = die.type,
            value = newValue,
            originalValue = (newValue ~= die.value) and die.value or nil,
        }
    end
    return result
end

-- Clamp values outside 0-10 range to 1 (for misread dice)
local function clampOutOfRangeValues(dice, isEnabled)
    if not isEnabled then
        return dice
    end

    local result = {}
    for i, die in ipairs(dice) do
        local value = die.value
        local clamped = value

        -- Values outside 0-10 range become 1
        if value < 0 or value > 10 then
            clamped = 1
            print(string.format("[DiceVision] Clamped %s value %d -> 1 (out of 0-10 range)", die.type, value))
        end

        result[i] = {
            type = die.type,
            value = clamped,
            originalValue = (clamped ~= value) and value or die.originalValue,
        }
    end
    return result
end

-- Apply dice selection (keep highest/lowest N)
local function applyDiceSelection(dice, selection)
    if not selection or not selection.count then
        return dice
    end

    -- Copy and sort dice
    local sorted = {}
    for i, die in ipairs(dice) do
        sorted[i] = {die = die, index = i}
    end

    if selection.keep == "highest" then
        table.sort(sorted, function(a, b) return a.die.value > b.die.value end)
    elseif selection.keep == "lowest" then
        table.sort(sorted, function(a, b) return a.die.value < b.die.value end)
    end

    -- Keep only the specified count
    local result = {}
    local count = math.min(selection.count, #sorted)
    for i = 1, count do
        result[i] = sorted[i].die
    end

    return result, sorted  -- Return sorted for display purposes
end

-- Detect dice selection from roll context (numKeep)
local function detectDiceSelection(pendingRoll)
    if not pendingRoll or not pendingRoll.originalRoll then
        return nil
    end

    -- Parse the roll string to check for numKeep
    local creature = pendingRoll.rollArgs and pendingRoll.rollArgs.creature
    local rollInfo = dmhub.ParseRoll(pendingRoll.originalRoll, creature)

    if rollInfo and rollInfo.categories then
        for catName, category in pairs(rollInfo.categories) do
            if category.groups then
                for _, group in ipairs(category.groups) do
                    if group.numKeep and group.numKeep > 0 and group.numDice and group.numDice > group.numKeep then
                        return {
                            keep = "highest",  -- Codex convention: numKeep means keep highest
                            count = group.numKeep,
                            total = group.numDice,
                        }
                    end
                end
            end
        end
    end

    return nil
end

-- Get effective rules for a roll (merges config with auto-detection)
local function getEffectiveRules(pendingRoll)
    local rules = {
        valueMappings = DiceVision.rules.valueMappings or {},
        diceSelection = DiceVision.rules.diceSelection,  -- Manual override
    }

    -- Auto-detect dice selection from roll context if not manually set
    if not rules.diceSelection then
        rules.diceSelection = detectDiceSelection(pendingRoll)
    end

    return rules
end

-- Main function to apply all dice rules
local function applyDiceRules(dice, pendingRoll)
    local rules = getEffectiveRules(pendingRoll)
    local processed = dice
    local droppedDice = nil

    -- 1. Apply out-of-range clamping first (before value mappings)
    processed = clampOutOfRangeValues(processed, DiceVision.rules.clampOutOfRange)

    -- 2. Apply value mappings (e.g., d10 0 -> 10)
    processed = applyValueMappings(processed, rules.valueMappings)

    -- 3. Apply dice selection (keep N)
    if rules.diceSelection then
        local sorted
        processed, sorted = applyDiceSelection(processed, rules.diceSelection)

        -- Track which dice were dropped for visual display
        if sorted and #sorted > #processed then
            droppedDice = {}
            for i = #processed + 1, #sorted do
                droppedDice[#droppedDice + 1] = sorted[i].die
            end
        end

        print(string.format("[DiceVision] Dice selection: keep %s %d of %d",
            rules.diceSelection.keep, rules.diceSelection.count, #dice))
    end

    return processed, droppedDice
end

-- ============================================================================
-- Custom Chat Message for Physical Dice Rolls
-- ============================================================================

DiceVisionRollMessage = RegisterGameType("DiceVisionRollMessage")

DiceVisionRollMessage.description = ""
DiceVisionRollMessage.dice = {}
DiceVisionRollMessage.modifier = 0
DiceVisionRollMessage.total = 0
DiceVisionRollMessage.tier = 1
DiceVisionRollMessage.tokenid = nil  -- Store the token ID for displaying character portrait

function DiceVisionRollMessage.CreateDiePanel(faces, value)
    -- Create a dice icon panel with the rolled value overlaid
    -- Pattern matches gui.UserDice from Gui.lua
    local diceStyle = dmhub.GetDiceStyling(
        dmhub.GetSettingValue("diceequipped"),
        dmhub.GetSettingValue("playercolor")
    )

    -- Outer panel with filled dice as background
    return gui.Panel{
        width = 40,
        height = 40,
        halign = "center",
        valign = "center",
        bgimage = string.format("ui-icons/d%d-filled.png", faces),
        bgcolor = diceStyle.bgcolor or "#2d5a2d",
        saturation = 0.7,
        brightness = 0.4,

        -- Dice outline/trim with value label nested inside
        gui.Panel{
            interactable = false,
            width = "100%",
            height = "100%",
            bgimage = string.format("ui-icons/d%d.png", faces),
            bgcolor = diceStyle.trimcolor or "#4a9a4a",

            -- Value label nested inside the outline panel
            gui.Label{
                interactable = false,
                width = "100%",
                height = "100%",
                halign = "center",
                valign = "center",
                textAlignment = "center",
                fontSize = 16,
                bold = true,
                color = diceStyle.color or "#ffffff",
                text = tostring(value),
            },
        },
    }
end

function DiceVisionRollMessage.GetTierLabel(tier)
    -- Return the tier range label matching native format
    if tier == 1 then
        return "11 or lower"
    elseif tier == 2 then
        return "12-16"
    else
        return "17 or higher"
    end
end

function DiceVisionRollMessage:GetToken()
    -- Get the token by ID (use try_get for backwards compatibility with old messages)
    local tokenid = self:try_get("tokenid")
    if tokenid then
        return dmhub.GetCharacterById(tokenid)
    end
    return nil
end

function DiceVisionRollMessage.Render(self, message)
    -- Get dice data safely
    local dice = self:try_get("dice") or {}
    local modifier = self:try_get("modifier") or 0
    local total = self:try_get("total") or 0
    local tier = self:try_get("tier") or 1
    local description = self:try_get("description") or "Roll"

    -- Build the dice icons
    local dicePanels = {}
    for i, die in ipairs(dice) do
        local faces = die.faces or 10
        local value = die.value or 0
        dicePanels[#dicePanels+1] = DiceVisionRollMessage.CreateDiePanel(faces, value)
    end

    -- Add modifier display if non-zero
    if modifier ~= 0 then
        local modSign = modifier > 0 and "+" or ""
        dicePanels[#dicePanels+1] = gui.Label{
            width = "auto",
            height = 40,
            halign = "center",
            valign = "center",
            textAlignment = "center",
            fontSize = 20,
            bold = true,
            color = "#cccccc",
            text = string.format("%s%d", modSign, modifier),
            lmargin = 4,
        }
    end

    -- Dice row panel
    local diceRowPanel = gui.Panel{
        flow = "horizontal",
        halign = "left",
        valign = "center",
        height = "auto",
        width = "auto",
    }
    -- Add dice panels as direct children
    for _, panel in ipairs(dicePanels) do
        diceRowPanel:AddChild(panel)
    end

    -- Large total on the right
    local totalLabel = gui.Label{
        width = 60,
        height = 50,
        halign = "right",
        valign = "center",
        textAlignment = "center",
        fontSize = 36,
        bold = true,
        color = "#ffffff",
        text = tostring(total),
    }

    -- Tier result label (matching native format: "11 or lower    tier 1 result")
    local tierRangeLabel = DiceVisionRollMessage.GetTierLabel(tier)
    local tierLabel = gui.Label{
        width = "100%",
        height = "auto",
        fontSize = 14,
        color = "#888888",
        tmargin = 4,
        text = string.format("%s    tier %d result", tierRangeLabel, tier),
    }

    -- Build the complete panel
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        hpad = 8,
        vpad = 8,

        -- Description header
        gui.Label{
            width = "100%",
            height = "auto",
            fontSize = 16,
            bold = true,
            color = "#ffffff",
            text = description,
        },

        -- Dice row with total
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            valign = "center",

            diceRowPanel,
            totalLabel,
        },

        -- Tier result
        tierLabel,
    }
end

-- ============================================================================
-- API Communication
-- ============================================================================

local function validateSession(callback)
    if not DiceVision.sessionCode then
        callback(false, "No session code configured")
        return
    end

    net.Get{
        url = DiceVision.baseUrl .. "/api/codex/session/" .. DiceVision.sessionCode,
        success = function(data)
            if data and data.active then
                DiceVision.connected = true
                callback(true, data)
            else
                DiceVision.connected = false
                callback(false, "Session not found or expired")
            end
        end,
        error = function(err)
            DiceVision.connected = false
            callback(false, "Connection error: " .. tostring(err))
        end,
    }
end

local function handleSessionExpired()
    chat.Send("[DiceVision] Session expired. Use /dv connect <code> to reconnect.")
    stopPolling()
    removeRollInterceptor()
    DiceVision.connected = false
    DiceVision.mode = "off"
    DiceVision.sessionCode = nil
    -- Note: removeRollInterceptor already clears pendingRoll and waitingForRoll
end

local function pollForRolls(callback)
    if not DiceVision.connected or not DiceVision.sessionCode then
        return
    end

    -- Use adaptive polling: "waiting" mode when actively waiting for a roll
    local pollMode = DiceVision.waitingForRoll and "waiting" or "background"

    local url = string.format(
        "%s/api/codex/session/%s/rolls?acknowledge=true&limit=10&mode=%s",
        DiceVision.baseUrl,
        DiceVision.sessionCode,
        pollMode
    )

    -- Include request_id when in waiting mode to prevent race condition
    -- The backend tracks fulfilled request IDs and won't re-trigger waiting for them
    if pollMode == "waiting" and DiceVision.currentRequestId then
        url = url .. "&request_id=" .. DiceVision.currentRequestId
    end

    net.Get{
        url = url,
        success = function(data)
            if data then
                local rollCount = (data.rolls and #data.rolls) or 0
                if rollCount > 0 then
                    callback(data.rolls)
                end
            end

            -- Update poll interval if server suggests different
            if data and data.poll_interval_ms then
                DiceVision.pollIntervalMs = data.poll_interval_ms
            end
        end,
        error = function(err, statusCode)

            -- Handle session expired (404)
            if statusCode == 404 or (type(err) == "string" and err:find("404")) then
                handleSessionExpired()
            end
        end,
    }
end

-- ============================================================================
-- Level 1: Chat Integration
-- ============================================================================

local function postRollToChat(rollData)
    -- Apply dice rules (value mappings, keep highest/lowest)
    -- Note: No pendingRoll context, so only manual rules apply (no auto-detect)
    local processedDice, droppedDice = applyDiceRules(rollData.dice, nil)

    -- Convert dice data from API format to message format
    -- API: {type: "d10", value: 7} -> Message: {faces: 10, value: 7}
    local diceForMessage = {}
    local diceSum = 0
    for _, die in ipairs(processedDice) do
        local faces = getDiceFaces(die.type)
        diceForMessage[#diceForMessage + 1] = {
            faces = faces,
            value = die.value,
            originalValue = die.originalValue,
        }
        diceSum = diceSum + die.value
    end

    -- Log dropped dice if any
    if droppedDice and #droppedDice > 0 then
        local droppedValues = {}
        for _, die in ipairs(droppedDice) do
            droppedValues[#droppedValues + 1] = tostring(die.value)
        end
        print("[DiceVision] Dropped dice: " .. table.concat(droppedValues, ", "))
    end

    -- Use dice sum (NOT rollData.total which is unprocessed)
    local total = diceSum

    -- Calculate tier from total
    local tier = calculateTier(total)

    -- Create and send the custom chat message
    local message = DiceVisionRollMessage.new{
        description = "Physical Dice Roll",
        dice = diceForMessage,
        modifier = 0,  -- No modifier in chat-only mode
        total = total,
        tier = tier,
    }

    chat.SendCustom(message)

    print(string.format("DBG: DiceVision roll posted to chat: total=%d, tier=%d", total, tier))
end

-- ============================================================================
-- Level 2: Dice Replacement
-- ============================================================================

local function showWaitingDialog()
    -- TODO: Show a visual indicator that we're waiting for physical dice
    -- For now, just post to chat
    chat.Send("[DiceVision] Waiting for physical dice roll...")
end

local function hideWaitingDialog()
    -- TODO: Hide the waiting indicator
end

-- Helper function to post roll result to chat
local function postDiceVisionRollToChat(rollData, rollInfo, pendingRoll)
    -- Convert dice data for chat message display
    -- API: {type: "d10", value: 7} -> Message: {faces: 10, value: 7}
    local diceForMessage = {}
    for _, die in ipairs(rollData.dice) do
        local faces = getDiceFaces(die.type)
        diceForMessage[#diceForMessage + 1] = {
            faces = faces,
            value = die.value
        }
    end

    -- Get token ID for chat message
    local tokenid = pendingRoll.tokenid
    if not tokenid and pendingRoll.creature then
        tokenid = dmhub.LookupTokenId(pendingRoll.creature)
    end

    -- Create and send the custom chat message
    local modifier = extractModifierFromRoll(pendingRoll.roll)
    local message = DiceVisionRollMessage.new{
        description = pendingRoll.description or "Roll",
        dice = diceForMessage,
        modifier = modifier,
        total = rollInfo.total,
        tier = rollInfo.tiers,
        tokenid = tokenid,
    }

    chat.SendCustom(message)
end

local function handlePendingRoll(rollData)
    if not DiceVision.pendingRoll then
        return false
    end

    local pendingRoll = DiceVision.pendingRoll
    DiceVision.pendingRoll = nil
    DiceVision.waitingForRoll = false
    -- Generate new request ID for next await cycle (old one is now marked as fulfilled on backend)
    DiceVision.currentRequestId = generateRequestId()
    hideWaitingDialog()

    -- Calculate values from physical dice
    local modifier = extractModifierFromRoll(pendingRoll.originalRoll)
    local diceSum = 0

    -- Apply dice rules (value mappings, keep highest/lowest)
    local processedDice, droppedDice = applyDiceRules(rollData.dice, pendingRoll)

    -- Build dice info for visual display
    local diceForMessage = {}
    for i, die in ipairs(processedDice) do
        local faces = getDiceFaces(die.type)
        diceSum = diceSum + die.value
        diceForMessage[i] = {
            faces = faces,
            value = die.value,
            originalValue = die.originalValue,  -- For showing remapped values
        }
    end

    -- Log dropped dice if any
    if droppedDice and #droppedDice > 0 then
        local droppedValues = {}
        for _, die in ipairs(droppedDice) do
            droppedValues[#droppedValues + 1] = tostring(die.value)
        end
        print("[DiceVision] Dropped dice: " .. table.concat(droppedValues, ", "))
    end

    -- Get edge/bane counts (stored separately in hook)
    local edges = pendingRoll.edges or 0
    local banes = pendingRoll.banes or 0

    -- Calculate roll modifier from edges/banes
    -- Single edge/bane: ±2 modifier
    -- Double edge/bane: 0 modifier (tier shift happens via callback injection)
    local edgeBaneMod = GetRollModFromEdgesAndBanes(edges, banes)

    -- Check if this is a non-targeted roll (no multitargets)
    local isNonTargeted = not pendingRoll.multitargets or #pendingRoll.multitargets == 0

    -- Base total without edge/bane modifier (used for ApplyBoons approach)
    local baseTotal = diceSum + modifier

    -- Final total with edge/bane modifier (used for display and targeted rolls)
    local finalTotal = baseTotal + edgeBaneMod

    -- Calculate tier for visual display (from final total)
    local tier = calculateTier(finalTotal)

    -- Get the stored rollArgs and modify the roll to be deterministic
    local rollArgs = pendingRoll.rollArgs
    if not rollArgs then
        chat.Send("[DiceVision] Error: Roll context not available. Try again.")
        return false
    end

    -- Get token ID for the visual message
    local tokenid = rollArgs.tokenid
    if not tokenid and rollArgs.creature then
        tokenid = dmhub.LookupTokenId(rollArgs.creature)
    end

    -- Create visual dice display message (sent in complete callback to ensure correct ordering)
    local visualMessage = DiceVisionRollMessage.new{
        description = pendingRoll.description or "Physical Dice",
        dice = diceForMessage,
        modifier = modifier,
        total = finalTotal,
        tier = tier,
        tokenid = tokenid,
    }
    -- Set the deterministic roll value
    rollArgs.instant = true  -- No dice animation needed since we're using a fixed total

    if isNonTargeted then
        -- NON-TARGETED ROLL: Use GameSystem.ApplyBoons to embed boons in the roll string
        -- This mirrors how DSRollDialog handles boons for non-targeted rolls
        -- The engine will read boons from the parsed roll string
        local boonsValue = edges - banes  -- Combined: -2 to +2
        print("[DiceVision] Non-targeted roll detected. baseTotal:", baseTotal, "boonsValue:", boonsValue)
        if boonsValue ~= 0 and GameSystem and GameSystem.ApplyBoons then
            local rollWithBoons = GameSystem.ApplyBoons(tostring(baseTotal), boonsValue)
            print("[DiceVision] GameSystem.ApplyBoons('" .. tostring(baseTotal) .. "', " .. boonsValue .. ") returned: '" .. tostring(rollWithBoons) .. "'")
            rollArgs.roll = rollWithBoons
        else
            print("[DiceVision] No boons to apply or GameSystem.ApplyBoons not available, using finalTotal:", finalTotal)
            rollArgs.roll = tostring(finalTotal)
        end
        -- Don't set rollArgs.boons/banes or synthetic multitargets - let engine handle from roll string
    else
        -- TARGETED ROLL: Pass baseTotal, let Codex apply edge/bane modifier
        -- Codex's BoonsAndBanesToMod() will add the +2/-2 based on boons/banes
        rollArgs.roll = tostring(baseTotal)

        -- Set boons/banes on rollArgs (may be used by C# engine)
        rollArgs.boons = edges
        rollArgs.banes = banes

        -- Update multitargets for UI indicators
        -- NOTE: multitargets.boons/banes are ADDITIONAL to base roll, not total
        -- Since edges/banes are already on rollArgs.boons/banes, set to 0 here
        rollArgs.properties = rollArgs.properties or {}
        rollArgs.properties.multitargets = pendingRoll.multitargets
        rollArgs.properties.multitargets[1].boons = 0
        rollArgs.properties.multitargets[1].banes = 0
    end

    -- Override tier via complete callback for double edge/bane tier shifts
    local originalComplete = rollArgs.complete
    rollArgs.complete = function(rollInfo)
        -- Only override for double edge/bane tier shifts
        if (edges >= 2 and banes == 0) or (banes >= 2 and edges == 0) then
            local calculatedTier = CalculateTierWithEdges(finalTotal, edges, banes)
            local props = rollInfo.properties or {}

            -- FIX: Use try_get instead of direct field access
            if not props:try_get("overrideTier") then
                props.overrideTier = calculatedTier
                rollInfo:UploadProperties(props)
            end
        end

        -- Send visual dice display AFTER roll is processed (so character token appears first)
        chat.SendCustom(visualMessage)

        if originalComplete then
            originalComplete(rollInfo)
        end
    end

    -- Now call dmhub.Roll with multitargets injected and tier override callback
    dmhub.Roll(rollArgs)

    return true
end

local function checkRollTimeout()
    if DiceVision.waitingForRoll then
        local elapsed = (dmhub.Time() * 1000) - DiceVision.rollStartTime
        if elapsed > DiceVision.rollTimeout then
            -- Timeout - cancel the roll
            chat.Send("[DiceVision] Timeout waiting for physical dice. Roll cancelled - try again.")
            DiceVision.waitingForRoll = false
            DiceVision.pendingRoll = nil
            -- Generate new request ID for next await cycle
            DiceVision.currentRequestId = generateRequestId()
            hideWaitingDialog()
        end
    end
end

-- ============================================================================
-- RollDialog Hook (called from RollDialog.lua before dmhub.Roll)
-- ============================================================================

-- Global function that DSRollDialog.lua calls before dmhub.Roll
-- Returns "intercept" to prevent dmhub.Roll from being called - we'll call it ourselves
-- with a deterministic total once physical dice arrive
RollDialog_BeforeRoll = function(context)
    -- Safety checks for graceful failure
    if not context then return nil end
    if not DiceVision then return nil end

    -- Only intercept if in replace mode and connected
    if DiceVision.mode ~= "replace" or not DiceVision.connected then
        return nil  -- Let normal roll proceed
    end

    -- If already waiting, don't intercept again
    if DiceVision.waitingForRoll then
        return nil
    end

    -- DEBUG: Trace boons and roll values through the hook
    print("[DiceVision] Hook received context.boons:", context.boons)
    print("[DiceVision] Hook received context.roll:", context.roll)

    -- Split combined boons into separate edges/banes
    local edges, banes = SplitBoons(context.boons)
    print("[DiceVision] After SplitBoons - edges:", edges, "banes:", banes)

    -- FALLBACK: If context.boons is 0, try parsing from roll string
    -- This handles the case where boonBar's prepare function reset m_boons to 0
    -- but the boons are still embedded in the roll string via GameSystem.ApplyBoons
    if edges == 0 and banes == 0 and context.roll then
        edges, banes = ParseBoonsFromRollString(context.roll)
        if edges > 0 or banes > 0 then
            print("[DiceVision] Parsed boons from roll string - edges:", edges, "banes:", banes)
        end
    end

    -- Store the roll context including the full rollArgs
    -- We'll modify rollArgs.roll and call dmhub.Roll when physical dice arrive
    DiceVision.pendingRoll = {
        rollArgs = context.rollArgs,  -- The full rollArgs object
        originalRoll = context.roll,   -- Store the original roll string for modifier extraction
        description = context.description,
        edges = edges,                 -- Edge count (0, 1, or 2)
        banes = banes,                 -- Bane count (0, 1, or 2)
        multitargets = context.multitargets,  -- Store for boons/banes injection
    }

    DiceVision.waitingForRoll = true
    DiceVision.rollStartTime = dmhub.Time() * 1000
    DiceVision.currentRequestId = generateRequestId()

    showWaitingDialog()
    chat.Send("[DiceVision] Waiting for physical dice...")

    return "intercept"  -- Tell DSRollDialog NOT to call dmhub.Roll - we'll do it
end

-- No-op functions for mode switching compatibility
local function installRollInterceptor()
    -- Hook is now in DSRollDialog.lua, no installation needed
end

removeRollInterceptor = function()
    -- Clear any pending state when switching modes
    DiceVision.pendingRoll = nil
    DiceVision.waitingForRoll = false
    DiceVision.currentRequestId = nil
end

-- ============================================================================
-- Polling Loop
-- ============================================================================

local function startPolling()
    if DiceVision.isPolling then
        return
    end

    DiceVision.isPolling = true

    -- Use a coroutine-style polling with scheduled callbacks
    local function poll()
        if not DiceVision.isPolling or not DiceVision.connected then
            return
        end

        -- Check for timeout on pending rolls
        checkRollTimeout()

        pollForRolls(function(rolls)
            for _, rollData in ipairs(rolls) do
                -- Level 2: Try to use for pending roll first
                local used = false
                if DiceVision.mode == "replace" and DiceVision.waitingForRoll then
                    used = handlePendingRoll(rollData)
                end

                -- Level 1: Post to chat (if not used by Level 2, or if in chat mode)
                if DiceVision.mode == "chat" or (DiceVision.mode == "replace" and not used) then
                    postRollToChat(rollData)
                end
            end
        end)

        -- Schedule next poll
        dmhub.Schedule(DiceVision.pollIntervalMs / 1000, poll)
    end

    -- Start the polling loop
    poll()
end

stopPolling = function()
    DiceVision.isPolling = false
end

-- ============================================================================
-- Commands
-- ============================================================================

Commands.dv = function(args)
    local parts = {}
    for part in string.gmatch(args, "%S+") do
        table.insert(parts, part)
    end

    local subcommand = parts[1] or "help"

    if subcommand == "connect" then
        local code = parts[2]
        if not code then
            chat.Send("[DiceVision] Usage: /dv connect <session_code>")
            return
        end

        DiceVision.sessionCode = code:upper()
        chat.Send("[DiceVision] Connecting to session " .. DiceVision.sessionCode .. "...")

        validateSession(function(success, result)
            if success then
                chat.Send("[DiceVision] Connected successfully!")
                if DiceVision.mode ~= "off" then
                    startPolling()
                end
            else
                chat.Send("[DiceVision] Connection failed: " .. tostring(result))
                DiceVision.sessionCode = nil
            end
        end)

    elseif subcommand == "disconnect" then
        stopPolling()
        removeRollInterceptor()
        DiceVision.sessionCode = nil
        DiceVision.connected = false
        DiceVision.mode = "off"
        chat.Send("[DiceVision] Disconnected")

    elseif subcommand == "status" then
        local status = string.format(
            "[DiceVision] Status:\n  Connected: %s\n  Session: %s\n  Mode: %s\n  Polling: %s",
            tostring(DiceVision.connected),
            DiceVision.sessionCode or "none",
            DiceVision.mode,
            tostring(DiceVision.isPolling)
        )
        chat.Send(status)

    elseif subcommand == "mode" then
        local newMode = parts[2]
        if not newMode or (newMode ~= "off" and newMode ~= "chat" and newMode ~= "replace") then
            chat.Send("[DiceVision] Usage: /dv mode <off|chat|replace>")
            chat.Send("[DiceVision] Current mode: " .. DiceVision.mode)
            return
        end

        local oldMode = DiceVision.mode
        DiceVision.mode = newMode

        -- Handle mode transitions
        if newMode == "off" then
            stopPolling()
            removeRollInterceptor()
        elseif newMode == "chat" then
            removeRollInterceptor()
            if DiceVision.connected then
                startPolling()
            end
        elseif newMode == "replace" then
            installRollInterceptor()
            if DiceVision.connected then
                startPolling()
            end
        end

        chat.Send("[DiceVision] Mode changed: " .. oldMode .. " -> " .. newMode)

    elseif subcommand == "test" then
        -- Test the API connection
        chat.Send("[DiceVision] Testing API connection...")
        net.Get{
            url = DiceVision.baseUrl,
            success = function(data)
                chat.Send("[DiceVision] API is reachable!")
            end,
            error = function(err)
                chat.Send("[DiceVision] API error: " .. tostring(err))
            end,
        }

    elseif subcommand == "rules" then
        local action = parts[2]

        if action == "show" then
            local msg = "[DiceVision] Current rules:\n"

            -- Show value mappings in detail
            if next(DiceVision.rules.valueMappings) then
                msg = msg .. "  Value mappings:\n"
                for dieType, mappings in pairs(DiceVision.rules.valueMappings) do
                    for from, to in pairs(mappings) do
                        msg = msg .. string.format("    %s: %d -> %d\n", dieType, from, to)
                    end
                end
            else
                msg = msg .. "  Value mappings: none\n"
            end

            -- Show dice selection
            msg = msg .. "  Dice selection: " .. (DiceVision.rules.diceSelection and
                string.format("keep %s %d", DiceVision.rules.diceSelection.keep, DiceVision.rules.diceSelection.count) or "auto-detect") .. "\n"

            -- Show clamping status
            msg = msg .. "  Out-of-range clamping: " .. (DiceVision.rules.clampOutOfRange and "enabled" or "disabled")
            chat.Send(msg)

        elseif action == "map" then
            -- /dv rules map d10 1 0  (map d10 value 1 to 0)
            local dieType = parts[3]
            local fromVal = tonumber(parts[4])
            local toVal = tonumber(parts[5])

            if dieType and fromVal and toVal then
                DiceVision.rules.valueMappings[dieType] = DiceVision.rules.valueMappings[dieType] or {}
                DiceVision.rules.valueMappings[dieType][fromVal] = toVal
                chat.Send(string.format("[DiceVision] Mapped %s: %d -> %d", dieType, fromVal, toVal))
            else
                chat.Send("[DiceVision] Usage: /dv rules map <dieType> <fromValue> <toValue>")
            end

        elseif action == "keep" then
            -- /dv rules keep highest 2
            local mode = parts[3]
            local count = tonumber(parts[4])

            if mode == "auto" or mode == "clear" then
                DiceVision.rules.diceSelection = nil
                chat.Send("[DiceVision] Dice selection: auto-detect from roll context")
            elseif mode and count then
                DiceVision.rules.diceSelection = {keep = mode, count = count}
                chat.Send(string.format("[DiceVision] Dice selection: keep %s %d", mode, count))
            else
                chat.Send("[DiceVision] Usage: /dv rules keep <highest|lowest|auto> [count]")
            end

        elseif action == "clamp" then
            local mode = parts[3]

            if mode == "on" then
                DiceVision.rules.clampOutOfRange = true
                chat.Send("[DiceVision] Out-of-range clamping enabled (values outside 0-10 -> 1)")
            elseif mode == "off" then
                DiceVision.rules.clampOutOfRange = false
                chat.Send("[DiceVision] Out-of-range clamping disabled")
            else
                local status = DiceVision.rules.clampOutOfRange and "enabled" or "disabled"
                chat.Send("[DiceVision] Out-of-range clamping: " .. status .. "\nUsage: /dv rules clamp <on|off>")
            end

        elseif action == "clear" then
            local clearAll = parts[3] == "all"

            if clearAll then
                -- Full clear - no rules at all
                DiceVision.rules = {valueMappings = {}, diceSelection = nil, clampOutOfRange = false}
                chat.Send("[DiceVision] All rules cleared (including defaults)")
            else
                -- Restore defaults
                DiceVision.rules = {valueMappings = {}, diceSelection = nil, clampOutOfRange = false}
                for dieType, mappings in pairs(DEFAULT_RULES.valueMappings) do
                    DiceVision.rules.valueMappings[dieType] = {}
                    for from, to in pairs(mappings) do
                        DiceVision.rules.valueMappings[dieType][from] = to
                    end
                end
                chat.Send("[DiceVision] Rules reset to defaults")
            end

        else
            chat.Send([[
[DiceVision] Rule commands:
  /dv rules show                    - Show current rules
  /dv rules map <die> <from> <to>   - Map die value (e.g., /dv rules map d10 0 10)
  /dv rules keep <mode> <count>     - Keep highest/lowest N dice
  /dv rules keep auto               - Auto-detect from roll context
  /dv rules clamp <on|off>          - Clamp values outside 0-10 to 1
  /dv rules clear                   - Reset rules to defaults
  /dv rules clear all               - Clear all rules (including defaults)
]])
        end

    else
        chat.Send([[
[DiceVision] Commands:
  /dv connect <code>  - Connect to DiceVision session
  /dv disconnect      - Disconnect from session
  /dv status          - Show connection status
  /dv mode <mode>     - Set mode: off, chat, or replace
  /dv rules           - Configure dice processing rules
  /dv test            - Test API connection

Modes:
  off     - DiceVision disabled
  chat    - Physical rolls shown in chat (alongside virtual)
  replace - Physical rolls replace virtual dice
]])
    end
end

-- Alias for convenience
Commands.dicevision = Commands.dv

-- ============================================================================
-- Initialization
-- ============================================================================

print("[DiceVision] Integration mod loaded. Use /dv help for commands.")
