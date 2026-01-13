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
}

-- ============================================================================
-- Utility Functions
-- ============================================================================

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
    -- Handle spaces around the operator: "2d10 + 2" or "2d10+2"
    local sign, num = rollStr:match("([%+%-])%s*(%d+)%s*$")
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

local function getTierRanges()
    -- Returns the tier threshold ranges for display
    return {
        { tier = 1, label = "1-11", min = nil, max = 11 },
        { tier = 2, label = "12-16", min = 12, max = 16 },
        { tier = 3, label = "17+", min = 17, max = nil },
    }
end

-- ============================================================================
-- Roll Info Construction (for game mechanics callbacks)
-- ============================================================================

local function constructRollInfo(physicalDice, pendingRoll)
    -- Build a rollInfo object that matches what dmhub.Roll callbacks expect
    -- This allows game mechanics (resource consumption, effects, etc.) to work properly

    local modifier = extractModifierFromRoll(pendingRoll.roll)
    local diceSum = 0
    local rolls = {}

    for i, die in ipairs(physicalDice) do
        local faces = getDiceFaces(die.type)
        diceSum = diceSum + die.value
        rolls[i] = {
            guid = dmhub.GenerateGuid(),
            result = die.value,
            numFaces = faces,
            dropped = false,
            explodes = false,
            category = "default",
        }
    end

    local total = diceSum + modifier
    local naturalRoll = diceSum
    local isD20 = (#rolls == 1 and rolls[1].numFaces == 20)
    local tier = calculateTier(total)

    -- Get token ID from creature if available
    local tokenid = pendingRoll.tokenid
    if not tokenid and pendingRoll.creature then
        tokenid = dmhub.LookupTokenId(pendingRoll.creature)
    end

    return {
        -- Core results
        total = total,
        naturalRoll = naturalRoll,
        rolls = rolls,

        -- Critical detection (only for single d20 rolls)
        nat1 = isD20 and naturalRoll == 1,
        nat20 = isD20 and naturalRoll == 20,
        autocrit = false,

        -- Status
        isComplete = true,
        waitingOnDice = false,
        timeRemaining = 0,

        -- Modifiers (not using physical advantage/disadvantage yet)
        advantage = false,
        disadvantage = false,
        boons = 0,
        banes = 0,

        -- Tier calculation (Draw Steel)
        tiers = tier,

        -- Metadata
        description = pendingRoll.description or "Roll",
        properties = pendingRoll.properties,
        forcedResult = false,
        autosuccess = false,
        autofailure = false,
        nottierone = false,
        nottierthree = false,

        -- Token info
        token = tokenid and dmhub.GetCharacterById(tokenid) or nil,
        playerName = dmhub.userDisplayName,
        playerColor = dmhub.GetSettingValue("playercolor") or "#ffffff",

        -- Categories (simple single category for now)
        categories = { ["default"] = total },
        resultInfo = {
            ["default"] = {
                mod = modifier,
                total = total,
                rolls = rolls,
            }
        },

        -- Additional fields for message display
        formattedText = string.format("%s: %d", pendingRoll.description or "Roll", total),
        result = tostring(total),
        rollStr = pendingRoll.roll,
        diceStyle = dmhub.GetDiceStyling(
            dmhub.GetSettingValue("diceequipped"),
            dmhub.GetSettingValue("playercolor")
        ),
    }
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
    -- Convert dice data from API format to message format
    -- API: {type: "d10", value: 7} -> Message: {faces: 10, value: 7}
    local diceForMessage = {}
    local diceSum = 0
    for _, die in ipairs(rollData.dice) do
        local faces = getDiceFaces(die.type)
        diceForMessage[#diceForMessage + 1] = {
            faces = faces,
            value = die.value
        }
        diceSum = diceSum + die.value
    end

    -- Use the total from the API if provided, otherwise use dice sum
    local total = rollData.total or diceSum

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
    hideWaitingDialog()

    -- Calculate values from physical dice
    local modifier = extractModifierFromRoll(pendingRoll.originalRoll)
    local diceSum = 0

    -- Build dice info for visual display
    local diceForMessage = {}
    for i, die in ipairs(rollData.dice) do
        local faces = getDiceFaces(die.type)
        diceSum = diceSum + die.value
        diceForMessage[i] = {
            faces = faces,
            value = die.value,
        }
    end

    local total = diceSum + modifier
    local tier = calculateTier(total)

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

    -- Send visual dice display to chat (shows dice icons with individual values)
    local visualMessage = DiceVisionRollMessage.new{
        description = pendingRoll.description or "Physical Dice",
        dice = diceForMessage,
        modifier = modifier,
        total = total,
        tier = tier,
        tokenid = tokenid,
    }
    chat.SendCustom(visualMessage)

    -- Change the roll to be the deterministic total
    -- This way the C# engine calculates tiers correctly from our physical dice total
    rollArgs.roll = tostring(total)
    rollArgs.instant = true  -- No dice animation needed since we're using a fixed total

    -- Now call dmhub.Roll with the modified args
    -- This creates a proper C# rollInfo object with correct tier calculations
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
    -- Only intercept if in replace mode and connected
    if DiceVision.mode ~= "replace" or not DiceVision.connected then
        return nil  -- Let normal roll proceed
    end

    -- If already waiting, don't intercept again
    if DiceVision.waitingForRoll then
        return nil
    end

    -- Store the roll context including the full rollArgs
    -- We'll modify rollArgs.roll and call dmhub.Roll when physical dice arrive
    DiceVision.pendingRoll = {
        rollArgs = context.rollArgs,  -- The full rollArgs object
        originalRoll = context.roll,   -- Store the original roll string for modifier extraction
        description = context.description,
    }

    DiceVision.waitingForRoll = true
    DiceVision.rollStartTime = dmhub.Time() * 1000

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

    else
        chat.Send([[
[DiceVision] Commands:
  /dv connect <code>  - Connect to DiceVision session
  /dv disconnect      - Disconnect from session
  /dv status          - Show connection status
  /dv mode <mode>     - Set mode: off, chat, or replace
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
