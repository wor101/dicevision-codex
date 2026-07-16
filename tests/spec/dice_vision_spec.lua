-- Tests for DiceVision (Codex/mods/DiceVision_5554/DiceVision.lua)

describe("DiceVision", function()
    setup(function()
        loadDiceVision()
    end)

    before_each(function()
        resetDiceVisionState()
    end)

    -- Shared across the contract blocks below: true if any sent chat message
    -- contains substr (plain-text, not a Lua pattern).
    local function chatHas(substr)
        for _, entry in ipairs(_G._chatLog) do
            if entry.type == "send" and string.find(entry.message, substr, 1, true) then
                return true
            end
        end
        return false
    end

    -- ============================================================================
    -- Category 1: Pure Utility Functions
    -- ============================================================================

    describe("formatDice", function()
        it("formats a single die", function()
            local result = DiceVision.formatDice({{type = "d10", value = 5}})
            assert.are.equal("d10:5", result)
        end)

        it("formats multiple dice of same type", function()
            local result = DiceVision.formatDice({
                {type = "d10", value = 5},
                {type = "d10", value = 3},
            })
            assert.are.equal("d10:5, d10:3", result)
        end)

        it("formats mixed die types", function()
            local result = DiceVision.formatDice({
                {type = "d10", value = 7},
                {type = "d6", value = 4},
            })
            assert.are.equal("d10:7, d6:4", result)
        end)

        it("returns empty string for empty array", function()
            assert.are.equal("", DiceVision.formatDice({}))
        end)

        it("formats a die with value 0", function()
            local result = DiceVision.formatDice({{type = "d10", value = 0}})
            assert.are.equal("d10:0", result)
        end)

        it("shows rawValue arrow notation when rawValue differs from value", function()
            local result = DiceVision.formatDice({{type = "d10", value = 0, rawValue = "00"}})
            assert.are.equal("d10:'00'->0", result)
        end)

        it("does not show rawValue when it matches value as string", function()
            local result = DiceVision.formatDice({{type = "d10", value = 5, rawValue = "5"}})
            assert.are.equal("d10:5", result)
        end)

        it("formats mixed raw and normal dice", function()
            local result = DiceVision.formatDice({
                {type = "d10", value = 0, rawValue = "00"},
                {type = "d10", value = 7, rawValue = "7"},
            })
            assert.are.equal("d10:'00'->0, d10:7", result)
        end)
    end)

    describe("formatRollForChat", function()
        it("formats a basic roll summary", function()
            local rollData = {
                dice = {{type = "d10", value = 5}, {type = "d10", value = 3}},
                total = 8,
            }
            assert.are.equal("[DiceVision] d10:5, d10:3 = 8", DiceVision.formatRollForChat(rollData))
        end)

        it("formats a single die with zero total", function()
            local rollData = {
                dice = {{type = "d10", value = 0}},
                total = 0,
            }
            assert.are.equal("[DiceVision] d10:0 = 0", DiceVision.formatRollForChat(rollData))
        end)

        it("formats a roll with large total", function()
            local rollData = {
                dice = {
                    {type = "d10", value = 10},
                    {type = "d10", value = 8},
                    {type = "d10", value = 7},
                },
                total = 25,
            }
            assert.are.equal("[DiceVision] d10:10, d10:8, d10:7 = 25", DiceVision.formatRollForChat(rollData))
        end)
    end)

    describe("GetTierLabel", function()
        it("returns '11 or lower' for tier 1", function()
            assert.are.equal("11 or lower", DiceVisionRollMessage.GetTierLabel(1))
        end)

        it("returns '12-16' for tier 2", function()
            assert.are.equal("12-16", DiceVisionRollMessage.GetTierLabel(2))
        end)

        it("returns '17 or higher' for tier 3", function()
            assert.are.equal("17 or higher", DiceVisionRollMessage.GetTierLabel(3))
        end)

        it("returns '17 or higher' for tier values above 3", function()
            assert.are.equal("17 or higher", DiceVisionRollMessage.GetTierLabel(4))
        end)
    end)

    -- ============================================================================
    -- Category 2: Rules Command Logic
    -- ============================================================================

    describe("rules map", function()
        it("adds a value mapping and sends confirmation", function()
            Commands.dv("rules map d6 0 6")
            assert.are.equal(6, DiceVision.rules.valueMappings["d6"][0])
            assert.are.equal(1, #_G._chatLog)
            assert.truthy(string.find(_G._chatLog[1].message, "Mapped d6: 0 %-> 6"))
        end)

        it("overwrites existing mapping for same die and value", function()
            Commands.dv("rules map d10 0 10")
            Commands.dv("rules map d10 0 20")
            assert.are.equal(20, DiceVision.rules.valueMappings["d10"][0])
        end)

        it("preserves existing mappings for same die type", function()
            Commands.dv("rules map d10 0 10")
            Commands.dv("rules map d10 1 11")
            assert.are.equal(10, DiceVision.rules.valueMappings["d10"][0])
            assert.are.equal(11, DiceVision.rules.valueMappings["d10"][1])
        end)

        it("shows usage when args are missing", function()
            Commands.dv("rules map")
            assert.are.equal(1, #_G._chatLog)
            assert.truthy(string.find(_G._chatLog[1].message, "Usage"))
        end)

        it("shows usage when only die type is given", function()
            Commands.dv("rules map d10")
            assert.truthy(string.find(_G._chatLog[1].message, "Usage"))
        end)
    end)

    describe("rules keep", function()
        it("sets keep highest with count", function()
            Commands.dv("rules keep highest 2")
            assert.is_not_nil(DiceVision.rules.diceSelection)
            assert.are.equal("highest", DiceVision.rules.diceSelection.keep)
            assert.are.equal(2, DiceVision.rules.diceSelection.count)
        end)

        it("sets keep lowest with count", function()
            Commands.dv("rules keep lowest 1")
            assert.is_not_nil(DiceVision.rules.diceSelection)
            assert.are.equal("lowest", DiceVision.rules.diceSelection.keep)
            assert.are.equal(1, DiceVision.rules.diceSelection.count)
        end)

        it("sends confirmation when setting keep mode", function()
            Commands.dv("rules keep highest 3")
            assert.are.equal(1, #_G._chatLog)
            assert.truthy(string.find(_G._chatLog[1].message, "keep highest 3"))
        end)

        it("clears with auto", function()
            DiceVision.rules.diceSelection = {keep = "highest", count = 2}
            Commands.dv("rules keep auto")
            assert.is_nil(DiceVision.rules.diceSelection)
            assert.truthy(string.find(_G._chatLog[1].message, "auto%-detect"))
        end)

        it("clears with clear", function()
            DiceVision.rules.diceSelection = {keep = "lowest", count = 1}
            Commands.dv("rules keep clear")
            assert.is_nil(DiceVision.rules.diceSelection)
        end)

        it("shows usage when args are missing", function()
            Commands.dv("rules keep")
            assert.truthy(string.find(_G._chatLog[1].message, "Usage"))
        end)

        it("shows usage when count is missing for highest", function()
            Commands.dv("rules keep highest")
            assert.truthy(string.find(_G._chatLog[1].message, "Usage"))
        end)
    end)

    describe("rules clamp", function()
        it("enables clamping with on", function()
            Commands.dv("rules clamp on")
            assert.is_true(DiceVision.rules.clampOutOfRange)
            assert.truthy(string.find(_G._chatLog[1].message, "enabled"))
        end)

        it("disables clamping with off", function()
            DiceVision.rules.clampOutOfRange = true
            Commands.dv("rules clamp off")
            assert.is_false(DiceVision.rules.clampOutOfRange)
            assert.truthy(string.find(_G._chatLog[1].message, "disabled"))
        end)

        it("shows current status with no argument", function()
            DiceVision.rules.clampOutOfRange = false
            Commands.dv("rules clamp")
            assert.truthy(string.find(_G._chatLog[1].message, "disabled"))
        end)

        it("shows enabled status when active", function()
            DiceVision.rules.clampOutOfRange = true
            Commands.dv("rules clamp")
            assert.truthy(string.find(_G._chatLog[1].message, "enabled"))
        end)
    end)

    describe("rules clear", function()
        it("resets to defaults with d10 0->10 mapping", function()
            -- Add custom rules first
            DiceVision.rules.valueMappings["d6"] = {[0] = 6}
            DiceVision.rules.clampOutOfRange = true
            Commands.dv("rules clear")
            -- Default d10 mapping restored
            assert.are.equal(10, DiceVision.rules.valueMappings["d10"][0])
            -- Custom d6 mapping removed
            assert.is_nil(DiceVision.rules.valueMappings["d6"])
            -- Clamp reset
            assert.is_false(DiceVision.rules.clampOutOfRange)
            -- Dice selection cleared
            assert.is_nil(DiceVision.rules.diceSelection)
            assert.truthy(string.find(_G._chatLog[1].message, "defaults"))
        end)

        it("clear all removes everything including defaults", function()
            Commands.dv("rules clear all")
            assert.is_nil(DiceVision.rules.valueMappings["d10"])
            assert.is_nil(next(DiceVision.rules.valueMappings))
            assert.is_false(DiceVision.rules.clampOutOfRange)
            assert.truthy(string.find(_G._chatLog[1].message, "All rules cleared"))
        end)
    end)

    describe("rules show", function()
        it("displays current rules header", function()
            Commands.dv("rules show")
            assert.are.equal(1, #_G._chatLog)
            local msg = _G._chatLog[1].message
            assert.truthy(string.find(msg, "Current rules"))
        end)

        it("shows value mappings", function()
            Commands.dv("rules show")
            local msg = _G._chatLog[1].message
            assert.truthy(string.find(msg, "d10"))
            assert.truthy(string.find(msg, "0 %-> 10"))
        end)

        it("shows auto-detect when no dice selection set", function()
            Commands.dv("rules show")
            local msg = _G._chatLog[1].message
            assert.truthy(string.find(msg, "auto%-detect"))
        end)

        it("shows dice selection when set", function()
            DiceVision.rules.diceSelection = {keep = "highest", count = 2}
            Commands.dv("rules show")
            local msg = _G._chatLog[1].message
            assert.truthy(string.find(msg, "keep highest 2"))
        end)

        it("shows clamping status", function()
            Commands.dv("rules show")
            local msg = _G._chatLog[1].message
            assert.truthy(string.find(msg, "disabled"))
        end)

        it("shows 'none' when no mappings exist", function()
            DiceVision.rules.valueMappings = {}
            Commands.dv("rules show")
            local msg = _G._chatLog[1].message
            assert.truthy(string.find(msg, "none"))
        end)
    end)

    describe("rules with no subcommand", function()
        it("shows rules help text", function()
            Commands.dv("rules")
            assert.are.equal(1, #_G._chatLog)
            local msg = _G._chatLog[1].message
            assert.truthy(string.find(msg, "Rule commands"))
            assert.truthy(string.find(msg, "rules show"))
            assert.truthy(string.find(msg, "rules map"))
        end)
    end)

    -- ============================================================================
    -- Category 3: State Management
    -- ============================================================================

    describe("DiceVision.setMode", function()
        it("returns false for invalid mode", function()
            assert.is_false(DiceVision.setMode("invalid"))
        end)

        it("returns false for nil mode", function()
            assert.is_false(DiceVision.setMode(nil))
        end)

        it("returns true for valid 'replace' mode", function()
            assert.is_true(DiceVision.setMode("replace"))
        end)

        it("returns true for valid 'off' mode from replace", function()
            DiceVision.mode = "replace"
            assert.is_true(DiceVision.setMode("off"))
        end)

        it("returns true without state change when mode is already set", function()
            DiceVision.mode = "replace"
            local originalOnBeforeRoll = RollDialog.OnBeforeRoll
            assert.is_true(DiceVision.setMode("replace"))
            -- Should not have changed RollDialog
            assert.are.equal(originalOnBeforeRoll, RollDialog.OnBeforeRoll)
        end)

        it("sets DiceVision.mode correctly", function()
            DiceVision.setMode("replace")
            assert.are.equal("replace", DiceVision.mode)
            DiceVision.setMode("off")
            assert.are.equal("off", DiceVision.mode)
        end)

        it("registers RollDialog.OnBeforeRoll when switching to replace", function()
            DiceVision.setMode("replace")
            assert.is_function(RollDialog.OnBeforeRoll)
        end)

        it("stops polling when switching to off", function()
            DiceVision.mode = "replace"
            DiceVision.isPolling = true
            DiceVision.setMode("off")
            assert.is_false(DiceVision.isPolling)
        end)

        it("removes roll interceptor when switching to off", function()
            DiceVision.mode = "replace"
            RollDialog.OnBeforeRoll = function() end
            DiceVision.setMode("off")
            assert.is_false(RollDialog.OnBeforeRoll)
            assert.is_nil(DiceVision.pendingRoll)
            assert.is_false(DiceVision.waitingForRoll)
            assert.is_nil(DiceVision.currentRequestId)
        end)

        it("falls back to dmhub.Roll when pending roll exists on switch to off", function()
            DiceVision.mode = "replace"
            DiceVision.waitingForRoll = true
            DiceVision.pendingRoll = {rollArgs = {roll = "2d10+5"}}
            DiceVision.setMode("off")
            assert.are.equal(1, #_G._dmhubRollLog)
            assert.are.equal("2d10+5", _G._dmhubRollLog[1].roll)
        end)

        it("does not call dmhub.Roll when no pending roll on switch to off", function()
            DiceVision.mode = "replace"
            DiceVision.setMode("off")
            assert.are.equal(0, #_G._dmhubRollLog)
        end)

        it("clears waitingForRoll after fallback to virtual dice", function()
            DiceVision.mode = "replace"
            DiceVision.waitingForRoll = true
            DiceVision.pendingRoll = {rollArgs = {roll = "2d10"}}
            DiceVision.setMode("off")
            assert.is_false(DiceVision.waitingForRoll)
            assert.is_nil(DiceVision.pendingRoll)
        end)

        it("does not call dmhub.Roll when pendingRoll has no rollArgs", function()
            DiceVision.mode = "replace"
            DiceVision.waitingForRoll = true
            DiceVision.pendingRoll = {rollArgs = nil}
            DiceVision.setMode("off")
            assert.are.equal(0, #_G._dmhubRollLog)
        end)
    end)

    describe("disconnect command", function()
        it("resets session state", function()
            DiceVision.sessionCode = "ABC123"
            DiceVision.connected = true
            DiceVision.mode = "replace"
            Commands.dv("disconnect")
            assert.is_nil(DiceVision.sessionCode)
            assert.is_false(DiceVision.connected)
            assert.are.equal("off", DiceVision.mode)
        end)

        it("clears pending roll state", function()
            DiceVision.pendingRoll = {rollArgs = {}}
            DiceVision.waitingForRoll = true
            DiceVision.currentRequestId = "test-123"
            Commands.dv("disconnect")
            assert.is_nil(DiceVision.pendingRoll)
            assert.is_false(DiceVision.waitingForRoll)
            assert.is_nil(DiceVision.currentRequestId)
        end)

        it("sets RollDialog.OnBeforeRoll to false", function()
            RollDialog.OnBeforeRoll = function() end
            Commands.dv("disconnect")
            assert.is_false(RollDialog.OnBeforeRoll)
        end)

        it("sets isPolling to false", function()
            DiceVision.isPolling = true
            Commands.dv("disconnect")
            assert.is_false(DiceVision.isPolling)
        end)

        it("sends disconnect confirmation message", function()
            Commands.dv("disconnect")
            assert.are.equal(1, #_G._chatLog)
            assert.truthy(string.find(_G._chatLog[1].message, "Disconnected"))
        end)
    end)

    describe("status command", function()
        it("sends status with connection info when connected", function()
            DiceVision.connected = true
            DiceVision.sessionCode = "ABC123"
            DiceVision.mode = "replace"
            DiceVision.isPolling = true
            Commands.dv("status")
            assert.are.equal(1, #_G._chatLog)
            local msg = _G._chatLog[1].message
            assert.truthy(string.find(msg, "true"))        -- connected
            assert.truthy(string.find(msg, "ABC123"))       -- session
            assert.truthy(string.find(msg, "replace"))      -- mode
        end)

        it("sends status with defaults when disconnected", function()
            Commands.dv("status")
            assert.are.equal(1, #_G._chatLog)
            local msg = _G._chatLog[1].message
            assert.truthy(string.find(msg, "false"))        -- not connected
            assert.truthy(string.find(msg, "none"))         -- no session
            assert.truthy(string.find(msg, "off"))          -- mode off
        end)
    end)

    -- ============================================================================
    -- Category 4: CreateDiePanel Styling
    -- ============================================================================

    describe("CreateDiePanel", function()
        it("uses normal styling when dropped is nil", function()
            local panel = DiceVisionRollMessage.CreateDiePanel(10, 7)
            assert.are.equal(0.7, panel.saturation)
            assert.are.equal(0.4, panel.brightness)
        end)

        it("uses normal styling when dropped is false", function()
            local panel = DiceVisionRollMessage.CreateDiePanel(10, 7, false)
            assert.are.equal(0.7, panel.saturation)
            assert.are.equal(0.4, panel.brightness)
        end)

        it("uses dimmed styling when dropped is true", function()
            local panel = DiceVisionRollMessage.CreateDiePanel(10, 7, true)
            assert.are.equal(0.3, panel.saturation)
            assert.are.equal(0.2, panel.brightness)
        end)

        it("uses dimmed label color when dropped is true", function()
            local panel = DiceVisionRollMessage.CreateDiePanel(10, 7, true)
            -- Inner panel is first array element, label is its first array element
            local innerPanel = panel[1]
            local label = innerPanel[1]
            assert.are.equal("#888888", label.color)
        end)

        it("uses normal label color when not dropped", function()
            local panel = DiceVisionRollMessage.CreateDiePanel(10, 7, false)
            local innerPanel = panel[1]
            local label = innerPanel[1]
            -- dmhub.GetDiceStyling returns {} in tests, so fallback is "#ffffff"
            assert.are.equal("#ffffff", label.color)
        end)

        it("renders a d3 on the d6 icon with the d3 value", function()
            -- No d3 icon exists; the card mirrors the official panel's
            -- "d3 uses the d6 model". Only the icon falls back - the
            -- value label must still show the d3 result.
            local panel = DiceVisionRollMessage.CreateDiePanel(3, 2)
            assert.are.equal("ui-icons/d6-filled.png", panel.bgimage)
            local innerPanel = panel[1]
            assert.are.equal("ui-icons/d6.png", innerPanel.bgimage)
            local label = innerPanel[1]
            assert.are.equal("2", label.text)
        end)

        it("does not remap icons for other face counts", function()
            local panel = DiceVisionRollMessage.CreateDiePanel(10, 7)
            assert.are.equal("ui-icons/d10-filled.png", panel.bgimage)
        end)
    end)

    -- ============================================================================
    -- Category 5: Dropped Dice in Chat Messages
    -- ============================================================================

    describe("postRollToChat with dropped dice", function()
        it("includes dropped dice in message when keep rule is active", function()
            -- Set up keep-lowest-2 rule
            DiceVision.rules.diceSelection = {keep = "lowest", count = 2}
            local rollData = {
                dice = {
                    {type = "d10", value = 8},
                    {type = "d10", value = 3},
                    {type = "d10", value = 5},
                },
                total = 16,
            }
            DiceVision.postRollToChat(rollData)
            assert.are.equal(1, #_G._chatLog)
            local msg = _G._chatLog[1].message
            local dice = msg.dice
            assert.are.equal(3, #dice)
            -- Count dropped vs kept
            local keptCount = 0
            local droppedCount = 0
            for _, die in ipairs(dice) do
                if die.dropped then
                    droppedCount = droppedCount + 1
                else
                    keptCount = keptCount + 1
                end
            end
            assert.are.equal(2, keptCount)
            assert.are.equal(1, droppedCount)
        end)

        it("total reflects only kept dice, not dropped", function()
            DiceVision.rules.diceSelection = {keep = "lowest", count = 2}
            local rollData = {
                dice = {
                    {type = "d10", value = 8},
                    {type = "d10", value = 3},
                    {type = "d10", value = 5},
                },
                total = 16,
            }
            DiceVision.postRollToChat(rollData)
            local msg = _G._chatLog[1].message
            -- Kept dice are the two lowest: 3 and 5 (after 0->10 mapping: 8,3,5 stay)
            -- Total should be sum of kept dice only
            local keptSum = 0
            for _, die in ipairs(msg.dice) do
                if not die.dropped then
                    keptSum = keptSum + die.value
                end
            end
            assert.are.equal(msg.total, keptSum)
        end)

        it("has no dropped entries without selection rule", function()
            DiceVision.rules.diceSelection = nil
            local rollData = {
                dice = {
                    {type = "d10", value = 3},
                    {type = "d10", value = 5},
                },
                total = 8,
            }
            DiceVision.postRollToChat(rollData)
            local msg = _G._chatLog[1].message
            for _, die in ipairs(msg.dice) do
                assert.is_falsy(die.dropped)
            end
        end)
    end)

    -- ============================================================================
    -- Category 6: onReroll Callback
    -- ============================================================================

    describe("onReroll callback", function()
        -- Capture the onReroll function before resetDiceVisionState clears it
        local onRerollFn
        before_each(function()
            DiceVision.setMode("replace")
            onRerollFn = RollDialog.OnReroll
            -- Reset state for each test
            resetDiceVisionState()
        end)

        it("returns nil when mode is off", function()
            DiceVision.mode = "off"
            DiceVision.connected = true
            local result = onRerollFn({
                originalRoll = "2d10+5",
                amendWithResult = function() end,
                rollArgs = { roll = "2d10+5", description = "Test" },
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            })
            assert.is_nil(result)
        end)

        it("returns nil when not connected", function()
            DiceVision.mode = "replace"
            DiceVision.connected = false
            local result = onRerollFn({
                originalRoll = "2d10+5",
                amendWithResult = function() end,
                rollArgs = { roll = "2d10+5", description = "Test" },
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            })
            assert.is_nil(result)
        end)

        it("returns nil when already waiting for a roll", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.waitingForRoll = true
            local result = onRerollFn({
                originalRoll = "2d10+5",
                amendWithResult = function() end,
                rollArgs = { roll = "2d10+5", description = "Test" },
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            })
            assert.is_nil(result)
        end)

        it("emits bypass chat notice when already waiting for a roll", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.waitingForRoll = true
            onRerollFn({
                originalRoll = "2d10+5",
                amendWithResult = function() end,
                rollArgs = { roll = "2d10+5", description = "Test" },
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            })
            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" and string.find(entry.message, "Another roll is in progress") then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("returns 'intercept' and sets pendingRoll with isReroll=true", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            local amendFn = function() end
            local activeRollObj = { id = "roll-1" }
            local setActiveRollFn = function() end
            local result = onRerollFn({
                originalRoll = "2d10+5",
                amendWithResult = amendFn,
                rollArgs = { roll = "2d10+5", boons = 0, description = "Test Reroll" },
                activeRoll = activeRollObj,
                setActiveRoll = setActiveRollFn,
            })
            assert.are.equal("intercept", result)
            assert.is_true(DiceVision.waitingForRoll)
            assert.is_not_nil(DiceVision.pendingRoll)
            assert.is_true(DiceVision.pendingRoll.isReroll)
            assert.are.equal(amendFn, DiceVision.pendingRoll.amendWithResult)
            assert.are.equal("Test Reroll", DiceVision.pendingRoll.description)
            assert.are.equal(activeRollObj, DiceVision.pendingRoll.activeRoll)
            assert.are.equal(setActiveRollFn, DiceVision.pendingRoll.setActiveRoll)
        end)

        it("gets description from rollArgs.description, not hookData.description", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            onRerollFn({
                originalRoll = "2d10+5",
                -- No top-level description (matches actual DSRollDialog hookData)
                amendWithResult = function() end,
                rollArgs = { roll = "2d10+5", boons = 0, description = "Ability: Power Roll" },
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            })
            assert.are.equal("Ability: Power Roll", DiceVision.pendingRoll.description)
        end)

        it("parses edges from originalRoll string", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            onRerollFn({
                originalRoll = "2d10+5 1 edge",
                amendWithResult = function() end,
                rollArgs = { roll = "2d10+5", boons = 0, description = "Test" },
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            })
            assert.are.equal(1, DiceVision.pendingRoll.edges)
            assert.are.equal(0, DiceVision.pendingRoll.banes)
        end)

        it("parses banes from originalRoll string", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            onRerollFn({
                originalRoll = "2d10+5 2 banes",
                amendWithResult = function() end,
                rollArgs = { roll = "2d10+5", boons = 0, description = "Test" },
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            })
            assert.are.equal(0, DiceVision.pendingRoll.edges)
            assert.are.equal(2, DiceVision.pendingRoll.banes)
        end)

        it("falls back to SplitBoons when roll string has no edges/banes", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            onRerollFn({
                originalRoll = "2d10+5",
                amendWithResult = function() end,
                rollArgs = { roll = "2d10+5", boons = 2, description = "Test" },
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            })
            assert.are.equal(2, DiceVision.pendingRoll.edges)
            assert.are.equal(0, DiceVision.pendingRoll.banes)
        end)

        it("sends re-roll waiting message to chat", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            onRerollFn({
                originalRoll = "2d10+5",
                amendWithResult = function() end,
                rollArgs = { roll = "2d10+5", boons = 0, description = "Test" },
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            })
            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if string.find(entry.message, "re%-roll") then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("uses try_get on properties when reading multitargets", function()
            -- Codex's RollProperties is a strict-typed registered game type.
            -- Direct field access throws "Attempt to read unknown field X
            -- in type RollProperties" for fields the active instance never
            -- had set. multitargets is set imperatively only on multi-
            -- target rolls (DSRollDialog.lua, EmbeddedRollDialog.lua);
            -- single-target ability checks never set it, so a direct
            -- read throws. onReroll must use try_get to safely return nil.
            DiceVision.mode = "replace"
            DiceVision.connected = true
            local rollPropsStrict = setmetatable({}, {
                __index = function(_, key)
                    error("Attempt to read unknown field " .. tostring(key)
                        .. " in type RollProperties")
                end,
            })
            -- Stub the registered-type's try_get directly so __index isn't
            -- consulted. (Real Codex stores try_get on the type's metatable
            -- chain; we approximate here.)
            rawset(rollPropsStrict, "try_get", function(self, key)
                return rawget(self, key)
            end)
            -- No multitargets field; try_get should return nil cleanly.
            assert.has_no.errors(function()
                onRerollFn({
                    originalRoll = "2d10+5",
                    amendWithResult = function() end,
                    rollArgs = {
                        roll = "2d10+5",
                        boons = 0,
                        description = "Ability Check",
                        properties = rollPropsStrict,
                    },
                    activeRoll = { id = "roll-1" },
                    setActiveRoll = function() end,
                })
            end)
            assert.is_nil(DiceVision.pendingRoll.multitargets)
        end)

        it("reads multitargets via try_get when properties is a typed object with the field", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            local fakeMultitargets = {
                { tokenid = "tok-1", boons = 2, banes = 0 },
            }
            local rollPropsWithMulti = {
                multitargets = fakeMultitargets,
                try_get = function(self, key) return rawget(self, key) end,
            }
            onRerollFn({
                originalRoll = "2d10+5",
                amendWithResult = function() end,
                rollArgs = {
                    roll = "2d10+5",
                    boons = 0,
                    description = "Targeted Ability",
                    properties = rollPropsWithMulti,
                },
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            })
            assert.are.equal(fakeMultitargets, DiceVision.pendingRoll.multitargets)
        end)
    end)

    -- ============================================================================
    -- Category 7: handlePendingRoll Re-roll Path
    -- ============================================================================

    describe("handlePendingRoll re-roll path", function()
        it("calls amendWithResult with finalTotal for re-rolls", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local amendCalled = nil
            local activeRollObj = { id = "roll-1" }
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Re-roll Test",
                edges = 0,
                banes = 0,
                isReroll = true,
                amendWithResult = function(val) amendCalled = val end,
                activeRoll = activeRollObj,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({
                        rolls = { rollData }
                    })
                end
            end

            DiceVision.isPolling = false
            DiceVision.startPolling()

            net.Get = originalNetGet

            -- baseTotal = 7+3+5 = 15 (no edge/bane mod applied)
            assert.is_not_nil(amendCalled)
            assert.are.equal("15", amendCalled)
            -- dmhub.Roll should NOT have been called
            assert.are.equal(0, #_G._dmhubRollLog)
        end)

        it("passes finalTotal with edge modifier for re-rolls", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local amendCalled = nil
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Re-roll Edge Test",
                edges = 1,
                banes = 0,
                isReroll = true,
                amendWithResult = function(val) amendCalled = val end,
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            -- finalTotal = 7+3+5+2 = 17 (edge mod +2 included)
            assert.are.equal("17", amendCalled)
        end)

        it("writes overrideTier on properties for 2-edge re-rolls before amend", function()
            -- Re-rolls bypass the dmhub.Roll complete-wrapper, so the
            -- tier-shift override (net edges/banes >= +/-2) must be set
            -- directly on the inherited properties before amendWithResult
            -- so the amend engine picks it up. Mirrors the initial-roll
            -- path's complete-callback behavior.
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local amendCalledAt = nil
            local props = {
                try_get = function(self, key) return rawget(self, key) end,
            }
            DiceVision.pendingRoll = {
                rollArgs = {
                    roll = "2d10+5",
                    creature = nil,
                    properties = props,
                },
                originalRoll = "2d10+5",
                description = "Re-roll 2 Edges",
                edges = 2,
                banes = 0,
                isReroll = true,
                amendWithResult = function(val)
                    -- Capture the overrideTier value at the moment amend
                    -- is invoked, so we verify the write happens BEFORE
                    -- amend (not after).
                    amendCalledAt = props.overrideTier
                end,
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            -- baseTotal = 7+3+5 = 15, T2 (12-16) -> +1 tier shift = T3
            local rollData = {
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.are.equal(3, amendCalledAt)
            assert.are.equal(3, props.overrideTier)
        end)

        it("does not write overrideTier on properties for 1-edge re-rolls", function()
            -- Net 1 is a flat +2 modifier, NOT a tier shift. No override.
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local props = {
                try_get = function(self, key) return rawget(self, key) end,
            }
            DiceVision.pendingRoll = {
                rollArgs = {
                    roll = "2d10+5",
                    creature = nil,
                    properties = props,
                },
                originalRoll = "2d10+5",
                description = "Re-roll 1 Edge",
                edges = 1,
                banes = 0,
                isReroll = true,
                amendWithResult = function() end,
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.is_nil(props.overrideTier)
        end)

        it("calls setActiveRoll before amendWithResult for re-rolls", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local callOrder = {}
            local activeRollObj = { id = "roll-1" }
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Re-roll Order Test",
                edges = 0,
                banes = 0,
                isReroll = true,
                amendWithResult = function() table.insert(callOrder, "amend") end,
                activeRoll = activeRollObj,
                setActiveRoll = function(roll)
                    table.insert(callOrder, "setActiveRoll")
                    assert.are.equal(activeRollObj, roll)
                end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.are.equal(2, #callOrder)
            assert.are.equal("setActiveRoll", callOrder[1])
            assert.are.equal("amend", callOrder[2])
        end)

        it("sends DiceVisionRollMessage to chat for re-rolls", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Re-roll Chat Test",
                edges = 0,
                banes = 0,
                isReroll = true,
                amendWithResult = function() end,
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            -- Check that a custom chat message was sent
            local customFound = false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "custom" and entry.message.description == "Re-roll Chat Test" then
                    customFound = true
                    break
                end
            end
            assert.is_true(customFound)
        end)

        it("does not call amendWithResult for non-reroll pending rolls", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Normal Roll",
                edges = 0,
                banes = 0,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            -- For non-reroll, dmhub.Roll should be called instead
            assert.are.equal(1, #_G._dmhubRollLog)
        end)
    end)

    -- ============================================================================
    -- Category 8: Fallback Paths for Re-rolls
    -- ============================================================================

    describe("fallback paths for re-rolls", function()
        it("timeout calls setActiveRoll then amendWithResult(originalRoll) for re-rolls", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local callOrder = {}
            local activeRollObj = { id = "roll-1" }
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5" },
                originalRoll = "2d10+5",
                description = "Timeout Reroll",
                edges = 0,
                banes = 0,
                isReroll = true,
                amendWithResult = function(val) table.insert(callOrder, {fn = "amend", val = val}) end,
                activeRoll = activeRollObj,
                setActiveRoll = function(roll) table.insert(callOrder, {fn = "setActiveRoll", val = roll}) end,
            }
            DiceVision.waitingForRoll = true

            -- Simulate net.Get success with no rolls (triggers timeout path)
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = {} })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.are.equal(2, #callOrder)
            assert.are.equal("setActiveRoll", callOrder[1].fn)
            assert.are.equal(activeRollObj, callOrder[1].val)
            assert.are.equal("amend", callOrder[2].fn)
            assert.are.equal("2d10+5", callOrder[2].val)
            assert.are.equal(0, #_G._dmhubRollLog)
        end)

        it("error calls setActiveRoll then amendWithResult(originalRoll) for re-rolls", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local callOrder = {}
            local activeRollObj = { id = "roll-1" }
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5" },
                originalRoll = "2d10+5",
                description = "Error Reroll",
                edges = 0,
                banes = 0,
                isReroll = true,
                amendWithResult = function(val) table.insert(callOrder, {fn = "amend", val = val}) end,
                activeRoll = activeRollObj,
                setActiveRoll = function(roll) table.insert(callOrder, {fn = "setActiveRoll", val = roll}) end,
            }
            DiceVision.waitingForRoll = true

            -- Simulate net.Get error
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.error then
                    args.error("connection failed", 500)
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.are.equal(2, #callOrder)
            assert.are.equal("setActiveRoll", callOrder[1].fn)
            assert.are.equal(activeRollObj, callOrder[1].val)
            assert.are.equal("amend", callOrder[2].fn)
            assert.are.equal("2d10+5", callOrder[2].val)
            assert.are.equal(0, #_G._dmhubRollLog)
        end)

        it("mode-off calls setActiveRoll then amendWithResult(originalRoll) for re-rolls", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            local callOrder = {}
            local activeRollObj = { id = "roll-1" }
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5" },
                originalRoll = "2d10+5",
                description = "Mode Off Reroll",
                edges = 0,
                banes = 0,
                isReroll = true,
                amendWithResult = function(val) table.insert(callOrder, {fn = "amend", val = val}) end,
                activeRoll = activeRollObj,
                setActiveRoll = function(roll) table.insert(callOrder, {fn = "setActiveRoll", val = roll}) end,
            }
            DiceVision.waitingForRoll = true

            DiceVision.setMode("off")

            assert.are.equal(2, #callOrder)
            assert.are.equal("setActiveRoll", callOrder[1].fn)
            assert.are.equal(activeRollObj, callOrder[1].val)
            assert.are.equal("amend", callOrder[2].fn)
            assert.are.equal("2d10+5", callOrder[2].val)
            assert.are.equal(0, #_G._dmhubRollLog)
        end)

        it("non-reroll timeout fallback still calls dmhub.Roll", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5" },
                originalRoll = "2d10+5",
                description = "Normal Timeout",
                edges = 0,
                banes = 0,
            }
            DiceVision.waitingForRoll = true

            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = {} })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.are.equal(1, #_G._dmhubRollLog)
            assert.are.equal("2d10+5", _G._dmhubRollLog[1].roll)
        end)

        it("non-reroll error fallback still calls dmhub.Roll", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5" },
                originalRoll = "2d10+5",
                description = "Normal Error",
                edges = 0,
                banes = 0,
            }
            DiceVision.waitingForRoll = true

            local originalNetGet = net.Get
            net.Get = function(args)
                if args.error then
                    args.error("connection failed", 500)
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.are.equal(1, #_G._dmhubRollLog)
            assert.are.equal("2d10+5", _G._dmhubRollLog[1].roll)
        end)

        it("non-reroll mode-off fallback still calls dmhub.Roll", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5" },
                originalRoll = "2d10+5",
                description = "Normal Mode Off",
                edges = 0,
                banes = 0,
            }
            DiceVision.waitingForRoll = true

            DiceVision.setMode("off")

            assert.are.equal(1, #_G._dmhubRollLog)
            assert.are.equal("2d10+5", _G._dmhubRollLog[1].roll)
        end)
    end)

    -- ============================================================================
    -- Category 9: onBeforeRoll stores setActiveRoll
    -- ============================================================================

    describe("onBeforeRoll setActiveRoll", function()
        local onBeforeRollFn
        before_each(function()
            DiceVision.setMode("replace")
            onBeforeRollFn = RollDialog.OnBeforeRoll
            resetDiceVisionState()
        end)

        it("stores setActiveRoll from context in pendingRoll", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            local setActiveRollFn = function() end
            onBeforeRollFn({
                roll = "2d10+5",
                description = "Test Ability",
                boons = 0,
                rollArgs = { roll = "2d10+5" },
                setActiveRoll = setActiveRollFn,
            })
            assert.are.equal(setActiveRollFn, DiceVision.pendingRoll.setActiveRoll)
        end)

        it("emits bypass chat notice when already waiting for a roll", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.waitingForRoll = true
            local result = onBeforeRollFn({
                roll = "2d10+5",
                description = "Test Ability",
                boons = 0,
                rollArgs = { roll = "2d10+5" },
                setActiveRoll = function() end,
            })
            assert.is_nil(result)
            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" and string.find(entry.message, "Another roll is in progress") then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("works when context has no setActiveRoll", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            onBeforeRollFn({
                roll = "2d10+5",
                description = "Test Ability",
                boons = 0,
                rollArgs = { roll = "2d10+5" },
            })
            assert.is_nil(DiceVision.pendingRoll.setActiveRoll)
        end)

        it("warns once when context.setActiveRoll is missing", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            -- First intercept on a Codex without setActiveRoll: should warn.
            onBeforeRollFn({
                roll = "2d10+5",
                description = "First Ability",
                boons = 0,
                rollArgs = { roll = "2d10+5" },
            })
            local warned = false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send"
                    and string.find(entry.message, "does not pass setActiveRoll")
                    and string.find(entry.message, "Re%-rolls") then
                    warned = true
                    break
                end
            end
            assert.is_true(warned)

            -- Reset state and trigger again: the warning must not re-fire.
            resetDiceVisionState()
            -- Preserve the session-scoped flag the way production would
            -- (resetDiceVisionState clears it in the test harness, so set
            -- it back so we can verify the dedupe).
            DiceVision.warnedMissingSetActiveRoll = true
            DiceVision.mode = "replace"
            DiceVision.connected = true
            onBeforeRollFn({
                roll = "2d10+5",
                description = "Second Ability",
                boons = 0,
                rollArgs = { roll = "2d10+5" },
            })
            local secondWarn = false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send"
                    and string.find(entry.message, "does not pass setActiveRoll") then
                    secondWarn = true
                    break
                end
            end
            assert.is_false(secondWarn)
        end)

        it("does not warn when context.setActiveRoll is present", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            onBeforeRollFn({
                roll = "2d10+5",
                description = "Test",
                boons = 0,
                rollArgs = { roll = "2d10+5" },
                setActiveRoll = function() end,
            })
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" then
                    assert.is_nil(string.find(entry.message, "does not pass setActiveRoll"))
                end
            end
        end)
    end)

    -- ============================================================================
    -- Category 10: handlePendingRoll initial roll calls setActiveRoll
    -- ============================================================================

    describe("handlePendingRoll initial roll setActiveRoll", function()
        it("calls setActiveRoll with dmhub.Roll return value", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local setActiveRollCalled = nil
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Initial Roll Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function(roll) setActiveRollCalled = roll end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            -- dmhub.Roll was called and returned a roll object
            assert.are.equal(1, #_G._dmhubRollLog)
            -- setActiveRoll should have been called with that roll object
            assert.is_not_nil(setActiveRollCalled)
            assert.are.equal("roll-1", setActiveRollCalled.id)
        end)

        it("does not call setActiveRoll when not provided", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "No SetActiveRoll Test",
                edges = 0,
                banes = 0,
                -- No setActiveRoll
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            -- Should still work without setActiveRoll
            assert.are.equal(1, #_G._dmhubRollLog)
        end)

        it("does not mutate the caller's rollArgs.roll", function()
            -- Regression: Codex's re-roll dialog reads g_activeRollArgs.roll
            -- (the original dice expression, e.g. "2d10+5") and amends with
            -- it. Mutating rollArgs.roll to a literal total in place would
            -- make the un-updated-Codex re-roll path silently fail because
            -- the amend can't re-roll a literal value.
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local origRollArgs = { roll = "2d10+5", creature = nil }
            DiceVision.pendingRoll = {
                rollArgs = origRollArgs,
                originalRoll = "2d10+5",
                description = "Mutation Test",
                edges = 0,
                banes = 0,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            -- The original rollArgs.roll must remain the dice expression.
            assert.are.equal("2d10+5", origRollArgs.roll)
            assert.is_nil(origRollArgs.boons)
            assert.is_nil(origRollArgs.banes)
            assert.is_nil(origRollArgs.instant)
            -- dmhub.Roll still received the deterministic-total version.
            assert.are.equal(1, #_G._dmhubRollLog)
            local sentToDmhub = _G._dmhubRollLog[1]
            assert.are_not_equal("2d10+5", sentToDmhub.roll)
            assert.is_true(sentToDmhub.instant)
        end)

        it("preserves rollArgs.properties identity (metatable not stripped)", function()
            -- Codex's properties is a registered game type with metamethods
            -- (try_get etc.). Shallow-copying it would strip the metatable
            -- and break ActionLogPanel/MCDMAbilityRollBehaviors which call
            -- properties:try_get(...). So we keep the same reference, even
            -- though that means the multitargets[1].boons=0 mutation leaks
            -- into the caller's properties (pre-existing behavior).
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local origProps = { foo = "bar" }
            local origRollArgs = {
                roll = "2d10+5",
                creature = nil,
                properties = origProps,
            }
            DiceVision.pendingRoll = {
                rollArgs = origRollArgs,
                originalRoll = "2d10+5",
                description = "Properties Identity Test",
                edges = 0,
                banes = 0,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            -- The properties table passed to dmhub.Roll must be the SAME
            -- object as the caller's, so its metatable is preserved.
            assert.are.equal(1, #_G._dmhubRollLog)
            assert.are.equal(origProps, _G._dmhubRollLog[1].properties)
        end)
    end)

    -- ============================================================================
    -- Category 11: Hook Lifecycle
    -- ============================================================================

    describe("OnReroll hook lifecycle", function()
        it("is registered when switching to replace mode", function()
            DiceVision.setMode("replace")
            assert.is_function(RollDialog.OnReroll)
        end)

        it("is cleared on disconnect", function()
            RollDialog.OnReroll = function() end
            Commands.dv("disconnect")
            assert.is_false(RollDialog.OnReroll)
        end)

        it("is cleared when mode set to off", function()
            DiceVision.mode = "replace"
            RollDialog.OnReroll = function() end
            DiceVision.setMode("off")
            assert.is_false(RollDialog.OnReroll)
        end)

        it("is registered on connect success", function()
            -- Stub net.Get to simulate successful validation
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ active = true })
                end
            end
            Commands.dv("connect ABC123")
            net.Get = originalNetGet
            assert.is_function(RollDialog.OnReroll)
        end)

        it("is registered at load time", function()
            -- After loadDiceVision() in setup(), OnReroll should be set
            -- We need to check this was set. Since resetDiceVisionState resets it,
            -- reload and check
            local originalNetGet = net.Get
            net.Get = function() end
            loadDiceVision()
            net.Get = originalNetGet
            assert.is_function(RollDialog.OnReroll)
        end)
    end)

    describe("mode command", function()
        it("changes mode and sends confirmation with old -> new", function()
            DiceVision.mode = "off"
            Commands.dv("mode replace")
            assert.are.equal("replace", DiceVision.mode)
            -- Find the confirmation message with old -> new
            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if string.find(entry.message, "off") and string.find(entry.message, "replace") then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("changes mode from replace to off", function()
            DiceVision.mode = "replace"
            Commands.dv("mode off")
            assert.are.equal("off", DiceVision.mode)
        end)

        it("shows usage for invalid mode", function()
            Commands.dv("mode invalid")
            assert.truthy(string.find(_G._chatLog[1].message, "Usage"))
        end)

        it("shows usage and current mode for missing mode argument", function()
            Commands.dv("mode")
            assert.are.equal(2, #_G._chatLog)
            assert.truthy(string.find(_G._chatLog[1].message, "Usage"))
            assert.truthy(string.find(_G._chatLog[2].message, "Current mode"))
        end)
    end)

    -- ============================================================================
    -- Category 12: onBeforeTableRoll callback
    -- ============================================================================

    describe("onBeforeTableRoll callback", function()
        local onTableRollFn
        before_each(function()
            DiceVision.setMode("replace")
            onTableRollFn = RollDialog.OnBeforeTableRoll
            resetDiceVisionState()
        end)

        it("returns nil when mode is off", function()
            DiceVision.mode = "off"
            DiceVision.connected = true
            local result = onTableRollFn({
                roll = "1d100",
                description = "Wild Magic",
                completeWithResult = function() end,
            })
            assert.is_nil(result)
        end)

        it("returns nil when not connected", function()
            DiceVision.mode = "replace"
            DiceVision.connected = false
            local result = onTableRollFn({
                roll = "1d100",
                description = "Wild Magic",
                completeWithResult = function() end,
            })
            assert.is_nil(result)
        end)

        it("returns nil when already waiting for a roll", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.waitingForRoll = true
            local result = onTableRollFn({
                roll = "1d100",
                description = "Wild Magic",
                completeWithResult = function() end,
            })
            assert.is_nil(result)
        end)

        it("emits bypass chat notice when already waiting for a roll", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.waitingForRoll = true
            onTableRollFn({
                roll = "1d100",
                description = "Wild Magic",
                completeWithResult = function() end,
            })
            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" and string.find(entry.message, "Another roll is in progress") then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("returns 'intercept' and sets pendingRoll with isTableRoll=true", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            local completeFn = function() end
            local result = onTableRollFn({
                roll = "1d100",
                description = "Wild Magic Surge",
                completeWithResult = completeFn,
            })
            assert.are.equal("intercept", result)
            assert.is_true(DiceVision.waitingForRoll)
            assert.is_not_nil(DiceVision.pendingRoll)
            assert.is_true(DiceVision.pendingRoll.isTableRoll)
            assert.are.equal(completeFn, DiceVision.pendingRoll.completeWithResult)
            assert.are.equal("1d100", DiceVision.pendingRoll.originalRoll)
            assert.are.equal("Wild Magic Surge", DiceVision.pendingRoll.description)
        end)

        it("does not set isReroll/amendWithResult on pendingRoll", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            onTableRollFn({
                roll = "1d100",
                description = "Wild Magic",
                completeWithResult = function() end,
            })
            -- Both fields are load-bearing: abandonPendingRoll keys on isReroll
            -- to choose its branch and reads amendWithResult from the same branch.
            assert.is_nil(DiceVision.pendingRoll.isReroll)
            assert.is_nil(DiceVision.pendingRoll.amendWithResult)
        end)

        it("round-trips tokenid, tableRef, tableName, guid", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            local tableRefObj = { id = "treasure-table" }
            onTableRollFn({
                roll = "1d100",
                description = "Treasure",
                tokenid = "token-42",
                tableRef = tableRefObj,
                tableName = "Treasure Hoard",
                guid = "guid-xyz",
                completeWithResult = function() end,
            })
            assert.are.equal("token-42", DiceVision.pendingRoll.tokenid)
            assert.are.equal(tableRefObj, DiceVision.pendingRoll.tableRef)
            assert.are.equal("Treasure Hoard", DiceVision.pendingRoll.tableName)
            assert.are.equal("guid-xyz", DiceVision.pendingRoll.guid)
        end)

        it("sends table-roll waiting message to chat", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            onTableRollFn({
                roll = "1d100",
                description = "Wild Magic",
                completeWithResult = function() end,
            })
            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if string.find(entry.message, "table roll") then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("falls back description to tableName when description not provided", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            onTableRollFn({
                roll = "1d100",
                tableName = "Wild Magic",
                completeWithResult = function() end,
            })
            assert.are.equal("Wild Magic", DiceVision.pendingRoll.description)
        end)
    end)

    -- ============================================================================
    -- Category 13: handlePendingRoll table-roll path
    -- ============================================================================

    describe("handlePendingRoll table-roll path", function()
        it("calls completeWithResult with integer total for d20 table roll", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local captured = nil
            DiceVision.pendingRoll = {
                originalRoll = "1d20",
                description = "Treasure Table",
                isTableRoll = true,
                completeWithResult = function(val) captured = val end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = { { type = "d20", value = 14 } },
                total = 14,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.are.equal(14, captured)
            assert.are.equal("number", type(captured))
        end)

        it("characterizes table-roll card faces for type-remapped d20s", function()
            -- The default d20 -> d10 mapping applies to ALL intercepted
            -- rolls, table rolls included (per the user decision: the
            -- native roller context opts in by default). Consequence
            -- pinned here: a REAL d20 showing 14 on a table roll renders
            -- on a 10-faced card die (value and total stay correct; the
            -- mapping exists for Draw Steel d20-shaped d10s, whose values
            -- never exceed 10).
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.pendingRoll = {
                originalRoll = "1d20",
                description = "Treasure Table",
                isTableRoll = true,
                completeWithResult = function() end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = { { type = "d20", value = 14 } },
                total = 14,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            local card = nil
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "custom" then card = entry.message end
            end
            assert.is_not_nil(card)
            assert.are.equal(10, card.dice[1].faces)
            assert.are.equal(14, card.dice[1].value)
            assert.are.equal(14, card.total)
        end)

        it("maps percentile pair '00'+'0' to total 100", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local captured = nil
            DiceVision.pendingRoll = {
                originalRoll = "1d100",
                description = "Wild Magic",
                isTableRoll = true,
                completeWithResult = function(val) captured = val end,
            }
            DiceVision.waitingForRoll = true

            -- API sends die.value as a string; handleDiceVisionRoll derives
            -- rawValue from it. Pass strings to match real-world shape.
            local rollData = {
                dice = {
                    { type = "d10", value = "00" },
                    { type = "d10", value = "0" },
                },
                total = 0,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.are.equal(100, captured)
            assert.are.equal("number", type(captured))
        end)

        it("computes percentile total 75 from '70'+'5'", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local captured = nil
            DiceVision.pendingRoll = {
                originalRoll = "1d100",
                description = "Wild Magic",
                isTableRoll = true,
                completeWithResult = function(val) captured = val end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = {
                    { type = "d10", value = "70" },
                    { type = "d10", value = "5" },
                },
                total = 75,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.are.equal(75, captured)
        end)

        it("computes percentile total when units die comes first ('5'+'70' -> 75)", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local captured = nil
            DiceVision.pendingRoll = {
                originalRoll = "1d100",
                description = "Wild Magic",
                isTableRoll = true,
                completeWithResult = function(val) captured = val end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = {
                    { type = "d10", value = "5" },
                    { type = "d10", value = "70" },
                },
                total = 75,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.are.equal(75, captured)
        end)

        it("sets isPercentile=true on chat message when percentile pair detected", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.pendingRoll = {
                originalRoll = "1d100",
                description = "Percentile Chat Test",
                isTableRoll = true,
                completeWithResult = function() end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = {
                    { type = "d10", value = "70" },
                    { type = "d10", value = "5" },
                },
                total = 75,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "custom"
                    and entry.message.description == "Percentile Chat Test"
                    and entry.message.isPercentile == true then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("applies modifier from originalRoll string (1d20+3 -> 13)", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local captured = nil
            DiceVision.pendingRoll = {
                originalRoll = "1d20+3",
                description = "Modified Table",
                isTableRoll = true,
                completeWithResult = function(val) captured = val end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = { { type = "d20", value = 10 } },
                total = 10,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.are.equal(13, captured)
        end)

        it("applies negative modifier from originalRoll (1d20-2 -> 8 from value 10)", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local captured = nil
            DiceVision.pendingRoll = {
                originalRoll = "1d20-2",
                description = "Negative Modifier Table",
                isTableRoll = true,
                completeWithResult = function(val) captured = val end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = { { type = "d20", value = 10 } },
                total = 10,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.are.equal(8, captured)
        end)

        it("does NOT call dmhub.Roll for table rolls", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.pendingRoll = {
                originalRoll = "1d20",
                description = "Table",
                isTableRoll = true,
                completeWithResult = function() end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = { { type = "d20", value = 14 } },
                total = 14,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.are.equal(0, #_G._dmhubRollLog)
        end)

        it("ignores edges/banes if defensively present on pendingRoll", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local captured = nil
            DiceVision.pendingRoll = {
                originalRoll = "1d20",
                description = "Defensive Edge Table",
                isTableRoll = true,
                edges = 99,
                banes = 0,
                completeWithResult = function(val) captured = val end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = { { type = "d20", value = 10 } },
                total = 10,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.are.equal(10, captured)
        end)

        it("sends DiceVisionRollMessage to chat with description and rollSource='table'", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.pendingRoll = {
                originalRoll = "1d20",
                description = "Treasure Lookup",
                isTableRoll = true,
                completeWithResult = function() end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = { { type = "d20", value = 14 } },
                total = 14,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "custom"
                    and entry.message.description == "Treasure Lookup"
                    and entry.message.rollSource == "table" then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("does not call setActiveRoll for table rolls", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local setActiveCalled = false
            DiceVision.pendingRoll = {
                originalRoll = "1d20",
                description = "Defensive setActiveRoll Table",
                isTableRoll = true,
                completeWithResult = function() end,
                setActiveRoll = function() setActiveCalled = true end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = { { type = "d20", value = 14 } },
                total = 14,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.is_false(setActiveCalled)
        end)
    end)

    -- ============================================================================
    -- Category 14: Fallback paths for table rolls
    -- ============================================================================

    describe("fallback paths for table rolls", function()
        it("timeout sends abandon notice and does not call completeWithResult", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local completeCalled = false
            DiceVision.pendingRoll = {
                originalRoll = "1d100",
                description = "Timeout Table",
                isTableRoll = true,
                completeWithResult = function() completeCalled = true end,
            }
            DiceVision.waitingForRoll = true

            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = {} })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.is_false(completeCalled)
            assert.are.equal(0, #_G._dmhubRollLog)
            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if string.find(entry.message, "abandoned") then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("error sends abandon notice and does not call completeWithResult", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local completeCalled = false
            DiceVision.pendingRoll = {
                originalRoll = "1d100",
                description = "Error Table",
                isTableRoll = true,
                completeWithResult = function() completeCalled = true end,
            }
            DiceVision.waitingForRoll = true

            local originalNetGet = net.Get
            net.Get = function(args)
                if args.error then
                    args.error("connection failed", 500)
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.is_false(completeCalled)
            assert.are.equal(0, #_G._dmhubRollLog)
            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if string.find(entry.message, "abandoned") then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("mode-off sends abandon notice and does not call completeWithResult", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            local completeCalled = false
            DiceVision.pendingRoll = {
                originalRoll = "1d100",
                description = "Mode Off Table",
                isTableRoll = true,
                completeWithResult = function() completeCalled = true end,
            }
            DiceVision.waitingForRoll = true

            DiceVision.setMode("off")

            assert.is_false(completeCalled)
            assert.are.equal(0, #_G._dmhubRollLog)
            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if string.find(entry.message, "abandoned") then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("/dv disconnect sends abandon notice and does not call completeWithResult", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            local completeCalled = false
            DiceVision.pendingRoll = {
                originalRoll = "1d100",
                description = "Disconnect Table",
                isTableRoll = true,
                completeWithResult = function() completeCalled = true end,
            }
            DiceVision.waitingForRoll = true

            Commands.dv("disconnect")

            assert.is_false(completeCalled)
            assert.are.equal(0, #_G._dmhubRollLog)
            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if string.find(entry.message, "abandoned") then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("timeout does not emit 'virtual dice' chat for table rolls", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.pendingRoll = {
                originalRoll = "1d100",
                description = "Timeout Chat Table",
                isTableRoll = true,
                completeWithResult = function() end,
            }
            DiceVision.waitingForRoll = true

            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = {} })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            for _, entry in ipairs(_G._chatLog) do
                assert.is_nil(string.find(entry.message, "virtual dice"))
            end
        end)

        it("error does not emit 'virtual dice' chat for table rolls", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.pendingRoll = {
                originalRoll = "1d100",
                description = "Error Chat Table",
                isTableRoll = true,
                completeWithResult = function() end,
            }
            DiceVision.waitingForRoll = true

            local originalNetGet = net.Get
            net.Get = function(args)
                if args.error then
                    args.error("connection failed", 500)
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            for _, entry in ipairs(_G._chatLog) do
                assert.is_nil(string.find(entry.message, "virtual dice"))
            end
        end)

        it("ability-roll timeout still emits 'virtual dice' chat (regression)", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5" },
                originalRoll = "2d10+5",
                description = "Ability Timeout",
                edges = 0,
                banes = 0,
            }
            DiceVision.waitingForRoll = true

            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = {} })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if string.find(entry.message, "virtual dice") then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("isTableRoll with nil completeWithResult emits internal-error chat and does not call dmhub.Roll", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.pendingRoll = {
                originalRoll = "1d100",
                description = "Buggy Hookdata",
                tableName = "Wild Magic",
                isTableRoll = true,
                completeWithResult = nil,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = { { type = "d20", value = "14" } },
                total = 14,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            assert.are.equal(0, #_G._dmhubRollLog)
            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if string.find(entry.message, "Internal error")
                    and string.find(entry.message, "callback missing") then
                    found = true
                    break
                end
            end
            assert.is_true(found)
            -- Must NOT surface the ability-roll fallthrough message
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" then
                    assert.is_nil(string.find(entry.message, "Roll context not available"))
                end
            end
        end)
    end)

    -- ============================================================================
    -- Category 15: OnBeforeTableRoll hook lifecycle
    -- ============================================================================

    describe("OnBeforeTableRoll hook lifecycle", function()
        it("is registered when switching to replace mode", function()
            DiceVision.setMode("replace")
            assert.is_function(RollDialog.OnBeforeTableRoll)
        end)

        it("is cleared on disconnect", function()
            RollDialog.OnBeforeTableRoll = function() end
            Commands.dv("disconnect")
            assert.is_false(RollDialog.OnBeforeTableRoll)
        end)

        it("is cleared when mode set to off", function()
            DiceVision.mode = "replace"
            RollDialog.OnBeforeTableRoll = function() end
            DiceVision.setMode("off")
            assert.is_false(RollDialog.OnBeforeTableRoll)
        end)

        it("is registered on connect success", function()
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ active = true })
                end
            end
            Commands.dv("connect ABC123")
            net.Get = originalNetGet
            assert.is_function(RollDialog.OnBeforeTableRoll)
        end)

        it("is registered at load time", function()
            local originalNetGet = net.Get
            net.Get = function() end
            loadDiceVision()
            net.Get = originalNetGet
            assert.is_function(RollDialog.OnBeforeTableRoll)
        end)
    end)

    -- ============================================================================
    -- Category 16: Hook probe & graceful degradation
    -- ============================================================================

    describe("registerHooks selective registration", function()
        local function stubConnectSuccess()
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then args.success({ active = true }) end
            end
            return originalNetGet
        end

        it("wires all three hooks when Codex declares all three", function()
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = false
            RollDialog.OnBeforeTableRoll = false
            DiceVision.setMode("replace")
            assert.is_function(RollDialog.OnBeforeRoll)
            assert.is_function(RollDialog.OnReroll)
            assert.is_function(RollDialog.OnBeforeTableRoll)
            assert.is_true(DiceVision.hooksRegistered.ability)
            assert.is_true(DiceVision.hooksRegistered.reroll)
            assert.is_true(DiceVision.hooksRegistered["table"])
        end)

        it("skips slots Codex did not declare (nil) and leaves them nil", function()
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = false
            RollDialog.OnBeforeTableRoll = nil
            DiceVision.setMode("replace")
            assert.is_function(RollDialog.OnBeforeRoll)
            assert.is_function(RollDialog.OnReroll)
            assert.is_nil(RollDialog.OnBeforeTableRoll)
            assert.is_true(DiceVision.hooksRegistered.ability)
            assert.is_true(DiceVision.hooksRegistered.reroll)
            assert.is_false(DiceVision.hooksRegistered["table"])
        end)

        it("setMode('replace') registration is silent (no chat warnings)", function()
            RollDialog.OnBeforeTableRoll = nil
            DiceVision.setMode("replace")
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" then
                    assert.is_nil(string.find(entry.message, "Codex does not expose"))
                end
            end
        end)

        it("/dv connect emits a chat warning per missing hook", function()
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = nil
            RollDialog.OnBeforeTableRoll = nil
            local originalNetGet = stubConnectSuccess()
            Commands.dv("connect ABC123")
            net.Get = originalNetGet

            local rerollWarn, tableWarn, abilityWarn = false, false, false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" and string.find(entry.message, "Codex does not expose") then
                    if string.find(entry.message, "OnReroll") then rerollWarn = true end
                    if string.find(entry.message, "OnBeforeTableRoll") then tableWarn = true end
                    if string.find(entry.message, "OnBeforeRoll;") then abilityWarn = true end
                end
            end
            assert.is_true(rerollWarn)
            assert.is_true(tableWarn)
            assert.is_false(abilityWarn)
        end)

        it("/dv connect emits no warnings when all hooks declared", function()
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = false
            RollDialog.OnBeforeTableRoll = false
            local originalNetGet = stubConnectSuccess()
            Commands.dv("connect ABC123")
            net.Get = originalNetGet

            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" then
                    assert.is_nil(string.find(entry.message, "Codex does not expose"))
                end
            end
        end)

        it("removeRollInterceptor clears hooksRegistered cache", function()
            DiceVision.setMode("replace")
            assert.is_true(DiceVision.hooksRegistered.ability)
            Commands.dv("disconnect")
            assert.is_false(DiceVision.hooksRegistered.ability)
            assert.is_false(DiceVision.hooksRegistered.reroll)
            assert.is_false(DiceVision.hooksRegistered["table"])
        end)

        it("removeRollInterceptor does not pollute slots Codex never declared", function()
            -- Codex declares only OnBeforeRoll; the others are nil.
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = nil
            RollDialog.OnBeforeTableRoll = nil
            DiceVision.setMode("replace")  -- captures snapshot, registers ability only
            Commands.dv("disconnect")      -- triggers removeRollInterceptor

            -- Slots Codex never declared must stay nil so a fresh probe (e.g.,
            -- across a Codex mod-reload) correctly identifies them as undeclared.
            assert.is_nil(RollDialog.OnReroll)
            assert.is_nil(RollDialog.OnBeforeTableRoll)
            -- Slot Codex did declare gets cleared as before.
            assert.is_false(RollDialog.OnBeforeRoll)
        end)

        it("simulated mod reload after disconnect re-detects undeclared slots", function()
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = nil
            RollDialog.OnBeforeTableRoll = nil
            DiceVision.setMode("replace")
            Commands.dv("disconnect")
            -- Simulate Codex reloading the mod: codexDeclaredHooks resets to
            -- nil (DiceVision global re-created), but RollDialog persists.
            DiceVision.codexDeclaredHooks = nil
            DiceVision.setMode("replace")
            assert.is_true(DiceVision.codexDeclaredHooks.ability)
            assert.is_false(DiceVision.codexDeclaredHooks.reroll)
            assert.is_false(DiceVision.codexDeclaredHooks["table"])
        end)

        it("connect -> disconnect -> connect on missing hook stays disabled", function()
            -- Regression: removeRollInterceptor writes false to all three slots,
            -- which would poison a live RollDialog[name]==nil probe on the next
            -- connect. The snapshot at first call must persist across the cycle.
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = false
            RollDialog.OnBeforeTableRoll = nil
            local originalNetGet = stubConnectSuccess()
            Commands.dv("connect ABC123")
            Commands.dv("disconnect")
            _G._chatLog = {}
            Commands.dv("connect ABC123")
            net.Get = originalNetGet

            assert.is_true(DiceVision.hooksRegistered.ability)
            assert.is_true(DiceVision.hooksRegistered.reroll)
            assert.is_false(DiceVision.hooksRegistered["table"])
            -- After the cycle, our hook is NOT installed on the originally
            -- undeclared slot.
            assert.are_not_equal("function", type(RollDialog.OnBeforeTableRoll))
            -- And the warning re-fires on the second connect.
            local warned = false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" and string.find(entry.message, "OnBeforeTableRoll") then
                    warned = true
                    break
                end
            end
            assert.is_true(warned)
        end)

        it("setMode replace -> off -> replace on missing hook stays disabled", function()
            -- Same regression as above but via the setMode lifecycle path.
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = false
            RollDialog.OnBeforeTableRoll = nil
            DiceVision.setMode("replace")
            DiceVision.setMode("off")
            DiceVision.setMode("replace")

            assert.is_true(DiceVision.hooksRegistered.ability)
            assert.is_false(DiceVision.hooksRegistered["table"])
            assert.are_not_equal("function", type(RollDialog.OnBeforeTableRoll))
        end)

        it("/dv mode replace fires verbose warning when slot is missing", function()
            DiceVision.mode = "off"
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = false
            RollDialog.OnBeforeTableRoll = nil
            _G._chatLog = {}
            Commands.dv("mode replace")

            local warned = false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send"
                    and string.find(entry.message, "Codex does not expose")
                    and string.find(entry.message, "OnBeforeTableRoll") then
                    warned = true
                    break
                end
            end
            assert.is_true(warned)
        end)

        it("printf log fires for missing hook even on silent path", function()
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = false
            RollDialog.OnBeforeTableRoll = nil
            _G._printLog = {}
            DiceVision.setMode("replace")  -- silent (verbose=nil)

            local logged = false
            for _, line in ipairs(_G._printLog) do
                if string.find(line, "hook RollDialog%.OnBeforeTableRoll missing") then
                    logged = true
                    break
                end
            end
            assert.is_true(logged)
        end)
    end)

    describe("/dv status hook reporting", function()
        local function findStatusMessage()
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" and string.find(entry.message, "%[DiceVision%] Status:") then
                    return entry.message
                end
            end
            return nil
        end

        it("reports YES for all three hooks when wired", function()
            DiceVision.setMode("replace")
            _G._chatLog = {}
            Commands.dv("status")
            local msg = findStatusMessage()
            assert.is_not_nil(msg)
            assert.truthy(string.find(msg, "ability=YES"))
            assert.truthy(string.find(msg, "reroll=YES"))
            assert.truthy(string.find(msg, "table=YES"))
            assert.is_nil(string.find(msg, "Missing Codex hooks"))
        end)

        it("reports NO for missing hooks and lists them", function()
            RollDialog.OnBeforeTableRoll = nil
            DiceVision.setMode("replace")
            _G._chatLog = {}
            Commands.dv("status")
            local msg = findStatusMessage()
            assert.is_not_nil(msg)
            assert.truthy(string.find(msg, "ability=YES"))
            assert.truthy(string.find(msg, "table=NO"))
            assert.truthy(string.find(msg, "Missing Codex hooks: RollDialog%.OnBeforeTableRoll"))
        end)

        it("reports all NO and full missing list before any registration", function()
            DiceVision.hooksRegistered = nil
            _G._chatLog = {}
            Commands.dv("status")
            local msg = findStatusMessage()
            assert.is_not_nil(msg)
            assert.truthy(string.find(msg, "ability=NO"))
            assert.truthy(string.find(msg, "reroll=NO"))
            assert.truthy(string.find(msg, "table=NO"))
        end)
    end)

    -- ============================================================================
    -- Category 17: Mode-command UX and snapshot edge cases
    -- ============================================================================

    describe("/dv mode no-op handling", function()
        it("emits 'Already in mode X' when re-issued for the current mode", function()
            DiceVision.mode = "replace"
            _G._chatLog = {}
            Commands.dv("mode replace")
            local found, alsoChanged = false, false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" and string.find(entry.message, "Already in mode replace") then
                    found = true
                end
                if entry.type == "send" and string.find(entry.message, "Mode changed:") then
                    alsoChanged = true
                end
            end
            assert.is_true(found)
            assert.is_false(alsoChanged)
        end)

        it("still emits 'Mode changed' on a real transition", function()
            DiceVision.mode = "off"
            _G._chatLog = {}
            Commands.dv("mode replace")
            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" and string.find(entry.message, "Mode changed: off %-> replace") then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)
    end)

    describe("registerHooks no-RollDialog snapshot lock", function()
        it("locks codexDeclaredHooks to all-false when RollDialog is nil", function()
            local savedRollDialog = _G.RollDialog
            _G.RollDialog = nil
            DiceVision.codexDeclaredHooks = nil
            DiceVision.setMode("off")  -- ensure off so setMode("replace") triggers
            DiceVision.setMode("replace")
            _G.RollDialog = savedRollDialog
            assert.is_not_nil(DiceVision.codexDeclaredHooks)
            assert.is_false(DiceVision.codexDeclaredHooks.ability)
            assert.is_false(DiceVision.codexDeclaredHooks.reroll)
            assert.is_false(DiceVision.codexDeclaredHooks["table"])
        end)

        it("does NOT re-snapshot from RollDialog if it appears later", function()
            -- Initial register with RollDialog absent locks the snapshot.
            local savedRollDialog = _G.RollDialog
            _G.RollDialog = nil
            DiceVision.codexDeclaredHooks = nil
            DiceVision.setMode("off")
            DiceVision.setMode("replace")
            -- RollDialog now appears with all hooks declared.
            _G.RollDialog = { OnBeforeRoll = false, OnReroll = false, OnBeforeTableRoll = false }
            DiceVision.setMode("off")
            DiceVision.setMode("replace")
            -- Snapshot still says all-false; no slots got wired.
            assert.is_false(DiceVision.codexDeclaredHooks.ability)
            assert.is_false(DiceVision.hooksRegistered.ability)
            _G.RollDialog = savedRollDialog
        end)
    end)

    describe("DVDicePanel._panelToggle contract", function()
        -- DVDicePanel.lua's click handler delegates to DiceVision._panelToggle.
        -- Testing the helper directly pins the panel's actual contract
        -- (verbose-on-replace, confirmation chat, mode flip, connected
        -- guard) rather than the looser setMode surface that contract is
        -- built on. Catches regressions where DVDicePanel reverts to
        -- calling setMode directly and skips the verbose flag.
        it("toggle from off to replace emits missing-hook warning when slot is missing", function()
            DiceVision.connected = true
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = false
            RollDialog.OnBeforeTableRoll = nil
            DiceVision.mode = "off"
            _G._chatLog = {}
            DiceVision._panelToggle()
            local warned = false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send"
                    and string.find(entry.message, "Codex does not expose")
                    and string.find(entry.message, "OnBeforeTableRoll")
                    and string.find(entry.message, "hook missing") then
                    warned = true
                    break
                end
            end
            assert.is_true(warned)
        end)

        it("toggle from replace to off emits no missing-hook warning", function()
            DiceVision.connected = true
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = false
            RollDialog.OnBeforeTableRoll = nil
            DiceVision.mode = "replace"
            _G._chatLog = {}
            DiceVision._panelToggle()
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" then
                    assert.is_nil(string.find(entry.message, "Codex does not expose"))
                end
            end
        end)

        it("toggle returns the new mode and emits 'Mode changed' confirmation", function()
            DiceVision.connected = true
            DiceVision.mode = "off"
            _G._chatLog = {}
            local newMode = DiceVision._panelToggle()
            assert.are.equal("replace", newMode)
            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" and string.find(entry.message, "Mode changed: off %-> replace") then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("toggle is a no-op when not connected", function()
            DiceVision.connected = false
            DiceVision.mode = "off"
            _G._chatLog = {}
            _G._printLog = {}
            local result = DiceVision._panelToggle()
            assert.is_nil(result)
            assert.are.equal("off", DiceVision.mode)
            assert.are.equal(0, #_G._chatLog)
            -- Audit trail: silent on chat, but the disconnected-bypass is
            -- logged so a future caller (hotkey, dev console) leaves a trail.
            local logged = false
            for _, line in ipairs(_G._printLog) do
                if string.find(line, "_panelToggle called while disconnected") then
                    logged = true
                    break
                end
            end
            assert.is_true(logged)
        end)
    end)

    describe("DiceVision.connect contract", function()
        -- Both /dv connect and the DVDicePanel connect popup route through
        -- DiceVision.connect. These tests pin the shared contract (normalize
        -- code, set sessionCode, flip to replace + connected on success, clear
        -- sessionCode on failure, fire onResult) and that the command handler
        -- still delegates. net.Get is stubbed per-test to drive validateSession.
        local originalNetGet

        before_each(function()
            originalNetGet = _G.net.Get
        end)

        after_each(function()
            _G.net.Get = originalNetGet
        end)

        local function stubSession(outcome)
            -- outcome: "active" | "inactive" | "error"
            _G.net.Get = function(args)
                if outcome == "active" then
                    args.success({active = true})
                elseif outcome == "inactive" then
                    args.success({active = false})
                else
                    args.error("boom")
                end
            end
        end

        it("on success sets connected, replace mode, uppercased code, and fires onResult(true)", function()
            stubSession("active")
            local cbSuccess, cbResult
            DiceVision.connect("ab1", function(success, result)
                cbSuccess, cbResult = success, result
            end)
            assert.is_true(DiceVision.connected)
            assert.are.equal("replace", DiceVision.mode)
            assert.are.equal("AB1", DiceVision.sessionCode)
            assert.is_true(chatHas("Connected!"))
            assert.is_true(cbSuccess)
            assert.are.equal(true, cbResult.active)
        end)

        it("on success re-arms the once-per-session unverifiable note", function()
            -- A prior session may have latched warnedUnverifiedForcedDice;
            -- a fresh connect must re-arm it so the note can fire again.
            DiceVision.warnedUnverifiedForcedDice = true
            stubSession("active")
            DiceVision.connect("ab1")
            assert.is_false(DiceVision.warnedUnverifiedForcedDice)
        end)

        it("on inactive session clears sessionCode, stays disconnected, fires onResult(false)", function()
            stubSession("inactive")
            local cbSuccess = nil
            DiceVision.connect("ab1", function(success) cbSuccess = success end)
            assert.is_false(DiceVision.connected)
            assert.is_nil(DiceVision.sessionCode)
            assert.is_true(chatHas("Connection failed"))
            assert.is_false(cbSuccess)
        end)

        it("on network error clears sessionCode and fires onResult(false)", function()
            stubSession("error")
            local cbSuccess = nil
            DiceVision.connect("ab1", function(success) cbSuccess = success end)
            assert.is_false(DiceVision.connected)
            assert.is_nil(DiceVision.sessionCode)
            assert.is_true(chatHas("Connection failed"))
            assert.is_false(cbSuccess)
        end)

        it("empty / whitespace code shows usage, fires onResult(false), never hits net", function()
            local netCalled = false
            _G.net.Get = function() netCalled = true end
            local cbSuccess = nil
            DiceVision.connect("   ", function(success) cbSuccess = success end)
            assert.is_false(netCalled)
            assert.is_false(cbSuccess)
            assert.is_true(chatHas("Usage: /dv connect"))
            assert.is_nil(DiceVision.sessionCode)
        end)

        it("nil code is treated as empty (usage), never hits net", function()
            local netCalled = false
            _G.net.Get = function() netCalled = true end
            DiceVision.connect(nil)
            assert.is_false(netCalled)
            assert.is_true(chatHas("Usage: /dv connect"))
        end)

        it("normalizes surrounding whitespace and uppercases the code", function()
            stubSession("active")
            DiceVision.connect("  ab1  ")
            assert.are.equal("AB1", DiceVision.sessionCode)
        end)

        it("strips interior whitespace, not just surrounding", function()
            stubSession("active")
            DiceVision.connect("a b 1")
            assert.are.equal("AB1", DiceVision.sessionCode)
        end)

        it("/dv connect command delegates to DiceVision.connect", function()
            stubSession("active")
            Commands.dv("connect ab1")
            assert.are.equal("AB1", DiceVision.sessionCode)
            assert.is_true(DiceVision.connected)
        end)
    end)

    describe("registerHooks silent path printf contract", function()
        -- Even when verbose=false (load-time, internal setMode), the printf
        -- trail must still emit per missing hook so a post-mortem trail
        -- exists. Augments the cluster above by pinning the positive printf
        -- signal alongside the chat-silence assertion.
        it("setMode('replace', false) still printf-logs each missing hook", function()
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = false
            RollDialog.OnBeforeTableRoll = nil
            _G._printLog = {}
            DiceVision.setMode("replace", false)
            local logged = false
            for _, line in ipairs(_G._printLog) do
                if string.find(line, "hook RollDialog%.OnBeforeTableRoll missing") then
                    logged = true
                    break
                end
            end
            assert.is_true(logged)
        end)
    end)

    describe("/dv refresh", function()
        it("nils codexDeclaredHooks and re-runs registerHooks verbose", function()
            -- First lock the snapshot via a register on a missing hook.
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = false
            RollDialog.OnBeforeTableRoll = nil
            DiceVision.setMode("replace")
            assert.is_false(DiceVision.codexDeclaredHooks["table"])

            -- Simulate Codex update declaring the hook.
            RollDialog.OnBeforeTableRoll = false
            _G._chatLog = {}
            Commands.dv("refresh")

            -- Snapshot should now reflect the new declaration.
            assert.is_true(DiceVision.codexDeclaredHooks["table"])
            assert.is_true(DiceVision.hooksRegistered["table"])
            -- Refresh confirmation chat fires.
            local confirmed = false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" and string.find(entry.message, "Hook probe refreshed") then
                    confirmed = true
                    break
                end
            end
            assert.is_true(confirmed)
        end)

        it("emits verbose warnings on missing hooks", function()
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = false
            RollDialog.OnBeforeTableRoll = nil
            DiceVision.setMode("replace")  -- locks snapshot
            _G._chatLog = {}
            Commands.dv("refresh")
            -- Hook is still missing; refresh re-emits the warning.
            local warned = false
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" and string.find(entry.message, "Codex does not expose")
                    and string.find(entry.message, "OnBeforeTableRoll") then
                    warned = true
                    break
                end
            end
            assert.is_true(warned)
        end)

        it("recovers from locked-all-false when RollDialog appears later", function()
            -- Simulate the load-order anomaly: RollDialog absent at first
            -- probe, snapshot locked all-false, RollDialog later loads with
            -- valid hooks. /dv refresh is the documented escape hatch.
            local savedRollDialog = _G.RollDialog
            _G.RollDialog = nil
            DiceVision.codexDeclaredHooks = nil
            DiceVision.setMode("off")
            DiceVision.setMode("replace")  -- locks snapshot to all-false
            assert.is_false(DiceVision.codexDeclaredHooks.ability)

            -- RollDialog appears with all hooks declared.
            _G.RollDialog = { OnBeforeRoll = false, OnReroll = false, OnBeforeTableRoll = false }
            Commands.dv("refresh")

            -- Snapshot now reflects the new declarations and hooks wire.
            assert.is_true(DiceVision.codexDeclaredHooks.ability)
            assert.is_true(DiceVision.codexDeclaredHooks.reroll)
            assert.is_true(DiceVision.codexDeclaredHooks["table"])
            assert.is_true(DiceVision.hooksRegistered.ability)

            _G.RollDialog = savedRollDialog
        end)

        it("reflects a hook that Codex stopped declaring", function()
            -- Inverse hot-reload: a hook that was previously wired is now
            -- no longer declared. /dv refresh must update both the snapshot
            -- and the wired-state cache.
            RollDialog.OnBeforeRoll = false
            RollDialog.OnReroll = false
            RollDialog.OnBeforeTableRoll = false
            DiceVision.setMode("replace")
            assert.is_true(DiceVision.codexDeclaredHooks["table"])
            assert.is_true(DiceVision.hooksRegistered["table"])

            -- Codex hot-removes the hook entirely.
            RollDialog.OnBeforeTableRoll = nil
            Commands.dv("refresh")

            assert.is_false(DiceVision.codexDeclaredHooks["table"])
            assert.is_false(DiceVision.hooksRegistered["table"])
        end)

        it("emits printf audit-trail line on invocation", function()
            DiceVision.setMode("replace")  -- some prior state
            _G._printLog = {}
            Commands.dv("refresh")
            local logged = false
            for _, line in ipairs(_G._printLog) do
                if string.find(line, "/dv refresh invoked") then
                    logged = true
                    break
                end
            end
            assert.is_true(logged)
        end)
    end)

    describe("DiceVision rules seams", function()
        -- The settings popup and the /dv rules commands share these seams.
        -- Coercion/validation lives in the seam (the popup passes raw text), so
        -- it is pinned here. Mirrors the connect/_panelToggle contract blocks.
        it("setValueMapping creates the nested table, sets the value, returns true", function()
            DiceVision.rules.valueMappings = {}
            local ok = DiceVision.setValueMapping("d20", "0", "20")
            assert.is_true(ok)
            assert.are.equal(20, DiceVision.rules.valueMappings["d20"][0])
            assert.is_true(chatHas("Mapped d20: 0 -> 20"))
        end)

        it("setValueMapping rejects non-numeric values: usage, no write, returns false", function()
            DiceVision.rules.valueMappings = {}
            local ok = DiceVision.setValueMapping("d20", "x", "20")
            assert.is_false(ok)
            assert.is_nil(DiceVision.rules.valueMappings["d20"])
            assert.is_true(chatHas("Usage: /dv rules map"))
        end)

        it("removeValueMapping removes the entry and prunes the emptied die table", function()
            DiceVision.rules.valueMappings = {["d10"] = {[0] = 10}}
            local ok = DiceVision.removeValueMapping("d10", "0")
            assert.is_true(ok)
            assert.is_nil(DiceVision.rules.valueMappings["d10"])
            assert.is_true(chatHas("Removed mapping d10: 0"))
        end)

        it("removeValueMapping keeps other faces of the same die", function()
            DiceVision.rules.valueMappings = {["d10"] = {[0] = 10, [1] = 11}}
            DiceVision.removeValueMapping("d10", 0)
            assert.is_nil(DiceVision.rules.valueMappings["d10"][0])
            assert.are.equal(11, DiceVision.rules.valueMappings["d10"][1])
        end)

        it("removeValueMapping is a no-op returning false on a missing mapping", function()
            DiceVision.rules.valueMappings = {}
            assert.is_false(DiceVision.removeValueMapping("d10", 5))
        end)

        it("setDiceSelection auto clears to nil", function()
            DiceVision.rules.diceSelection = {keep = "highest", count = 2}
            local result = DiceVision.setDiceSelection("auto")
            assert.is_nil(result)
            assert.is_nil(DiceVision.rules.diceSelection)
        end)

        it("setDiceSelection highest+count sets the table", function()
            local result = DiceVision.setDiceSelection("highest", "3")
            assert.are.same({keep = "highest", count = 3}, result)
            assert.are.same({keep = "highest", count = 3}, DiceVision.rules.diceSelection)
        end)

        it("setDiceSelection with a mode but no count leaves selection unchanged (usage)", function()
            DiceVision.rules.diceSelection = nil
            local result = DiceVision.setDiceSelection("highest")
            assert.is_nil(result)
            assert.is_nil(DiceVision.rules.diceSelection)
            assert.is_true(chatHas("Usage: /dv rules keep"))
        end)

        it("setClampOutOfRange toggles the boolean and confirms", function()
            assert.is_true(DiceVision.setClampOutOfRange(true))
            assert.is_true(DiceVision.rules.clampOutOfRange)
            assert.is_true(chatHas("clamping enabled"))
            assert.is_false(DiceVision.setClampOutOfRange(false))
            assert.is_false(DiceVision.rules.clampOutOfRange)
        end)

        it("clearRules(false) resets to defaults (d10 0 -> 10)", function()
            DiceVision.rules.valueMappings = {["d20"] = {[0] = 20}}
            DiceVision.rules.clampOutOfRange = true
            DiceVision.clearRules(false)
            assert.are.equal(10, DiceVision.rules.valueMappings["d10"][0])
            assert.is_nil(DiceVision.rules.valueMappings["d20"])
            assert.is_false(DiceVision.rules.clampOutOfRange)
        end)

        it("clearRules(true) clears everything including defaults", function()
            DiceVision.clearRules(true)
            assert.is_nil(next(DiceVision.rules.valueMappings))
            assert.is_nil(DiceVision.rules.diceSelection)
            assert.is_false(DiceVision.rules.clampOutOfRange)
        end)
    end)

    describe("DiceVision connection seams", function()
        local originalNetGet

        before_each(function()
            originalNetGet = _G.net.Get
        end)

        after_each(function()
            _G.net.Get = originalNetGet
        end)

        it("disconnect clears connection state, sets mode off, stops polling", function()
            DiceVision.connected = true
            DiceVision.sessionCode = "ABC"
            DiceVision.mode = "replace"
            DiceVision.isPolling = true
            DiceVision.disconnect()
            assert.is_false(DiceVision.connected)
            assert.is_nil(DiceVision.sessionCode)
            assert.are.equal("off", DiceVision.mode)
            assert.is_false(DiceVision.isPolling)
            assert.is_true(chatHas("Disconnected"))
        end)

        it("refreshHooks re-probes and confirms", function()
            DiceVision.codexDeclaredHooks = {ability = true}
            DiceVision.refreshHooks()
            assert.is_table(DiceVision.hooksRegistered)
            assert.is_true(chatHas("Hook probe refreshed"))
        end)

        it("testConnection fires onResult(true) and confirms on success", function()
            _G.net.Get = function(args) args.success({ok = true}) end
            local cbOk = nil
            DiceVision.testConnection(function(success) cbOk = success end)
            assert.is_true(cbOk)
            assert.is_true(chatHas("API is reachable!"))
        end)

        it("testConnection fires onResult(false) and reports on error", function()
            _G.net.Get = function(args) args.error("boom") end
            local cbOk = nil
            DiceVision.testConnection(function(success) cbOk = success end)
            assert.is_false(cbOk)
            assert.is_true(chatHas("API error:"))
        end)

        it("getStatus reports connected fields and no missing hooks when all registered", function()
            DiceVision.connected = true
            DiceVision.sessionCode = "ABC"
            DiceVision.mode = "replace"
            DiceVision.hooksRegistered = {ability = true, reroll = true, ["table"] = true}
            local s = DiceVision.getStatus()
            assert.is_true(s.connected)
            assert.are.equal("ABC", s.sessionCode)
            assert.are.equal("replace", s.mode)
            assert.are.equal(0, #s.missing)
        end)

        it("getStatus lists missing hooks by RollDialog name when none are registered", function()
            DiceVision.hooksRegistered = {ability = false, reroll = false, ["table"] = false}
            local s = DiceVision.getStatus()
            assert.are.equal(3, #s.missing)
            -- Pin the formatting contract (feeds both /dv status and the popup),
            -- not just the count, so a mislabeled hook name is caught.
            local joined = table.concat(s.missing, ",")
            assert.is_truthy(string.find(joined, "RollDialog.", 1, true))
            for _, name in ipairs({"RollDialog.OnBeforeRoll", "RollDialog.OnReroll", "RollDialog.OnBeforeTableRoll"}) do
                assert.is_truthy(string.find(joined, name, 1, true))
            end
        end)
    end)

    -- ============================================================================
    -- forcedDice path (engine forcedDice support behind DiceVision.useForcedDice)
    -- ============================================================================

    describe("forcedDice path", function()
        -- Drives a physical-dice delivery through the same polling seam the
        -- other handlePendingRoll suites use.
        local function deliverRoll(rollData)
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet
        end

        local function setupReplaceMode()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.useForcedDice = true
        end

        it("passes the intact expression and forcedDice to dmhub.Roll", function()
            setupReplaceMode()
            local setActiveRollArg = nil
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Forced Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function(roll) setActiveRollArg = roll end,
            }
            DiceVision.waitingForRoll = true

            -- Second die reads 0: the default d10 0->10 mapping must apply
            -- before the forcedDice table is built.
            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 0 },
                },
                total = 7,
            })

            assert.are.equal(1, #_G._dmhubRollLog)
            local logged = _G._dmhubRollLog[1]
            assert.are.equal("2d10+5", logged.roll)
            assert.are.same(
                {{numFaces = 10, result = 7}, {numFaces = 10, result = 10}},
                logged.forcedDice)
            -- Engine owns boons/banes and pacing on this path.
            assert.is_nil(logged.boons)
            assert.is_nil(logged.banes)
            assert.is_nil(logged.instant)
            -- setActiveRoll must receive the object dmhub.Roll returned
            -- (the stub returns {id = "roll-N"}), not just be called.
            assert.is_not_nil(setActiveRollArg)
            assert.are.equal("roll-1", setActiveRollArg.id)
        end)

        it("does not zero multitargets boons on targeted rolls", function()
            setupReplaceMode()
            local multitargets = {{ boons = 1, banes = 0 }}
            local props = {
                multitargets = multitargets,
                try_get = function(self, key) return rawget(self, key) end,
            }
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil, properties = props },
                originalRoll = "2d10+5",
                description = "Targeted Forced Test",
                edges = 1,
                banes = 0,
                multitargets = multitargets,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            })

            local logged = _G._dmhubRollLog[1]
            assert.are.equal("2d10+5", logged.roll)
            -- Legacy zeroed multitargets[1] to avoid double-counting a
            -- collapsed literal; with the expression intact the engine owns
            -- the boon math and the mod must not touch it.
            assert.are.equal(1, multitargets[1].boons)
            assert.is_nil(logged.boons)
        end)

        it("suppresses the DiceVision chat card by default", function()
            setupReplaceMode()
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "No Card Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            })

            for _, entry in ipairs(_G._chatLog) do
                assert.are_not.equal("custom", entry.type)
            end
            -- The complete wrapper is always installed (it carries the
            -- no-readable-dice note and the optional card send), but with
            -- the card off it must not send a custom message even after
            -- the roll completes.
            local logged = _G._dmhubRollLog[1]
            assert.is_function(logged.complete)
            logged.complete({ rolls = {
                { result = 7, numFaces = 10 },
                { result = 3, numFaces = 10 },
            }})
            for _, entry in ipairs(_G._chatLog) do
                assert.are_not.equal("custom", entry.type)
            end
        end)

        it("sends the chat card from the complete wrapper when enabled", function()
            setupReplaceMode()
            DiceVision.forcedDiceChatCard = true
            local originalCompleteCalled = false
            DiceVision.pendingRoll = {
                rollArgs = {
                    roll = "2d10+5",
                    creature = nil,
                    complete = function() originalCompleteCalled = true end,
                },
                originalRoll = "2d10+5",
                description = "Card Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 0 },
                },
                total = 7,
            })

            local logged = _G._dmhubRollLog[1]
            assert.is_function(logged.complete)

            -- Card only sends once the engine reports the roll complete.
            local customBefore = 0
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "custom" then customBefore = customBefore + 1 end
            end
            assert.are.equal(0, customBefore)

            logged.complete({})

            local card = nil
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "custom" then card = entry.message end
            end
            assert.is_not_nil(card)
            -- Card documents what the camera read: 7 + (0->10) + 5 = 22, T3.
            assert.are.equal(22, card.total)
            assert.are.equal(3, card.tier)
            assert.is_true(originalCompleteCalled)
        end)

        it("amends re-rolls with the original expression and forcedDice extraFields", function()
            setupReplaceMode()
            local amendFormula, amendExtra
            local props = {
                try_get = function(self, key) return rawget(self, key) end,
            }
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil, properties = props },
                originalRoll = "2d10+5",
                description = "Forced Re-roll",
                edges = 2,
                banes = 0,
                isReroll = true,
                amendWithResult = function(formula, extra)
                    amendFormula = formula
                    amendExtra = extra
                end,
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            })

            assert.are.equal("2d10+5", amendFormula)
            assert.is_not_nil(amendExtra)
            assert.are.same(
                {{numFaces = 10, result = 7}, {numFaces = 10, result = 3}},
                amendExtra.forcedDice)
            -- Tier shift is the engine's job now: no overrideTier write even
            -- for net +2 edges (legacy wrote 3 here).
            assert.is_nil(props.overrideTier)
            assert.are.equal(0, #_G._dmhubRollLog)
        end)

        it("falls back to the legacy path on dice-count mismatch", function()
            setupReplaceMode()
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10", creature = nil },
                originalRoll = "2d10",
                description = "Mismatch Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            -- Three physical dice for a 2d10 expression with no keep rule.
            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                    { type = "d10", value = 5 },
                },
                total = 15,
            })

            local logged = _G._dmhubRollLog[1]
            assert.is_not_nil(logged)
            -- Legacy collapse: deterministic literal, instant, no forcedDice.
            assert.are.equal("15", logged.roll)
            assert.is_true(logged.instant)
            assert.is_nil(logged.forcedDice)
            -- The mismatch is player-actionable, so the fallback must be
            -- announced in chat, not just the debug console.
            assert.is_true(chatHas("Physical dice do not match the roll"))
            assert.is_true(chatHas("wrong number of dice"))
        end)

        it("falls back to the legacy path for unsupported dice", function()
            setupReplaceMode()
            DiceVision.pendingRoll = {
                rollArgs = { roll = "1d100", creature = nil },
                originalRoll = "1d100",
                description = "Percentile Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                },
                total = 7,
            })

            local logged = _G._dmhubRollLog[1]
            assert.is_not_nil(logged)
            assert.is_nil(logged.forcedDice)
            assert.is_true(logged.instant)
            -- Pin the legacy total too, not just the absence of forcedDice.
            assert.are.equal("7", logged.roll)
        end)

        it("uses the engine ParseRoll/RollToString round-trip end to end", function()
            -- Production Codex has both APIs; the default test stubs force
            -- the textual fallback everywhere else, so this test wires live
            -- stubs to exercise the branch users actually run, including
            -- the creature pass-through.
            setupReplaceMode()
            local parseCreature = nil
            dmhub.ParseRoll = function(rollStr, creature)
                parseCreature = creature
                return { boons = 1, banes = 0 }
            end
            dmhub.RollToString = function(parsed) return "2d10+5" end
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5 1 edge", creature = "creature-9" },
                originalRoll = "2d10+5 1 edge",
                description = "Round-trip Test",
                edges = 1,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            })

            local logged = _G._dmhubRollLog[1]
            -- The ORIGINAL expression (with the edge) goes to the engine;
            -- the round-trip only cleans the dice-extraction input.
            assert.are.equal("2d10+5 1 edge", logged.roll)
            assert.are.same(
                {{numFaces = 10, result = 7}, {numFaces = 10, result = 3}},
                logged.forcedDice)
            assert.are.equal("creature-9", parseCreature)
        end)

        it("remaps Draw Steel d20-shaped d10s via the default type mapping", function()
            -- Draw Steel's official dice are 20-sided but numbered 1-10
            -- twice; the camera classifies by shape and reports "d20". The
            -- default d20 -> d10 type mapping lets them fill the
            -- expression's d10 slots instead of type-mismatching to legacy.
            setupReplaceMode()
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Draw Steel Dice Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d20", value = 7 },
                    { type = "d20", value = 3 },
                },
                total = 10,
            })

            local logged = _G._dmhubRollLog[1]
            assert.are.equal("2d10+5", logged.roll)
            assert.are.same(
                {{numFaces = 10, result = 7}, {numFaces = 10, result = 3}},
                logged.forcedDice)
            -- No fallback notice: the forced path handled it.
            assert.is_false(chatHas("Physical dice do not match the roll"))
        end)

        it("applies d10 value rules to type-remapped dice", function()
            -- A remapped Draw Steel die misread as 0 must pick up the d10
            -- 0 -> 10 value mapping (type mapping runs first).
            setupReplaceMode()
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10", creature = nil },
                originalRoll = "2d10",
                description = "Draw Steel Zero Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d20", value = 7 },
                    { type = "d20", value = 0 },
                },
                total = 7,
            })

            assert.are.same(
                {{numFaces = 10, result = 7}, {numFaces = 10, result = 10}},
                _G._dmhubRollLog[1].forcedDice)
        end)

        it("remaps 6-sided d3s via the default type mapping", function()
            -- d3s are 6-sided but numbered 1-3 twice; the camera reports
            -- them as "d6". The default d6 -> d3 mapping lets them fill a
            -- d3 expression's slots (the engine takes numFaces = 3 as a
            -- first-class die and renders it on the d6 model).
            setupReplaceMode()
            DiceVision.pendingRoll = {
                rollArgs = { roll = "1d3", creature = nil },
                originalRoll = "1d3",
                description = "d3 Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = { { type = "d6", value = 2 } },
                total = 2,
            })

            local logged = _G._dmhubRollLog[1]
            assert.are.equal("1d3", logged.roll)
            assert.are.same({{numFaces = 3, result = 2}}, logged.forcedDice)
            assert.is_false(chatHas("Physical dice do not match the roll"))
        end)

        it("falls back when a remapped d6 reads above 3 on a d3 roll", function()
            -- A REAL d6 (or a misread) showing 4-6 cannot be a d3 face:
            -- out-of-range refusal -> announced legacy fallback naming the
            -- mapping, with the value-correct total.
            setupReplaceMode()
            DiceVision.pendingRoll = {
                rollArgs = { roll = "1d3", creature = nil },
                originalRoll = "1d3",
                description = "d3 Range Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = { { type = "d6", value = 5 } },
                total = 5,
            })

            assert.is_true(chatHas("a die value out of range"))
            assert.is_true(chatHas("type mapping d6 -> d3 was applied"))
            local logged = _G._dmhubRollLog[1]
            assert.are.equal("5", logged.roll)
            assert.is_nil(logged.forcedDice)
        end)

        it("characterizes the real-d6 divert under the default mapping", function()
            -- Same trade-off as the real d20: a REAL d6 rolled for a d6
            -- expression is remapped to d3 and can never fill the d6 slot
            -- -> announced legacy fallback naming the mapping.
            setupReplaceMode()
            DiceVision.pendingRoll = {
                rollArgs = { roll = "1d6", creature = nil },
                originalRoll = "1d6",
                description = "Real d6 Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = { { type = "d6", value = 4 } },
                total = 4,
            })

            assert.is_true(chatHas("wrong die types"))
            assert.is_true(chatHas("type mapping d6 -> d3 was applied"))
            -- The literal escape hatch at the moment of friction.
            assert.is_true(chatHas("remove with /dv rules type d6 clear"))
            local logged = _G._dmhubRollLog[1]
            assert.are.equal("4", logged.roll)
            assert.is_true(logged.instant)
            assert.is_nil(logged.forcedDice)
        end)

        it("characterizes the real-d20 divert under the default mapping", function()
            -- Ships enabled by default: a REAL d20 rolled for a d20
            -- expression is remapped to d10 by the default rule, so it can
            -- never fill the d20 slot -> announced legacy fallback. The
            -- notice must NAME the mapping -- the user rolled exactly the
            -- right die, and 'wrong die types' alone would be a permanent,
            -- undiagnosable puzzle.
            setupReplaceMode()
            DiceVision.pendingRoll = {
                rollArgs = { roll = "1d20", creature = nil },
                originalRoll = "1d20",
                description = "Real d20 Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = { { type = "d20", value = 14 } },
                total = 14,
            })

            assert.is_true(chatHas("wrong die types"))
            assert.is_true(chatHas("type mapping d20 -> d10 was applied"))
            assert.is_true(chatHas("remove with /dv rules type d20 clear"))
            -- Legacy fallback keeps the roll value-correct.
            local logged = _G._dmhubRollLog[1]
            assert.are.equal("14", logged.roll)
            assert.is_true(logged.instant)
            assert.is_nil(logged.forcedDice)
        end)

        it("remapped dice survive keep-surplus reconciliation", function()
            setupReplaceMode()
            DiceVision.rules.diceSelection = { keep = "highest", count = 2 }
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Remap Keep Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d20", value = 7 },
                    { type = "d20", value = 3 },
                    { type = "d20", value = 5 },
                },
                total = 15,
            })

            -- All three remap to d10, keep-highest 2 selects 7 and 5, and
            -- the remapped type must survive selection into the slots.
            assert.are.same(
                {{numFaces = 10, result = 7}, {numFaces = 10, result = 5}},
                _G._dmhubRollLog[1].forcedDice)
        end)

        it("clamps a remapped misread before forcing when clamp is on", function()
            setupReplaceMode()
            DiceVision.rules.clampOutOfRange = true
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10", creature = nil },
                originalRoll = "2d10",
                description = "Remap Clamp Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            -- A d20-shaped die misread as 15: remap to d10, clamp 15 -> 1.
            deliverRoll({
                dice = {
                    { type = "d20", value = 15 },
                    { type = "d20", value = 7 },
                },
                total = 22,
            })

            assert.are.same(
                {{numFaces = 10, result = 1}, {numFaces = 10, result = 7}},
                _G._dmhubRollLog[1].forcedDice)
        end)

        it("falls back on a remapped out-of-range value when clamp is off", function()
            setupReplaceMode()
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10", creature = nil },
                originalRoll = "2d10",
                description = "Remap Out-of-range Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d20", value = 15 },
                    { type = "d20", value = 7 },
                },
                total = 22,
            })

            assert.is_true(chatHas("a die value out of range"))
            assert.is_true(chatHas("type mapping d20 -> d10 was applied"))
            local logged = _G._dmhubRollLog[1]
            assert.are.equal("22", logged.roll)
            assert.is_nil(logged.forcedDice)
        end)

        it("amends re-rolls with remapped Draw Steel dice", function()
            setupReplaceMode()
            local amendFormula, amendExtra
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Remap Re-roll Test",
                edges = 0,
                banes = 0,
                isReroll = true,
                amendWithResult = function(formula, extra)
                    amendFormula = formula
                    amendExtra = extra
                end,
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d20", value = 7 },
                    { type = "d20", value = 3 },
                },
                total = 10,
            })

            assert.are.equal("2d10+5", amendFormula)
            assert.are.same(
                {{numFaces = 10, result = 7}, {numFaces = 10, result = 3}},
                amendExtra.forcedDice)
        end)

        it("characterizes the d10-centric clamp on non-d10 dice", function()
            -- Known limitation pinned on purpose: the clamp rule is defined
            -- as "outside 0-10 -> 1", so with clamp enabled a legitimate
            -- physical d20 result above 10 is clamped to 1 and forced as
            -- such. Users rolling non-d10 dice should keep clamp off.
            setupReplaceMode()
            DiceVision.rules.clampOutOfRange = true
            -- Clear the default d20 -> d10 type mapping: this test is about
            -- clamp on a REAL d20, which the mapping would divert to a d10
            -- slot mismatch.
            DiceVision.rules.typeMappings = {}
            DiceVision.pendingRoll = {
                rollArgs = { roll = "1d20", creature = nil },
                originalRoll = "1d20",
                description = "Clamp d20 Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d20", value = 15 },
                },
                total = 15,
            })

            local logged = _G._dmhubRollLog[1]
            assert.are.same({{numFaces = 20, result = 1}}, logged.forcedDice)
        end)

        it("uses the legacy path when the toggle is off", function()
            setupReplaceMode()
            DiceVision.useForcedDice = false
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Toggle Off Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            })

            local logged = _G._dmhubRollLog[1]
            assert.are.equal("15", logged.roll)
            assert.is_true(logged.instant)
            assert.is_nil(logged.forcedDice)
        end)

        it("never disables on a value mismatch, even as the FIRST completion", function()
            -- The reported power-roll bug: Codex's doRerollAmend re-fires
            -- the initial wrapper with the reroll's rollInfo BEFORE the
            -- initial completion, so the wrapper's first completion is a
            -- value mismatch against the initial forced set -- yet the dice
            -- were honored. Verification must NEVER disable or warn on a
            -- value mismatch.
            setupReplaceMode()
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Mismatch First Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            })

            local complete = _G._dmhubRollLog[1].complete
            assert.is_function(complete)
            -- First completion carries different (reroll) values.
            complete({ rolls = {
                { result = 2, numFaces = 10 },
                { result = 9, numFaces = 10 },
            }})

            assert.is_true(DiceVision.useForcedDice)
            assert.is_false(chatHas("WARNING"))
            assert.is_false(chatHas("ignored forcedDice"))
            -- A mismatch (false) must not trigger the no-readable-dice note
            -- either: honored == nil is its ONLY trigger. If it fired here
            -- it would fire on every power-roll reroll re-fire, and setting
            -- the latch would also suppress the legitimate note later.
            assert.is_false(chatHas("couldn't read the dice"))
            assert.is_false(DiceVision.warnedUnverifiedForcedDice)
        end)

        it("does not fall back to legacy when setActiveRoll throws", function()
            -- dmhub.Roll has already fired by the time setActiveRoll runs.
            -- An error escaping to handlePendingRoll's pcall would trigger
            -- the legacy fallback and roll a SECOND time on top of the
            -- forced roll; it must be contained inside tryForcedDicePath.
            setupReplaceMode()
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "setActiveRoll Throw Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() error("wiring failure") end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            })

            -- Exactly one engine roll, and it is the forced one (intact
            -- expression + forcedDice), not a legacy collapsed total.
            assert.are.equal(1, #_G._dmhubRollLog)
            assert.are.equal("2d10+5", _G._dmhubRollLog[1].roll)
            assert.is_not_nil(_G._dmhubRollLog[1].forcedDice)
        end)

        it("notes once (quietly) when the engine returns no readable dice, without disabling", function()
            -- honored == nil (no readable rolls) is the only signal we keep.
            -- It never disables; it says so once per session. Rerolls yield
            -- a value mismatch (false), never nil, so they do not trigger it.
            setupReplaceMode()
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Unreadable Dice Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            })

            _G._dmhubRollLog[1].complete({})

            assert.is_true(DiceVision.useForcedDice)
            assert.is_true(chatHas("couldn't read the dice results"))
            assert.is_false(chatHas("WARNING"))
            assert.is_true(DiceVision.warnedUnverifiedForcedDice)

            -- Second unreadable completion: no repeat note.
            local before = #_G._chatLog
            _G._dmhubRollLog[1].complete({})
            local newNotes = 0
            for i = before + 1, #_G._chatLog do
                if _G._chatLog[i].type == "send"
                    and string.find(_G._chatLog[i].message, "couldn't read the dice", 1, true) then
                    newNotes = newNotes + 1
                end
            end
            assert.are.equal(0, newNotes)
        end)

        it("stays enabled when the engine honored forcedDice", function()
            setupReplaceMode()
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Supported Build Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            })

            _G._dmhubRollLog[1].complete({ rolls = {
                { result = 7, numFaces = 10 },
                { result = 3, numFaces = 10 },
            }})

            assert.is_true(DiceVision.useForcedDice)
            assert.is_false(chatHas("WARNING"))
        end)

        it("re-enabling re-arms the once-per-session unverifiable note", function()
            DiceVision.warnedUnverifiedForcedDice = true
            DiceVision.useForcedDice = false
            Commands.dv("forceddice on")
            assert.is_true(DiceVision.useForcedDice)
            assert.is_false(DiceVision.warnedUnverifiedForcedDice)
        end)

        it("still calls the original complete when the card send throws", function()
            setupReplaceMode()
            DiceVision.forcedDiceChatCard = true
            local originalCompleteCalled = false
            DiceVision.pendingRoll = {
                rollArgs = {
                    roll = "2d10+5",
                    creature = nil,
                    complete = function() originalCompleteCalled = true end,
                },
                originalRoll = "2d10+5",
                description = "Card Throw Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            })

            local originalSendCustom = chat.SendCustom
            chat.SendCustom = function() error("card render failed") end
            _G._dmhubRollLog[1].complete({ rolls = {
                { result = 7, numFaces = 10 },
                { result = 3, numFaces = 10 },
            }})
            chat.SendCustom = originalSendCustom

            -- The cosmetic card must never block Codex's completion logic.
            assert.is_true(originalCompleteCalled)
        end)

        it("falls back to the legacy reroll amend when forced construction fails on a reroll", function()
            setupReplaceMode()
            local amendFormula, amendExtra
            local props = {
                try_get = function(self, key) return rawget(self, key) end,
            }
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil, properties = props },
                originalRoll = "2d10+5",
                description = "Reroll Fallback Test",
                edges = 2,
                banes = 0,
                isReroll = true,
                amendWithResult = function(formula, extra)
                    amendFormula = formula
                    amendExtra = extra
                end,
                activeRoll = { id = "roll-1" },
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            -- Three physical dice for a 2d10 expression: count mismatch on
            -- the forced path must land in the LEGACY reroll amend, which
            -- collapses to a literal and writes overrideTier for net +2.
            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                    { type = "d10", value = 5 },
                },
                total = 15,
            })

            -- Legacy: diceSum 15 + modifier 5 = 20, net +2 edges = no flat
            -- mod, tier 3 override.
            assert.are.equal("20", amendFormula)
            assert.is_nil(amendExtra)
            assert.are.equal(3, props.overrideTier)
            assert.are.equal(0, #_G._dmhubRollLog)
        end)

        it("reconciles surplus dice with an explicit keep rule before forcing", function()
            setupReplaceMode()
            DiceVision.rules.diceSelection = { keep = "highest", count = 2 }
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Surplus Keep Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                    { type = "d10", value = 5 },
                },
                total = 15,
            })

            local logged = _G._dmhubRollLog[1]
            assert.are.equal("2d10+5", logged.roll)
            -- Keep-highest 2 of {7,3,5} -> the two highest values forced.
            assert.are.same(
                {{numFaces = 10, result = 7}, {numFaces = 10, result = 5}},
                logged.forcedDice)
        end)

        it("falls back to legacy when the keep rule cannot reconcile the count", function()
            setupReplaceMode()
            DiceVision.rules.diceSelection = { keep = "highest", count = 1 }
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10", creature = nil },
                originalRoll = "2d10",
                description = "Keep Mismatch Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            -- Keep 1 of 3 leaves 1 die for a 2-die expression: still a count
            -- mismatch, so legacy must take over.
            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                    { type = "d10", value = 5 },
                },
                total = 15,
            })

            local logged = _G._dmhubRollLog[1]
            assert.is_nil(logged.forcedDice)
            assert.is_true(logged.instant)
        end)

        it("falls back to legacy when the forced path raises an error", function()
            -- The pcall at the fork is what keeps the "a roll is never
            -- lost" contract true even for unanticipated errors (and stops
            -- isPolling from being stranded true).
            setupReplaceMode()
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Error Fallback Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            local originalExtract = DiceRollLogic.extractExpectedDiceList
            DiceRollLogic.extractExpectedDiceList = function() error("boom") end
            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            })
            DiceRollLogic.extractExpectedDiceList = originalExtract

            local logged = _G._dmhubRollLog[1]
            assert.is_not_nil(logged)
            assert.are.equal("15", logged.roll)
            assert.is_true(logged.instant)
            assert.is_nil(logged.forcedDice)
            assert.is_false(DiceVision.isPolling)
        end)
    end)

    -- ============================================================================
    -- Panel forcedDice path (panel rolls shown as engine virtual dice)
    -- ============================================================================

    describe("panel forcedDice path", function()
        -- Drives a physical-dice delivery through the polling seam with the
        -- panel (not a pending Codex roll) waiting for dice.
        local function deliverRoll(rollData)
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet
        end

        local function setupPanelWaiting()
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.useForcedDice = true
            DiceVision.panelWaitingForRoll = true
            DiceVision.panelRequestId = "req-panel"
            DiceVision.panelTokenId = "token-1"
        end

        local function customChatEntries()
            local entries = {}
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "custom" then
                    entries[#entries + 1] = entry
                end
            end
            return entries
        end

        it("rolls engine virtual dice from an expression built from the physical dice", function()
            setupPanelWaiting()

            -- Second die reads 0: the d10 0->10 value mapping applies on
            -- panel rolls too, before the forcedDice table is built.
            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 0 },
                },
                total = 7,
            })

            assert.are.equal(1, #_G._dmhubRollLog)
            local logged = _G._dmhubRollLog[1]
            assert.are.equal("2d10", logged.roll)
            assert.are.same(
                {{numFaces = 10, result = 7}, {numFaces = 10, result = 10}},
                logged.forcedDice)
            assert.are.equal("Physical Dice Roll", logged.description)
            assert.are.equal("token-1", logged.tokenid)
            -- Cosmetic roll: no game fields, engine owns pacing.
            assert.is_nil(logged.boons)
            assert.is_nil(logged.banes)
            assert.is_nil(logged.instant)
            -- Panel state consumed.
            assert.is_false(DiceVision.panelWaitingForRoll)
            assert.is_nil(DiceVision.panelTokenId)
        end)

        it("builds a mixed-type expression largest die first", function()
            setupPanelWaiting()

            deliverRoll({
                dice = {
                    { type = "d8", value = 5 },
                    { type = "d12", value = 11 },
                },
                total = 16,
            })

            local logged = _G._dmhubRollLog[1]
            assert.are.equal("1d12+1d8", logged.roll)
            assert.are.same(
                {{numFaces = 12, result = 11}, {numFaces = 8, result = 5}},
                logged.forcedDice)
        end)

        it("suppresses the DiceVision chat card by default", function()
            setupPanelWaiting()

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            })

            assert.are.equal(0, #customChatEntries())
            -- The complete wrapper is installed (honor note + optional
            -- card) but must not send a card with the toggle off.
            local logged = _G._dmhubRollLog[1]
            assert.is_function(logged.complete)
            logged.complete({ rolls = {
                { result = 7, numFaces = 10 },
                { result = 3, numFaces = 10 },
            }})
            assert.are.equal(0, #customChatEntries())
        end)

        it("sends the DiceVision card after completion when the card is enabled", function()
            setupPanelWaiting()
            DiceVision.forcedDiceChatCard = true

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            })

            -- Card only fires from the complete wrapper, after the engine
            -- roll resolves.
            assert.are.equal(0, #customChatEntries())
            local logged = _G._dmhubRollLog[1]
            logged.complete({ rolls = {
                { result = 7, numFaces = 10 },
                { result = 3, numFaces = 10 },
            }})
            local cards = customChatEntries()
            assert.are.equal(1, #cards)
            local card = cards[1].message
            assert.are.equal("Physical Dice Roll", card.description)
            assert.are.equal("panel", card.rollSource)
            assert.are.equal(10, card.total)
            assert.are.equal("token-1", card.tokenid)
        end)

        it("stays chat-card-only when forcedDice is off", function()
            setupPanelWaiting()
            DiceVision.useForcedDice = false

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                },
                total = 10,
            })

            assert.are.equal(0, #_G._dmhubRollLog)
            local cards = customChatEntries()
            assert.are.equal(1, #cards)
            assert.are.equal("Physical Dice Roll", cards[1].message.description)
            assert.is_false(DiceVision.panelWaitingForRoll)
        end)

        it("keeps percentile pairs on the chat card display", function()
            setupPanelWaiting()

            -- String values so the conversion seam preserves rawValue
            -- ("30" tens + "7" units), matching real API payloads.
            deliverRoll({
                dice = {
                    { type = "d10", value = "30" },
                    { type = "d10", value = "7" },
                },
                total = 37,
            })

            assert.are.equal(0, #_G._dmhubRollLog)
            local cards = customChatEntries()
            assert.are.equal(1, #cards)
            assert.is_true(cards[1].message.isPercentile)
            assert.are.equal(37, cards[1].message.total)
        end)

        it("falls back to the chat card for unsupported die types", function()
            setupPanelWaiting()

            deliverRoll({
                dice = { { type = "d100", value = 40 } },
                total = 40,
            })

            assert.are.equal(0, #_G._dmhubRollLog)
            local cards = customChatEntries()
            assert.are.equal(1, #cards)
            -- The fallback card must keep the token attribution.
            assert.are.equal("token-1", cards[1].message.tokenid)
            assert.is_nil(DiceVision.panelTokenId)
        end)

        it("falls back to the chat card for out-of-range values", function()
            setupPanelWaiting()
            -- Without the default 0->10 mapping an unmapped d10 zero is
            -- out of range for the engine; refuse and use the card.
            DiceVision.rules.valueMappings = {}

            deliverRoll({
                dice = { { type = "d10", value = 0 } },
                total = 0,
            })

            assert.are.equal(0, #_G._dmhubRollLog)
            assert.are.equal(1, #customChatEntries())
        end)

        it("excludes keep-rule dropped dice from the expression", function()
            setupPanelWaiting()
            DiceVision.rules.diceSelection = {keep = "highest", count = 2}

            deliverRoll({
                dice = {
                    { type = "d10", value = 7 },
                    { type = "d10", value = 3 },
                    { type = "d10", value = 5 },
                },
                total = 15,
            })

            local logged = _G._dmhubRollLog[1]
            assert.are.equal("2d10", logged.roll)
            assert.are.same(
                {{numFaces = 10, result = 7}, {numFaces = 10, result = 5}},
                logged.forcedDice)
        end)

        it("remaps d20 physicals when type mappings apply to panel rolls", function()
            setupPanelWaiting()
            DiceVision.rules.typeMappingsOnPanel = true

            deliverRoll({
                dice = {
                    { type = "d20", value = 7 },
                    { type = "d20", value = 3 },
                },
                total = 10,
            })

            local logged = _G._dmhubRollLog[1]
            assert.are.equal("2d10", logged.roll)
            assert.are.same(
                {{numFaces = 10, result = 7}, {numFaces = 10, result = 3}},
                logged.forcedDice)
        end)

        it("keeps a d20 a d20 when type mappings do not apply to panel rolls", function()
            setupPanelWaiting()
            assert.is_false(DiceVision.rules.typeMappingsOnPanel)

            deliverRoll({
                dice = { { type = "d20", value = 15 } },
                total = 15,
            })

            local logged = _G._dmhubRollLog[1]
            assert.are.equal("1d20", logged.roll)
            assert.are.same({{numFaces = 20, result = 15}}, logged.forcedDice)
        end)

        it("notes once when the engine returns no readable dice", function()
            setupPanelWaiting()

            deliverRoll({
                dice = { { type = "d10", value = 7 } },
                total = 7,
            })

            local logged = _G._dmhubRollLog[1]
            logged.complete({})
            assert.is_true(DiceVision.warnedUnverifiedForcedDice)
            assert.is_true(chatHas("couldn't read the dice results"))
            -- Never disables, and never repeats the note.
            assert.is_true(DiceVision.useForcedDice)
            local noteCount = 0
            logged.complete({})
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "send" and entry.message:find("couldn't read the dice results", 1, true) then
                    noteCount = noteCount + 1
                end
            end
            assert.are.equal(1, noteCount)
        end)

        it("falls back to the chat card when the forced path raises an error", function()
            setupPanelWaiting()

            local originalBuild = DiceRollLogic.buildPanelRollExpression
            DiceRollLogic.buildPanelRollExpression = function() error("boom") end
            deliverRoll({
                dice = { { type = "d10", value = 7 } },
                total = 7,
            })
            DiceRollLogic.buildPanelRollExpression = originalBuild

            assert.are.equal(0, #_G._dmhubRollLog)
            assert.are.equal(1, #customChatEntries())
            assert.is_false(DiceVision.panelWaitingForRoll)
            assert.is_false(DiceVision.isPolling)
        end)
    end)

    -- ============================================================================
    -- /dv forceddice command and status
    -- ============================================================================

    describe("/dv forceddice command", function()
        it("enables forcedDice with on", function()
            Commands.dv("forceddice on")
            assert.is_true(DiceVision.useForcedDice)
            assert.is_true(chatHas("forcedDice enabled"))
        end)

        it("disables forcedDice with off", function()
            DiceVision.useForcedDice = true
            Commands.dv("forceddice off")
            assert.is_false(DiceVision.useForcedDice)
            assert.is_true(chatHas("forcedDice disabled"))
        end)

        it("enables the chat card with card on", function()
            Commands.dv("forceddice card on")
            assert.is_true(DiceVision.forcedDiceChatCard)
            assert.is_true(chatHas("chat card enabled"))
        end)

        it("disables the chat card with card off", function()
            DiceVision.forcedDiceChatCard = true
            Commands.dv("forceddice card off")
            assert.is_false(DiceVision.forcedDiceChatCard)
            assert.is_true(chatHas("chat card disabled"))
        end)

        it("shows usage for card without on/off", function()
            Commands.dv("forceddice card")
            assert.is_true(chatHas("/dv forceddice card <on|off>"))
        end)

        it("shows current state and usage with no argument", function()
            Commands.dv("forceddice")
            assert.is_true(chatHas("forcedDice: off"))
            assert.is_true(chatHas("/dv forceddice <on|off>"))
        end)

        it("reports state through getStatus and /dv status", function()
            DiceVision.useForcedDice = true
            local s = DiceVision.getStatus()
            assert.is_true(s.useForcedDice)
            assert.is_false(s.forcedDiceChatCard)

            Commands.dv("status")
            assert.is_true(chatHas("ForcedDice: on (chat card: off)"))
        end)
    end)

    -- ============================================================================
    -- Type mapping rules (/dv rules type) and panel gating
    -- ============================================================================

    describe("type mapping rules", function()
        it("panel rolls keep the reported die type by default", function()
            local rollData = {
                dice = {
                    { type = "d20", value = 7 },
                    { type = "d20", value = 3 },
                },
                total = 10,
            }
            DiceVision.postRollToChat(rollData)
            local msg = _G._chatLog[1].message
            -- Message dice carry face counts; unmapped d20s stay 20-faced.
            assert.are.equal(20, msg.dice[1].faces)
            assert.are.equal(20, msg.dice[2].faces)
        end)

        it("panel rolls remap when typeMappingsOnPanel is enabled", function()
            DiceVision.rules.typeMappingsOnPanel = true
            local rollData = {
                dice = {
                    { type = "d20", value = 7 },
                },
                total = 7,
            }
            DiceVision.postRollToChat(rollData)
            local msg = _G._chatLog[1].message
            assert.are.equal(10, msg.dice[1].faces)
        end)

        it("adds a type mapping via /dv rules type", function()
            DiceVision.rules.typeMappings = {}
            Commands.dv("rules type d12 d6")
            assert.are.equal("d6", DiceVision.rules.typeMappings["d12"])
            assert.is_true(chatHas("Type mapping: d12 -> d6"))
        end)

        it("normalizes case and rejects invalid or self mappings", function()
            Commands.dv("rules type D12 D6")
            assert.are.equal("d6", DiceVision.rules.typeMappings["d12"])

            assert.is_false(DiceVision.setTypeMapping("d10", "d10"))
            assert.is_false(DiceVision.setTypeMapping("banana", "d10"))
            assert.is_false(DiceVision.setTypeMapping("d10", nil))
        end)

        it("removes a type mapping via /dv rules type <from> clear", function()
            Commands.dv("rules type d20 clear")
            assert.is_nil(DiceVision.rules.typeMappings["d20"])
            assert.is_true(chatHas("Removed type mapping for d20"))

            _G._chatLog = {}
            Commands.dv("rules type d20 clear")
            assert.is_true(chatHas("No type mapping for d20"))
        end)

        it("toggles panel application via /dv rules type panel", function()
            Commands.dv("rules type panel on")
            assert.is_true(DiceVision.rules.typeMappingsOnPanel)
            Commands.dv("rules type panel off")
            assert.is_false(DiceVision.rules.typeMappingsOnPanel)
            _G._chatLog = {}
            Commands.dv("rules type panel bogus")
            assert.is_true(chatHas("/dv rules type panel <on|off>"))
        end)

        it("shows type mappings in /dv rules show and bare /dv rules type", function()
            Commands.dv("rules show")
            assert.is_true(chatHas("Type mappings:"))
            assert.is_true(chatHas("d20 -> d10"))
            assert.is_true(chatHas("Type mappings on panel rolls: disabled"))

            _G._chatLog = {}
            Commands.dv("rules type")
            assert.is_true(chatHas("d20 -> d10"))
            assert.is_true(chatHas("Panel rolls: off"))
        end)

        it("rules clear restores the default type mappings; clear all empties them", function()
            DiceVision.rules.typeMappings = {}
            DiceVision.rules.typeMappingsOnPanel = true
            Commands.dv("rules clear")
            assert.are.equal("d10", DiceVision.rules.typeMappings["d20"])
            assert.are.equal("d3", DiceVision.rules.typeMappings["d6"])
            assert.is_false(DiceVision.rules.typeMappingsOnPanel)

            Commands.dv("rules clear all")
            assert.is_nil(next(DiceVision.rules.typeMappings))
        end)

        it("module load applied DEFAULT_RULES (not just the test helper)", function()
            -- resetDiceVisionState overwrites rules with the helper's copy
            -- of the defaults before every test; this asserts the snapshot
            -- taken at module-load time, so deleting the DEFAULT_RULES
            -- copy loop in DiceVision.lua fails a test.
            assert.is_not_nil(_G._loadTimeRules)
            assert.are.equal("d10", _G._loadTimeRules.d20TypeMapping)
            assert.are.equal("d3", _G._loadTimeRules.d6TypeMapping)
            assert.are.equal(10, _G._loadTimeRules.d10ZeroMapping)
            assert.is_false(_G._loadTimeRules.typeMappingsOnPanel)
            -- Production defaults: forcedDice path ON (never auto-disables;
            -- unsupported builds need a manual /dv forceddice off), chat
            -- card off.
            assert.is_true(_G._loadTimeRules.useForcedDice)
            assert.is_false(_G._loadTimeRules.forcedDiceChatCard)
        end)

        it("drives a roll at the exact shipped defaults", function()
            -- Behavior pin for the production configuration, not just the
            -- value snapshot: restore the load-time toggles over the
            -- fixture baseline (rules already match the shipped defaults,
            -- asserted here) and confirm a Draw Steel roll takes the
            -- forced path.
            assert.are.equal("d10", DiceVision.rules.typeMappings["d20"])
            assert.are.equal("d3", DiceVision.rules.typeMappings["d6"])
            assert.are.equal(10, DiceVision.rules.valueMappings["d10"][0])
            DiceVision.useForcedDice = _G._loadTimeRules.useForcedDice
            DiceVision.forcedDiceChatCard = _G._loadTimeRules.forcedDiceChatCard
            assert.is_true(DiceVision.useForcedDice)

            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10+5", creature = nil },
                originalRoll = "2d10+5",
                description = "Shipped Defaults Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = {
                    { type = "d20", value = 7 },
                    { type = "d20", value = 0 },
                },
                total = 7,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            local logged = _G._dmhubRollLog[1]
            assert.are.equal("2d10+5", logged.roll)
            assert.are.same(
                {{numFaces = 10, result = 7}, {numFaces = 10, result = 10}},
                logged.forcedDice)
        end)

        it("legacy path card shows faces 3 for a remapped d3", function()
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.useForcedDice = false
            DiceVision.pendingRoll = {
                rollArgs = { roll = "1d3", creature = nil },
                originalRoll = "1d3",
                description = "Legacy d3 Card Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = { { type = "d6", value = 2 } },
                total = 2,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            local logged = _G._dmhubRollLog[1]
            assert.are.equal("2", logged.roll)
            logged.complete({})
            local card = nil
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "custom" then card = entry.message end
            end
            assert.is_not_nil(card)
            assert.are.equal(3, card.dice[1].faces)
            assert.are.equal(2, card.dice[1].value)
        end)

        it("legacy path remaps Draw Steel dice end to end", function()
            -- The legacy collapse path stays reachable (/dv forceddice off,
            -- or a per-roll fallback when forced construction fails), and
            -- the remap + d10 0->10 value rule must fire there too.
            DiceVision.mode = "replace"
            DiceVision.connected = true
            DiceVision.sessionCode = "TEST"
            DiceVision.useForcedDice = false
            DiceVision.pendingRoll = {
                rollArgs = { roll = "2d10", creature = nil },
                originalRoll = "2d10",
                description = "Legacy Draw Steel Test",
                edges = 0,
                banes = 0,
                setActiveRoll = function() end,
            }
            DiceVision.waitingForRoll = true

            local rollData = {
                dice = {
                    { type = "d20", value = 7 },
                    { type = "d20", value = 0 },
                },
                total = 7,
            }
            local originalNetGet = net.Get
            net.Get = function(args)
                if args.success then
                    args.success({ rolls = { rollData } })
                end
            end
            DiceVision.isPolling = false
            DiceVision.startPolling()
            net.Get = originalNetGet

            -- Legacy collapse: 7 + (0 -> 10) = 17.
            local logged = _G._dmhubRollLog[1]
            assert.are.equal("17", logged.roll)
            assert.is_true(logged.instant)

            -- The card (sent from the legacy complete wrapper) must show
            -- remapped d10 faces and the mapped value.
            logged.complete({})
            local card = nil
            for _, entry in ipairs(_G._chatLog) do
                if entry.type == "custom" then card = entry.message end
            end
            assert.is_not_nil(card)
            assert.are.equal(10, card.dice[1].faces)
            assert.are.equal(10, card.dice[2].faces)
            assert.are.equal(10, card.dice[2].value)
            assert.are.equal(17, card.total)
        end)

        it("panel remapping cannot cause percentile misdetection", function()
            -- Percentile detection takes the RAW dice; even with the panel
            -- opt-in enabled, a Draw Steel pair reading 00 + 7 must post a
            -- standard roll, not a bogus d100. Guard for the ordering: if
            -- someone moves the remap ahead of detection, the remapped
            -- d10s with these rawValues would misdetect.
            DiceVision.rules.typeMappingsOnPanel = true
            local rollData = {
                dice = {
                    { type = "d20", value = 0, rawValue = "00" },
                    { type = "d20", value = 7, rawValue = "7" },
                },
                total = 7,
            }
            DiceVision.postRollToChat(rollData)
            local msg = _G._chatLog[1].message
            assert.are_not.equal("Percentile Roll (d100)", msg.description)
            -- Standard panel message with remapped faces + 0->10 value rule.
            assert.are.equal(10, msg.dice[1].faces)
            assert.are.equal(10, msg.dice[1].value)
            assert.are.equal(10, msg.dice[2].faces)
            assert.are.equal(17, msg.total)
        end)

        it("keywords are case-insensitive in /dv rules type", function()
            Commands.dv("rules type PANEL on")
            assert.is_true(DiceVision.rules.typeMappingsOnPanel)

            Commands.dv("rules type D20 CLEAR")
            assert.is_nil(DiceVision.rules.typeMappings["d20"])
        end)

        it("rejects unforceable mapping targets", function()
            Commands.dv("rules type d10 d100")
            assert.is_nil(DiceVision.rules.typeMappings["d10"])
            assert.is_true(chatHas("Target die must be one of"))
        end)

        it("setTypeMapping returns failure-specific reasons for the popup", function()
            local ok, reason = DiceVision.setTypeMapping("d10", "d10")
            assert.is_false(ok)
            assert.are.equal("self", reason)

            ok, reason = DiceVision.setTypeMapping("d10", "d100")
            assert.is_false(ok)
            assert.are.equal("target", reason)

            ok, reason = DiceVision.setTypeMapping("banana", "d10")
            assert.is_false(ok)
            assert.are.equal("usage", reason)
        end)
    end)
end)
