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
    -- Sum every standalone +N/-N term. The trailing [dD]? capture filters
    -- out dice groups: in "1d10+2d6+3" the "+2" belongs to "+2d6" and must
    -- not be read as a modifier.
    local total = 0
    for sign, num, dieSuffix in rollStr:gmatch("([%+%-])%s*(%d+)([dD]?)") do
        if dieSuffix == "" then
            local modifier = tonumber(num) or 0
            if sign == "-" then
                modifier = -modifier
            end
            total = total + modifier
        end
    end
    return total
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

--- Remap physical die types before any other rule runs. Exists for dice
-- whose shape does not match their faces: MCDM's Draw Steel dice are
-- 20-sided but numbered 1-10 twice, so the camera (which classifies by
-- shape) reports them as "d20" while every Draw Steel expression wants
-- d10s. mappings is { [fromType] = toType }, e.g. { ["d20"] = "d10" }.
-- Mappings are applied in a SINGLE PASS from the original type -- no
-- chaining: with {d20="d12", d12="d10"} a d20 becomes a d12, not a d10,
-- and a d20<->d10 swap cycle is safe.
-- Remapped dice keep all fields and record originalType, which
-- tryForcedDicePath reads to explain mapping-caused fallbacks.
function DiceRollLogic.applyTypeMappings(dice, mappings)
    if not mappings or next(mappings) == nil then
        return dice
    end
    local result = {}
    for i, die in ipairs(dice) do
        local mapped = mappings[die.type]
        if mapped and mapped ~= die.type then
            local copy = {}
            for k, v in pairs(die) do copy[k] = v end
            copy.type = mapped
            copy.originalType = die.type
            result[i] = copy
        else
            result[i] = die
        end
    end
    return result
end

function DiceRollLogic.applyValueMappings(dice, mappings)
    if not mappings or next(mappings) == nil then
        return dice
    end
    local result = {}
    for i, die in ipairs(dice) do
        local dieType = die.type
        local typeMapping = mappings[dieType] or mappings["*"] or {}
        local newValue = typeMapping[die.value] or die.value
        -- Full copy so provenance fields set by earlier stages
        -- (originalType from applyTypeMappings, originalValue from
        -- clampOutOfRangeValues) survive this rebuild.
        local copy = {}
        for k, v in pairs(die) do copy[k] = v end
        copy.value = newValue
        copy.originalValue = (newValue ~= die.value) and die.value or die.originalValue
        result[i] = copy
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
        -- Full copy: keep provenance fields from earlier stages (see
        -- applyValueMappings).
        local copy = {}
        for k, v in pairs(die) do copy[k] = v end
        copy.value = clamped
        copy.originalValue = (clamped ~= value) and value or die.originalValue
        result[i] = copy
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
    -- Type mappings run FIRST so remapped dice pick up the target type's
    -- value rules (e.g. a Draw Steel d20-shaped d10 gets the d10 0 -> 10
    -- mapping). Intercepted rolls (pendingRoll present) apply them by
    -- default -- the roll expression declares the expected dice. Panel
    -- rolls are freeform (a physical d20 might really be a d20), so they
    -- require the explicit opt-in flag.
    if pendingRoll ~= nil or DiceVision.rules.typeMappingsOnPanel then
        processed = DiceRollLogic.applyTypeMappings(processed, DiceVision.rules.typeMappings)
    end
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

-- Dice the engine can render/force. d3 is first-class in Codex's Draw Steel
-- UI (the dice panel tile rolls dmhub.Roll{numFaces = 3} and renders it on
-- the d6 model showing 1-3, and rollable tables offer 1d3), so numFaces = 3
-- forcedDice entries match engine d3 dice. d100 is intentionally absent: the
-- ability roll path never handled percentile, so a d100 expression falls
-- back to the legacy collapse path.
local SUPPORTED_FORCED_DICE = {
    [3] = true,
    [4] = true, [6] = true, [8] = true, [10] = true, [12] = true, [20] = true,
}

--- True if dieType names a die the engine can render/force ("d4".."d20").
-- Used to validate type-mapping TARGETS: mapping to an unforceable type
-- (d0, d100, ...) would guarantee a permanent forced-path fallback and feed
-- bogus face counts to the chat card icons.
function DiceRollLogic.isSupportedDieType(dieType)
    if type(dieType) ~= "string" then
        return false
    end
    local faces = tonumber(dieType:match("^[dD](%d+)$"))
    return faces ~= nil and SUPPORTED_FORCED_DICE[faces] == true
end

--- Extract the ordered, flattened list of dice face counts a roll expression
-- expects (e.g. "2d10+3 1 bane" -> {10, 10}). Used to build the forcedDice
-- table passed to dmhub.Roll. Returns nil if the expression is unparseable
-- or contains unsupported dice, signalling the caller to use the legacy path.
-- The ParseRoll/RollToString round-trip (strip boons/banes so the dice regex
-- does not have to know about them) mirrors the official DicePanel.lua
-- extractDiceList. Divergence from the official (which returns nil when the
-- APIs are unavailable): we fall back to textually stripping "N edge(s)"/
-- "N bane(s)". The round-trip is pcall'd and type-checked because a throwing
-- ParseRoll or a non-string RollToString must degrade to the textual strip,
-- not crash the roll.
function DiceRollLogic.extractExpectedDiceList(rollStr, creature)
    if type(rollStr) ~= "string" then
        return nil
    end
    local cleanRoll = nil
    if dmhub and dmhub.ParseRoll and dmhub.RollToString then
        local ok, result = pcall(function()
            local parsed = dmhub.ParseRoll(rollStr, creature)
            if parsed == nil then
                return nil
            end
            parsed.boons = nil
            parsed.banes = nil
            local s = dmhub.RollToString(parsed)
            if type(s) == "string" then
                return s
            end
            return nil
        end)
        if ok then
            cleanRoll = result
        end
    end
    if cleanRoll == nil then
        cleanRoll = rollStr:gsub("%d+%s+edges?", ""):gsub("%d+%s+banes?", "")
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

