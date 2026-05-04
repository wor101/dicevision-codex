--[[
    DiceVision Integration for MCDM Codex - MINIMAL TEST
]]

local _ = dmhub.GetModLoading() -- luacheck: ignore

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
        local raw = die.rawValue
        if raw ~= nil and tostring(raw) ~= tostring(die.value) then
            table.insert(parts, string.format("%s:'%s'->%s", die.type, tostring(raw), tostring(die.value)))
        else
            table.insert(parts, string.format("%s:%s", die.type, tostring(die.value)))
        end
    end
    return table.concat(parts, ", ")
end
DiceVision.formatDice = formatDice

local function formatRollForChat(rollData)
    local diceStr = formatDice(rollData.dice)
    return string.format("[DiceVision] %s = %d", diceStr, rollData.total)
end
DiceVision.formatRollForChat = formatRollForChat

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
DiceVisionRollMessage.isPercentile = false

function DiceVisionRollMessage.CreateDiePanel(faces, value, dropped)
    local diceStyle = dmhub.GetDiceStyling(
        dmhub.GetSettingValue("diceequipped"),
        dmhub.GetSettingValue("playercolor")
    )
    local sat = dropped and 0.3 or 0.7
    local bright = dropped and 0.2 or 0.4
    local labelColor = dropped and "#888888" or (diceStyle.color or "#ffffff")
    return gui.Panel{
        width = 40,
        height = 40,
        halign = "center",
        valign = "center",
        bgimage = string.format("ui-icons/d%d-filled.png", faces),
        bgcolor = diceStyle.bgcolor or "#2d5a2d",
        saturation = sat,
        brightness = bright,
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
                color = labelColor,
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
    local isPercentile = self:try_get("isPercentile") or false

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
    for _, die in ipairs(dice) do
        local faces = die.faces or 10
        local value = die.value or 0
        local dropped = die.dropped or false
        dicePanels[#dicePanels+1] = DiceVisionRollMessage.CreateDiePanel(faces, value, dropped)
    end

    if isPercentile then
        dicePanels[#dicePanels+1] = gui.Label{
            width = "auto",
            height = 40,
            halign = "center",
            valign = "center",
            textAlignment = "center",
            fontSize = 16,
            bold = true,
            color = "#aaaaaa",
            text = "d100",
            lmargin = 6,
        }
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
        width = 80,
        height = 50,
        halign = "right",
        valign = "center",
        textAlignment = "center",
        fontSize = 36,
        bold = true,
        color = "#ffffff",
        text = tostring(total),
    }

    local tierLabel = nil
    if rollSource ~= "panel" then
        local tierRangeLabel = DiceVisionRollMessage.GetTierLabel(tier)
        tierLabel = gui.Label{
            width = "100%",
            height = "auto",
            fontSize = 14,
            color = "#888888",
            tmargin = 4,
            text = string.format("%s    tier %d result", tierRangeLabel, tier),
        }
    end

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
local abandonPendingRoll    -- Used by longPollForRolls, setMode
local handlePendingRoll     -- Used by handleDiceVisionRoll
local postRollToChat        -- Used by handleDiceVisionRoll
local longPollForRolls      -- Recursive call
local onBeforeRoll          -- Used by /dv connect, registered on RollDialog.OnBeforeRoll
local onReroll              -- Used by /dv connect, registered on RollDialog.OnReroll
local onBeforeTableRoll     -- Used by /dv connect, registered on RollDialog.OnBeforeTableRoll

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

local function handleSessionExpired() -- luacheck: ignore
    chat.Send("[DiceVision] Session expired. Use /dv connect <code> to reconnect.")
    stopPolling()
    removeRollInterceptor()
    DiceVision.connected = false
    DiceVision.mode = "off"
    DiceVision.sessionCode = nil
end

local function handleDiceVisionRoll(rollData)
    -- Build new dice tables from API response (net.Get tables don't support assignment)
    local convertedDice = {}
    for i, die in ipairs(rollData.dice) do
        convertedDice[i] = {
            type = die.type,
            rawValue = die.value,  -- Preserve original string (e.g., "00", "30", "7")
            value = tonumber(die.value) or 0,
        }
    end
    rollData = { dice = convertedDice, total = rollData.total }

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

abandonPendingRoll = function()
    local pendingRoll = DiceVision.pendingRoll
    if not pendingRoll then return end
    local rollArgs = pendingRoll.rollArgs

    DiceVision.waitingForRoll = false
    DiceVision.pendingRoll = nil
    DiceVision.currentRequestId = generateRequestId()
    stopPolling()

    if pendingRoll.isReroll and pendingRoll.amendWithResult then
        if pendingRoll.setActiveRoll and pendingRoll.activeRoll then
            pendingRoll.setActiveRoll(pendingRoll.activeRoll)
        end
        pendingRoll.amendWithResult(pendingRoll.originalRoll)
    elseif pendingRoll.isTableRoll then
        printf("DV: table roll abandoned - tableName='%s', description='%s', originalRoll='%s', elapsedMs=%d",
            tostring(pendingRoll.tableName), tostring(pendingRoll.description),
            tostring(pendingRoll.originalRoll),
            math.floor(dmhub.Time() * 1000 - (DiceVision.rollStartTime or 0)))
        chat.Send("[DiceVision] Table roll abandoned. Re-trigger to retry.")
    elseif rollArgs then
        dmhub.Roll(rollArgs)
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
            -- (table rolls have no virtual fallback; abandonPendingRoll emits the
            -- table-roll-specific notice on its own).
            if DiceVision.waitingForRoll then
                if not (DiceVision.pendingRoll and DiceVision.pendingRoll.isTableRoll) then
                    chat.Send("[DiceVision] Physical dice timeout. Falling back to virtual dice...")
                end
                abandonPendingRoll()
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
            -- (table rolls have no virtual fallback; abandonPendingRoll emits the
            -- table-roll-specific notice on its own).
            if DiceVision.waitingForRoll then
                if not (DiceVision.pendingRoll and DiceVision.pendingRoll.isTableRoll) then
                    chat.Send("[DiceVision] Connection error. Falling back to virtual dice...")
                end
                abandonPendingRoll()
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

local function buildDiceMessage(rollDice, pendingRoll)
    local processedDice, droppedDice = DiceRollLogic.applyDiceRules(rollDice, pendingRoll)
    local diceForMessage = {}
    local diceSum = 0
    for _, die in ipairs(processedDice) do
        diceForMessage[#diceForMessage + 1] = {
            faces = DiceRollLogic.getDiceFaces(die.type),
            value = die.value,
            originalValue = die.originalValue,
        }
        diceSum = diceSum + die.value
    end
    if droppedDice and #droppedDice > 0 then
        local droppedValues = {}
        for _, die in ipairs(droppedDice) do
            diceForMessage[#diceForMessage + 1] = {
                faces = DiceRollLogic.getDiceFaces(die.type),
                value = die.value,
                originalValue = die.originalValue,
                dropped = true,
            }
            droppedValues[#droppedValues + 1] = tostring(die.value)
        end
        print("[DiceVision] Dropped dice: " .. table.concat(droppedValues, ", "))
    end
    return diceForMessage, diceSum
end

postRollToChat = function(rollData)
    -- Check for percentile (d100) pair before applying standard rules
    local percentile = DiceRollLogic.detectPercentilePair(rollData.dice)
    if percentile then
        local diceForMessage = {
            { faces = 10, value = tostring(percentile.tens.rawValue) },   -- "00" shows as "00"
            { faces = 10, value = tostring(percentile.units.rawValue) },  -- "7" shows as "7"
        }
        local total = percentile.total
        local tier = DiceRollLogic.calculateTier(total)
        local message = DiceVisionRollMessage.new{
            description = "Percentile Roll (d100)",
            dice = diceForMessage,
            modifier = 0,
            total = total,
            tier = tier,
            tokenid = DiceVision.panelTokenId,
            rollSource = "panel",
            isPercentile = true,
        }
        chat.SendCustom(message)
        DiceVision.panelTokenId = nil
        print(string.format("DV: postRollToChat - d100 detected, tens=%s units=%s total=%d tier=%d",
            tostring(percentile.tens.rawValue), tostring(percentile.units.rawValue), total, tier))
        return
    end

    -- Standard path: apply dice rules (including 0->10 mapping for standard d10s)
    local diceForMessage, diceSum = buildDiceMessage(rollData.dice, nil)
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

handlePendingRoll = function(rollData)
    if not DiceVision.pendingRoll then
        return false
    end
    local pendingRoll = DiceVision.pendingRoll
    DiceVision.pendingRoll = nil
    DiceVision.waitingForRoll = false
    DiceVision.currentRequestId = generateRequestId()

    -- Stop polling after roll is handled (for replace mode)
    if DiceVision.mode == "replace" then
        stopPolling()
    end

    local modifier = DiceRollLogic.extractModifierFromRoll(pendingRoll.originalRoll)
    print(string.format("DV: handlePendingRoll - originalRoll='%s', modifier=%d",
        tostring(pendingRoll.originalRoll), modifier))
    local diceForMessage, diceSum = buildDiceMessage(rollData.dice, pendingRoll)

    -- Table-roll path: completeWithResult takes an integer; no edge/bane/tier math
    if pendingRoll.isTableRoll then
        if not pendingRoll.completeWithResult then
            print(string.format("DV: ERROR - table roll missing completeWithResult; tableName='%s'",
                tostring(pendingRoll.tableName)))
            chat.Send("[DiceVision] Internal error: table roll callback missing. Re-trigger to retry.")
            return false
        end
        local percentile = DiceRollLogic.detectPercentilePair(rollData.dice)
        local total
        local isPercentile = false
        if percentile then
            total = percentile.total
            isPercentile = true
        else
            total = diceSum + modifier
        end
        local visualMessage = DiceVisionRollMessage.new{
            description = pendingRoll.description or "Table Roll",
            dice = diceForMessage,
            modifier = modifier,
            total = total,
            tier = nil,
            tokenid = pendingRoll.tokenid,
            rollSource = "table",
            isPercentile = isPercentile,
        }
        chat.SendCustom(visualMessage)
        pendingRoll.completeWithResult(total)
        return true
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
        modifier = modifier + edgeBaneMod,
        total = finalTotal,
        tier = tier,
        tokenid = tokenid,
        rollSource = "ability",
    }

    -- Re-roll path: use amendWithResult callback instead of dmhub.Roll
    if pendingRoll.isReroll and pendingRoll.amendWithResult then
        if pendingRoll.setActiveRoll and pendingRoll.activeRoll then
            pendingRoll.setActiveRoll(pendingRoll.activeRoll)
        end
        chat.SendCustom(visualMessage)
        pendingRoll.amendWithResult(tostring(finalTotal))
        return true
    end

    -- Shallow-copy the TOP LEVEL of rollArgs to isolate our deterministic-
    -- total mutations (roll/boons/banes/instant). Codex holds the same
    -- rollArgs reference in g_activeRollArgs; on un-updated Codex the
    -- re-roll dialog reads g_activeRollArgs.roll and amends with it, so
    -- mutating roll in place would make the amend re-roll a literal value
    -- and silently fail. The copy isolates that.
    --
    -- We do NOT copy rollArgs.properties: Codex's properties is a
    -- registered game type with metamethods (try_get etc.) and a shallow
    -- copy strips the metatable, breaking downstream code that calls
    -- properties:try_get(...) (ActionLogPanel, MCDMAbilityRollBehaviors).
    -- Keeping the same properties reference means our multitargets[1]
    -- mutation below leaks into the caller's properties, but that mutation
    -- pre-existed our copy fix and Codex already tolerates it.
    local rollArgsForDmhub = {}
    for k, v in pairs(rollArgs) do rollArgsForDmhub[k] = v end

    rollArgsForDmhub.instant = true

    print(string.format("DV: handlePendingRoll - isNonTargeted=%s, rollArgs.roll='%s'",
        tostring(isNonTargeted), tostring(rollArgs.roll)))

    if isNonTargeted then
        local boonsValue = edges - banes
        print("[DiceVision] Non-targeted roll detected. baseTotal:", baseTotal, "boonsValue:", boonsValue)
        if boonsValue ~= 0 and GameSystem and GameSystem.ApplyBoons then
            local rollWithBoons = GameSystem.ApplyBoons(tostring(baseTotal), boonsValue)
            print("[DiceVision] GameSystem.ApplyBoons('" .. tostring(baseTotal) .. "', " .. boonsValue .. ") returned: '" .. tostring(rollWithBoons) .. "'")
            rollArgsForDmhub.roll = rollWithBoons
        else
            print("[DiceVision] No boons to apply or GameSystem.ApplyBoons not available, using finalTotal:", finalTotal)
            rollArgsForDmhub.roll = tostring(finalTotal)
        end
    else
        local net = edges - banes
        rollArgsForDmhub.roll = tostring(baseTotal)
        if net > 0 then
            rollArgsForDmhub.boons = net
            rollArgsForDmhub.banes = 0
        elseif net < 0 then
            rollArgsForDmhub.boons = 0
            rollArgsForDmhub.banes = -net
        else
            rollArgsForDmhub.boons = 0
            rollArgsForDmhub.banes = 0
        end
        rollArgsForDmhub.properties = rollArgsForDmhub.properties or {}
        rollArgsForDmhub.properties.multitargets = pendingRoll.multitargets
        rollArgsForDmhub.properties.multitargets[1].boons = 0
        rollArgsForDmhub.properties.multitargets[1].banes = 0
    end

    local originalComplete = rollArgs.complete
    rollArgsForDmhub.complete = function(rollInfo)
        local net = edges - banes
        if net >= 2 or net <= -2 then
            local calculatedTier = DiceRollLogic.CalculateTierWithEdges(finalTotal, edges, banes)
            -- rollInfo is a Codex registered game type; direct .properties
            -- access could throw on subtypes that don't declare it, and the
            -- previous `or {}` fallback was broken (next line called :try_get
            -- on a plain table, crashing). Read defensively via try_get with
            -- a rawget fallback for plain-table stubs.
            local props = nil
            if type(rollInfo.try_get) == "function" then
                props = rollInfo:try_get("properties")
            elseif rollInfo then
                props = rawget(rollInfo, "properties")
            end
            if props and type(props.try_get) == "function"
                and not props:try_get("overrideTier") then
                -- TODO(verify in Phase 3): this assignment writes a
                -- (possibly-undeclared) field on a strict-typed
                -- RollProperties instance. If Codex's __newindex rejects
                -- undeclared writes, every tier-shift roll (net edges/banes
                -- >= ±2) crashes here. Phase 3 testing should specifically
                -- exercise edge-2 and bane-2 rolls to confirm this path is
                -- safe. If it isn't, wrap in pcall + log + chat fallback.
                props.overrideTier = calculatedTier
                rollInfo:UploadProperties(props)
            end
        end
        chat.SendCustom(visualMessage)
        if originalComplete then
            originalComplete(rollInfo)
        end
    end

    local roll = dmhub.Roll(rollArgsForDmhub)
    if pendingRoll.setActiveRoll and roll then
        pendingRoll.setActiveRoll(roll)
    end
    return true
end

-- Hooks DiceVision registers on RollDialog. Order here drives /dv status
-- and chat-warning ordering. spec.key indexes both DiceVision.codexDeclaredHooks
-- (the static snapshot of Codex's declarations) and DiceVision.hooksRegistered
-- (the runtime view of which slots are currently wired) -- see registerHooks.
local HOOK_SPECS = {
    { name = "OnBeforeRoll",      key = "ability", label = "ability rolls" },
    { name = "OnReroll",          key = "reroll",  label = "re-rolls" },
    { name = "OnBeforeTableRoll", key = "table",   label = "table rolls" },
}

local function getHookFn(specName)
    if specName == "OnBeforeRoll" then return onBeforeRoll end
    if specName == "OnReroll" then return onReroll end
    if specName == "OnBeforeTableRoll" then return onBeforeTableRoll end
end

-- Register hooks selectively: only assign to slots Codex declares.
-- Caches the result on DiceVision.hooksRegistered for /dv status. When
-- verbose=true, emits a chat warning per missing hook; the printf trail
-- fires unconditionally so the silent paths (load-time, internal setMode)
-- still leave a post-mortem record.
--
-- DiceVision.codexDeclaredHooks is a snapshot of Codex's original
-- declaration state, captured once on the first call and never re-derived
-- in production (test-reset is the only legal nilling -- see test_setup.lua).
-- Once DiceVision installs its hook functions the live RollDialog table no
-- longer reflects Codex's intent: any code that mutates the slots after
-- that point (removeRollInterceptor today; any future teardown path) writes
-- false into every slot. A live re-probe would then misread "a slot
-- DiceVision cleared on teardown" as "Codex declared this hook" and
-- silently re-wire a slot Codex never invokes. The /dv refresh command is
-- the user-visible escape hatch for legitimate re-probes (e.g. after a
-- Codex hot-reload changes which hooks are declared).
local function registerHooks(verbose)
    local registered = { ability = false, reroll = false, ["table"] = false }
    if not RollDialog then
        printf("DV: RollDialog global is nil; no hooks registered")
        if verbose then
            chat.Send("[DiceVision] Warning: RollDialog not available; physical dice will not intercept any rolls.")
        end
        -- Lock the snapshot so a future call does not re-derive from a
        -- newly-appearing-but-already-mutated RollDialog.
        if DiceVision.codexDeclaredHooks == nil then
            DiceVision.codexDeclaredHooks = { ability = false, reroll = false, ["table"] = false }
        end
        DiceVision.hooksRegistered = registered
        return registered
    end
    if DiceVision.codexDeclaredHooks == nil then
        local snapshot = {}
        for _, spec in ipairs(HOOK_SPECS) do
            snapshot[spec.key] = (RollDialog[spec.name] ~= nil)
        end
        DiceVision.codexDeclaredHooks = snapshot
    end
    for _, spec in ipairs(HOOK_SPECS) do
        if not DiceVision.codexDeclaredHooks[spec.key] then
            printf("DV: hook RollDialog.%s missing; %s will use virtual dice", spec.name, spec.label)
            if verbose then
                chat.Send(string.format(
                    "[DiceVision] Warning: Codex does not expose RollDialog.%s (hook missing); %s will use virtual dice. (Requires a Codex build that declares this hook.)",
                    spec.name, spec.label))
            end
        else
            RollDialog[spec.name] = getHookFn(spec.name)
            registered[spec.key] = true
        end
    end
    DiceVision.hooksRegistered = registered
    return registered
end

removeRollInterceptor = function()
    DiceVision.pendingRoll = nil
    DiceVision.waitingForRoll = false
    DiceVision.currentRequestId = nil
    DiceVision.hooksRegistered = { ability = false, reroll = false, ["table"] = false }
    if RollDialog then
        -- Only clear slots Codex originally declared. Slots that were nil
        -- pre-load must stay nil so a future snapshot re-capture (e.g.,
        -- across a Codex mod-reload where codexDeclaredHooks resets but
        -- RollDialog persists) correctly identifies them as undeclared.
        local declared = DiceVision.codexDeclaredHooks
            or { ability = true, reroll = true, ["table"] = true }
        for _, spec in ipairs(HOOK_SPECS) do
            if declared[spec.key] then
                RollDialog[spec.name] = false
            end
        end
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

-- Public mode setter (used by /dv mode command and DVDicePanel toggle).
-- Pass verbose=true on user-driven transitions to "replace" so missing-hook
-- warnings surface to chat. Internal/setup callers default to silent.
DiceVision.setMode = function(newMode, verbose)
    if newMode ~= "off" and newMode ~= "replace" then
        return false
    end
    local oldMode = DiceVision.mode
    if oldMode == newMode then return true end

    DiceVision.mode = newMode

    if newMode == "off" then
        -- If a pending ability roll exists, fall back to virtual dice
        abandonPendingRoll()
        stopPolling()
        removeRollInterceptor()
    elseif newMode == "replace" then
        registerHooks(verbose == true)
    end

    return true
end

-- Panel-toggle entry point (called from DVDicePanel.lua). Extracted from
-- the panel click handler so this exact contract -- "compute opposite mode,
-- pass verbose on replace, emit confirmation chat" -- has a unit-testable
-- seam. Guards on DiceVision.connected internally so any future caller
-- cannot silently bypass the precondition. Returns the new mode for tests
-- to assert toggle direction without re-reading DiceVision.mode; the panel
-- currently ignores it. If a UI caller starts consuming this, treat as
-- load-bearing public API.
DiceVision._panelToggle = function()
    if not DiceVision.connected then
        printf("DV: _panelToggle called while disconnected; ignoring")
        return nil
    end
    local oldMode = DiceVision.mode
    local newMode = (oldMode == "replace") and "off" or "replace"
    DiceVision.setMode(newMode, newMode == "replace")
    chat.Send("[DiceVision] Mode changed: " .. oldMode .. " -> " .. newMode)
    return newMode
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
                DiceVision.mode = "replace"
                -- Probe-and-register: warn the user about any hook the Codex
                -- install is missing so they know which roll types will fall
                -- back to virtual dice.
                registerHooks(true)
                chat.Send("[DiceVision] Connected! Ready to capture dice rolls.")
            else
                chat.Send("[DiceVision] Connection failed: " .. tostring(result))
                DiceVision.sessionCode = nil
            end
        end)

    elseif subcommand == "disconnect" then
        abandonPendingRoll()
        stopPolling()
        removeRollInterceptor()
        DiceVision.sessionCode = nil
        DiceVision.connected = false
        DiceVision.mode = "off"
        chat.Send("[DiceVision] Disconnected")

    elseif subcommand == "status" then
        local hooks = DiceVision.hooksRegistered
            or { ability = false, reroll = false, ["table"] = false }
        local function yn(v) return v and "YES" or "NO" end
        local missing = {}
        for _, spec in ipairs(HOOK_SPECS) do
            if not hooks[spec.key] then
                missing[#missing + 1] = "RollDialog." .. spec.name
            end
        end
        local status = string.format(
            "[DiceVision] Status:\n  Connected: %s\n  Session: %s\n  Mode: %s\n  Polling: %s\n  Hooks: ability=%s, reroll=%s, table=%s",
            tostring(DiceVision.connected),
            DiceVision.sessionCode or "none",
            DiceVision.mode,
            tostring(DiceVision.isPolling),
            yn(hooks.ability), yn(hooks.reroll), yn(hooks["table"])
        )
        if #missing > 0 then
            status = status .. "\n  Missing Codex hooks: " .. table.concat(missing, ", ")
        end
        chat.Send(status)

    elseif subcommand == "refresh" then
        -- Drop the cached snapshot so the next register reads RollDialog
        -- afresh. The user-visible escape hatch for two failure shapes:
        -- (1) Codex hot-reload changes which hooks are declared,
        -- (2) snapshot was locked all-false at first probe (RollDialog nil,
        -- or RollDialog present but no hook slots declared yet).
        printf("DV: /dv refresh invoked")
        DiceVision.codexDeclaredHooks = nil
        registerHooks(true)
        chat.Send("[DiceVision] Hook probe refreshed. See /dv status for current state.")

    elseif subcommand == "mode" then
        local newMode = parts[2]
        if not newMode or (newMode ~= "off" and newMode ~= "replace") then
            chat.Send("[DiceVision] Usage: /dv mode <off|replace>")
            chat.Send("[DiceVision] Current mode: " .. DiceVision.mode)
            return
        end

        local oldMode = DiceVision.mode
        if oldMode == newMode then
            chat.Send("[DiceVision] Already in mode " .. newMode .. ". Use /dv refresh to re-probe Codex hooks.")
        else
            -- User-driven mode change: surface missing-hook warnings on the
            -- replace transition so the player sees the same diagnostic as
            -- /dv connect.
            DiceVision.setMode(newMode, newMode == "replace")
            chat.Send("[DiceVision] Mode changed: " .. oldMode .. " -> " .. newMode)
        end

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
  /dv status          - Show connection status (includes Codex hook state)
  /dv mode <mode>     - Set mode: off or replace
  /dv refresh         - Re-probe Codex hooks (use after Codex update)
  /dv rules           - Configure dice processing rules
  /dv test            - Test API connection

Modes:
  off     - DiceVision disabled
  replace - Physical rolls replace virtual dice

Codex requirements:
  DiceVision uses three RollDialog hooks. Missing hooks fall back to
  virtual dice for that roll type only.
    OnBeforeRoll       - ability rolls
    OnReroll           - re-rolls
    OnBeforeTableRoll  - random table lookups
  Run /dv status to see which hooks the current Codex install supports.
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
        chat.Send("[DiceVision] Another roll is in progress; this roll will use virtual dice.")
        return nil
    end

    -- Codex compatibility check: setActiveRoll is required for re-rolls of
    -- intercepted rolls to work. Without it, g_activeRoll stays nil after
    -- our intercept and the re-roll button silently bails. The integration
    -- branch passes this callback; un-updated Codex does not. Warn once so
    -- the user understands why re-roll fails. We still intercept so the
    -- initial roll gets physical dice.
    if not context.setActiveRoll then
        printf("DV: onBeforeRoll context missing setActiveRoll; re-rolls of intercepted rolls will not work")
        if not DiceVision.warnedMissingSetActiveRoll then
            DiceVision.warnedMissingSetActiveRoll = true
            chat.Send("[DiceVision] Note: Codex's OnBeforeRoll does not pass setActiveRoll. Re-rolls of intercepted rolls will silently fail until Codex is updated. (This message appears once per session.)")
        end
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
        setActiveRoll = context.setActiveRoll,
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

-- ============================================================================
-- RollDialog.OnReroll Callback (official Codex hook API)
-- ============================================================================

onReroll = function(hookData)
    if not hookData then return nil end
    if not DiceVision then return nil end

    if DiceVision.mode ~= "replace" or not DiceVision.connected then
        return nil
    end

    if DiceVision.waitingForRoll then
        chat.Send("[DiceVision] Another roll is in progress; this roll will use virtual dice.")
        return nil
    end

    print(string.format("DV: onReroll - originalRoll='%s', description='%s'",
        tostring(hookData.originalRoll), tostring(hookData.rollArgs and hookData.rollArgs.description)))

    local edges, banes = DiceRollLogic.ParseBoonsFromRollString(hookData.originalRoll)

    if edges == 0 and banes == 0 and hookData.rollArgs then
        edges, banes = DiceRollLogic.SplitBoons(hookData.rollArgs.boons)
    end

    print(string.format("DV: onReroll - parsed edges=%d, banes=%d", edges, banes))

    -- properties is a RollProperties registered type with strict field
    -- access -- direct .multitargets read throws "Attempt to read
    -- unknown field multitargets in type RollProperties" on instances
    -- where Codex never assigned the field (multitargets is set
    -- imperatively only on multi-target rolls; single-target ability
    -- checks never set it). try_get safely returns nil for missing
    -- fields. Falls back to rawget (which bypasses metamethods) for
    -- plain-table inputs that don't define try_get -- typically test
    -- stubs.
    local rollProps = hookData.rollArgs and hookData.rollArgs.properties
    local multitargets = nil
    if rollProps then
        if type(rollProps.try_get) == "function" then
            multitargets = rollProps:try_get("multitargets")
        else
            multitargets = rawget(rollProps, "multitargets")
        end
    end

    DiceVision.pendingRoll = {
        rollArgs = hookData.rollArgs,
        originalRoll = hookData.originalRoll,
        description = hookData.rollArgs and hookData.rollArgs.description,
        edges = edges,
        banes = banes,
        multitargets = multitargets,
        isReroll = true,
        amendWithResult = hookData.amendWithResult,
        activeRoll = hookData.activeRoll,
        setActiveRoll = hookData.setActiveRoll,
    }

    DiceVision.waitingForRoll = true
    DiceVision.rollStartTime = dmhub.Time() * 1000
    DiceVision.currentRequestId = generateRequestId()

    if DiceVision.connected and not DiceVision.isPolling then
        startPolling()
    end

    showWaitingDialog()
    chat.Send("[DiceVision] Waiting for physical dice (re-roll)...")

    return "intercept"
end

-- ============================================================================
-- RollDialog.OnBeforeTableRoll Callback (table roll interception)
-- ============================================================================

onBeforeTableRoll = function(hookData)
    if not hookData then return nil end
    if not DiceVision then return nil end

    if DiceVision.mode ~= "replace" or not DiceVision.connected then
        return nil
    end

    if DiceVision.waitingForRoll then
        chat.Send("[DiceVision] Another roll is in progress; this roll will use virtual dice.")
        return nil
    end

    print(string.format("DV: onBeforeTableRoll - roll='%s', tableName='%s', description='%s'",
        tostring(hookData.roll), tostring(hookData.tableName), tostring(hookData.description)))

    DiceVision.pendingRoll = {
        originalRoll = hookData.roll,
        description = hookData.description or hookData.tableName,
        tokenid = hookData.tokenid,
        tableRef = hookData.tableRef,
        tableName = hookData.tableName,
        guid = hookData.guid,
        completeWithResult = hookData.completeWithResult,
        isTableRoll = true,
    }

    DiceVision.waitingForRoll = true
    DiceVision.rollStartTime = dmhub.Time() * 1000
    DiceVision.currentRequestId = generateRequestId()

    if DiceVision.connected and not DiceVision.isPolling then
        startPolling()
    end

    showWaitingDialog()
    chat.Send("[DiceVision] Waiting for physical dice (table roll)...")

    return "intercept"
end

-- Register callbacks at load time. Silent: the user has not opted in yet
-- (no /dv connect), so any missing-hook warning would be noise. The cached
-- DiceVision.hooksRegistered still reflects what got wired, so /dv status
-- can report it accurately even before the first connect.
registerHooks(false)

print("DV: DiceVision script loaded")
