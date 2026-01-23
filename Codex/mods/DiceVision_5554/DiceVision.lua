--[[
    DiceVision Integration for MCDM Codex - MINIMAL TEST
]]

local mod = dmhub.GetModLoading()

-- ============================================================================
-- Configuration & State
-- ============================================================================

DiceVision = {
    -- Connection settings
    baseUrl = "https://dicevision.dirtyowlbear.com",
    sessionCode = nil,
    connected = false,

    -- Mode: "off", "chat", or "replace"
    mode = "off",

    -- Polling state
    isPolling = false,
    pollIntervalMs = 500,
    lastPollTime = 0,
    longpoll = true,  -- Use long-polling endpoint (default: true)

    -- Pending roll state
    pendingRoll = nil,
    waitingForRoll = false,
    rollTimeout = 30000,
    rollStartTime = 0,

    -- Request ID for polling
    currentRequestId = nil,

    -- Panel-specific state (independent of replace mode)
    panelWaitingForRoll = false,
    panelPollStartTime = 0,
    panelRequestId = nil,
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
    valueMappings = {},
    diceSelection = nil,
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
    return tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
end

-- Expose for DVDicePanel.lua
DiceVision.generateRequestId = generateRequestId

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
    if not rollStr then return 0 end
    local strippedStr = rollStr:gsub("%s+%d+%s+edges?%s*$", "")
    strippedStr = strippedStr:gsub("%s+%d+%s+banes?%s*$", "")
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
    local faces = dieType:match("d(%d+)")
    return tonumber(faces) or 10
end

local function calculateTier(total)
    if total >= 17 then
        return 3
    elseif total >= 12 then
        return 2
    else
        return 1
    end
end

local function SplitBoons(combinedBoons)
    combinedBoons = combinedBoons or 0
    if combinedBoons >= 0 then
        return combinedBoons, 0
    else
        return 0, -combinedBoons
    end
end

local function GetRollModFromEdgesAndBanes(edges, banes)
    edges = edges or 0
    banes = banes or 0
    local bonus = 0
    if banes == 0 then
        if edges == 1 then
            bonus = 2
        end
    elseif edges == 0 then
        if banes == 1 then
            bonus = -2
        end
    elseif edges > banes then
        bonus = 2
    elseif edges < banes then
        bonus = -2
    else
        bonus = 0
    end
    return bonus
end

local function CalculateTierWithEdges(total, edges, banes)
    local tier = 1
    if total >= 17 then
        tier = 3
    elseif total >= 12 then
        tier = 2
    end
    if edges >= 2 and banes == 0 then
        tier = tier + 1
    elseif banes >= 2 and edges == 0 then
        tier = tier - 1
    end
    if tier > 3 then tier = 3 end
    if tier < 1 then tier = 1 end
    return tier
end

local function ParseBoonsFromRollString(rollString)
    if not rollString then return 0, 0 end
    local edges = 0
    local banes = 0
    local edgeMatch = string.match(rollString, "(%d+)%s+edge")
    if edgeMatch then
        edges = tonumber(edgeMatch) or 0
    end
    local baneMatch = string.match(rollString, "(%d+)%s+bane")
    if baneMatch then
        banes = tonumber(baneMatch) or 0
    end
    return edges, banes
end

local function getTierRanges()
    return {
        { tier = 1, label = "1-11", min = nil, max = 11 },
        { tier = 2, label = "12-16", min = 12, max = 16 },
        { tier = 3, label = "17+", min = 17, max = nil },
    }
end

-- ============================================================================
-- Dice Rule Processing
-- ============================================================================

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

local function clampOutOfRangeValues(dice, isEnabled)
    if not isEnabled then
        return dice
    end
    local result = {}
    for i, die in ipairs(dice) do
        local value = die.value
        local clamped = value
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

local function applyDiceSelection(dice, selection)
    if not selection or not selection.count then
        return dice
    end
    local sorted = {}
    for i, die in ipairs(dice) do
        sorted[i] = {die = die, index = i}
    end
    if selection.keep == "highest" then
        table.sort(sorted, function(a, b) return a.die.value > b.die.value end)
    elseif selection.keep == "lowest" then
        table.sort(sorted, function(a, b) return a.die.value < b.die.value end)
    end
    local result = {}
    local count = math.min(selection.count, #sorted)
    for i = 1, count do
        result[i] = sorted[i].die
    end
    return result, sorted
end

local function detectDiceSelection(pendingRoll)
    if not pendingRoll or not pendingRoll.originalRoll then
        return nil
    end
    local creature = pendingRoll.rollArgs and pendingRoll.rollArgs.creature
    local rollInfo = dmhub.ParseRoll(pendingRoll.originalRoll, creature)
    if rollInfo and rollInfo.categories then
        for catName, category in pairs(rollInfo.categories) do
            if category.groups then
                for _, group in ipairs(category.groups) do
                    if group.numKeep and group.numKeep > 0 and group.numDice and group.numDice > group.numKeep then
                        return {
                            keep = "highest",
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

local function getEffectiveRules(pendingRoll)
    local rules = {
        valueMappings = DiceVision.rules.valueMappings or {},
        diceSelection = DiceVision.rules.diceSelection,
    }
    if not rules.diceSelection then
        rules.diceSelection = detectDiceSelection(pendingRoll)
    end
    return rules
end

local function applyDiceRules(dice, pendingRoll)
    local rules = getEffectiveRules(pendingRoll)
    local processed = dice
    local droppedDice = nil
    processed = clampOutOfRangeValues(processed, DiceVision.rules.clampOutOfRange)
    processed = applyValueMappings(processed, rules.valueMappings)
    if rules.diceSelection then
        local sorted
        processed, sorted = applyDiceSelection(processed, rules.diceSelection)
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
DiceVisionRollMessage.tokenid = nil

function DiceVisionRollMessage.CreateDiePanel(faces, value)
    local diceStyle = dmhub.GetDiceStyling(
        dmhub.GetSettingValue("diceequipped"),
        dmhub.GetSettingValue("playercolor")
    )
    return gui.Panel{
        width = 40,
        height = 40,
        halign = "center",
        valign = "center",
        bgimage = string.format("ui-icons/d%d-filled.png", faces),
        bgcolor = diceStyle.bgcolor or "#2d5a2d",
        saturation = 0.7,
        brightness = 0.4,
        gui.Panel{
            interactable = false,
            width = "100%",
            height = "100%",
            bgimage = string.format("ui-icons/d%d.png", faces),
            bgcolor = diceStyle.trimcolor or "#4a9a4a",
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
    if tier == 1 then
        return "11 or lower"
    elseif tier == 2 then
        return "12-16"
    else
        return "17 or higher"
    end
end

function DiceVisionRollMessage:GetToken()
    local tokenid = self:try_get("tokenid")
    if tokenid then
        return dmhub.GetCharacterById(tokenid)
    end
    return nil
end

function DiceVisionRollMessage.Render(self, message)
    local dice = self:try_get("dice") or {}
    local modifier = self:try_get("modifier") or 0
    local total = self:try_get("total") or 0
    local tier = self:try_get("tier") or 1
    local description = self:try_get("description") or "Roll"

    local dicePanels = {}
    for i, die in ipairs(dice) do
        local faces = die.faces or 10
        local value = die.value or 0
        dicePanels[#dicePanels+1] = DiceVisionRollMessage.CreateDiePanel(faces, value)
    end

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

    local diceRowPanel = gui.Panel{
        flow = "horizontal",
        halign = "left",
        valign = "center",
        height = "auto",
        width = "auto",
    }
    for _, panel in ipairs(dicePanels) do
        diceRowPanel:AddChild(panel)
    end

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

    local tierRangeLabel = DiceVisionRollMessage.GetTierLabel(tier)
    local tierLabel = gui.Label{
        width = "100%",
        height = "auto",
        fontSize = 14,
        color = "#888888",
        tmargin = 4,
        text = string.format("%s    tier %d result", tierRangeLabel, tier),
    }

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        hpad = 8,
        vpad = 8,
        gui.Label{
            width = "100%",
            height = "auto",
            fontSize = 16,
            bold = true,
            color = "#ffffff",
            text = description,
        },
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            valign = "center",
            diceRowPanel,
            totalLabel,
        },
        tierLabel,
    }
end

-- ============================================================================
-- Forward Declarations
-- ============================================================================

local startPolling          -- Used by RollDialog_BeforeRoll
local stopPolling
local removeRollInterceptor
local checkRollTimeout      -- Used by longPollForRolls
local handlePendingRoll     -- Used by handleDiceVisionRoll
local postRollToChat        -- Used by handleDiceVisionRoll
local longPollForRolls      -- Recursive call

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
end

local function pollForRolls(callback)
    if not DiceVision.connected or not DiceVision.sessionCode then
        return
    end
    local pollMode = DiceVision.waitingForRoll and "waiting" or "background"
    local url = string.format(
        "%s/api/codex/session/%s/rolls?acknowledge=true&limit=10&mode=%s",
        DiceVision.baseUrl,
        DiceVision.sessionCode,
        pollMode
    )
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
            if data and data.poll_interval_ms then
                DiceVision.pollIntervalMs = data.poll_interval_ms
            end
        end,
        error = function(err, statusCode)
            if statusCode == 404 or (type(err) == "string" and err:find("404")) then
                handleSessionExpired()
            end
        end,
    }
end

local function handleDiceVisionRoll(rollData)
    -- Handle panel-initiated roll first
    if DiceVision.panelWaitingForRoll then
        postRollToChat(rollData)
        DiceVision.panelWaitingForRoll = false
        DiceVision.panelRequestId = generateRequestId()
        return
    end

    local used = false
    if DiceVision.mode == "replace" and DiceVision.waitingForRoll then
        used = handlePendingRoll(rollData)
    end

    if DiceVision.mode == "chat" or (DiceVision.mode == "replace" and not used) then
        postRollToChat(rollData)
    end
end

longPollForRolls = function()
    if not DiceVision.connected or not DiceVision.sessionCode then
        return
    end

    local url = DiceVision.baseUrl .. "/api/codex/session/" .. DiceVision.sessionCode .. "/wait?timeout=25"

    -- Add mode and request_id parameters
    local mode = DiceVision.waitingForRoll and "waiting" or "background"
    url = url .. "&acknowledge=true&limit=10&mode=" .. mode
    if DiceVision.waitingForRoll and DiceVision.currentRequestId then
        url = url .. "&request_id=" .. DiceVision.currentRequestId
    end

    net.Get{
        url = url,
        success = function(data)
            -- Process response (same as pollForRolls success handler)
            if data and data.poll_interval_ms then
                DiceVision.pollIntervalMs = data.poll_interval_ms
            end
            if data and data.rolls then
                for _, roll in ipairs(data.rolls) do
                    handleDiceVisionRoll(roll)
                end
            end
            -- Immediately reconnect if still polling
            if DiceVision.isPolling and DiceVision.connected then
                checkRollTimeout()
                longPollForRolls()
            end
        end,
        error = function(err, statusCode)
            printf("[DiceVision] Long-poll error: %s (status: %s)", tostring(err), tostring(statusCode or "unknown"))
            -- Fall back to short polling on error, then retry long-poll
            if DiceVision.isPolling and DiceVision.connected then
                dmhub.Schedule(2, function()
                    if DiceVision.isPolling and DiceVision.connected then
                        longPollForRolls()
                    end
                end)
            end
        end,
    }
end

-- ============================================================================
-- Level 1: Chat Integration
-- ============================================================================

postRollToChat = function(rollData)
    local processedDice, droppedDice = applyDiceRules(rollData.dice, nil)
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
    if droppedDice and #droppedDice > 0 then
        local droppedValues = {}
        for _, die in ipairs(droppedDice) do
            droppedValues[#droppedValues + 1] = tostring(die.value)
        end
        print("[DiceVision] Dropped dice: " .. table.concat(droppedValues, ", "))
    end
    local total = diceSum
    local tier = calculateTier(total)
    local message = DiceVisionRollMessage.new{
        description = "Physical Dice Roll",
        dice = diceForMessage,
        modifier = 0,
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
    chat.Send("[DiceVision] Waiting for physical dice roll...")
end

local function hideWaitingDialog()
    -- TODO: Hide the waiting indicator
end

local function postDiceVisionRollToChat(rollData, rollInfo, pendingRoll)
    local diceForMessage = {}
    for _, die in ipairs(rollData.dice) do
        local faces = getDiceFaces(die.type)
        diceForMessage[#diceForMessage + 1] = {
            faces = faces,
            value = die.value
        }
    end
    local tokenid = pendingRoll.tokenid
    if not tokenid and pendingRoll.creature then
        tokenid = dmhub.LookupTokenId(pendingRoll.creature)
    end
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

handlePendingRoll = function(rollData)
    if not DiceVision.pendingRoll then
        return false
    end
    local pendingRoll = DiceVision.pendingRoll
    DiceVision.pendingRoll = nil
    DiceVision.waitingForRoll = false
    DiceVision.currentRequestId = generateRequestId()
    hideWaitingDialog()

    -- Stop polling after roll is handled (for replace mode)
    if DiceVision.mode == "replace" then
        stopPolling()
    end

    local modifier = extractModifierFromRoll(pendingRoll.originalRoll)
    local diceSum = 0
    local processedDice, droppedDice = applyDiceRules(rollData.dice, pendingRoll)
    local diceForMessage = {}
    for i, die in ipairs(processedDice) do
        local faces = getDiceFaces(die.type)
        diceSum = diceSum + die.value
        diceForMessage[i] = {
            faces = faces,
            value = die.value,
            originalValue = die.originalValue,
        }
    end
    if droppedDice and #droppedDice > 0 then
        local droppedValues = {}
        for _, die in ipairs(droppedDice) do
            droppedValues[#droppedValues + 1] = tostring(die.value)
        end
        print("[DiceVision] Dropped dice: " .. table.concat(droppedValues, ", "))
    end

    local edges = pendingRoll.edges or 0
    local banes = pendingRoll.banes or 0
    local edgeBaneMod = GetRollModFromEdgesAndBanes(edges, banes)
    local isNonTargeted = not pendingRoll.multitargets or #pendingRoll.multitargets == 0
    local baseTotal = diceSum + modifier
    local finalTotal = baseTotal + edgeBaneMod
    local tier = calculateTier(finalTotal)

    local rollArgs = pendingRoll.rollArgs
    if not rollArgs then
        chat.Send("[DiceVision] Error: Roll context not available. Try again.")
        return false
    end

    local tokenid = rollArgs.tokenid
    if not tokenid and rollArgs.creature then
        tokenid = dmhub.LookupTokenId(rollArgs.creature)
    end

    local visualMessage = DiceVisionRollMessage.new{
        description = pendingRoll.description or "Physical Dice",
        dice = diceForMessage,
        modifier = modifier,
        total = finalTotal,
        tier = tier,
        tokenid = tokenid,
    }
    rollArgs.instant = true

    if isNonTargeted then
        local boonsValue = edges - banes
        print("[DiceVision] Non-targeted roll detected. baseTotal:", baseTotal, "boonsValue:", boonsValue)
        if boonsValue ~= 0 and GameSystem and GameSystem.ApplyBoons then
            local rollWithBoons = GameSystem.ApplyBoons(tostring(baseTotal), boonsValue)
            print("[DiceVision] GameSystem.ApplyBoons('" .. tostring(baseTotal) .. "', " .. boonsValue .. ") returned: '" .. tostring(rollWithBoons) .. "'")
            rollArgs.roll = rollWithBoons
        else
            print("[DiceVision] No boons to apply or GameSystem.ApplyBoons not available, using finalTotal:", finalTotal)
            rollArgs.roll = tostring(finalTotal)
        end
    else
        rollArgs.roll = tostring(baseTotal)
        rollArgs.boons = edges
        rollArgs.banes = banes
        rollArgs.properties = rollArgs.properties or {}
        rollArgs.properties.multitargets = pendingRoll.multitargets
        rollArgs.properties.multitargets[1].boons = 0
        rollArgs.properties.multitargets[1].banes = 0
    end

    local originalComplete = rollArgs.complete
    rollArgs.complete = function(rollInfo)
        if (edges >= 2 and banes == 0) or (banes >= 2 and edges == 0) then
            local calculatedTier = CalculateTierWithEdges(finalTotal, edges, banes)
            local props = rollInfo.properties or {}
            if not props:try_get("overrideTier") then
                props.overrideTier = calculatedTier
                rollInfo:UploadProperties(props)
            end
        end
        chat.SendCustom(visualMessage)
        if originalComplete then
            originalComplete(rollInfo)
        end
    end

    dmhub.Roll(rollArgs)
    return true
end

checkRollTimeout = function()
    if DiceVision.waitingForRoll then
        local elapsed = (dmhub.Time() * 1000) - DiceVision.rollStartTime
        if elapsed > DiceVision.rollTimeout then
            chat.Send("[DiceVision] Timeout waiting for physical dice. Roll cancelled - try again.")
            DiceVision.waitingForRoll = false
            DiceVision.pendingRoll = nil
            DiceVision.currentRequestId = generateRequestId()
            hideWaitingDialog()

            -- Stop polling on timeout (for replace mode)
            if DiceVision.mode == "replace" then
                stopPolling()
            end
        end
    end

    -- Panel roll timeout
    if DiceVision.panelWaitingForRoll then
        local elapsed = (dmhub.Time() * 1000) - DiceVision.panelPollStartTime
        if elapsed > DiceVision.rollTimeout then
            chat.Send("[DiceVision] Timeout waiting for dice. Try again.")
            DiceVision.panelWaitingForRoll = false
            DiceVision.panelRequestId = generateRequestId()
        end
    end
end

-- ============================================================================
-- RollDialog Hook (called from RollDialog.lua before dmhub.Roll)
-- ============================================================================

RollDialog_BeforeRoll = function(context)
    if not context then return nil end
    if not DiceVision then return nil end

    if DiceVision.mode ~= "replace" or not DiceVision.connected then
        return nil
    end

    if DiceVision.waitingForRoll then
        return nil
    end

    print("[DiceVision] Hook received context.boons:", context.boons)
    print("[DiceVision] Hook received context.roll:", context.roll)

    local edges, banes = SplitBoons(context.boons)
    print("[DiceVision] After SplitBoons - edges:", edges, "banes:", banes)

    if edges == 0 and banes == 0 and context.roll then
        edges, banes = ParseBoonsFromRollString(context.roll)
        if edges > 0 or banes > 0 then
            print("[DiceVision] Parsed boons from roll string - edges:", edges, "banes:", banes)
        end
    end

    DiceVision.pendingRoll = {
        rollArgs = context.rollArgs,
        originalRoll = context.roll,
        description = context.description,
        edges = edges,
        banes = banes,
        multitargets = context.multitargets,
    }

    DiceVision.waitingForRoll = true
    DiceVision.rollStartTime = dmhub.Time() * 1000
    DiceVision.currentRequestId = generateRequestId()

    -- Start polling now (will send mode=waiting immediately)
    if DiceVision.connected and not DiceVision.isPolling then
        startPolling()
    end

    showWaitingDialog()
    chat.Send("[DiceVision] Waiting for physical dice...")

    return "intercept"
end

local function installRollInterceptor()
    -- Hook is now in DSRollDialog.lua, no installation needed
end

removeRollInterceptor = function()
    DiceVision.pendingRoll = nil
    DiceVision.waitingForRoll = false
    DiceVision.currentRequestId = nil
end

-- ============================================================================
-- Polling Loop
-- ============================================================================

startPolling = function()
    if DiceVision.isPolling then
        return
    end

    DiceVision.isPolling = true

    if DiceVision.longpoll then
        -- Long-polling mode: single persistent connection
        longPollForRolls()
    else
        -- Short-polling mode: existing behavior
        local function poll()
            if not DiceVision.isPolling or not DiceVision.connected then
                return
            end

            checkRollTimeout()

            pollForRolls(function(rolls)
                for _, rollData in ipairs(rolls) do
                    handleDiceVisionRoll(rollData)
                end
            end)

            dmhub.Schedule(DiceVision.pollIntervalMs / 1000, poll)
        end
        poll()
    end
end

stopPolling = function()
    DiceVision.isPolling = false
end

-- Expose for DVDicePanel.lua
DiceVision.startPolling = startPolling
DiceVision.postRollToChat = postRollToChat

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
        local pollingMode = DiceVision.longpoll and "long-poll" or "500ms interval"
        local status = string.format(
            "[DiceVision] Status:\n  Connected: %s\n  Session: %s\n  Mode: %s\n  Polling: %s (%s)",
            tostring(DiceVision.connected),
            DiceVision.sessionCode or "none",
            DiceVision.mode,
            tostring(DiceVision.isPolling),
            pollingMode
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
            -- Don't start polling here - wait for ability test to trigger it
            -- This ensures the first request sends mode=waiting immediately
        end

        chat.Send("[DiceVision] Mode changed: " .. oldMode .. " -> " .. newMode)

    elseif subcommand == "test" then
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

    elseif subcommand == "testtimeout" then
        local seconds = tonumber(parts[2])
        local testTimeoutParam = (parts[3] == "timeout")  -- /dv testtimeout 30 timeout

        if not seconds then
            chat.Send("[DiceVision] Usage: /dv testtimeout <seconds> [timeout]")
            chat.Send("[DiceVision] Add 'timeout' to test passing timeout parameter to net.Get")
            return
        end

        local startTime = dmhub.Time()
        local testMode = testTimeoutParam and " (with timeout param)" or ""
        chat.Send(string.format("[DiceVision] Testing %ds delay%s...", seconds, testMode))

        local requestArgs = {
            url = "https://dicevision.dirtyowlbear.com/api/codex/test/delay?seconds=" .. seconds,
            success = function(data)
                local elapsed = dmhub.Time() - startTime
                chat.Send(string.format("[DiceVision] SUCCESS: %ds test completed in %.1fs", seconds, elapsed))
                if data and data.actual_seconds then
                    chat.Send(string.format("[DiceVision] Server reported: %.2fs actual delay", data.actual_seconds))
                end
            end,
            error = function(err, statusCode)
                local elapsed = dmhub.Time() - startTime
                chat.Send(string.format("[DiceVision] FAILED after %.1fs: %s (status: %s)",
                    elapsed, tostring(err), tostring(statusCode or "unknown")))
            end,
        }

        -- Test undocumented timeout parameter
        if testTimeoutParam then
            requestArgs.timeout = seconds + 10  -- Give 10s buffer
        end

        net.Get(requestArgs)

    elseif subcommand == "config" then
        local setting = parts[2]
        local value = parts[3]

        if setting == "longpoll" then
            if value == "on" or value == "true" then
                DiceVision.longpoll = true
                chat.Send("[DiceVision] Long-polling enabled")
                -- Restart polling if currently active
                if DiceVision.isPolling then
                    stopPolling()
                    startPolling()
                end
            elseif value == "off" or value == "false" then
                DiceVision.longpoll = false
                chat.Send("[DiceVision] Long-polling disabled (using 500ms polling)")
                if DiceVision.isPolling then
                    stopPolling()
                    startPolling()
                end
            else
                chat.Send("[DiceVision] Current: longpoll = " .. (DiceVision.longpoll and "on" or "off"))
                chat.Send("[DiceVision] Usage: /dv config longpoll on|off")
            end
        else
            chat.Send("[DiceVision] Available config options:")
            chat.Send("  longpoll on|off - Use long-polling endpoint (current: " .. (DiceVision.longpoll and "on" or "off") .. ")")
        end

    elseif subcommand == "rules" then
        local action = parts[2]

        if action == "show" then
            local msg = "[DiceVision] Current rules:\n"
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
            msg = msg .. "  Dice selection: " .. (DiceVision.rules.diceSelection and
                string.format("keep %s %d", DiceVision.rules.diceSelection.keep, DiceVision.rules.diceSelection.count) or "auto-detect") .. "\n"
            msg = msg .. "  Out-of-range clamping: " .. (DiceVision.rules.clampOutOfRange and "enabled" or "disabled")
            chat.Send(msg)

        elseif action == "map" then
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
                DiceVision.rules = {valueMappings = {}, diceSelection = nil, clampOutOfRange = false}
                chat.Send("[DiceVision] All rules cleared (including defaults)")
            else
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
            chat.Send([=[
[DiceVision] Rule commands:
  /dv rules show                    - Show current rules
  /dv rules map <die> <from> <to>   - Map die value (e.g., /dv rules map d10 0 10)
  /dv rules keep <mode> <count>     - Keep highest/lowest N dice
  /dv rules keep auto               - Auto-detect from roll context
  /dv rules clamp <on|off>          - Clamp values outside 0-10 to 1
  /dv rules clear                   - Reset rules to defaults
  /dv rules clear all               - Clear all rules (including defaults)
]=])
        end

    else
        chat.Send([=[
[DiceVision] Commands:
  /dv connect <code>  - Connect to DiceVision session
  /dv disconnect      - Disconnect from session
  /dv status          - Show connection status
  /dv mode <mode>     - Set mode: off, chat, or replace
  /dv config          - Configure settings (longpoll)
  /dv rules           - Configure dice processing rules
  /dv test            - Test API connection

Modes:
  off     - DiceVision disabled
  chat    - Physical rolls shown in chat (alongside virtual)
  replace - Physical rolls replace virtual dice
]=])
    end
end

Commands.dicevision = Commands.dv

print("DV: DiceVision script loaded")
