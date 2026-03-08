# DiceVision Integration - Complete Technical Documentation

## Overview

This document provides a complete picture of how the DiceVision mod integrates physical dice recognition with MCDM's Codex VTT for Draw Steel.

---

## Architecture Summary

```
User clicks "Roll Dice" in Codex
         ↓
DSRollDialog.lua constructs rollArgs (line ~3200)
         ↓
Calls RollDialog.OnBeforeRoll callback (line 3247-3263)
         ↓
DiceVision (if mode="replace" & connected):
  - Stores rollArgs, edges/banes, multitargets
  - Returns "intercept"
  - Shows "Waiting for physical dice..."
         ↓
DSRollDialog sees "intercept", skips dmhub.Roll (line 3266-3268)
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

## Official Codex Hook: RollDialog.OnBeforeRoll

### DSRollDialog.lua (Official, Unmodified)

The `RollDialog.OnBeforeRoll` callback is built into the official Codex codebase ([`Draw_Steel_UI_bd58/DSRollDialog.lua`](https://github.com/VerisimLLC/draw-steel-codex/blob/main/Draw_Steel_UI_bd58/DSRollDialog.lua)). DiceVision no longer needs to modify this file.

**How it works (Lines 3247-3268):**

```lua
-- Hook for external mods to intercept rolls
local hookResult = nil
if RollDialog.OnBeforeRoll then
    hookResult = RollDialog.OnBeforeRoll({
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
        boons = m_boons,
    })
end

if hookResult == "intercept" then
    return
end
```

The `RollDialog` table is declared at line 10 of DSRollDialog.lua with `OnBeforeRoll = false`. DiceVision assigns its callback function to `RollDialog.OnBeforeRoll` at connect time.

---

## DiceVision Mod Files

### `DiceVision_5554/DiceRollLogic.lua`

Pure roll utility and dice rule processing functions, extracted from DiceVision.lua for maintainability. All functions live on the global `DiceRollLogic` table; DiceVision.lua calls them directly as `DiceRollLogic.func()` at runtime (no load-order dependency).

**Functions:**

| Function | Purpose |
|----------|---------|
| `extractModifierFromRoll(str)` | Get modifier from "2d10+5" |
| `getDiceFaces(dieType)` | Get face count from "d10" |
| `calculateTier(total)` | Raw tier from total (1-11=T1, 12-16=T2, 17+=T3) |
| `SplitBoons(combined)` | Convert combined boons value to (edges, banes) |
| `GetRollModFromEdgesAndBanes(e, b)` | Net-based ±2 modifier (net ±1 only) |
| `CalculateTierWithEdges(total, e, b)` | Tier with net-based tier shift (net ±2+) |
| `ParseBoonsFromRollString(str)` | Fallback: extract from "2d10 1 edge" |
| `getTierRanges()` | Tier threshold definitions |
| `applyValueMappings(dice, mappings)` | Apply value remapping (e.g., 0→10) |
| `clampOutOfRangeValues(dice, isEnabled)` | Clamp values outside 0-10 to 1 |
| `applyDiceSelection(dice, selection)` | Keep highest/lowest N dice |
| `detectDiceSelection(pendingRoll)` | Auto-detect numKeep from roll context |
| `getEffectiveRules(pendingRoll)` | Merge manual rules with auto-detection |
| `applyDiceRules(dice, pendingRoll)` | Main entry point - applies all rules |
| `detectPercentilePair(dice)` | Detect d100 pair from raw string values |

### `DiceVision_5554/DiceVision.lua`

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

#### Edge/Bane Utility Functions (in DiceRollLogic.lua)

| Function | Purpose | Returns |
|----------|---------|---------|
| `SplitBoons(combined)` | Convert combined boons value to separate counts | `(edges, banes)` |
| `GetRollModFromEdgesAndBanes(e, b)` | Net-based ±2 modifier (net ±1 only; net ±2+ returns 0) | `0`, `+2`, or `-2` |
| `CalculateTierWithEdges(total, e, b)` | Tier with net-based tier shift (net ±2+) | `1`, `2`, or `3` |
| `ParseBoonsFromRollString(str)` | Fallback: extract from "2d10 1 edge" | `(edges, banes)` |
| `extractModifierFromRoll(str)` | Get modifier from "2d10+5" | `5` |

#### onBeforeRoll Callback (registered on RollDialog.OnBeforeRoll)

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

**Registration pattern (load order safe):**
```lua
-- At load time (guarded — RollDialog may not exist yet)
if RollDialog then
    RollDialog.OnBeforeRoll = onBeforeRoll
