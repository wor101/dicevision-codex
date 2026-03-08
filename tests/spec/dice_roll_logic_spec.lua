-- Tests for DiceRollLogic (Codex/mods/DiceVision_5554/DiceRollLogic.lua)

-- ============================================================================
-- Pure Utility Functions
-- ============================================================================

describe("extractModifierFromRoll", function()
    it("extracts a positive modifier", function()
        assert.are.equal(5, DiceRollLogic.extractModifierFromRoll("2d10+5"))
    end)

    it("extracts a negative modifier", function()
        assert.are.equal(-3, DiceRollLogic.extractModifierFromRoll("2d10-3"))
    end)

    it("returns 0 when no modifier is present", function()
        assert.are.equal(0, DiceRollLogic.extractModifierFromRoll("2d10"))
    end)

    it("returns 0 for nil input", function()
        assert.are.equal(0, DiceRollLogic.extractModifierFromRoll(nil))
    end)

    it("handles spaces around modifier", function()
        assert.are.equal(7, DiceRollLogic.extractModifierFromRoll("2d10+ 7"))
    end)

    it("handles large modifiers", function()
        assert.are.equal(100, DiceRollLogic.extractModifierFromRoll("1d20+100"))
    end)

    it("extracts the first modifier when multiple signs exist", function()
        local result = DiceRollLogic.extractModifierFromRoll("2d10+3-1")
        -- Should match the first sign+num pattern: +3
        assert.are.equal(3, result)
    end)
end)

describe("getDiceFaces", function()
    it("returns 10 for d10", function()
        assert.are.equal(10, DiceRollLogic.getDiceFaces("d10"))
    end)

    it("returns 20 for d20", function()
        assert.are.equal(20, DiceRollLogic.getDiceFaces("d20"))
    end)

    it("returns 6 for d6", function()
        assert.are.equal(6, DiceRollLogic.getDiceFaces("d6"))
    end)

    it("returns 4 for d4", function()
        assert.are.equal(4, DiceRollLogic.getDiceFaces("d4"))
    end)

    it("returns 10 as default for invalid input", function()
        assert.are.equal(10, DiceRollLogic.getDiceFaces("invalid"))
    end)

    it("handles dice with count prefix like 2d10", function()
        assert.are.equal(10, DiceRollLogic.getDiceFaces("2d10"))
    end)
end)

describe("calculateTier", function()
    it("returns tier 1 for total 1", function()
        assert.are.equal(1, DiceRollLogic.calculateTier(1))
    end)

    it("returns tier 1 for total 11 (upper boundary)", function()
        assert.are.equal(1, DiceRollLogic.calculateTier(11))
    end)

    it("returns tier 2 for total 12 (lower boundary)", function()
        assert.are.equal(2, DiceRollLogic.calculateTier(12))
    end)

    it("returns tier 2 for total 16 (upper boundary)", function()
        assert.are.equal(2, DiceRollLogic.calculateTier(16))
    end)

    it("returns tier 3 for total 17 (lower boundary)", function()
        assert.are.equal(3, DiceRollLogic.calculateTier(17))
    end)

    it("returns tier 3 for total 25", function()
        assert.are.equal(3, DiceRollLogic.calculateTier(25))
    end)

    it("returns tier 1 for negative totals", function()
        assert.are.equal(1, DiceRollLogic.calculateTier(-5))
    end)

    it("returns tier 1 for total 0", function()
        assert.are.equal(1, DiceRollLogic.calculateTier(0))
    end)
end)

describe("SplitBoons", function()
    it("splits positive combined into edges", function()
        local edges, banes = DiceRollLogic.SplitBoons(2)
        assert.are.equal(2, edges)
        assert.are.equal(0, banes)
    end)

    it("splits negative combined into banes", function()
        local edges, banes = DiceRollLogic.SplitBoons(-3)
        assert.are.equal(0, edges)
        assert.are.equal(3, banes)
    end)

    it("returns 0,0 for zero", function()
        local edges, banes = DiceRollLogic.SplitBoons(0)
        assert.are.equal(0, edges)
        assert.are.equal(0, banes)
    end)

    it("returns 0,0 for nil", function()
        local edges, banes = DiceRollLogic.SplitBoons(nil)
        assert.are.equal(0, edges)
        assert.are.equal(0, banes)
    end)

    it("handles 1 edge", function()
        local edges, banes = DiceRollLogic.SplitBoons(1)
        assert.are.equal(1, edges)
        assert.are.equal(0, banes)
    end)

    it("handles -1 bane", function()
        local edges, banes = DiceRollLogic.SplitBoons(-1)
        assert.are.equal(0, edges)
        assert.are.equal(1, banes)
    end)
end)

