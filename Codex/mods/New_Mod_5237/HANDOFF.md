# DiceVision Integration - Complete Technical Documentation

## Overview

This document provides a complete picture of how the DiceVision mod integrates physical dice recognition with MCDM's Codex VTT for Draw Steel.

---

## Architecture Summary

```
User clicks "Roll Dice" in Codex
         ↓
DSRollDialog.lua constructs rollArgs (line 3144-3199)
         ↓
Calls RollDialog_BeforeRoll hook (line 3207-3223)
         ↓
DiceVision (if mode="replace" & connected):
  - Stores rollArgs, edges/banes, multitargets
  - Returns "intercept"
  - Shows "Waiting for physical dice..."
         ↓
DSRollDialog sees "intercept", skips dmhub.Roll (line 3227-3228)
         ↓
User rolls physical dice
         ↓
DiceVision API returns dice results
         ↓
handlePendingRoll():
  - Calculates total from physical dice + modifier
  - Sends visual DiceVisionRollMessage to chat
  - Calls dmhub.Roll with deterministic total
         ↓
C# engine processes roll with correct tier/damage
```

---

## Files Modified

### 1. `Draw_Steel_UI_bd58/DSRollDialog.lua`

**Hook Addition (Lines 3203-3229)**

```lua
-- Hook for external mods to intercept rolls (e.g., DiceVision physical dice)
local hookResult = nil
if RollDialog_BeforeRoll then
    hookResult = RollDialog_BeforeRoll({
        rollArgs = rollArgs,
        roll = rollArgs.roll,
        description = rollArgs.description,
        creature = rollArgs.creature,
        tokenid = rollArgs.tokenid,
        properties = rollArgs.properties,
        dmonly = rollArgs.dmonly,
        instant = rollArgs.instant,
        silent = rollArgs.silent,
        delay = rollArgs.delay,
        guid = rollArgs.guid,
        modifiers = modifiersUsed,
        multitargets = multitargetsUsed,
        boons = m_boons,  -- Edge/Bane state for DiceVision
    })
end

-- If hook returns "intercept", the mod will handle calling dmhub.Roll
if hookResult == "intercept" then
    return
end
```

**m_boons State Management**

| Line | Operation | Context |
|------|-----------|---------|
| 480 | Declaration | `local m_boons = 0` |
| 531 | Applied to roll | `roll = GameSystem.ApplyBoons(roll, m_boons)` |
| 1611 | Updated by click | User clicks boon/bane label |
| 1614 | Sync to multitarget | Updates `multitargets[i].boonsOverride` |
| 1649 | Reset on prepare | `m_boons = 0` in boonBar prepare |
| 1653 | Load from multitarget | If multitarget active |
| 3222 | Passed to hook | `boons = m_boons` |

---

### 2. `New_Mod_5237/DiceVision.lua`

**Core Components:**

#### State Management
```lua
local DiceVision = {
    baseUrl = "https://dicevision.dirtyowlbear.com",
    sessionCode = nil,
    connected = false,
    mode = "off",  -- "off", "chat", or "replace"
    isPolling = false,
    pollIntervalMs = 500,
    pendingRoll = nil,
    waitingForRoll = false,
    rollTimeout = 30000,
    currentRequestId = nil,  -- Race condition prevention
}
```

#### Edge/Bane Utility Functions

| Function | Purpose | Returns |
|----------|---------|---------|
| `SplitBoons(combined)` | Convert -2..+2 to separate counts | `(edges, banes)` |
| `GetRollModFromEdgesAndBanes(e, b)` | Calculate ±2 modifier (NOT tier shift) | `0`, `+2`, or `-2` |
| `CalculateTierWithEdges(total, e, b)` | Calculate tier with double edge/bane shifts | `1`, `2`, or `3` |
| `ParseBoonsFromRollString(str)` | Fallback: extract from "2d10 1 edge" | `(edges, banes)` |
| `extractModifierFromRoll(str)` | Get modifier from "2d10+5" | `5` |