end

-- At connect time (guaranteed — all mods loaded by then)
if RollDialog then
    RollDialog.OnBeforeRoll = onBeforeRoll
end
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
-- Convert raw edges/banes to net values so the engine handles them correctly
local net = edges - banes
rollArgs.roll = tostring(baseTotal)
if net > 0 then
    rollArgs.boons = net
    rollArgs.banes = 0
elseif net < 0 then
    rollArgs.boons = 0
    rollArgs.banes = -net
else
    rollArgs.boons = 0
    rollArgs.banes = 0
end
-- Zero out multitargets to prevent double-counting
rollArgs.properties.multitargets[1].boons = 0
rollArgs.properties.multitargets[1].banes = 0
```

**Net Edge/Bane Tier Shift Override:**
```lua
-- Wrap complete callback to inject overrideTier
rollArgs.complete = function(rollInfo)
    local net = edges - banes
    if net >= 2 or net <= -2 then
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

Edges and banes cancel 1-for-1. Apply rules based on net (edges - banes):

| Net | Effect |
|-----|--------|
| +1 | +2 modifier |
| -1 | -2 modifier |
| +2 or more | +1 tier shift (no modifier) |
| -2 or less | -1 tier shift (no modifier) |
| 0 | No effect (cancelled out) |

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

### Rule Processing Functions (in DiceRollLogic.lua)

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

## RollDialog Hook Integration

### RollDialog.OnBeforeRoll

The `RollDialog.OnBeforeRoll` callback is part of the official Codex codebase. No core file modifications are needed.

- **If DiceVision is loaded**: It registers `onBeforeRoll` on `RollDialog.OnBeforeRoll` at connect time
- **If DiceVision is not loaded**: `RollDialog.OnBeforeRoll` remains `false`, rolls proceed normally
- **On disconnect**: DiceVision sets `RollDialog.OnBeforeRoll = false` to restore normal behavior

**Load order handling**: DiceVision attempts registration both at load time (guarded check for `RollDialog` existence) and at connect time (by then all mods are guaranteed to be loaded).

### RollDialog.OnReroll (Re-roll Support)

When DiceVision intercepts a roll via `OnBeforeRoll`, the `EmbeddedRollDialog.lua` re-roll button cannot function normally because `g_activeRoll` is `nil` (the intercept `return` skips `g_activeRoll = activeRoll`). The `RollDialog.OnReroll` hook addresses this.

**How it works:**

1. `onBeforeRoll` saves the original roll context to `DiceVision.lastInterceptedContext` (including the original `rollArgs.complete` callback and `rollArgs.instant` value before `handlePendingRoll` modifies them)
2. When the user clicks "Re-roll", `EmbeddedRollDialog.lua` checks `g_activeRoll == nil` and calls `RollDialog.OnReroll({rollArgs = g_activeRollArgs})`
3. `onReroll` restores `rollArgs.roll`, `rollArgs.complete`, and `rollArgs.instant` to their original values (preventing double-wrapping of the complete callback)
4. `onReroll` calls `startDiceIntercept()` to set up a new pending roll and returns `"intercept"`

**State flow for re-rolls:**
```
onBeforeRoll -> saves lastInterceptedContext (original values)
             -> startDiceIntercept() sets up pendingRoll + polling
             -> handlePendingRoll modifies rollArgs (roll, complete, instant)
             -> user sees result

onReroll     -> restores rollArgs from lastInterceptedContext
             -> startDiceIntercept() sets up new pendingRoll + polling
             -> handlePendingRoll processes new physical dice
             -> user sees new result (can re-roll again)
```