describe("GetRollModFromEdgesAndBanes", function()
    it("returns +2 for net +1 (1 edge, 0 banes)", function()
        assert.are.equal(2, DiceRollLogic.GetRollModFromEdgesAndBanes(1, 0))
    end)

    it("returns -2 for net -1 (0 edges, 1 bane)", function()
        assert.are.equal(-2, DiceRollLogic.GetRollModFromEdgesAndBanes(0, 1))
    end)

    it("returns 0 for net 0 (cancelled out)", function()
        assert.are.equal(0, DiceRollLogic.GetRollModFromEdgesAndBanes(1, 1))
    end)

    it("returns 0 for net +2 (tier shift, no modifier)", function()
        assert.are.equal(0, DiceRollLogic.GetRollModFromEdgesAndBanes(2, 0))
    end)

    it("returns 0 for net -2 (tier shift, no modifier)", function()
        assert.are.equal(0, DiceRollLogic.GetRollModFromEdgesAndBanes(0, 2))
    end)

    it("returns +2 for net +1 with cancellation (3 edges, 2 banes)", function()
        assert.are.equal(2, DiceRollLogic.GetRollModFromEdgesAndBanes(3, 2))
    end)

    it("returns -2 for net -1 with cancellation (1 edge, 2 banes)", function()
        assert.are.equal(-2, DiceRollLogic.GetRollModFromEdgesAndBanes(1, 2))
    end)

    it("returns 0 for net +3 (large positive)", function()
        assert.are.equal(0, DiceRollLogic.GetRollModFromEdgesAndBanes(3, 0))
    end)

    it("handles nil edges", function()
        assert.are.equal(-2, DiceRollLogic.GetRollModFromEdgesAndBanes(nil, 1))
    end)

    it("handles nil banes", function()
        assert.are.equal(2, DiceRollLogic.GetRollModFromEdgesAndBanes(1, nil))
    end)

    it("handles both nil", function()
        assert.are.equal(0, DiceRollLogic.GetRollModFromEdgesAndBanes(nil, nil))
    end)
end)

describe("CalculateTierWithEdges", function()
    it("shifts tier up with net +2 edges", function()
        -- total=14 -> tier 2, net +2 -> tier 3
        assert.are.equal(3, DiceRollLogic.CalculateTierWithEdges(14, 2, 0))
    end)

    it("shifts tier down with net -2 banes", function()
        -- total=14 -> tier 2, net -2 -> tier 1
        assert.are.equal(1, DiceRollLogic.CalculateTierWithEdges(14, 0, 2))
    end)

    it("does not shift with net +1 (modifier only)", function()
        -- total=14 -> tier 2, net +1 -> still tier 2
        assert.are.equal(2, DiceRollLogic.CalculateTierWithEdges(14, 1, 0))
    end)

    it("does not shift with net -1 (modifier only)", function()
        -- total=14 -> tier 2, net -1 -> still tier 2
        assert.are.equal(2, DiceRollLogic.CalculateTierWithEdges(14, 0, 1))
    end)

    it("does not shift with net 0 (cancelled)", function()
        assert.are.equal(2, DiceRollLogic.CalculateTierWithEdges(14, 1, 1))
    end)

    it("clamps tier to max 3", function()
        -- total=17 -> tier 3, net +2 -> would be 4, clamped to 3
        assert.are.equal(3, DiceRollLogic.CalculateTierWithEdges(17, 2, 0))
    end)

    it("clamps tier to min 1", function()
        -- total=5 -> tier 1, net -2 -> would be 0, clamped to 1
        assert.are.equal(1, DiceRollLogic.CalculateTierWithEdges(5, 0, 2))
    end)

    it("shifts tier 1 up to tier 2 with net +2", function()
        assert.are.equal(2, DiceRollLogic.CalculateTierWithEdges(8, 3, 1))
    end)

    it("shifts tier 3 down to tier 2 with net -2", function()
        assert.are.equal(2, DiceRollLogic.CalculateTierWithEdges(18, 0, 2))
    end)

    it("handles large net values", function()
        -- net +5 still only shifts +1
        assert.are.equal(3, DiceRollLogic.CalculateTierWithEdges(14, 5, 0))
    end)
end)

