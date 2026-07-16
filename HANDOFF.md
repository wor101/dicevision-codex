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

## Codex Hook Requirements & Graceful Degradation

DiceVision registers three callbacks on `RollDialog`:

| Hook | Roll type | Declared in Codex (file:line) |
|---|---|---|
| `RollDialog.OnBeforeRoll` | Ability rolls | `Draw Steel UI/DSRollDialog.lua:11` (declaration), `:3308-3309` (call site) |
| `RollDialog.OnReroll` | Re-rolls | `Draw Steel UI/DSRollDialog.lua:12` (declaration), `:2211-2212` (call site) |
| `RollDialog.OnBeforeTableRoll` | Random table lookups | `Draw Steel UI/DSRollDialog.lua:13` (declaration), `DMHub Game Hud/RollOnTableDialog.lua:181-211` (call site) |

The hook field on `RollDialog` is declared as `false` by official Codex. DiceVision detects "Codex declared this hook" by the field being non-nil at load time. Once we install our hook functions, the live `RollDialog` table no longer reflects Codex's original declaration state -- subsequent lifecycle events (`removeRollInterceptor`, `setMode("off")`, future cleanup paths) write `false` into every slot. So the source-of-truth is captured **once at load time** into a snapshot.

**Graceful degradation:** DiceVision registers selectively -- only assigning a callback to slots Codex declared. Missing hooks fall back to virtual dice for that roll type only; other roll types are unaffected. The user sees a chat warning naming each missing hook on every user-driven opt-in (`/dv connect`, `/dv mode replace`, the dice-panel toggle). A `printf` log entry is emitted for every missing hook regardless of the verbose-vs-silent path, so a post-mortem trail exists even on the load-time silent path. `/dv status` shows the wired/missing state at any time.

**Two caches:**
- `DiceVision.codexDeclaredHooks = { ability = bool, reroll = bool, ["table"] = bool }` -- captured once on the first `registerHooks` call from the live `RollDialog` state, then never re-derived. This is the load-bearing snapshot. **Never reset in production.**
- `DiceVision.hooksRegistered = { ability = bool, reroll = bool, ["table"] = bool }` -- reflects whether each hook is currently wired. Updated by `registerHooks` and cleared by `removeRollInterceptor`. Read by `/dv status`.

**Verbose vs silent paths:** `registerHooks(verbose)` emits chat warnings only when `verbose=true`. User-driven entry points (`/dv connect`, `/dv mode replace`, panel toggle, `/dv refresh`) pass `true`. Internal/setup paths (load-time, hidden mode transitions) pass `false`. The `printf` trail fires unconditionally.

**Escape hatch -- `/dv refresh`:** The snapshot is sticky on purpose, but if the user updates Codex mid-session (changing which hooks are declared) or hits a load-order anomaly that locked the snapshot all-false, `/dv refresh` nils `codexDeclaredHooks` and re-runs `registerHooks(true)`. This is the only legal way to drop the snapshot in production code; do not nil `codexDeclaredHooks` from any other site.

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
    mode = "off",  -- "off" or "replace"
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
    multitargets = context.multitargets,
    setActiveRoll = context.setActiveRoll,  -- Callback to set active roll on dialog
    -- Re-roll only fields (set by onReroll, nil for initial rolls):
    isReroll = nil,                   -- true when this is a re-roll
    amendWithResult = nil,            -- Callback: amendWithResult(totalString)
    activeRoll = nil,                 -- Original roll object to restore before amend
    -- Table-roll only fields (set by onBeforeTableRoll, nil for ability rolls):
    isTableRoll = nil,                -- true when this is a table roll
    completeWithResult = nil,         -- Callback: completeWithResult(totalInteger)
    tableRef = nil,                   -- Codex table reference passed by hook
    tableName = nil,
    tokenid = nil,                    -- For table rolls only; ability rolls use rollArgs.tokenid
    guid = nil,
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

#### onReroll Callback (registered on RollDialog.OnReroll)

The `RollDialog.OnReroll` hook is called when a player clicks the re-roll button on an existing roll result. DiceVision intercepts re-rolls the same way it intercepts initial rolls.

**Hook data from DSRollDialog:**
```lua
hookData = {
    originalRoll = rollString,       -- The original roll expression (e.g., "2d10+5")
    rollArgs = rollArgs,             -- Full rollArgs table (contains .description, .boons, etc.)
    amendWithResult = function(val), -- Callback: pass new total as string to amend the roll
    activeRoll = rollObject,         -- The original active roll object
    setActiveRoll = function(roll),  -- Callback to restore g_activeRoll before amend
}
```