-- Strict die-type parse for buildForcedDice. Unlike getDiceFaces (which
-- defaults unknown types to 10), an unrecognized type must never match a
-- slot: a garbage entry like type="unknown" would otherwise force a d10.
local function strictDiceFaces(dieType)
    if type(dieType) ~= "string" then
        return nil
    end
    return tonumber(dieType:match("^[dD](%d+)$"))
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
            if not used[i] and strictDiceFaces(die.type) == faces then
                used[i] = true
                found = die
                break
            end
        end
        if not found then
            return nil, "type-mismatch"
        end
        -- Out-of-range and fractional values (e.g. an unmapped d10 "0" or a
        -- camera misread) would be dropped engine-side with a warning;
        -- refuse instead so the legacy path handles the roll
        -- deterministically.
        if type(found.value) ~= "number"
            or found.value < 1 or found.value > faces
            or found.value % 1 ~= 0 then
            return nil, "out-of-range"
        end
        forced[#forced + 1] = { numFaces = faces, result = found.value }
    end
    return forced
end

--- Build a roll expression FROM physical dice, for panel rolls that have no
-- pending Codex roll (and thus no expression of their own). Dice are grouped
-- by face count, largest die first: two d10s and a d6 -> "2d10+1d6".
-- dice: rule-processed dice ({type, value} each), dropped dice already
-- excluded.
-- Returns exprString, expectedFaces on success -- expectedFaces is ordered to
-- match the expression's dice slots so buildForcedDice(dice, expectedFaces)
-- yields entries aligned with the expression -- or nil, reason on failure
-- ("missing-input", "unsupported-type"). Any failure means the caller should
-- use the chat-card-only display.
function DiceRollLogic.buildPanelRollExpression(dice)
    if type(dice) ~= "table" or #dice == 0 then
        return nil, "missing-input"
    end
    local counts = {}
    for _, die in ipairs(dice) do
        local faces = strictDiceFaces(die.type)
        if not faces or not SUPPORTED_FORCED_DICE[faces] then
            return nil, "unsupported-type"
        end
        counts[faces] = (counts[faces] or 0) + 1
    end
    local order = {}
    for faces in pairs(counts) do
        order[#order + 1] = faces
    end
    table.sort(order, function(a, b) return a > b end)
    local parts = {}
    local expectedFaces = {}
    for _, faces in ipairs(order) do
        parts[#parts + 1] = string.format("%dd%d", counts[faces], faces)
        for _ = 1, counts[faces] do
            expectedFaces[#expectedFaces + 1] = faces
        end
    end
    return table.concat(parts, "+"), expectedFaces
end

--- Compare a forcedDice table against the completed roll's rollInfo.rolls
-- (each entry: {result, numFaces, ...}).
-- Returns true if every forced entry appears in the rolled dice (subset
-- match, since game-system mechanics may add dice beyond the forced ones),
-- false on a confirmed value mismatch, or nil when rollInfo carries no
-- readable rolls array (cannot verify either way).
-- NOTE: only the `nil` return now drives behavior (a quiet, non-disabling
-- "couldn't read dice" note in tryForcedDicePath). The true/false value
-- comparison is retained for completeness/tests but is no longer acted on:
-- it produced false negatives under Codex's reroll/power-roll re-fire
-- ordering and was disabling a working feature.
function DiceRollLogic.forcedDiceHonored(rollInfo, forcedDice)
    if rollInfo == nil or type(forcedDice) ~= "table" or #forcedDice == 0 then
        return nil
    end
    -- rollInfo may be a plain table or a userdata-backed type; property
    -- access on unexpected shapes must not throw inside a complete callback.
    local ok, rolls = pcall(function() return rollInfo.rolls end)
    if not ok or type(rolls) ~= "table" or #rolls == 0 then
        return nil
    end
    -- The entry-field reads below are pcall'd too: rolls passed the table
    -- check, but its ENTRIES may still be userdata proxies whose field
    -- access throws. A throw means "cannot read the dice" (nil); it must
    -- never escape into the complete callback that calls this.
    local okCompare, honored = pcall(function()
        local used = {}
        for _, entry in ipairs(forcedDice) do
            local found = false
            for i, rolled in ipairs(rolls) do
                -- d3 equivalence: the engine renders d3 on the d6 model, and
                -- whether rollInfo.rolls reports such a die as 3- or 6-faced
                -- is not verifiable from Lua (no official code path forces a
                -- d3). Accept either face count for a forced d3 entry so this
                -- check does not spuriously report a d3 roll as unverified.
                -- (Only the nil return of this function is acted on now; the
                -- honor check is non-disabling.)
                local facesMatch = rolled.numFaces == entry.numFaces
                    or (entry.numFaces == 3 and rolled.numFaces == 6)
                if not used[i]
                    and facesMatch
                    and rolled.result == entry.result then
                    used[i] = true
                    found = true
                    break
                end
            end
            if not found then
                return false
            end
        end
        return true
    end)
    if not okCompare then
        return nil
    end
    return honored
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