describe("ParseBoonsFromRollString", function()
    it("parses edges from roll string", function()
        local edges, banes = DiceRollLogic.ParseBoonsFromRollString("2d10 1 edge")
        assert.are.equal(1, edges)
        assert.are.equal(0, banes)
    end)

    it("parses banes from roll string", function()
        local edges, banes = DiceRollLogic.ParseBoonsFromRollString("2d10 2 bane")
        assert.are.equal(0, edges)
        assert.are.equal(2, banes)
    end)

    it("parses both edges and banes", function()
        local edges, banes = DiceRollLogic.ParseBoonsFromRollString("2d10 1 edge 2 bane")
        assert.are.equal(1, edges)
        assert.are.equal(2, banes)
    end)

    it("returns 0,0 when neither present", function()
        local edges, banes = DiceRollLogic.ParseBoonsFromRollString("2d10+5")
        assert.are.equal(0, edges)
        assert.are.equal(0, banes)
    end)

    it("returns 0,0 for nil input", function()
        local edges, banes = DiceRollLogic.ParseBoonsFromRollString(nil)
        assert.are.equal(0, edges)
        assert.are.equal(0, banes)
    end)

    it("parses multi-digit edge counts", function()
        local edges, banes = DiceRollLogic.ParseBoonsFromRollString("2d10 10 edge")
        assert.are.equal(10, edges)
        assert.are.equal(0, banes)
    end)
end)