**Re-roll flow:**
1. `onReroll` intercepts, stores `pendingRoll` with `isReroll=true`
2. Physical dice arrive, `handlePendingRoll` processes them
3. Re-roll path: calls `setActiveRoll(activeRoll)` to restore the roll context
4. Sends `DiceVisionRollMessage` to chat (visual display)
5. Calls `amendWithResult(tostring(finalTotal))` to update the roll result
6. Unlike initial rolls, does NOT call `dmhub.Roll()` -- the amend engine handles it

**Important:** `amendWithResult` receives `finalTotal` (with edge/bane modifier applied), because the Codex amend engine does NOT re-apply edge/bane modifiers.

#### onBeforeTableRoll Callback (registered on RollDialog.OnBeforeTableRoll)

The `RollDialog.OnBeforeTableRoll` hook is called when a player triggers a random table lookup (e.g., 1d100 wild magic table, 1d20 treasure table). DiceVision intercepts these the same way it intercepts initial rolls and re-rolls.

**Hook data from DSRollDialog:**
```lua
hookData = {
    roll = rollString,                  -- e.g., "1d100" or "1d20+3"
    description = string,
    creature = creature,
    tokenid = tokenId,
    properties = props,
    tableRef = tableRef,                -- Codex table reference object
    tableName = string,
    guid = string,
    completeWithResult = function(int), -- Callback: pass final total as integer
}
```

Note the shape differs from `OnBeforeRoll` / `OnReroll`: there is no `boons`, `banes`, `multitargets`, `rollArgs`, `activeRoll`, or `setActiveRoll`. Table rolls are simple lookups and skip all edge/bane/tier logic.

**Table-roll flow:**
1. `onBeforeTableRoll` intercepts, stores `pendingRoll` with `isTableRoll=true`
2. Physical dice arrive; `handlePendingRoll` enters the table-roll branch (must run before the ability-roll dispatcher because that path requires `rollArgs`, which table rolls do not carry)
3. Detects d100 percentile pair via `DiceRollLogic.detectPercentilePair` (handles "00"+"0" -> 100 case)
4. Sends `DiceVisionRollMessage` to chat with `rollSource="table"`
5. Calls `completeWithResult(total)` -- `total` is an **integer**, not a string (different from `amendWithResult`)
6. Does NOT call `dmhub.Roll()` and does NOT apply edge/bane math

**Important:** On timeout / error / mode-off, table rolls are silently abandoned with a chat notice ("Table roll abandoned. Re-trigger to retry."). Unlike re-rolls, there is no synchronous fallback -- `completeWithResult` requires an integer, and there is no way to evaluate the table-roll formula locally without invoking the async `dmhub.Roll`.

#### handlePendingRoll

**Two top-level paths selected by `DiceVision.useForcedDice` (default `true`; never auto-disabled -- an unsupported build must be turned off manually with `/dv forceddice off`):**

