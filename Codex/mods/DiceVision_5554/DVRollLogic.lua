--[[
    DVRollLogic - Pure roll utility and dice rule processing functions
    Extracted from DiceVision.lua for maintainability.

    Loaded before DiceVision.lua (alphabetical sort: uppercase 'R' < lowercase 'i').
    All functions are on the global DVRollLogic table so DiceVision.lua can alias them.
]]

DVRollLogic = {}

-- ============================================================================
-- Pure Utility Functions
-- ============================================================================

function DVRollLogic.extractModifierFromRoll(rollStr)
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

function DVRollLogic.getDiceFaces(dieType)
    local faces = dieType:match("d(%d+)")
    return tonumber(faces) or 10
end

function DVRollLogic.calculateTier(total)
    if total >= 17 then
        return 3
    elseif total >= 12 then
        return 2
    else
        return 1
    end
end

function DVRollLogic.SplitBoons(combinedBoons)
    combinedBoons = combinedBoons or 0
    if combinedBoons >= 0 then
        return combinedBoons, 0
    else
        return 0, -combinedBoons
    end
end

--- Calculate the +-2 modifier from edges and banes using net cancellation.
-- Net +1 = +2 modifier, net -1 = -2 modifier.
-- Net >=2 or <=-2 produce no modifier (tier shift handled by CalculateTierWithEdges).
-- Net 0 = no effect (cancelled out).
function DVRollLogic.GetRollModFromEdgesAndBanes(edges, banes)
    edges = edges or 0
    banes = banes or 0
    local net = edges - banes
    if net == 1 then
        return 2
    elseif net == -1 then
        return -2
    else
        return 0
    end
end

--- Calculate tier with edge/bane tier shifts using net cancellation.
-- Net >=2 = +1 tier shift, net <=-2 = -1 tier shift.
-- Tier is clamped to 1-3.
function DVRollLogic.CalculateTierWithEdges(total, edges, banes)
    local tier = DVRollLogic.calculateTier(total)
    local net = edges - banes
    if net >= 2 then
        tier = tier + 1
    elseif net <= -2 then
        tier = tier - 1
    end
    if tier > 3 then tier = 3 end
    if tier < 1 then tier = 1 end
    return tier
end

function DVRollLogic.ParseBoonsFromRollString(rollString)
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

function DVRollLogic.getTierRanges()
    return {
        { tier = 1, label = "1-11", min = nil, max = 11 },
        { tier = 2, label = "12-16", min = 12, max = 16 },
        { tier = 3, label = "17+", min = 17, max = nil },
    }
end

-- ============================================================================
-- Dice Rule Processing
-- ============================================================================

function DVRollLogic.applyValueMappings(dice, mappings)
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

function DVRollLogic.clampOutOfRangeValues(dice, isEnabled)
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

function DVRollLogic.applyDiceSelection(dice, selection)
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

function DVRollLogic.detectDiceSelection(pendingRoll)
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

function DVRollLogic.getEffectiveRules(pendingRoll)
    local rules = {
        valueMappings = DiceVision.rules.valueMappings or {},
        diceSelection = DiceVision.rules.diceSelection,
    }
    if not rules.diceSelection then
        rules.diceSelection = DVRollLogic.detectDiceSelection(pendingRoll)
    end
    return rules
end

function DVRollLogic.applyDiceRules(dice, pendingRoll)
    local rules = DVRollLogic.getEffectiveRules(pendingRoll)
    local processed = dice
    local droppedDice = nil
    processed = DVRollLogic.clampOutOfRangeValues(processed, DiceVision.rules.clampOutOfRange)
    processed = DVRollLogic.applyValueMappings(processed, rules.valueMappings)
    if rules.diceSelection then
        local sorted
        processed, sorted = DVRollLogic.applyDiceSelection(processed, rules.diceSelection)
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

print("DV: DVRollLogic loaded")