#### RollDialog_BeforeRoll Hook (Lines 814-862)

**Stores pending roll context:**
```lua
DiceVision.pendingRoll = {
    rollArgs = context.rollArgs,      -- Full object, modified when dice arrive
    originalRoll = context.roll,      -- For modifier extraction
    description = context.description,
    edges = edges,                    -- From SplitBoons or ParseBoonsFromRollString
    banes = banes,
    multitargets = context.multitargets
}
```

**Fallback for boons reset issue:** If `context.boons == 0` but roll string contains "1 edge" or "2 bane", parses from string (handles boonBar.prepare reset).

#### handlePendingRoll (Lines 658-790)

**Two code paths based on targeting:**

**Non-Targeted Rolls (no multitargets):**
```lua
-- Use GameSystem.ApplyBoons to embed boons in roll string
local boonsValue = edges - banes
local rollWithBoons = GameSystem.ApplyBoons(tostring(baseTotal), boonsValue)
rollArgs.roll = rollWithBoons  -- e.g., "35 1 edge"
-- Engine parses boons from roll string
```

**Targeted Rolls (has multitargets):**
```lua
-- Pass baseTotal, let Codex apply edge/bane modifier
rollArgs.roll = tostring(baseTotal)
rollArgs.boons = edges
rollArgs.banes = banes
-- Zero out multitargets to prevent double-counting
rollArgs.properties.multitargets[1].boons = 0
rollArgs.properties.multitargets[1].banes = 0
```

**Double Edge/Bane Tier Shift Override:**
```lua
-- Wrap complete callback to inject overrideTier
rollArgs.complete = function(rollInfo)
    if (edges >= 2 and banes == 0) or (banes >= 2 and edges == 0) then
        local calculatedTier = CalculateTierWithEdges(finalTotal, edges, banes)
        props.overrideTier = calculatedTier
        rollInfo:UploadProperties(props)
    end
    if originalComplete then originalComplete(rollInfo) end
end
```

#### DiceVisionRollMessage (Lines 312-487)

Custom chat panel rendering physical dice with icons:
- `CreateDiePanel(faces, value)` - 40x40 dice icon with value overlay
- Uses `dmhub.GetDiceStyling()` for consistent appearance
- Displays: description, dice icons, modifier, total, tier label

#### API Polling (Lines 527-571, 880-921)

**Endpoints:**
- `GET /api/codex/session/{code}` - Validate session
- `GET /api/codex/session/{code}/rolls?acknowledge=true&mode={waiting|background}&request_id={id}` - Poll for rolls

**Adaptive polling:**
- `waiting` mode when `waitingForRoll == true` (faster response)
- `background` mode otherwise (lower resource usage)
- `request_id` prevents race condition where fulfilled rolls re-trigger

---

## Edge/Bane Rules (Draw Steel)

| Situation | Effect |
|-----------|--------|
| 1 edge, 0 banes | +2 to roll |
| 0 edges, 1 bane | -2 to roll |
| 2+ edges, 0 banes | +1 tier shift |
| 0 edges, 2+ banes | -1 tier shift |
| edges > banes | +2 to roll |
| banes > edges | -2 to roll |
| edges == banes | No effect |

**Tier Thresholds:**
- Tier 1: 1-11
- Tier 2: 12-16
- Tier 3: 17+

---

## Commands

| Command | Description |
|---------|-------------|
| `/dv connect <code>` | Connect to DiceVision session |
| `/dv disconnect` | Disconnect from session |
| `/dv status` | Show connection status |
| `/dv mode <off\|chat\|replace>` | Set operation mode |
| `/dv rules <subcommand>` | Configure dice processing rules |
| `/dv test` | Test API connection |

---

## Dice Rule Processing

DiceVision includes a configurable rule system for processing physical dice values before they're used in rolls.

### Configuration Structure