**forcedDice path (`tryForcedDicePath`, requires a Codex build where `dmhub.Roll` accepts `forcedDice`):**
```lua
-- Pass the INTACT expression plus the physical faces; the engine computes
-- boons/banes, tier shifts, and nat detection natively.
dmhub.Roll{
    roll = "2d10+5 1 edge",   -- NOT collapsed
    forcedDice = {{numFaces = 10, result = 7}, {numFaces = 10, result = 4}},
    ...
}
```
- `DiceRollLogic.extractExpectedDiceList(rollStr, creature)` computes the ordered face-count list the expression expects (engine `ParseRoll`/`RollToString` round-trip to strip boons, textual fallback otherwise). Supported dice: d4/d6/d8/d10/d12/d20 (d100 -> legacy fallback).
- Type mappings apply first (Draw Steel's 20-sided d10s arrive as "d20" and would otherwise type-mismatch -- see "Draw Steel Physical Dice" below), then clamp + value-mapping rules (d10 0 -> 10, camera misreads). Keep-selection is NOT applied unless the user rolled more dice than expected and an explicit keep rule exists.
- Known limitation: the clamp rule is d10-centric by definition (values outside 0-10 -> 1), so with clamp enabled a legitimate d20/d12 result above 10 is clamped to 1 and forced as such. Keep clamp off when rolling non-d10 dice. (Characterization test pins this.)
- Detected fallbacks are announced in chat (`Physical dice do not match the roll (<reason>)`), not just the debug console, since count/type/range mismatches are player-actionable. When a die-type mapping contributed (e.g. a REAL d20 rolled for a d20 expression gets diverted by the default `d20 -> d10` rule), the notice names the mapping and points at `/dv rules type`; successful remaps leave a debug-console breadcrumb.
- `DiceRollLogic.buildForcedDice(dice, expectedFaces)` matches physical dice to expected faces by type; refuses on count-mismatch / type-mismatch / out-of-range (never partial-force).
- Deliberately NOT done on this path (all legacy-only workarounds for the collapsed literal): boons/banes field splitting, `multitargets[1]` zeroing, `instant = true`, `overrideTier` injection.
- Re-rolls: `amendWithResult(originalRoll, { forcedDice = forcedDice })` - `doRerollAmend` (dialog Lua in DSRollDialog.lua / EmbeddedRollDialog.lua) merges extraFields into amendArgs before `Amend()`; requires a dialog version whose `doRerollAmend` accepts extraFields.
- The custom DiceVisionRollMessage chat card is OFF by default here (engine message shows real dice); `/dv forceddice card on` re-enables it. The card documents what the camera read (natural dice + static modifier); the engine message is the authoritative result including boons.
- **Any failure the mod can detect falls through to the legacy path below.** The exception is a Codex build without forcedDice support: it cannot be feature-detected from Lua, and the engine silently ignores the field and rolls VIRTUAL dice, discarding the physical values.
- **Verification is best-effort and NON-DISABLING.** The `complete` wrapper never sets `useForcedDice = false`. History: a post-roll comparison of `rollInfo.rolls` against the forced values (`DiceRollLogic.forcedDiceHonored`) produced false negatives that disabled a WORKING feature, because Codex's `doRerollAmend` reuses and RE-FIRES the initial roll's `complete` wrapper with the reroll's `rollInfo` (and for a power roll the reroll fires BEFORE the initial completion), while the closure still holds the initial forced set -- so the value comparison saw a mismatch even though the engine honored the dice. Three attempts to make the comparison robust (deterministic latch, global latch, per-roll `checked`) all failed against this ordering. The wrapper now keeps only one signal: a single quiet, once-per-session note when the engine returns NO readable dice at all (`forcedDiceHonored == nil`). Rerolls yield a value mismatch (`false`), not `nil`, so they never trigger it, and an old build that returns readable-but-virtual dice is not auto-detected -- the user turns it off with `/dv forceddice off`. `warnedUnverifiedForcedDice` gates the note and re-arms on connect and `/dv forceddice on`.
- An uncaught Lua error inside `tryForcedDicePath` is caught by a `pcall` at the fork in `handlePendingRoll` and falls through to legacy; without it the error would strand `isPolling=true` and wedge all subsequent rolls.

**Legacy collapse path (fallback, or `/dv forceddice off`) - two code paths based on targeting:**

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
| `/dv mode <off\|replace>` | Set operation mode |
| `/dv rules <subcommand>` | Configure dice processing rules |
| `/dv forceddice <on\|off>` | Use engine forcedDice (default on; never auto-disables, turn off manually on unsupported builds) |
| `/dv forceddice card <on\|off>` | DiceVision chat card on the forcedDice path (default off) |
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
    typeMappings = {
        ["d20"] = "d10",       -- Draw Steel 20-sided d10s report as "d20"
        ["d6"] = "d3",         -- 6-sided d3s (numbered 1-3 twice) report as "d6"
    },
    diceSelection = nil,
}

-- Runtime rules (modified by commands)
DiceVision.rules = {
    valueMappings = {},         -- {dieType = {fromValue = toValue}}
    typeMappings = {},          -- {fromType = toType}, e.g. {d20 = "d10"}
    typeMappingsOnPanel = false, -- Apply type mappings to panel rolls too
    diceSelection = nil,        -- {keep = "highest"|"lowest", count = N}
    clampOutOfRange = false,    -- Clamp values outside 0-10 to 1
}
```

### Rule Processing Functions (in DiceRollLogic.lua)

| Function | Purpose | Parameters |
|----------|---------|------------|
| `applyTypeMappings(dice, mappings)` | Remap die types (e.g., d20 -> d10) | dice array, mapping table |
| `clampOutOfRangeValues(dice, isEnabled)` | Clamp values outside 0-10 to 1 | dice array, boolean |
| `applyValueMappings(dice, mappings)` | Apply value remapping (e.g., 0 -> 10) | dice array, mapping table |
| `applyDiceSelection(dice, selection)` | Keep highest/lowest N dice | dice array, selection config |
| `detectDiceSelection(pendingRoll)` | Auto-detect numKeep from roll context | pendingRoll object |
| `getEffectiveRules(pendingRoll)` | Merge manual rules with auto-detection | pendingRoll object |
| `applyDiceRules(dice, pendingRoll)` | Main entry point - applies all rules | dice array, pendingRoll |

### Rule Application Order

```lua
function applyDiceRules(dice, pendingRoll)
    -- 1. Type mappings first, so remapped dice pick up the target type's
    --    value rules. Context-gated: intercepted rolls (pendingRoll
    --    present) always; panel rolls only when typeMappingsOnPanel.
    if pendingRoll ~= nil or DiceVision.rules.typeMappingsOnPanel then
        processed = applyTypeMappings(processed, DiceVision.rules.typeMappings)
    end

    -- 2. Clamp out-of-range values (before value mappings)
    processed = clampOutOfRangeValues(processed, DiceVision.rules.clampOutOfRange)

    -- 3. Apply value mappings (e.g., d10 0 -> 10)
    processed = applyValueMappings(processed, rules.valueMappings)

    -- 4. Apply dice selection (keep highest/lowest N)
    processed, droppedDice = applyDiceSelection(processed, rules.diceSelection)

    return processed, droppedDice
