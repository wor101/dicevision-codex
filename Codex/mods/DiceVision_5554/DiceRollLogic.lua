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

    local rollStr = pendingRoll.originalRoll
    local numKeep, numDice

    -- Method 1: Parse roll string for "keep [low|high] N" pattern
    local keepMatch = string.match(rollStr, "keep%s+%a*%s*(%d+)")
    if keepMatch then
        numKeep = tonumber(keepMatch)
        numDice = tonumber(string.match(rollStr, "(%d+)d%d+"))
    end

    -- Method 2: Fall back to dmhub.ParseRoll()
    if not numKeep or not numDice then
        local creature = pendingRoll.rollArgs and pendingRoll.rollArgs.creature
        local rollInfo = dmhub.ParseRoll(rollStr, creature)
        if rollInfo and rollInfo.categories then
            for _, category in pairs(rollInfo.categories) do
                if category.groups then
                    for _, group in ipairs(category.groups) do
                        if group.numKeep and group.numKeep > 0
                           and group.numDice and group.numDice > group.numKeep then
                            numKeep = group.numKeep
                            numDice = group.numDice
                            break
                        end
                    end
                end
                if numKeep then break end
            end
        end
    end

    if not numKeep or not numDice or numKeep >= numDice then
        return nil
    end

    -- Determine keep direction
    local keepDirection = "highest"
    if string.find(rollStr, "keep%s+low") then
        keepDirection = "lowest"
    elseif dmhub.GetRollAdvantage then
        local advState = dmhub.GetRollAdvantage(rollStr)
        if advState == "disadvantage" then
            keepDirection = "lowest"
        end
    end

    return {
        keep = keepDirection,
        count = numKeep,
        total = numDice,
    }
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

-- ============================================================================
-- Forced Dice (engine forcedDice support)
-- ============================================================================

-- Dice the engine can render/force. d100 is intentionally absent: the ability
-- roll path never handled percentile, so a d100 expression falls back to the
-- legacy collapse path.
local SUPPORTED_FORCED_DICE = {
    [4] = true, [6] = true, [8] = true, [10] = true, [12] = true, [20] = true,
}

--- Extract the ordered, flattened list of dice face counts a roll expression
-- expects (e.g. "2d10+3 1 bane" -> {10, 10}). Used to build the forcedDice
-- table passed to dmhub.Roll. Returns nil if the expression is unparseable
-- or contains unsupported dice, signalling the caller to use the legacy path.
-- Mirrors the official DicePanel.lua extractDiceList: prefer an engine
-- ParseRoll/RollToString round-trip to strip boons/banes so the dice regex
-- does not have to know about them; fall back to textual stripping when
-- those APIs are unavailable.
function DiceRollLogic.extractExpectedDiceList(rollStr, creature)
    if type(rollStr) ~= "string" then
        return nil
    end
    local cleanRoll = rollStr
    if dmhub and dmhub.ParseRoll and dmhub.RollToString then
        local parsed = dmhub.ParseRoll(rollStr, creature)
        if parsed ~= nil then
            parsed.boons = nil
            parsed.banes = nil
            cleanRoll = dmhub.RollToString(parsed) or rollStr
        end
    else
        cleanRoll = cleanRoll:gsub("%d+%s+edges?", ""):gsub("%d+%s+banes?", "")
    end
    local diceList = {}
    for n, sides in string.gmatch(cleanRoll, "(%d*)[dD](%d+)") do
        local faces = tonumber(sides)
        if not SUPPORTED_FORCED_DICE[faces] then
            return nil
        end
        for _ = 1, (tonumber(n) or 1) do
            diceList[#diceList + 1] = faces
        end
    end
    if #diceList == 0 then
        return nil
    end
    return diceList
end

--- Build the forcedDice table for dmhub.Roll from physical dice.
-- dice: physical dice AFTER clamp/value-mapping rules ({type, value} each).
-- expectedFaces: array from extractExpectedDiceList.
-- Each expected face count is matched to an unused physical die of the same
-- face count (order-independent by type, first-come within a type).
-- Returns forcedDice, nil on success or nil, reason on failure. Any failure
-- means the caller should use the legacy path: never partial-force, since the
-- engine would virtually roll unmatched dice, violating physical-dice intent.
function DiceRollLogic.buildForcedDice(dice, expectedFaces)
    if not dice or not expectedFaces then
        return nil, "missing-input"
    end
    if #dice ~= #expectedFaces then
        return nil, "count-mismatch"
    end
    local used = {}
    local forced = {}
    for _, faces in ipairs(expectedFaces) do
        local found = nil
        for i, die in ipairs(dice) do
            if not used[i] and DiceRollLogic.getDiceFaces(die.type) == faces then
                used[i] = true
                found = die
                break
            end
        end
        if not found then
            return nil, "type-mismatch"
        end
        -- Out-of-range values (e.g. an unmapped d10 "0" or a camera misread)
        -- would be dropped engine-side with a warning; refuse instead so the
        -- legacy path handles the roll deterministically.
        if type(found.value) ~= "number" or found.value < 1 or found.value > faces then
            return nil, "out-of-range"
        end
        forced[#forced + 1] = { numFaces = faces, result = found.value }
    end
    return forced
end

-- ============================================================================
-- Percentile (d100) Detection
-- ============================================================================

--- Detect a percentile (d100) pair from raw string die values.
-- Requires exactly 2 d10 dice. A "tens" die has rawValue "00" or a two-digit
-- multiple of 10 ("10".."90"). A "units" die has a single-digit rawValue ("0".."9").
-- Returns { tens = die, units = die, total = number } or nil.
-- Special case: total of 0 ("00" + "0") maps to 100.
function DiceRollLogic.detectPercentilePair(dice)
    if not dice or #dice ~= 2 then
        return nil
    end

    -- Both must be d10
    if dice[1].type ~= "d10" or dice[2].type ~= "d10" then
        return nil
    end

    -- Valid percentile tens faces: "00", "10", "20", ... "90"
    local function isTensDie(die)
        local raw = tostring(die.rawValue)
        if raw == "00" then return true end
        local num = tonumber(raw)
        if num and num >= 10 and num <= 90 and num % 10 == 0 then
            return true
        end
        return false
    end

    -- Valid units faces: single digit "0" through "9"
    local function isUnitsDie(die)
        local raw = tostring(die.rawValue)
        return raw:match("^%d$") ~= nil
    end

    local tens, units

    if isTensDie(dice[1]) and isUnitsDie(dice[2]) then
        tens = dice[1]
        units = dice[2]
    elseif isTensDie(dice[2]) and isUnitsDie(dice[1]) then
        tens = dice[2]
        units = dice[1]
    else
        return nil
    end

    local total = tens.value + units.value
    if total == 0 then
        total = 100
    end

    return { tens = tens, units = units, total = total }
end

print("DV: DiceRollLogic loaded")
