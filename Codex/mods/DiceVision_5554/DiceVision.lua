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

    -- Mode: "off" or "replace"
    mode = "off",

    -- Polling state
    isPolling = false,
    lastPollTime = 0,

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
    panelTokenId = nil,  -- Token ID for panel roll attribution
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
    convertDice = true,  -- Auto-convert d6 values for d3 rolls (default ON)
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

-- Forward declaration for functions called before definition
local hideWaitingDialog

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
DiceVisionRollMessage.rollSource = "unknown"  -- "panel" | "ability"

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
    local rollSource = self:try_get("rollSource") or "unknown"

    -- Token panel only for panel rolls
    local tokenPanel = nil
    if rollSource == "panel" then
        local token = self:GetToken()
        if token ~= nil then
            tokenPanel = gui.Panel{
                flow = "vertical",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                rmargin = 8,

                gui.CreateTokenImage(token, {
                    scale = 0.9,
                    halign = "center",
                }),

                gui.Label{
                    width = "auto",
                    height = "auto",
                    fontSize = 12,
                    bold = true,
                    color = "#ffffff",
                    halign = "center",
                    textAlignment = "center",
                    text = token.name,
                },
            }
        end
    end

    -- Separator only for panel rolls (matches native dice panel styling)
    local separator = nil
    if rollSource == "panel" then
        separator = gui.Panel{
            bgimage = "panels/square.png",
            width = "96%",
            height = 1,
            vmargin = 4,
            halign = "center",
            bgcolor = "white",
            gradient = gui.Gradient{
                point_a = {x = 0, y = 0},
                point_b = {x = 1, y = 0},
                stops = {
                    { position = 0, color = "#ffffff00" },
                    { position = 0.2, color = "#ffffffff" },
                    { position = 0.8, color = "#ffffffff" },
                    { position = 1, color = "#ffffff00" },
                },
            },
        }
    end

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

        separator,  -- Top line (nil for ability rolls)

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            hpad = 8,
            vpad = 8,

            tokenPanel,  -- Portrait (nil for ability rolls)

            gui.Panel{
                flow = "vertical",
                width = tokenPanel and "100%-60" or "100%",
                height = "auto",

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
            },
        },
    }
end

-- ============================================================================
-- Forward Declarations
-- ============================================================================

local startPolling          -- Used by onBeforeRoll
local stopPolling
local removeRollInterceptor
local checkRollTimeout      -- Used by longPollForRolls
local handlePendingRoll     -- Used by handleDiceVisionRoll
local postRollToChat        -- Used by handleDiceVisionRoll
local longPollForRolls      -- Recursive call
local onBeforeRoll          -- Used by /dv connect, registered on RollDialog.OnBeforeRoll

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

local function handleDiceVisionRoll(rollData)
    print(string.format("DV: handleDiceVisionRoll - panelWaiting=%s, mode=%s, waitingForRoll=%s, dice=%s",
        tostring(DiceVision.panelWaitingForRoll), DiceVision.mode, tostring(DiceVision.waitingForRoll),
        formatDice(rollData.dice)))
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

    if DiceVision.mode == "replace" and not used then
        postRollToChat(rollData)
    end
end

longPollForRolls = function()
    if not DiceVision.connected or not DiceVision.sessionCode then
        return
    end

    local url = DiceVision.baseUrl .. "/api/codex/session/" .. DiceVision.sessionCode .. "/wait?timeout=25"

    -- Add mode and request_id parameters
    local mode = (DiceVision.waitingForRoll or DiceVision.panelWaitingForRoll) and "waiting" or "background"
    url = url .. "&acknowledge=true&limit=10&mode=" .. mode
    if mode == "waiting" then
        -- Use the correct request_id based on which roll type is waiting
        local requestId = nil
        if DiceVision.waitingForRoll then
            requestId = DiceVision.currentRequestId
        elseif DiceVision.panelWaitingForRoll then
            requestId = DiceVision.panelRequestId
        end
        if requestId then
            url = url .. "&request_id=" .. requestId
        end
    end

    net.Get{
        url = url,
        success = function(data)
            -- Process response
            if data and data.rolls then
                for _, roll in ipairs(data.rolls) do
                    handleDiceVisionRoll(roll)
                end
            end
            DiceVision.isPolling = false

            -- Replace mode timeout: if still waiting, fall back to virtual dice
            if DiceVision.waitingForRoll then
                local rollArgs = DiceVision.pendingRoll and DiceVision.pendingRoll.rollArgs

                chat.Send("[DiceVision] Physical dice timeout. Falling back to virtual dice...")
                DiceVision.waitingForRoll = false
                DiceVision.pendingRoll = nil
                DiceVision.currentRequestId = generateRequestId()
                hideWaitingDialog()
                stopPolling()

                if rollArgs then
                    dmhub.Roll(rollArgs)
                end
            end

            -- Panel timeout: if still waiting, roll didn't arrive
            if DiceVision.panelWaitingForRoll then
                chat.Send("[DiceVision] Timeout waiting for dice. Try again.")
                DiceVision.panelWaitingForRoll = false
                DiceVision.panelRequestId = generateRequestId()
            end
        end,
        error = function(err, statusCode)
            printf("[DiceVision] Long-poll error: %s (status: %s)", tostring(err), tostring(statusCode or "unknown"))
            DiceVision.isPolling = false

            -- Replace mode: fall back to virtual dice on error
            if DiceVision.waitingForRoll then
                local rollArgs = DiceVision.pendingRoll and DiceVision.pendingRoll.rollArgs

                chat.Send("[DiceVision] Connection error. Falling back to virtual dice...")
                DiceVision.waitingForRoll = false
                DiceVision.pendingRoll = nil
                DiceVision.currentRequestId = generateRequestId()
                hideWaitingDialog()
                stopPolling()

                if rollArgs then
                    dmhub.Roll(rollArgs)
                end
            end

            -- Panel: clear waiting state on error
            if DiceVision.panelWaitingForRoll then
                chat.Send("[DiceVision] Connection error. Try again.")
                DiceVision.panelWaitingForRoll = false
                DiceVision.panelRequestId = generateRequestId()
            end
        end,
    }