**Key design decisions:**
- **Separate `OnReroll` hook** (not reusing `OnBeforeRoll`): The re-roll button only has access to `g_activeRollArgs`, not to `m_boons` or `multitargetsUsed` (scoped to the submit handler). DiceVision uses its saved context instead.
- **Saving `originalComplete`**: `handlePendingRoll` wraps `rollArgs.complete` to inject tier override + visual message. Without restoring on re-roll, each re-roll adds another wrapper, causing duplicate messages.
- **`startDiceIntercept` helper**: Shared between `onBeforeRoll` and `onReroll` to avoid duplicating pending roll setup logic.

**Registration/cleanup:** `RollDialog.OnReroll` is registered alongside `RollDialog.OnBeforeRoll` at connect time, load time, and `setMode("replace")`. It is set to `false` in `removeRollInterceptor()` (called by disconnect and `setMode("off")`).

---

## Installation Requirements

DiceVision's replace mode requires only the DiceVision mod files installed in Codex's mods directory:

| # | Requirement | Details |
|---|-------------|---------|
| 1 | **DiceVision mod files** | `DiceVision_5554/` folder with `DiceVision.lua`, `DiceRollLogic.lua`, `DVDicePanel.lua`, and `Main.lua` in the Codex mods directory |

No core Codex file modifications are needed. The `RollDialog.OnBeforeRoll` callback is built into the official DSRollDialog.lua. See the [official Codex repo](https://github.com/VerisimLLC/draw-steel-codex) for the source.

---

## Percentile (d100) Detection

DiceVision can detect percentile (d100) rolls when the API sends die values as **strings**. This preserves the distinction between `"0"` (standard d10 zero face) and `"00"` (percentile tens-die zero face).

### How It Works

1. **String preservation**: `handleDiceVisionRoll` saves each die's original string as `die.rawValue` before converting `die.value` to an integer.
2. **Detection**: `DiceRollLogic.detectPercentilePair(dice)` examines `rawValue` strings on exactly 2 d10 dice:
   - **Tens die**: `rawValue` is `"00"` or a two-digit multiple of 10 (`"10"`, `"20"`, ... `"90"`)
   - **Units die**: `rawValue` is a single digit (`"0"` through `"9"`)
3. **Total calculation**: `tens.value + units.value`, with the special case that `0 + 0 = 100` (standard d100 convention).
4. **Bypass**: Percentile rolls skip `applyDiceRules` entirely — no 0→10 mapping, no clamping, no dice selection.

### Dependency

This feature requires the DiceVision API router to send die values as **strings** rather than integers. If the router converts to integers before sending, all values arrive as numbers and percentile detection cannot distinguish `"00"` from `"0"`.

### Key Cases

| Tens rawValue | Units rawValue | Total | Notes |
|---------------|----------------|-------|-------|
| `"30"` | `"7"` | 37 | Standard percentile |
| `"00"` | `"7"` | 7 | Detected via "00" string |
| `"00"` | `"0"` | **100** | 0+0 → 100 convention |
| `"10"` | `"0"` | 10 | |
| Two `"0"` values | | Standard 2d10 | No tens die detected; 0→10 mapping applies |

---

## Known Limitations

1. Action Log shows total rather than individual dice values (visual panel compensates)
2. Requires active DiceVision API connection
3. Only works with Draw Steel roll dialogs (DSRollDialog.lua)

---

## History: How the Hook Was Added to Codex

DiceVision originally required a local modification to DSRollDialog.lua because no pre-roll hook existed. We explored several alternatives (wrapping `dmhub.Roll()`, file shadowing, global events, UI events) but none worked due to engine limitations.

We submitted a PR to the Codex team proposing a `RollDialog_BeforeRoll` global function pattern. They accepted the concept but implemented it as `RollDialog.OnBeforeRoll` — a callback field on the `RollDialog` table declared at the top of DSRollDialog.lua. This is now part of the official codebase, so DiceVision no longer requires any core file modifications.

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
