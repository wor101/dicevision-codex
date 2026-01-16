# DiceVision Integration - Handoff Documentation

## Overview

This document summarizes the changes made to integrate DiceVision (physical dice recognition) with Codex (MCDM's Draw Steel VTT). The integration allows players to roll physical dice and have those results used in the game, replacing virtual dice rolls.

## Files Modified

### 1. `Draw_Steel_UI_bd58/DSRollDialog.lua`

**Location:** Lines 3203-3228

**Change:** Added a hook system that allows external mods to intercept dice rolls before `dmhub.Roll` is called.

```lua
-- Hook for external mods to intercept rolls (e.g., DiceVision physical dice)
-- Returns "intercept" if the mod wants to handle the roll itself
-- In that case, we skip dmhub.Roll - the mod will call it later with modified args
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
    })
end

-- If hook returns "intercept", the mod will handle calling dmhub.Roll
if hookResult == "intercept" then
    return
end
```

**Why:** The hook allows DiceVision to intercept the roll, wait for physical dice, then call `dmhub.Roll` with the calculated total. This ensures the C# engine properly calculates tiers and damage.

### 2. `New_Mod_5237/Fetch.lua`

**This is the main DiceVision integration mod.** Key components:

#### Global Hook Function: `RollDialog_BeforeRoll`
- Called by DSRollDialog before any dice roll
- Returns `"intercept"` when DiceVision is in replace mode and connected
- Stores the `rollArgs` for later use when physical dice arrive
- Shows "Waiting for physical dice..." message

#### `handlePendingRoll(rollData)` Function
- Called when physical dice results arrive from the DiceVision API
- Calculates total from physical dice values + modifier from original roll string
- Sends a visual `DiceVisionRollMessage` to chat showing individual dice icons and values
- Modifies `rollArgs.roll` to be the deterministic total (e.g., "15" instead of "2d10+2")
- Calls `dmhub.Roll(rollArgs)` with `instant = true` to process game mechanics

#### `DiceVisionRollMessage` Custom Chat Panel
- Renders dice icons with individual values
- Shows modifier, total, and tier result
- Matches the visual style of native Codex dice

## Architecture

### Roll Interception Flow

```
1. User initiates roll (e.g., Ranged Free Strike)
     |
2. DSRollDialog.lua calls RollDialog_BeforeRoll hook
     |
3. DiceVision (if in replace mode + connected):
   - Stores rollArgs
   - Returns "intercept"
   - Shows "Waiting for physical dice..."
     |
4. DSRollDialog sees "intercept", skips dmhub.Roll
     |
5. User rolls physical dice
     |
6. DiceVision API returns dice results
     |
7. handlePendingRoll():
   - Calculates total from physical dice
   - Sends visual dice display to chat
   - Calls dmhub.Roll with deterministic total
     |
8. C# engine processes roll with correct tier/damage
```

### Why This Approach?

Previous attempts tried:
1. **Creating Lua rollInfo tables** - Failed because UI binds to C# userdata objects, not Lua tables
2. **Using SetInfo() on C# objects** - Failed because virtual dice still animated with random values

The current approach works because:
- We intercept BEFORE `dmhub.Roll` is called, preventing virtual dice
- We call `dmhub.Roll` ourselves with a deterministic total
- The C# engine creates a proper `ChatMessageDiceRollInfoLua` object
- Tier highlighting and damage calculation work correctly

## Commands

The mod provides `/dv` commands:

- `/dv help` - Show help
- `/dv status` - Show connection status
- `/dv connect <session-code>` - Connect to DiceVision API
- `/dv disconnect` - Disconnect from DiceVision
- `/dv mode <chat|replace>` - Set operation mode
  - `chat`: Posts physical dice results to chat only
  - `replace`: Replaces virtual dice rolls with physical dice

## Configuration

- **API Base URL:** Configured in `DiceVision.apiBaseUrl`
- **Poll Interval:** Default 250ms, can be adjusted by server response
- **Roll Timeout:** Default 30 seconds

## Testing

1. Start Codex
2. Run `/dv connect <session-code>` with a valid DiceVision session
3. Run `/dv mode replace`
4. Initiate a power roll targeting an enemy
5. Roll physical dice
6. Verify:
   - Visual dice display appears in chat with individual values
   - Tier highlights correctly in power table
   - Damage is applied correctly to target

## Known Limitations

- Action Log shows the total rather than individual dice values (the visual panel compensates for this)
- Requires active DiceVision API connection
- Only works with Draw Steel roll dialogs (DSRollDialog.lua)
