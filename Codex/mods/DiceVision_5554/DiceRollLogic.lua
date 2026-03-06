--[[
    DiceRollLogic - Pure roll utility and dice rule processing functions
    Extracted from DiceVision.lua for maintainability.

    All functions are on the global DiceRollLogic table.
    DiceVision.lua calls them as DiceRollLogic.func() at runtime (no load-order dependency).
]]

DiceRollLogic = {}

-- ============================================================================
-- Pure Utility Functions
-- ============================================================================

function DiceRollLogic.extractModifierFromRoll(rollStr)
    if not rollStr then return 0 end
    local sign, num = rollStr:match("([%+%-])%s*(%d+)")
    if sign and num then
        local modifier = tonumber(num) or 0
        if sign == "-" then
            modifier = -modifier
        end
        return modifier
    end
    return 0
end

function DiceRollLogic.getDiceFaces(dieType)
    local faces = dieType:match("d(%d+)")
    return tonumber(faces) or 10
end

function DiceRollLogic.parseExpectedDiceTypes(rollStr)
    if not rollStr then return {} end
    local result = {}
    for count, faces in rollStr:gmatch("(%d+)d(%d+)") do
        result[#result + 1] = {
            count = tonumber(count),
            faces = tonumber(faces),
            type = "d" .. faces,
        }
    end
    return result
end

function DiceRollLogic.convertDiceTypes(dice, pendingRoll)
    if not DiceVision.rules.convertDice then
        return dice
    end
    if not pendingRoll or not pendingRoll.originalRoll then
        return dice
    end

    local expectedTypes = DiceRollLogic.parseExpectedDiceTypes(pendingRoll.originalRoll)
    if #expectedTypes == 0 then
        return dice
    end

    -- Expand expected types into ordered slots: {count=2, type="d3"} -> two d3 slots
    local expectedSlots = {}
    for _, entry in ipairs(expectedTypes) do
        for i = 1, entry.count do
            expectedSlots[#expectedSlots + 1] = {
                faces = entry.faces,
                type = entry.type,
            }
        end
    end

    local result = {}
    for i, die in ipairs(dice) do
        local slot = expectedSlots[i]
        if slot then
            local physicalFaces = DiceRollLogic.getDiceFaces(die.type)
            local expectedFaces = slot.faces
            if physicalFaces == 6 and physicalFaces ~= expectedFaces then
                -- Convert: e.g., d6 value -> d3 value
                local converted = math.ceil(die.value * expectedFaces / physicalFaces)
                -- Clamp to valid range
                if converted < 1 then converted = 1 end
                if converted > expectedFaces then converted = expectedFaces end
                print(string.format("[DiceVision] Converted %s:%d -> %s:%d",
                    die.type, die.value, slot.type, converted))
                result[i] = {
                    type = slot.type,
                    value = converted,
                    physicalType = die.type,
                    physicalValue = die.value,
                }
            else
                result[i] = {
                    type = die.type,
                    value = die.value,
                }
            end
        else
            result[i] = {
                type = die.type,
                value = die.value,
            }
        end
    end
    return result
end

function DiceRollLogic.calculateTier(total)
    if total >= 17 then
        return 3
    elseif total >= 12 then
        return 2
    else
        return 1
    end
end

function DiceRollLogic.SplitBoons(combinedBoons)
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
function DiceRollLogic.GetRollModFromEdgesAndBanes(edges, banes)
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
function DiceRollLogic.CalculateTierWithEdges(total, edges, banes)
    local tier = DiceRollLogic.calculateTier(total)
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

function DiceRollLogic.ParseBoonsFromRollString(rollString)
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

function DiceRollLogic.getTierRanges()
    return {
        { tier = 1, label = "1-11", min = nil, max = 11 },
        { tier = 2, label = "12-16", min = 12, max = 16 },
        { tier = 3, label = "17+", min = 17, max = nil },
    }
end

-- ============================================================================
-- Dice Rule Processing
-- ============================================================================

function DiceRollLogic.applyValueMappings(dice, mappings)
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

function DiceRollLogic.clampOutOfRangeValues(dice, isEnabled)
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

function DiceRollLogic.applyDiceSelection(dice, selection)
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

function DiceRollLogic.detectDiceSelection(pendingRoll)
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

function DiceRollLogic.getEffectiveRules(pendingRoll)
    local rules = {
        valueMappings = DiceVision.rules.valueMappings or {},
        diceSelection = DiceVision.rules.diceSelection,
    }
    if not rules.diceSelection then
        rules.diceSelection = DiceRollLogic.detectDiceSelection(pendingRoll)
    end
    return rules
end

function DiceRollLogic.applyDiceRules(dice, pendingRoll)
    local rules = DiceRollLogic.getEffectiveRules(pendingRoll)
    local processed = dice
    local droppedDice = nil
    -- 0. Convert dice types (e.g., physical d6 -> virtual d3)
    processed = DiceRollLogic.convertDiceTypes(processed, pendingRoll)
    -- 1. Clamp out-of-range values
    processed = DiceRollLogic.clampOutOfRangeValues(processed, DiceVision.rules.clampOutOfRange)
    processed = DiceRollLogic.applyValueMappings(processed, rules.valueMappings)
    if rules.diceSelection then
        local sorted
        processed, sorted = DiceRollLogic.applyDiceSelection(processed, rules.diceSelection)
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

print("DV: DiceRollLogic loaded")
