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

    it("sums multiple standalone modifiers", function()
        assert.are.equal(8, DiceRollLogic.extractModifierFromRoll("2d10+5+3"))
        assert.are.equal(2, DiceRollLogic.extractModifierFromRoll("2d10+5-3"))
    end)

    it("does not read a dice group count as a modifier", function()
        -- "+2" belongs to "+2d6" here; only "+3" is a modifier.
        assert.are.equal(3, DiceRollLogic.extractModifierFromRoll("1d10+2d6+3"))
        assert.are.equal(0, DiceRollLogic.extractModifierFromRoll("1d10+2d6"))
        assert.are.equal(-1, DiceRollLogic.extractModifierFromRoll("2d6+1d10-1"))
    end)

    it("sums all modifiers when multiple signs exist", function()
        -- Previously only the first sign+num pattern was matched (+3);
        -- multi-term expressions now sum correctly: +3-1 = 2.
        local result = DiceRollLogic.extractModifierFromRoll("2d10+3-1")
        assert.are.equal(2, result)
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

    -- ----------------------------------------------------------------
    -- Nil / missing input
    -- ----------------------------------------------------------------

    it("returns nil for nil input", function()
        assert.is_nil(DiceRollLogic.detectDiceSelection(nil))
    end)

    it("returns nil when no originalRoll", function()
        assert.is_nil(DiceRollLogic.detectDiceSelection({}))
    end)

    -- ----------------------------------------------------------------
    -- Method 1: Roll string parsing ("keep [low|high] N")
    -- ----------------------------------------------------------------

    it("parses 'keep low N' from roll string when ParseRoll returns nil", function()
        dmhub.ParseRoll = function() return nil end
        local pendingRoll = {originalRoll = "3d10+2 keep low 2"}
        local result = DiceRollLogic.detectDiceSelection(pendingRoll)
        assert.is_not_nil(result)
        assert.are.equal("lowest", result.keep)
        assert.are.equal(2, result.count)
        assert.are.equal(3, result.total)
    end)

    it("parses 'keep N' from roll string when ParseRoll returns nil", function()
        dmhub.ParseRoll = function() return nil end
        local pendingRoll = {originalRoll = "3d10+1 keep 2"}
        local result = DiceRollLogic.detectDiceSelection(pendingRoll)
        assert.is_not_nil(result)
        assert.are.equal("highest", result.keep)
        assert.are.equal(2, result.count)
        assert.are.equal(3, result.total)
    end)

    it("parses 'keep high N' from roll string as highest", function()
        dmhub.ParseRoll = function() return nil end
        local pendingRoll = {originalRoll = "3d10 keep high 2"}
        local result = DiceRollLogic.detectDiceSelection(pendingRoll)
        assert.is_not_nil(result)
        assert.are.equal("highest", result.keep)
        assert.are.equal(2, result.count)
        assert.are.equal(3, result.total)
    end)

    it("'keep low' in roll string takes priority over GetRollAdvantage 'normal'", function()
        dmhub.ParseRoll = function() return nil end
        dmhub.GetRollAdvantage = function() return "normal" end
        local pendingRoll = {originalRoll = "3d10+2 keep low 2"}
        local result = DiceRollLogic.detectDiceSelection(pendingRoll)
        assert.are.equal("lowest", result.keep)
    end)

    it("returns nil when keepCount >= numDice from roll string", function()
        dmhub.ParseRoll = function() return nil end
        local pendingRoll = {originalRoll = "2d10 keep 2"}
        assert.is_nil(DiceRollLogic.detectDiceSelection(pendingRoll))
    end)

    it("returns nil when keepCount > numDice from roll string", function()
        dmhub.ParseRoll = function() return nil end
        local pendingRoll = {originalRoll = "2d10 keep 3"}
        assert.is_nil(DiceRollLogic.detectDiceSelection(pendingRoll))
    end)

    it("does not call GetRollAdvantage when roll string contains 'keep low'", function()
        dmhub.ParseRoll = function() return nil end
        local advCalled = false
        dmhub.GetRollAdvantage = function()
            advCalled = true
            return "normal"
        end
        local pendingRoll = {originalRoll = "3d10+2 keep low 2"}
        DiceRollLogic.detectDiceSelection(pendingRoll)
        assert.is_false(advCalled)
    end)

    -- ----------------------------------------------------------------
    -- Method 2: ParseRoll fallback (no "keep" keyword in string)
    -- ----------------------------------------------------------------

    it("falls back to ParseRoll when no 'keep' in roll string", function()
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

    it("returns nil when ParseRoll returns nil and no keep in string", function()
        dmhub.ParseRoll = function() return nil end
        local pendingRoll = {originalRoll = "2d10"}
        assert.is_nil(DiceRollLogic.detectDiceSelection(pendingRoll))
    end)

    it("returns nil when no categories in rollInfo", function()
        dmhub.ParseRoll = function() return {} end
        local pendingRoll = {originalRoll = "2d10"}
        assert.is_nil(DiceRollLogic.detectDiceSelection(pendingRoll))
    end)

    it("returns nil when numKeep equals numDice via ParseRoll", function()
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

    it("returns nil when numKeep is 0 via ParseRoll", function()
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

    -- ----------------------------------------------------------------
    -- Keep direction via GetRollAdvantage (ParseRoll fallback path)
    -- ----------------------------------------------------------------

    it("returns keep = 'lowest' for disadvantage via ParseRoll fallback", function()
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

    -- ----------------------------------------------------------------
    -- Roll string parsing + ParseRoll interaction
    -- ----------------------------------------------------------------

    it("skips ParseRoll when roll string has 'keep' keyword", function()
        local parseRollCalled = false
        dmhub.ParseRoll = function()
            parseRollCalled = true
            return nil
        end
        local pendingRoll = {originalRoll = "3d10+1 keep 2"}
        DiceRollLogic.detectDiceSelection(pendingRoll)
        assert.is_false(parseRollCalled)
    end)

    it("returns keep = 'lowest' when roll string has 'keep low' and ParseRoll has data", function()
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
        local pendingRoll = {originalRoll = "3d10+2 keep low 2"}
        local result = DiceRollLogic.detectDiceSelection(pendingRoll)
        assert.is_not_nil(result)
        assert.are.equal("lowest", result.keep)
        assert.are.equal(2, result.count)
        assert.are.equal(3, result.total)
    end)

    it("returns keep = 'highest' when roll string has 'keep' without 'low'", function()
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
        local pendingRoll = {originalRoll = "3d10+1 keep 2"}
        local result = DiceRollLogic.detectDiceSelection(pendingRoll)
        assert.is_not_nil(result)
        assert.are.equal("highest", result.keep)
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

    it("auto-detects keep lowest from 'keep low' roll string (ParseRoll returns nil)", function()
        DiceVision.rules.diceSelection = nil
        dmhub.ParseRoll = function() return nil end
        dmhub.GetRollAdvantage = function() return "normal" end
        local pendingRoll = {originalRoll = "3d10+2 keep low 2"}
        local rules = DiceRollLogic.getEffectiveRules(pendingRoll)
        assert.is_not_nil(rules.diceSelection)
        assert.are.equal("lowest", rules.diceSelection.keep)
        assert.are.equal(2, rules.diceSelection.count)
        assert.are.equal(3, rules.diceSelection.total)
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

-- ============================================================================
-- Type Mappings
-- ============================================================================

describe("applyTypeMappings", function()
    it("remaps a matching die type and records the original", function()
        local result = DiceRollLogic.applyTypeMappings(
            {{type = "d20", value = 7, rawValue = "7"}},
            {["d20"] = "d10"})
        assert.are.equal("d10", result[1].type)
        assert.are.equal("d20", result[1].originalType)
        assert.are.equal(7, result[1].value)
        assert.are.equal("7", result[1].rawValue)
    end)

    it("leaves non-mapped types untouched", function()
        local dice = {{type = "d6", value = 4}, {type = "d20", value = 9}}
        local result = DiceRollLogic.applyTypeMappings(dice, {["d20"] = "d10"})
        assert.are.equal("d6", result[1].type)
        assert.is_nil(result[1].originalType)
        assert.are.equal("d10", result[2].type)
    end)

    it("returns dice unchanged for nil or empty mappings", function()
        local dice = {{type = "d20", value = 7}}
        assert.are.equal(dice, DiceRollLogic.applyTypeMappings(dice, nil))
        assert.are.equal(dice, DiceRollLogic.applyTypeMappings(dice, {}))
    end)

    it("ignores a self-mapping", function()
        local dice = {{type = "d10", value = 7}}
        local result = DiceRollLogic.applyTypeMappings(dice, {["d10"] = "d10"})
        assert.are.equal("d10", result[1].type)
        assert.is_nil(result[1].originalType)
    end)

    it("applies mappings in a single pass with no chaining", function()
        -- {d20 -> d12, d12 -> d10}: a d20 becomes a d12, NOT a d10. A
        -- future fixpoint 'improvement' would change results silently (or
        -- infinite-loop on a swap cycle) -- this pins the contract.
        local result = DiceRollLogic.applyTypeMappings(
            {{type = "d20", value = 7}, {type = "d12", value = 5}},
            {["d20"] = "d12", ["d12"] = "d10"})
        assert.are.equal("d12", result[1].type)
        assert.are.equal("d10", result[2].type)
    end)

    it("handles a swap cycle safely", function()
        local result = DiceRollLogic.applyTypeMappings(
            {{type = "d20", value = 7}, {type = "d10", value = 5}},
            {["d20"] = "d10", ["d10"] = "d20"})
        assert.are.equal("d10", result[1].type)
        assert.are.equal("d20", result[2].type)
    end)
end)

describe("provenance fields survive the rules pipeline", function()
    it("originalType survives clampOutOfRangeValues and applyValueMappings", function()
        local dice = DiceRollLogic.applyTypeMappings(
            {{type = "d20", value = 0}},
            {["d20"] = "d10"})
        dice = DiceRollLogic.clampOutOfRangeValues(dice, true)
        dice = DiceRollLogic.applyValueMappings(dice, {["d10"] = {[0] = 10}})
        assert.are.equal("d10", dice[1].type)
        assert.are.equal("d20", dice[1].originalType)
        assert.are.equal(10, dice[1].value)
    end)

    it("clamp's originalValue survives applyValueMappings", function()
        -- Regression pin: applyValueMappings used to rebuild dice with
        -- originalValue=nil for unmapped values, erasing the clamp's
        -- record of what the camera actually read.
        local dice = DiceRollLogic.clampOutOfRangeValues(
            {{type = "d10", value = 15}}, true)
        assert.are.equal(15, dice[1].originalValue)
        dice = DiceRollLogic.applyValueMappings(dice, {["d10"] = {[0] = 10}})
        assert.are.equal(15, dice[1].originalValue)
        assert.are.equal(1, dice[1].value)
    end)
end)

describe("isSupportedDieType", function()
    it("accepts the engine-renderable dice", function()
        for _, dieType in ipairs({"d3", "d4", "d6", "d8", "d10", "d12", "d20"}) do
            assert.is_true(DiceRollLogic.isSupportedDieType(dieType))
        end
        assert.is_true(DiceRollLogic.isSupportedDieType("D10"))
    end)

    it("rejects unforceable or malformed types", function()
        assert.is_false(DiceRollLogic.isSupportedDieType("d100"))
        assert.is_false(DiceRollLogic.isSupportedDieType("d0"))
        assert.is_false(DiceRollLogic.isSupportedDieType("d1000"))
        assert.is_false(DiceRollLogic.isSupportedDieType("banana"))
        assert.is_false(DiceRollLogic.isSupportedDieType(nil))
        assert.is_false(DiceRollLogic.isSupportedDieType(10))
    end)
end)

describe("applyDiceRules type-mapping context gating", function()
    before_each(function()
        resetStubs()
        DiceVision.rules.typeMappings = {["d20"] = "d10"}
    end)

    it("applies type mappings for intercepted rolls (pendingRoll present)", function()
        local processed = DiceRollLogic.applyDiceRules(
            {{type = "d20", value = 7}},
            {originalRoll = "2d10"})
        assert.are.equal("d10", processed[1].type)
    end)

    it("does not apply type mappings for panel rolls by default", function()
        local processed = DiceRollLogic.applyDiceRules(
            {{type = "d20", value = 7}},
            nil)
        assert.are.equal("d20", processed[1].type)
    end)

    it("applies type mappings for panel rolls when opted in", function()
        DiceVision.rules.typeMappingsOnPanel = true
        local processed = DiceRollLogic.applyDiceRules(
            {{type = "d20", value = 7}},
            nil)
        assert.are.equal("d10", processed[1].type)
    end)

    it("remapped dice pick up the target type's value mappings", function()
        DiceVision.rules.valueMappings = {["d10"] = {[0] = 10}}
        local processed = DiceRollLogic.applyDiceRules(
            {{type = "d20", value = 0}},
            {originalRoll = "1d10"})
        assert.are.equal("d10", processed[1].type)
        assert.are.equal(10, processed[1].value)
    end)
end)

-- ============================================================================
-- Forced Dice (engine forcedDice support)
-- ============================================================================

describe("extractExpectedDiceList", function()
    before_each(function()
        resetStubs()
    end)

    it("extracts dice from a simple expression", function()
        assert.are.same({10, 10}, DiceRollLogic.extractExpectedDiceList("2d10+3"))
    end)

    it("extracts a single die with implicit count", function()
        assert.are.same({20}, DiceRollLogic.extractExpectedDiceList("d20"))
    end)

    it("strips edges textually when engine round-trip is unavailable", function()
        -- Default stubs: ParseRoll returns nil, RollToString undefined.
        assert.are.same({10, 10}, DiceRollLogic.extractExpectedDiceList("2d10 1 edge"))
        assert.are.same({10, 10}, DiceRollLogic.extractExpectedDiceList("2d10 2 banes"))
    end)

    it("flattens keep expressions to the full dice count", function()
        -- Engine keep semantics run against the forced faces, so all
        -- physical dice must be supplied.
        assert.are.same({10, 10, 10}, DiceRollLogic.extractExpectedDiceList("3d10 keep 2"))
    end)

    it("supports d3 expressions", function()
        -- d3 is first-class in Codex's Draw Steel UI (panel tile, tables).
        assert.are.same({3}, DiceRollLogic.extractExpectedDiceList("1d3"))
        assert.are.same({3, 3}, DiceRollLogic.extractExpectedDiceList("2d3+1"))
    end)

    it("handles mixed dice groups in order", function()
        assert.are.same({6, 6, 10}, DiceRollLogic.extractExpectedDiceList("2d6+1d10"))
    end)

    it("uses the engine round-trip and nils boons/banes when available", function()
        local parseArgs, toStringArg
        dmhub.ParseRoll = function(rollStr, creature)
            parseArgs = {rollStr = rollStr, creature = creature}
            return {boons = 1, banes = 0, categories = {}}
        end
        dmhub.RollToString = function(parsed)
            toStringArg = parsed
            return "2d10"
        end
        local result = DiceRollLogic.extractExpectedDiceList("2d10 1 edge", "creature-1")
        dmhub.RollToString = nil
        assert.are.same({10, 10}, result)
        assert.are.equal("2d10 1 edge", parseArgs.rollStr)
        assert.are.equal("creature-1", parseArgs.creature)
        assert.is_nil(toStringArg.boons)
        assert.is_nil(toStringArg.banes)
    end)

    it("returns nil for unsupported dice (d100)", function()
        assert.is_nil(DiceRollLogic.extractExpectedDiceList("1d100"))
    end)

    it("falls back to textual stripping when ParseRoll throws", function()
        dmhub.ParseRoll = function() error("engine parse error") end
        dmhub.RollToString = function() return "should not be reached" end
        local result = DiceRollLogic.extractExpectedDiceList("2d10 1 edge")
        dmhub.RollToString = nil
        assert.are.same({10, 10}, result)
    end)

    it("falls back to textual stripping when RollToString returns a non-string", function()
        dmhub.ParseRoll = function() return {boons = 1, banes = 0} end
        dmhub.RollToString = function() return {} end
        local result = DiceRollLogic.extractExpectedDiceList("2d10 1 edge")
        dmhub.RollToString = nil
        assert.are.same({10, 10}, result)
    end)

    it("returns nil for expressions with no dice", function()
        assert.is_nil(DiceRollLogic.extractExpectedDiceList("5"))
    end)

    it("returns nil for non-string input", function()
        assert.is_nil(DiceRollLogic.extractExpectedDiceList(nil))
        assert.is_nil(DiceRollLogic.extractExpectedDiceList(15))
    end)
end)

describe("buildForcedDice", function()
    it("builds entries in expression order", function()
        local forced = DiceRollLogic.buildForcedDice(
            {{type = "d10", value = 7}, {type = "d10", value = 3}},
            {10, 10})
        assert.are.same({{numFaces = 10, result = 7}, {numFaces = 10, result = 3}}, forced)
    end)

    it("matches mixed faces by type regardless of arrival order", function()
        local forced = DiceRollLogic.buildForcedDice(
            {{type = "d6", value = 4}, {type = "d10", value = 9}},
            {10, 6})
        assert.are.same({{numFaces = 10, result = 9}, {numFaces = 6, result = 4}}, forced)
    end)

    it("accepts a d10 result of 10 (post 0->10 mapping)", function()
        local forced = DiceRollLogic.buildForcedDice(
            {{type = "d10", value = 10}},
            {10})
        assert.are.same({{numFaces = 10, result = 10}}, forced)
    end)

    it("returns count-mismatch when dice counts differ", function()
        local forced, reason = DiceRollLogic.buildForcedDice(
            {{type = "d10", value = 7}},
            {10, 10})
        assert.is_nil(forced)
        assert.are.equal("count-mismatch", reason)
    end)

    it("returns type-mismatch when a die type is missing", function()
        local forced, reason = DiceRollLogic.buildForcedDice(
            {{type = "d10", value = 7}, {type = "d10", value = 3}},
            {10, 6})
        assert.is_nil(forced)
        assert.are.equal("type-mismatch", reason)
    end)

    it("returns out-of-range for an unmapped d10 zero", function()
        local forced, reason = DiceRollLogic.buildForcedDice(
            {{type = "d10", value = 0}},
            {10})
        assert.is_nil(forced)
        assert.are.equal("out-of-range", reason)
    end)

    it("returns out-of-range for a value above the face count", function()
        local forced, reason = DiceRollLogic.buildForcedDice(
            {{type = "d6", value = 7}},
            {6})
        assert.is_nil(forced)
        assert.are.equal("out-of-range", reason)
    end)

    it("returns out-of-range for a fractional value", function()
        -- Engine behavior for non-integer results is undefined; refuse.
        local forced, reason = DiceRollLogic.buildForcedDice(
            {{type = "d6", value = 2.5}},
            {6})
        assert.is_nil(forced)
        assert.are.equal("out-of-range", reason)
    end)

    it("returns type-mismatch for an unrecognized die type", function()
        -- getDiceFaces defaults unknown types to 10; buildForcedDice must
        -- NOT, or garbage entries would force d10 slots.
        local forced, reason = DiceRollLogic.buildForcedDice(
            {{type = "unknown", value = 5}},
            {10})
        assert.is_nil(forced)
        assert.are.equal("type-mismatch", reason)
    end)

    it("returns type-mismatch for a non-string die type", function()
        local forced, reason = DiceRollLogic.buildForcedDice(
            {{type = nil, value = 5}},
            {10})
        assert.is_nil(forced)
        assert.are.equal("type-mismatch", reason)
    end)

    it("returns missing-input for nil arguments", function()
        local forced, reason = DiceRollLogic.buildForcedDice(nil, {10})
        assert.is_nil(forced)
        assert.are.equal("missing-input", reason)
        forced, reason = DiceRollLogic.buildForcedDice({}, nil)
        assert.is_nil(forced)
        assert.are.equal("missing-input", reason)
    end)
end)

describe("forcedDiceHonored", function()
    local FORCED = {{numFaces = 10, result = 7}, {numFaces = 10, result = 3}}

    it("returns true when every forced entry appears in the rolled dice", function()
        assert.is_true(DiceRollLogic.forcedDiceHonored(
            { rolls = {
                { result = 7, numFaces = 10 },
                { result = 3, numFaces = 10 },
            }},
            FORCED))
    end)

    it("returns true on a subset match with extra rolled dice", function()
        -- Game-system mechanics may add dice beyond the forced ones.
        assert.is_true(DiceRollLogic.forcedDiceHonored(
            { rolls = {
                { result = 7, numFaces = 10 },
                { result = 2, numFaces = 4 },
                { result = 3, numFaces = 10 },
            }},
            FORCED))
    end)

    it("returns false when a forced value was not rolled", function()
        assert.is_false(DiceRollLogic.forcedDiceHonored(
            { rolls = {
                { result = 2, numFaces = 10 },
                { result = 9, numFaces = 10 },
            }},
            FORCED))
    end)

    it("does not reuse one rolled die for two forced duplicates", function()
        assert.is_false(DiceRollLogic.forcedDiceHonored(
            { rolls = {
                { result = 7, numFaces = 10 },
                { result = 2, numFaces = 10 },
            }},
            {{numFaces = 10, result = 7}, {numFaces = 10, result = 7}}))
    end)

    it("returns nil when rollInfo has no readable rolls", function()
        assert.is_nil(DiceRollLogic.forcedDiceHonored({}, FORCED))
        assert.is_nil(DiceRollLogic.forcedDiceHonored({ rolls = {} }, FORCED))
        assert.is_nil(DiceRollLogic.forcedDiceHonored(nil, FORCED))
    end)

    it("returns nil for a missing or empty forcedDice table", function()
        local info = { rolls = {{ result = 7, numFaces = 10 }} }
        assert.is_nil(DiceRollLogic.forcedDiceHonored(info, nil))
        assert.is_nil(DiceRollLogic.forcedDiceHonored(info, {}))
    end)

    it("accepts a 6-faced rolled die for a forced d3 entry", function()
        -- The engine renders d3 on the d6 model; whether rollInfo.rolls
        -- reports 3 or 6 faces is unverifiable from Lua, so either must
        -- pass or a 6-faced report would deterministically auto-disable
        -- the feature on every 1d3 roll.
        assert.is_true(DiceRollLogic.forcedDiceHonored(
            { rolls = {{ result = 2, numFaces = 6 }} },
            {{numFaces = 3, result = 2}}))
        assert.is_true(DiceRollLogic.forcedDiceHonored(
            { rolls = {{ result = 2, numFaces = 3 }} },
            {{numFaces = 3, result = 2}}))
    end)

    it("still detects a mismatched result on a d3 entry", function()
        assert.is_false(DiceRollLogic.forcedDiceHonored(
            { rolls = {{ result = 5, numFaces = 6 }} },
            {{numFaces = 3, result = 2}}))
    end)

    it("does not extend the d3 equivalence to other face counts", function()
        assert.is_false(DiceRollLogic.forcedDiceHonored(
            { rolls = {{ result = 7, numFaces = 20 }} },
            {{numFaces = 10, result = 7}}))
    end)
end)