end

-- ============================================================================
-- Level 1: Chat Integration
-- ============================================================================

postRollToChat = function(rollData)
    local processedDice, droppedDice = DiceRollLogic.applyDiceRules(rollData.dice, nil)
    local diceForMessage = {}
    local diceSum = 0
    for _, die in ipairs(processedDice) do
        local faces = DiceRollLogic.getDiceFaces(die.type)
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
    local tier = DiceRollLogic.calculateTier(total)
    local message = DiceVisionRollMessage.new{
        description = "Physical Dice Roll",
        dice = diceForMessage,
        modifier = 0,
        total = total,
        tier = tier,
        tokenid = DiceVision.panelTokenId,
        rollSource = "panel",
    }
    chat.SendCustom(message)
    DiceVision.panelTokenId = nil  -- Clear after use
    print(string.format("DV: postRollToChat - total=%d, tier=%d", total, tier))
end

-- ============================================================================
-- Level 2: Dice Replacement
-- ============================================================================

local function showWaitingDialog()
    chat.Send("[DiceVision] Waiting for physical dice roll...")
end

hideWaitingDialog = function()
    -- TODO: Hide the waiting indicator
end

local function postDiceVisionRollToChat(rollData, rollInfo, pendingRoll)
    local modifier = DiceRollLogic.extractModifierFromRoll(pendingRoll.roll)
    print(string.format("DV: postDiceVisionRollToChat - modifier=%d, total=%d, tier=%s",
        modifier, rollInfo.total, tostring(rollInfo.tiers)))
    local diceForMessage = {}
    for _, die in ipairs(rollData.dice) do
        local faces = DiceRollLogic.getDiceFaces(die.type)
        diceForMessage[#diceForMessage + 1] = {
            faces = faces,
            value = die.value
        }
    end
    local tokenid = pendingRoll.tokenid
    if not tokenid and pendingRoll.creature then
        tokenid = dmhub.LookupTokenId(pendingRoll.creature)
    end
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

    local modifier = DiceRollLogic.extractModifierFromRoll(pendingRoll.originalRoll)
    print(string.format("DV: handlePendingRoll - originalRoll='%s', modifier=%d",
        tostring(pendingRoll.originalRoll), modifier))
    local diceSum = 0
    local processedDice, droppedDice = DiceRollLogic.applyDiceRules(rollData.dice, pendingRoll)
    local diceForMessage = {}
    for i, die in ipairs(processedDice) do
        local faces = die.physicalType
            and DiceRollLogic.getDiceFaces(die.physicalType)
            or DiceRollLogic.getDiceFaces(die.type)
        diceSum = diceSum + die.value
        diceForMessage[i] = {
            faces = faces,
            value = die.value,
            originalValue = die.originalValue or die.physicalValue,
        }
    end
    print(string.format("DV: handlePendingRoll - diceSum=%d, processedDice=%d, droppedDice=%d",
        diceSum, #processedDice, droppedDice and #droppedDice or 0))
    if droppedDice and #droppedDice > 0 then
        local droppedValues = {}
        for _, die in ipairs(droppedDice) do
            droppedValues[#droppedValues + 1] = tostring(die.value)
        end
        print("[DiceVision] Dropped dice: " .. table.concat(droppedValues, ", "))
    end

    local edges = pendingRoll.edges or 0
    local banes = pendingRoll.banes or 0
    local edgeBaneMod = DiceRollLogic.GetRollModFromEdgesAndBanes(edges, banes)
    local isNonTargeted = not pendingRoll.multitargets or #pendingRoll.multitargets == 0
    local baseTotal = diceSum + modifier
    local finalTotal = baseTotal + edgeBaneMod
    local tier = DiceRollLogic.CalculateTierWithEdges(finalTotal, edges, banes)

    print(string.format("DV: handlePendingRoll - edges=%d, banes=%d, net=%d, edgeBaneMod=%d, baseTotal=%d, finalTotal=%d, tier=%d",
        edges, banes, edges - banes, edgeBaneMod, baseTotal, finalTotal, tier))

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
        rollSource = "ability",
    }
    rollArgs.instant = true

    print(string.format("DV: handlePendingRoll - isNonTargeted=%s, rollArgs.roll='%s'",
        tostring(isNonTargeted), tostring(rollArgs.roll)))

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
        local net = edges - banes
        rollArgs.roll = tostring(baseTotal)
        if net > 0 then
            rollArgs.boons = net
            rollArgs.banes = 0
        elseif net < 0 then
            rollArgs.boons = 0
            rollArgs.banes = -net
        else
            rollArgs.boons = 0
            rollArgs.banes = 0
        end
        rollArgs.properties = rollArgs.properties or {}
        rollArgs.properties.multitargets = pendingRoll.multitargets
        rollArgs.properties.multitargets[1].boons = 0
        rollArgs.properties.multitargets[1].banes = 0
    end

    local originalComplete = rollArgs.complete
    rollArgs.complete = function(rollInfo)
        local net = edges - banes
        if net >= 2 or net <= -2 then
            local calculatedTier = DiceRollLogic.CalculateTierWithEdges(finalTotal, edges, banes)
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

removeRollInterceptor = function()
    DiceVision.pendingRoll = nil
    DiceVision.waitingForRoll = false
    DiceVision.currentRequestId = nil
    if RollDialog then
        RollDialog.OnBeforeRoll = false
    end
end

-- ============================================================================
-- Polling Loop
-- ============================================================================

startPolling = function()
    if DiceVision.isPolling then
        return
    end

    DiceVision.isPolling = true
    longPollForRolls()
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
                DiceVision.mode = "replace"
                -- Ensure callback is registered (handles load order)
                if RollDialog then
                    RollDialog.OnBeforeRoll = onBeforeRoll
                end
                chat.Send("[DiceVision] Connected! Ready to capture dice rolls.")
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
        if not newMode or (newMode ~= "off" and newMode ~= "replace") then
            chat.Send("[DiceVision] Usage: /dv mode <off|replace>")
            chat.Send("[DiceVision] Current mode: " .. DiceVision.mode)
            return
        end

        local oldMode = DiceVision.mode
        DiceVision.mode = newMode

        if newMode == "off" then
            stopPolling()
            removeRollInterceptor()
        end
        -- No action needed for replace mode - dmhub.Roll wrapper handles interception

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
            msg = msg .. "\n  Dice conversion: " .. (DiceVision.rules.convertDice and "enabled" or "disabled")
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

        elseif action == "convert" then
            local mode = parts[3]
            if mode == "on" then
                DiceVision.rules.convertDice = true
                chat.Send("[DiceVision] Dice conversion enabled (d6 values auto-converted for d3 rolls)")
            elseif mode == "off" then
                DiceVision.rules.convertDice = false
                chat.Send("[DiceVision] Dice conversion disabled (use if you have physical d3 dice)")
            else
                local status = DiceVision.rules.convertDice and "enabled" or "disabled"
                chat.Send("[DiceVision] Dice conversion: " .. status .. "\nUsage: /dv rules convert <on|off>")
            end

        elseif action == "clear" then
            local clearAll = parts[3] == "all"
            if clearAll then
                DiceVision.rules = {valueMappings = {}, diceSelection = nil, clampOutOfRange = false, convertDice = false}
                chat.Send("[DiceVision] All rules cleared (including defaults)")
            else
                DiceVision.rules = {valueMappings = {}, diceSelection = nil, clampOutOfRange = false, convertDice = true}
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
  /dv rules convert <on|off>       - Auto-convert d6 values for d3 rolls
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
  /dv mode <mode>     - Set mode: off or replace
  /dv rules           - Configure dice processing rules
  /dv test            - Test API connection

Modes:
  off     - DiceVision disabled
  replace - Physical rolls replace virtual dice
]=])
    end