describe("getTierRanges", function()
    it("returns a table with 3 entries", function()
        local ranges = DiceRollLogic.getTierRanges()
        assert.are.equal(3, #ranges)
    end)

    it("has correct tier 1 range", function()
        local ranges = DiceRollLogic.getTierRanges()
        assert.are.equal(1, ranges[1].tier)
        assert.are.equal("1-11", ranges[1].label)
        assert.is_nil(ranges[1].min)
        assert.are.equal(11, ranges[1].max)
    end)

    it("has correct tier 2 range", function()
        local ranges = DiceRollLogic.getTierRanges()
        assert.are.equal(2, ranges[2].tier)
        assert.are.equal("12-16", ranges[2].label)
        assert.are.equal(12, ranges[2].min)
        assert.are.equal(16, ranges[2].max)
    end)

    it("has correct tier 3 range", function()
        local ranges = DiceRollLogic.getTierRanges()
        assert.are.equal(3, ranges[3].tier)
        assert.are.equal("17+", ranges[3].label)
        assert.are.equal(17, ranges[3].min)
        assert.is_nil(ranges[3].max)
    end)
end)

describe("applyValueMappings", function()
    it("maps dice values according to type-specific mappings", function()
        local dice = {
            {type = "d10", value = 0},
            {type = "d10", value = 5},
        }
        local mappings = {
            d10 = {[0] = 10},
        }
        local result = DiceRollLogic.applyValueMappings(dice, mappings)
        assert.are.equal(10, result[1].value)
        assert.are.equal(0, result[1].originalValue)
        assert.are.equal(5, result[2].value)
        assert.is_nil(result[2].originalValue)
    end)

    it("uses wildcard '*' mapping when type-specific not found", function()
        local dice = {
            {type = "d6", value = 0},
        }
        local mappings = {
            ["*"] = {[0] = 10},
        }
        local result = DiceRollLogic.applyValueMappings(dice, mappings)
        assert.are.equal(10, result[1].value)
        assert.are.equal(0, result[1].originalValue)
    end)

    it("returns identity when no mappings provided", function()
        local dice = {
            {type = "d10", value = 7},
        }
        local result = DiceRollLogic.applyValueMappings(dice, nil)
        assert.are.equal(7, result[1].value)
    end)

    it("returns identity when mappings table is empty", function()
        local dice = {
            {type = "d10", value = 7},
        }
        local result = DiceRollLogic.applyValueMappings(dice, {})
        assert.are.equal(7, result[1].value)
    end)

    it("preserves die type in result", function()
        local dice = {
            {type = "d20", value = 15},
        }
        local result = DiceRollLogic.applyValueMappings(dice, {})
        assert.are.equal("d20", result[1].type)
    end)

    it("does not set originalValue when value is unchanged", function()
        local dice = {
            {type = "d10", value = 5},
        }
        local mappings = {d10 = {[0] = 10}} -- no mapping for 5
        local result = DiceRollLogic.applyValueMappings(dice, mappings)
        assert.are.equal(5, result[1].value)
        assert.is_nil(result[1].originalValue)
    end)

    it("type-specific mapping takes priority over wildcard", function()
        local dice = {
            {type = "d10", value = 0},
        }
        local mappings = {
            d10 = {[0] = 10},
            ["*"] = {[0] = 99},
        }
        local result = DiceRollLogic.applyValueMappings(dice, mappings)
        assert.are.equal(10, result[1].value)
    end)
end)

describe("clampOutOfRangeValues", function()
    before_each(function()
        resetPrintLog()
    end)

    it("clamps negative values to 1 when enabled", function()
        local dice = {{type = "d10", value = -1}}
        local result = DiceRollLogic.clampOutOfRangeValues(dice, true)
        assert.are.equal(1, result[1].value)
        assert.are.equal(-1, result[1].originalValue)
    end)

    it("clamps values over 10 to 1 when enabled", function()
        local dice = {{type = "d10", value = 11}}
        local result = DiceRollLogic.clampOutOfRangeValues(dice, true)
        assert.are.equal(1, result[1].value)
        assert.are.equal(11, result[1].originalValue)
    end)

    it("does not clamp values in valid range", function()
        local dice = {{type = "d10", value = 5}}
        local result = DiceRollLogic.clampOutOfRangeValues(dice, true)
        assert.are.equal(5, result[1].value)
        assert.is_nil(result[1].originalValue)
    end)

    it("allows 0 as a valid value", function()
        local dice = {{type = "d10", value = 0}}
        local result = DiceRollLogic.clampOutOfRangeValues(dice, true)
        assert.are.equal(0, result[1].value)
    end)

    it("allows 10 as a valid value", function()
        local dice = {{type = "d10", value = 10}}
        local result = DiceRollLogic.clampOutOfRangeValues(dice, true)
        assert.are.equal(10, result[1].value)
    end)

    it("passes through when disabled", function()
        local dice = {{type = "d10", value = -1}}
        local result = DiceRollLogic.clampOutOfRangeValues(dice, false)
        assert.are.equal(-1, result[1].value)
    end)

    it("preserves existing originalValue when clamping", function()
        local dice = {{type = "d10", value = 15, originalValue = 20}}
        local result = DiceRollLogic.clampOutOfRangeValues(dice, true)
        assert.are.equal(1, result[1].value)
        -- originalValue should be the pre-clamp value (15), not the prior originalValue
        assert.are.equal(15, result[1].originalValue)
    end)

    it("prints a message when clamping", function()
        local dice = {{type = "d10", value = 11}}
        DiceRollLogic.clampOutOfRangeValues(dice, true)
        assert.are.equal(1, #_G._printLog)
        assert.truthy(string.find(_G._printLog[1], "Clamped"))
    end)
end)

describe("applyDiceSelection", function()
    it("keeps highest N dice", function()
        local dice = {
            {type = "d10", value = 3},
            {type = "d10", value = 7},
            {type = "d10", value = 5},
        }
        local selection = {keep = "highest", count = 2}
        local result = DiceRollLogic.applyDiceSelection(dice, selection)
        assert.are.equal(2, #result)
        assert.are.equal(7, result[1].value)
        assert.are.equal(5, result[2].value)
    end)

    it("keeps lowest N dice", function()
        local dice = {
            {type = "d10", value = 3},
            {type = "d10", value = 7},
            {type = "d10", value = 5},
        }
        local selection = {keep = "lowest", count = 1}
        local result = DiceRollLogic.applyDiceSelection(dice, selection)
        assert.are.equal(1, #result)
        assert.are.equal(3, result[1].value)
    end)

    it("returns all dice when selection is nil", function()
        local dice = {
            {type = "d10", value = 3},
            {type = "d10", value = 7},
        }
        local result = DiceRollLogic.applyDiceSelection(dice, nil)
        assert.are.equal(2, #result)
    end)

    it("returns all dice when selection has no count", function()
        local dice = {
            {type = "d10", value = 3},
        }
        local result = DiceRollLogic.applyDiceSelection(dice, {keep = "highest"})
        assert.are.equal(1, #result)
    end)

    it("returns sorted array as second return value", function()
        local dice = {
            {type = "d10", value = 3},
            {type = "d10", value = 7},
            {type = "d10", value = 5},
        }
        local selection = {keep = "highest", count = 2}
        local _, sorted = DiceRollLogic.applyDiceSelection(dice, selection)
        assert.is_not_nil(sorted)
        assert.are.equal(3, #sorted)
        -- sorted should be descending by value for "highest"
        assert.are.equal(7, sorted[1].die.value)
        assert.are.equal(5, sorted[2].die.value)
        assert.are.equal(3, sorted[3].die.value)
    end)

    it("handles count larger than dice array", function()
        local dice = {
            {type = "d10", value = 3},
        }
        local selection = {keep = "highest", count = 5}
        local result = DiceRollLogic.applyDiceSelection(dice, selection)
        assert.are.equal(1, #result)
    end)

    it("preserves die type in results", function()
        local dice = {
            {type = "d6", value = 2},
            {type = "d10", value = 8},
        }
        local selection = {keep = "highest", count = 1}
        local result = DiceRollLogic.applyDiceSelection(dice, selection)
        assert.are.equal("d10", result[1].type)
    end)
end)

-- ============================================================================
-- Functions Requiring Stubs
-- ============================================================================

describe("detectDiceSelection", function()
    before_each(function()
        resetStubs()
    end)

    it("returns nil for nil input", function()
        assert.is_nil(DiceRollLogic.detectDiceSelection(nil))
    end)

    it("returns nil when no originalRoll", function()
        assert.is_nil(DiceRollLogic.detectDiceSelection({}))
    end)

    it("returns nil when ParseRoll returns nil", function()
        dmhub.ParseRoll = function() return nil end
        local pendingRoll = {originalRoll = "2d10"}
        assert.is_nil(DiceRollLogic.detectDiceSelection(pendingRoll))
    end)

    it("returns nil when no categories in rollInfo", function()
        dmhub.ParseRoll = function() return {} end
        local pendingRoll = {originalRoll = "2d10"}
        assert.is_nil(DiceRollLogic.detectDiceSelection(pendingRoll))
    end)

    it("returns selection when numKeep < numDice", function()
        dmhub.ParseRoll = function()
            return {
                categories = {
                    main = {
                        groups = {
                            {numKeep = 2, numDice = 3},
                        },
                    },
                },
            }
        end
        local pendingRoll = {originalRoll = "3d10k2"}
        local result = DiceRollLogic.detectDiceSelection(pendingRoll)
        assert.is_not_nil(result)
        assert.are.equal("highest", result.keep)
        assert.are.equal(2, result.count)
        assert.are.equal(3, result.total)
    end)

    it("returns nil when numKeep equals numDice", function()
        dmhub.ParseRoll = function()
            return {
                categories = {
                    main = {
                        groups = {
                            {numKeep = 3, numDice = 3},
                        },
                    },
                },
            }
        end
        local pendingRoll = {originalRoll = "3d10"}
        assert.is_nil(DiceRollLogic.detectDiceSelection(pendingRoll))
    end)

    it("returns nil when numKeep is 0", function()
        dmhub.ParseRoll = function()
            return {
                categories = {
                    main = {
                        groups = {
                            {numKeep = 0, numDice = 3},
                        },
                    },
                },
            }
        end
        local pendingRoll = {originalRoll = "3d10"}
        assert.is_nil(DiceRollLogic.detectDiceSelection(pendingRoll))
    end)

    it("passes creature from rollArgs to ParseRoll", function()
        local capturedCreature = nil
        dmhub.ParseRoll = function(rollStr, creature)
            capturedCreature = creature
            return nil
        end
        local pendingRoll = {
            originalRoll = "2d10",
            rollArgs = {creature = "test_creature"},
        }
        DiceRollLogic.detectDiceSelection(pendingRoll)
        assert.are.equal("test_creature", capturedCreature)
    end)

    it("returns keep = 'lowest' for disadvantage rolls", function()
        dmhub.ParseRoll = function()
            return {
                categories = {
                    main = {
                        groups = {
                            {numKeep = 2, numDice = 3},
                        },
                    },
                },
            }
        end
        dmhub.GetRollAdvantage = function() return "disadvantage" end
        local pendingRoll = {originalRoll = "3d10k2"}
        local result = DiceRollLogic.detectDiceSelection(pendingRoll)
        assert.is_not_nil(result)
        assert.are.equal("lowest", result.keep)
        assert.are.equal(2, result.count)
        assert.are.equal(3, result.total)
    end)

    it("returns keep = 'highest' for advantage rolls", function()
        dmhub.ParseRoll = function()
            return {
                categories = {
                    main = {
                        groups = {
                            {numKeep = 2, numDice = 3},
                        },
                    },
                },
            }
        end
        dmhub.GetRollAdvantage = function() return "advantage" end
        local pendingRoll = {originalRoll = "3d10k2"}
        local result = DiceRollLogic.detectDiceSelection(pendingRoll)
        assert.is_not_nil(result)
        assert.are.equal("highest", result.keep)
    end)

    it("defaults to keep = 'highest' for normal rolls", function()
        dmhub.ParseRoll = function()
            return {
                categories = {
                    main = {
                        groups = {
                            {numKeep = 2, numDice = 3},
                        },
                    },
                },
            }
        end
        dmhub.GetRollAdvantage = function() return "normal" end
        local pendingRoll = {originalRoll = "3d10k2"}
        local result = DiceRollLogic.detectDiceSelection(pendingRoll)
        assert.is_not_nil(result)
        assert.are.equal("highest", result.keep)
    end)

    it("falls back to keep = 'highest' when GetRollAdvantage is nil", function()
        dmhub.ParseRoll = function()
            return {
                categories = {
                    main = {
                        groups = {
                            {numKeep = 2, numDice = 3},
                        },
                    },
                },
            }
        end
        dmhub.GetRollAdvantage = nil
        local pendingRoll = {originalRoll = "3d10k2"}
        local result = DiceRollLogic.detectDiceSelection(pendingRoll)
        assert.is_not_nil(result)
        assert.are.equal("highest", result.keep)
    end)

    it("passes originalRoll to GetRollAdvantage", function()
        local capturedRollStr = nil
        dmhub.ParseRoll = function()
            return {
                categories = {
                    main = {
                        groups = {
                            {numKeep = 2, numDice = 3},
                        },
                    },
                },
            }
        end
        dmhub.GetRollAdvantage = function(rollStr)
            capturedRollStr = rollStr
            return "normal"
        end
        local pendingRoll = {originalRoll = "3d10k2 with disadvantage"}
        DiceRollLogic.detectDiceSelection(pendingRoll)
        assert.are.equal("3d10k2 with disadvantage", capturedRollStr)
    end)
end)

describe("getEffectiveRules", function()
    before_each(function()
        resetStubs()
    end)

    it("returns rules from DiceVision.rules", function()
        DiceVision.rules.valueMappings = {d10 = {[0] = 10}}
        local rules = DiceRollLogic.getEffectiveRules(nil)
        assert.is_not_nil(rules.valueMappings)
        assert.are.equal(10, rules.valueMappings.d10[0])
    end)

    it("uses manual diceSelection when set", function()
        DiceVision.rules.diceSelection = {keep = "lowest", count = 1}
        local rules = DiceRollLogic.getEffectiveRules(nil)
        assert.are.equal("lowest", rules.diceSelection.keep)
        assert.are.equal(1, rules.diceSelection.count)
    end)

    it("auto-detects diceSelection when not manually set", function()
        DiceVision.rules.diceSelection = nil
        dmhub.ParseRoll = function()
            return {
                categories = {
                    main = {
                        groups = {
                            {numKeep = 2, numDice = 3},
                        },
                    },
                },
            }
        end
        local pendingRoll = {originalRoll = "3d10k2"}
        local rules = DiceRollLogic.getEffectiveRules(pendingRoll)
        assert.is_not_nil(rules.diceSelection)
        assert.are.equal("highest", rules.diceSelection.keep)
        assert.are.equal(2, rules.diceSelection.count)
    end)

    it("returns nil diceSelection when not set and not detected", function()
        DiceVision.rules.diceSelection = nil
        dmhub.ParseRoll = function() return nil end
        local pendingRoll = {originalRoll = "2d10"}
        local rules = DiceRollLogic.getEffectiveRules(pendingRoll)
        assert.is_nil(rules.diceSelection)
    end)

    it("returns empty valueMappings when none configured", function()
        DiceVision.rules.valueMappings = nil
        local rules = DiceRollLogic.getEffectiveRules(nil)
        assert.is_not_nil(rules.valueMappings)
        assert.is_nil(next(rules.valueMappings))
    end)

    it("auto-detects keep lowest for disadvantage rolls", function()
        DiceVision.rules.diceSelection = nil
        dmhub.ParseRoll = function()
            return {
                categories = {
                    main = {
                        groups = {
                            {numKeep = 2, numDice = 3},
                        },
                    },
                },
            }
        end
        dmhub.GetRollAdvantage = function() return "disadvantage" end
        local pendingRoll = {originalRoll = "3d10k2"}
        local rules = DiceRollLogic.getEffectiveRules(pendingRoll)
        assert.is_not_nil(rules.diceSelection)
        assert.are.equal("lowest", rules.diceSelection.keep)
        assert.are.equal(2, rules.diceSelection.count)
    end)
end)

describe("applyDiceRules", function()
    before_each(function()
        resetStubs()
    end)

    it("applies full pipeline: clamp -> map -> select", function()
        DiceVision.rules.clampOutOfRange = true
        DiceVision.rules.valueMappings = {d10 = {[0] = 10}}
        DiceVision.rules.diceSelection = {keep = "highest", count = 2}

        local dice = {
            {type = "d10", value = 0},
            {type = "d10", value = 8},
            {type = "d10", value = 5},
        }
        local result, dropped = DiceRollLogic.applyDiceRules(dice, nil)
        -- 0 is in valid range (not clamped), then mapped to 10
        -- After mapping: 10, 8, 5
        -- Keep highest 2: 10, 8
        assert.are.equal(2, #result)
        assert.are.equal(10, result[1].value)
        assert.are.equal(8, result[2].value)
        assert.is_not_nil(dropped)
        assert.are.equal(1, #dropped)
        assert.are.equal(5, dropped[1].value)
    end)

    it("returns nil dropped when no selection", function()
        DiceVision.rules.clampOutOfRange = false
        DiceVision.rules.diceSelection = nil
        dmhub.ParseRoll = function() return nil end

        local dice = {
            {type = "d10", value = 5},
            {type = "d10", value = 8},
        }
        local result, dropped = DiceRollLogic.applyDiceRules(dice, {originalRoll = "2d10"})
        assert.are.equal(2, #result)
        assert.is_nil(dropped)
    end)

    it("clamps out-of-range values when enabled", function()
        DiceVision.rules.clampOutOfRange = true
        DiceVision.rules.diceSelection = nil
        dmhub.ParseRoll = function() return nil end

        local dice = {
            {type = "d10", value = 15},
            {type = "d10", value = 5},
        }
        local result = DiceRollLogic.applyDiceRules(dice, {originalRoll = "2d10"})
        assert.are.equal(1, result[1].value)
        assert.are.equal(5, result[2].value)
    end)

    it("does not clamp when disabled", function()
        DiceVision.rules.clampOutOfRange = false
        DiceVision.rules.diceSelection = nil
        dmhub.ParseRoll = function() return nil end

        local dice = {
            {type = "d10", value = 15},
        }
        local result = DiceRollLogic.applyDiceRules(dice, {originalRoll = "2d10"})
        assert.are.equal(15, result[1].value)
    end)

    it("applies value mappings", function()
        DiceVision.rules.clampOutOfRange = false
        DiceVision.rules.valueMappings = {d10 = {[0] = 10}}
        DiceVision.rules.diceSelection = nil
        dmhub.ParseRoll = function() return nil end

        local dice = {
            {type = "d10", value = 0},
        }
        local result = DiceRollLogic.applyDiceRules(dice, {originalRoll = "2d10"})
        assert.are.equal(10, result[1].value)
        assert.are.equal(0, result[1].originalValue)
    end)
end)

-- ============================================================================
-- Percentile (d100) Detection
-- ============================================================================

describe("detectPercentilePair", function()
    it("returns nil for nil input", function()
        assert.is_nil(DiceRollLogic.detectPercentilePair(nil))
    end)

    it("returns nil for empty table", function()
        assert.is_nil(DiceRollLogic.detectPercentilePair({}))
    end)

    it("returns nil for a single die", function()
        assert.is_nil(DiceRollLogic.detectPercentilePair({
            {type = "d10", value = 0, rawValue = "00"},
        }))
    end)

    it("returns nil for three dice", function()
        assert.is_nil(DiceRollLogic.detectPercentilePair({
            {type = "d10", value = 30, rawValue = "30"},
            {type = "d10", value = 7, rawValue = "7"},
            {type = "d10", value = 5, rawValue = "5"},
        }))
    end)

    it("returns nil for non-d10 dice", function()
        assert.is_nil(DiceRollLogic.detectPercentilePair({
            {type = "d10", value = 30, rawValue = "30"},
            {type = "d6", value = 3, rawValue = "3"},
        }))
    end)

    it("returns nil for mixed d10/d6", function()
        assert.is_nil(DiceRollLogic.detectPercentilePair({
            {type = "d6", value = 4, rawValue = "4"},
            {type = "d10", value = 0, rawValue = "00"},
        }))
    end)

    it("detects standard percentile: tens=30 units=7 -> total 37", function()
        local dice = {
            {type = "d10", value = 30, rawValue = "30"},
            {type = "d10", value = 7, rawValue = "7"},
        }
        local result = DiceRollLogic.detectPercentilePair(dice)
        assert.is_not_nil(result)
        assert.are.equal(37, result.total)
        assert.are.equal(30, result.tens.value)
        assert.are.equal(7, result.units.value)
    end)

    it("detects reversed order: units first, tens second -> total 37", function()
        local dice = {
            {type = "d10", value = 7, rawValue = "7"},
            {type = "d10", value = 30, rawValue = "30"},
        }
        local result = DiceRollLogic.detectPercentilePair(dice)
        assert.is_not_nil(result)
        assert.are.equal(37, result.total)
        assert.are.equal(30, result.tens.value)
        assert.are.equal(7, result.units.value)
    end)

    it("maps 00+0 to total 100", function()
        local dice = {
            {type = "d10", value = 0, rawValue = "00"},
            {type = "d10", value = 0, rawValue = "0"},
        }
        local result = DiceRollLogic.detectPercentilePair(dice)
        assert.is_not_nil(result)
        assert.are.equal(100, result.total)
    end)

    it("detects 00+7 -> total 7", function()
        local dice = {
            {type = "d10", value = 0, rawValue = "00"},
            {type = "d10", value = 7, rawValue = "7"},
        }
        local result = DiceRollLogic.detectPercentilePair(dice)
        assert.is_not_nil(result)
        assert.are.equal(7, result.total)
    end)

    it("detects 10+0 -> total 10", function()
        local dice = {
            {type = "d10", value = 10, rawValue = "10"},
            {type = "d10", value = 0, rawValue = "0"},
        }
        local result = DiceRollLogic.detectPercentilePair(dice)
        assert.is_not_nil(result)
        assert.are.equal(10, result.total)
    end)

    it("detects 90+9 -> total 99", function()
        local dice = {
            {type = "d10", value = 90, rawValue = "90"},
            {type = "d10", value = 9, rawValue = "9"},
        }
        local result = DiceRollLogic.detectPercentilePair(dice)
        assert.is_not_nil(result)
        assert.are.equal(99, result.total)
    end)

    it("returns nil for two single-digit rawValues (not percentile)", function()
        assert.is_nil(DiceRollLogic.detectPercentilePair({
            {type = "d10", value = 5, rawValue = "5"},
            {type = "d10", value = 3, rawValue = "3"},
        }))
    end)

    it("returns nil for two multi-digit non-multiple-of-10 rawValues", function()
        assert.is_nil(DiceRollLogic.detectPercentilePair({
            {type = "d10", value = 15, rawValue = "15"},
            {type = "d10", value = 3, rawValue = "3"},
        }))
    end)

    it("returns nil when dice have integer values without rawValue", function()
        assert.is_nil(DiceRollLogic.detectPercentilePair({
            {type = "d10", value = 5},
            {type = "d10", value = 3},
        }))
    end)

    it("returns correct tens and units die references", function()
        local tensDie = {type = "d10", value = 40, rawValue = "40"}
        local unitsDie = {type = "d10", value = 2, rawValue = "2"}
        local result = DiceRollLogic.detectPercentilePair({tensDie, unitsDie})
        assert.is_not_nil(result)
        assert.are.equal(tensDie, result.tens)
        assert.are.equal(unitsDie, result.units)
    end)

    it("returns nil for rawValue '05' (not valid tens or single-digit units)", function()
        assert.is_nil(DiceRollLogic.detectPercentilePair({
            {type = "d10", value = 5, rawValue = "05"},
            {type = "d10", value = 3, rawValue = "3"},
        }))
    end)

    it("detects 00+9 -> total 9", function()
        local dice = {
            {type = "d10", value = 0, rawValue = "00"},
            {type = "d10", value = 9, rawValue = "9"},
        }
        local result = DiceRollLogic.detectPercentilePair(dice)
        assert.is_not_nil(result)
        assert.are.equal(9, result.total)
    end)
end)