end
```

Percentile detection (`detectPercentilePair`) always takes the RAW `rollData.dice` array (panel path: top of `postRollToChat`; table path: inside `handlePendingRoll`), never the rule-processed copy -- so type mappings cannot cause d100 misdetection. Note the table path runs `buildDiceMessage` (and therefore the rules) BEFORE detection chronologically; the protection is the raw input, not the ordering.

### Draw Steel Physical Dice (why type mappings exist)

MCDM's official Draw Steel dice are 20-sided but numbered 1-10 twice, and physical d3s are 6-sided but numbered 1-3 twice. The dice-vision camera classifies dice by physical shape (its taxonomy is d4/d6/d8/d10/d12/d20 only -- see `DiceType` in dice-vision `backend/app/models/shared_types.py`), so these dice arrive as `{type = "d20", value = 1..10}` / `{type = "d6", value = 1..3}` and would type-mismatch against `2d10` / `1d3` expressions on the forcedDice path. The default `d20 -> d10` and `d6 -> d3` type mappings remap them for intercepted rolls; panel rolls are freeform (a physical d20/d6 might really be a d20/d6), so they only remap when `typeMappingsOnPanel` is enabled.

d3 forcing works because d3 is first-class in Codex's Draw Steel UI: the dice panel tile rolls `dmhub.Roll{numDice = 1, numFaces = 3}` and renders it on the d6 geometry showing 1-3 (see `Draw Steel UX Update/DicePanel.lua`), and rollable tables offer `1d3`. The DiceVision chat card mirrors that choice: `CreateDiePanel` renders `faces = 3` on the d6 icon (no d3 icon exists). Because no official code path forces a d3 and whether `rollInfo.rolls` reports such a die as 3- or 6-faced is unverifiable from Lua, `forcedDiceHonored` accepts either face count for a forced d3 entry (this mattered when the honor check drove an auto-disable; the check is now non-disabling, but the equivalence is retained for correctness of its `nil`/value semantics).

Note: Codex's own dice-panel tiles (the 3/6/10/Power Roll buttons) call `dmhub.Roll` directly and are never intercepted by DiceVision -- only rolls that pass through `RollDialog.OnBeforeRoll`/`OnReroll`/`OnBeforeTableRoll` are. Rolling a physical die against a Codex panel tile does nothing to that roll.

Trade-off (same as the real-d20 divert): a REAL d6 rolled for a d6 expression is remapped to d3 and diverts to the announced legacy fallback naming the mapping. Remove with `/dv rules type d6 clear` if real d6s are in play.

### Rules Commands

| Command | Description |
|---------|-------------|
| `/dv rules show` | Display current rule configuration |
| `/dv rules map <die> <from> <to>` | Add value mapping (e.g., `/dv rules map d10 0 10`) |
| `/dv rules type <from> <to>` | Add die type mapping (e.g., `/dv rules type d20 d10`) |
| `/dv rules type <from> clear` | Remove a die type mapping |
| `/dv rules type panel <on\|off>` | Apply type mappings to panel rolls (default off) |
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

## RollDialog.OnBeforeRoll Integration

The `RollDialog.OnBeforeRoll` callback is part of the official Codex codebase. No core file modifications are needed.

- **If DiceVision is loaded**: It registers `onBeforeRoll` on `RollDialog.OnBeforeRoll` at connect time
- **If DiceVision is not loaded**: `RollDialog.OnBeforeRoll` remains `false`, rolls proceed normally
- **On disconnect**: DiceVision sets `RollDialog.OnBeforeRoll = false` to restore normal behavior

**Load order handling**: DiceVision attempts registration both at load time (guarded check for `RollDialog` existence) and at connect time (by then all mods are guaranteed to be loaded).

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