```lua
-- Default rules (restored on "rules clear")
local DEFAULT_RULES = {
    valueMappings = {
        ["d10"] = {[0] = 10},  -- Standard d10: 0 reads as 10
    },
    diceSelection = nil,
}

-- Runtime rules (modified by commands)
DiceVision.rules = {
    valueMappings = {},      -- {dieType = {fromValue = toValue}}
    diceSelection = nil,     -- {keep = "highest"|"lowest", count = N}
    clampOutOfRange = false, -- Clamp values outside 0-10 to 1
}
```

### Rule Processing Functions (Lines 246-398)

| Function | Purpose | Parameters |
|----------|---------|------------|
| `clampOutOfRangeValues(dice, isEnabled)` | Clamp values outside 0-10 to 1 | dice array, boolean |
| `applyValueMappings(dice, mappings)` | Apply value remapping (e.g., 0→10) | dice array, mapping table |
| `applyDiceSelection(dice, selection)` | Keep highest/lowest N dice | dice array, selection config |
| `detectDiceSelection(pendingRoll)` | Auto-detect numKeep from roll context | pendingRoll object |
| `getEffectiveRules(pendingRoll)` | Merge manual rules with auto-detection | pendingRoll object |
| `applyDiceRules(dice, pendingRoll)` | Main entry point - applies all rules | dice array, pendingRoll |

### Rule Application Order

```lua
function applyDiceRules(dice, pendingRoll)
    -- 1. Clamp out-of-range values first (before mappings)
    processed = clampOutOfRangeValues(processed, DiceVision.rules.clampOutOfRange)

    -- 2. Apply value mappings (e.g., d10 0 -> 10)
    processed = applyValueMappings(processed, rules.valueMappings)

    -- 3. Apply dice selection (keep highest/lowest N)
    processed, droppedDice = applyDiceSelection(processed, rules.diceSelection)

    return processed, droppedDice
end
```

### Rules Commands

| Command | Description |
|---------|-------------|
| `/dv rules show` | Display current rule configuration |
| `/dv rules map <die> <from> <to>` | Add value mapping (e.g., `/dv rules map d10 0 10`) |
| `/dv rules keep <highest\|lowest> <count>` | Override dice selection |
| `/dv rules keep auto` | Use auto-detection from roll context |
| `/dv rules clamp <on\|off>` | Toggle out-of-range clamping |
| `/dv rules clear` | Reset to default rules |
| `/dv rules clear all` | Clear all rules (no defaults) |

### Clamping Behavior

When `clampOutOfRange` is enabled:
- Applies to **all rolls** (targeted, non-targeted, and chat mode)
- Values < 0 or > 10 are clamped to 1
- Logs clamped values: `[DiceVision] Clamped d10 value 14 -> 1 (out of 0-10 range)`
- Useful for handling DiceVision misreads

---

## Recent Bug Fixes (from git history)

1. **Prevent tier shift indicator on single edge targeted rolls** - Single edges should give +2 modifier, not tier shift indicator
2. **Prevent edge/bane double-counting on targeted rolls** - Zero out `multitargets[1].boons/banes` after setting on `rollArgs`
3. **Renamed Fetch.lua to DiceVision.lua** - Clarity improvement

---

## Known Limitations

1. Action Log shows total rather than individual dice values (visual panel compensates)
2. Requires active DiceVision API connection
3. Only works with Draw Steel roll dialogs (DSRollDialog.lua)

---

## Key Integration Points with Codex

| Codex Function | Usage |
|----------------|-------|
| `dmhub.Roll(rollArgs)` | Execute roll with deterministic total |
| `GameSystem.ApplyBoons(roll, boons)` | Embed edge/bane in roll string |
| `dmhub.GetDiceStyling()` | Get user's dice color preferences |
| `chat.SendCustom(message)` | Send custom chat panel |
| `dmhub.Schedule(delay, fn)` | Schedule polling callbacks |
| `rollInfo:UploadProperties(props)` | Inject overrideTier for tier shifts |