end

Commands.dicevision = Commands.dv

-- ============================================================================
-- RollDialog.OnBeforeRoll Callback (official Codex hook API)
-- ============================================================================

onBeforeRoll = function(context)
    if not context then return nil end
    if not DiceVision then return nil end

    if DiceVision.mode ~= "replace" or not DiceVision.connected then
        return nil
    end

    if DiceVision.waitingForRoll then
        return nil
    end

    print(string.format("DV: onBeforeRoll - roll='%s', boons=%s, description='%s'",
        tostring(context.roll), tostring(context.boons), tostring(context.description)))

    local edges, banes = DiceRollLogic.ParseBoonsFromRollString(context.roll)

    if edges == 0 and banes == 0 then
        edges, banes = DiceRollLogic.SplitBoons(context.boons)
    end

    print(string.format("DV: onBeforeRoll - parsed edges=%d, banes=%d, multitargets=%s",
        edges, banes, tostring(context.multitargets and #context.multitargets or 0)))

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

    if DiceVision.connected and not DiceVision.isPolling then
        startPolling()
    end

    showWaitingDialog()
    chat.Send("[DiceVision] Waiting for physical dice...")

    return "intercept"
end

-- Register callback (guarded for load order)
if RollDialog then
    RollDialog.OnBeforeRoll = onBeforeRoll
end

print("DV: DiceVision script loaded")
