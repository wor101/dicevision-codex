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
    -- Category 4: Re-roll Functionality
    -- ============================================================================

    describe("onBeforeRoll saves lastInterceptedContext", function()
        it("stores originalRoll, description, edges, banes, multitargets", function()
            DiceVision.connected = true
            DiceVision.setMode("replace")

            local rollArgs = {
                roll = "2d10+3",
                description = "Power Roll",
                complete = nil,
                instant = false,
            }

            RollDialog.OnBeforeRoll({
                rollArgs = rollArgs,
                roll = "2d10+3",
                description = "Power Roll",
                boons = 0,
                multitargets = nil,
            })

            local saved = DiceVision.lastInterceptedContext
            assert.is_not_nil(saved)
            assert.are.equal("2d10+3", saved.originalRoll)
            assert.are.equal("Power Roll", saved.description)
            assert.are.equal(0, saved.edges)
            assert.are.equal(0, saved.banes)
        end)

        it("stores originalComplete and originalInstant from rollArgs", function()
            DiceVision.connected = true
            DiceVision.setMode("replace")

            local completeFn = function() end
            local rollArgs = {
                roll = "2d10",
                description = "Test",
                complete = completeFn,
                instant = true,
            }

            RollDialog.OnBeforeRoll({
                rollArgs = rollArgs,
                roll = "2d10",
                description = "Test",
                boons = 0,
                multitargets = nil,
            })

            local saved = DiceVision.lastInterceptedContext
            assert.are.equal(completeFn, saved.originalComplete)
            assert.are.equal(true, saved.originalInstant)
        end)

        it("stores edges and banes from boons context", function()
            DiceVision.connected = true
            DiceVision.setMode("replace")

            local rollArgs = {
                roll = "2d10",
                description = "Test",
                complete = nil,
                instant = false,
            }

            RollDialog.OnBeforeRoll({
                rollArgs = rollArgs,
                roll = "2d10",
                description = "Test",
                boons = 1,  -- 1 edge
                multitargets = nil,
            })

            local saved = DiceVision.lastInterceptedContext
            assert.are.equal(1, saved.edges)
            assert.are.equal(0, saved.banes)
        end)

        it("stores multitargets when present", function()
            DiceVision.connected = true
            DiceVision.setMode("replace")

            local targets = {{boons = 0, banes = 0}}
            local rollArgs = {
                roll = "2d10",
                description = "Test",
                complete = nil,
                instant = false,
            }

            RollDialog.OnBeforeRoll({
                rollArgs = rollArgs,
                roll = "2d10",
                description = "Test",
                boons = 0,
                multitargets = targets,
            })

            local saved = DiceVision.lastInterceptedContext
            assert.are.equal(targets, saved.multitargets)
        end)
    end)

    describe("onReroll", function()
        local savedComplete
        local savedRollArgs

        before_each(function()
            DiceVision.connected = true
            DiceVision.setMode("replace")

            savedComplete = function() return "original" end
            savedRollArgs = {
                roll = "2d10+3",
                description = "Power Roll",
                complete = savedComplete,
                instant = false,
            }

            -- Simulate a prior onBeforeRoll intercept
            RollDialog.OnBeforeRoll({
                rollArgs = savedRollArgs,
                roll = "2d10+3",
                description = "Power Roll",
                boons = 0,
                multitargets = nil,
            })

            -- Clear the waiting state (simulates handlePendingRoll completing)
            DiceVision.waitingForRoll = false
            DiceVision.pendingRoll = nil
            _G._chatLog = {}

            -- Simulate handlePendingRoll having modified rollArgs
            savedRollArgs.roll = "15"
            savedRollArgs.complete = function() return "wrapped" end
            savedRollArgs.instant = true
        end)

        it("returns nil when context is nil", function()
            assert.is_nil(RollDialog.OnReroll(nil))
        end)

        it("returns nil when not connected", function()
            DiceVision.connected = false
            local result = RollDialog.OnReroll({rollArgs = savedRollArgs})
            assert.is_nil(result)
        end)

        it("returns nil when mode is off", function()
            DiceVision.mode = "off"
            local result = RollDialog.OnReroll({rollArgs = savedRollArgs})
            assert.is_nil(result)
        end)

        it("returns nil when no previous intercept", function()
            DiceVision.lastInterceptedContext = nil
            local result = RollDialog.OnReroll({rollArgs = savedRollArgs})
            assert.is_nil(result)
        end)

        it("returns nil when already waiting for a roll", function()
            DiceVision.waitingForRoll = true
            local result = RollDialog.OnReroll({rollArgs = savedRollArgs})
            assert.is_nil(result)
        end)

        it("returns 'intercept' and sets up pendingRoll", function()
            local result = RollDialog.OnReroll({rollArgs = savedRollArgs})
            assert.are.equal("intercept", result)
            assert.is_not_nil(DiceVision.pendingRoll)
            assert.is_true(DiceVision.waitingForRoll)
            assert.is_not_nil(DiceVision.currentRequestId)
        end)

        it("restores rollArgs.roll to original", function()
            RollDialog.OnReroll({rollArgs = savedRollArgs})
            assert.are.equal("2d10+3", savedRollArgs.roll)
        end)

        it("restores rollArgs.complete to original", function()
            RollDialog.OnReroll({rollArgs = savedRollArgs})
            assert.are.equal(savedComplete, savedRollArgs.complete)
        end)

        it("restores rollArgs.instant to original", function()
            RollDialog.OnReroll({rollArgs = savedRollArgs})
            assert.are.equal(false, savedRollArgs.instant)
        end)

        it("sends re-roll chat message", function()
            RollDialog.OnReroll({rollArgs = savedRollArgs})
            local found = false
            for _, entry in ipairs(_G._chatLog) do
                if string.find(entry.message, "Re%-rolling") then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("sets pendingRoll with saved context values", function()
            RollDialog.OnReroll({rollArgs = savedRollArgs})
            local pending = DiceVision.pendingRoll
            assert.are.equal("2d10+3", pending.originalRoll)
            assert.are.equal("Power Roll", pending.description)
            assert.are.equal(0, pending.edges)
            assert.are.equal(0, pending.banes)
        end)
    end)

    describe("re-roll cleanup", function()
        before_each(function()
            DiceVision.connected = true
            DiceVision.setMode("replace")
            DiceVision.lastInterceptedContext = {
                originalRoll = "2d10",
                description = "Test",
                edges = 0,
                banes = 0,
            }
        end)

        it("disconnect clears lastInterceptedContext", function()
            Commands.dv("disconnect")
            assert.is_nil(DiceVision.lastInterceptedContext)
        end)

        it("disconnect sets RollDialog.OnReroll to false", function()
            RollDialog.OnReroll = function() end
            Commands.dv("disconnect")
            assert.is_false(RollDialog.OnReroll)
        end)

        it("setMode('off') clears lastInterceptedContext", function()
            DiceVision.setMode("off")
            assert.is_nil(DiceVision.lastInterceptedContext)
        end)

        it("setMode('off') sets RollDialog.OnReroll to false", function()
            RollDialog.OnReroll = function() end
            DiceVision.setMode("off")
            assert.is_false(RollDialog.OnReroll)
        end)

        it("setMode('replace') registers RollDialog.OnReroll", function()
            DiceVision.mode = "off"
            DiceVision.setMode("replace")
            assert.is_function(RollDialog.OnReroll)
        end)
    end)
end)
