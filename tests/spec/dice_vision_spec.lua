-- Tests for DiceVision (Codex/mods/DiceVision_5554/DiceVision.lua)

describe("DiceVision", function()
    setup(function()
        loadDiceVision()
    end)

    before_each(function()
        resetDiceVisionState()
    end)

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
            local setActiveRollCalled = nil
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
        -- Testing the helper directly (not just setMode) ensures a regression
        -- in DVDicePanel's call site -- e.g. accidentally passing a literal
        -- mode instead of letting the helper compute it -- is still caught.
        it("toggle from off to replace emits missing-hook warning when slot is missing", function()
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
    end)
end)
