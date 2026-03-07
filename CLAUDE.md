# DiceVision Mod for MCDM Codex

## Project Overview
This repository contains a mod that integrates physical dice recognition (DiceVision) with MCDM's Codex VTT for Draw Steel. Players can roll physical dice and have those results used in-game instead of virtual dice.

**Official Codex repo**: https://github.com/VerisimLLC/draw-steel-codex (MIT licensed)

## Key Files

| File | Purpose |
|------|---------|
| `Codex/mods/DiceVision_5554/DiceVision.lua` | Main mod - state, API polling, roll interception, commands, chat display |
| `Codex/mods/DiceVision_5554/DiceRollLogic.lua` | Pure roll utility & dice rule processing functions |
| `Codex/mods/DiceVision_5554/DVDicePanel.lua` | Dice panel UI component |
| `Codex/mods/DiceVision_5554/Main.lua` | Mod entry point |
| `HANDOFF.md` | **Detailed technical documentation** - read this for implementation details |
| [`DSRollDialog.lua`](https://github.com/VerisimLLC/draw-steel-codex/blob/main/Draw_Steel_UI_bd58/DSRollDialog.lua) | Official Codex file containing `RollDialog.OnBeforeRoll` hook (external) |

## Architecture (High-Level)
1. User clicks "Roll Dice" in Codex
2. `RollDialog.OnBeforeRoll` callback intercepts (if DiceVision connected in replace mode)
3. DiceVision waits for physical dice from API
4. `handlePendingRoll()` processes result and calls `dmhub.Roll()` with deterministic total

## Draw Steel Edge/Bane Rules (Critical)

Edges and banes cancel 1-for-1. Apply rules based on net (edges - banes):

| Net | Effect |
|-----|--------|
| +1 | +2 modifier |
| -1 | -2 modifier |
| +2 or more | +1 tier shift (no modifier) |
| -2 or less | -1 tier shift (no modifier) |
| 0 | No effect (cancelled out) |

**Tier Thresholds**: T1 (1-11), T2 (12-16), T3 (17+)

## Commands
- `/dv connect <code>` - Connect to DiceVision session
- `/dv disconnect` - Disconnect
- `/dv status` - Show connection status
- `/dv mode <off|replace>` - Set operation mode
- `/dv rules <subcommand>` - Configure dice processing rules (map, keep, clamp, clear)

## Coding Rules
- **ASCII only in Lua files**: Never use non-ASCII / UTF-8 characters (e.g. `->`, `--`, curly quotes) anywhere in `.lua` source files — not in strings, comments, or identifiers. Codex's Lua parser cannot handle multi-byte characters and will fail with misleading syntax errors. Use ASCII equivalents instead (e.g. `->`, `--`, straight quotes).

## Testing

Tests use [Busted](https://lunarmodules.github.io/busted/) (BDD-style Lua testing framework). Test files live in `tests/`.

| File | Purpose |
|------|---------|
| `.busted` | Busted configuration |
| `tests/helpers/test_setup.lua` | Shared setup: loads modules, stubs globals |
| `tests/spec/dice_roll_logic_spec.lua` | Tests for all DiceRollLogic functions |

**Run tests:**
```bash
busted                    # run all tests
busted --verbose          # verbose output
busted -t "functionName"  # run specific test by name
```

**Requirements:**
- Always add tests for new features and bug fixes
- Always run all existing tests (`busted`) after any code changes and verify they pass before considering work complete
- Test files go in `tests/spec/` with the `_spec.lua` suffix
- Shared helpers go in `tests/helpers/`

## Common Tasks
- **Debugging roll issues**: Check `handlePendingRoll()` in DiceVision.lua
- **Edge/bane problems**: Two code paths exist - targeted vs non-targeted rolls. Core logic in DiceRollLogic.lua
- **API issues**: Check polling logic in DiceVision.lua (`longPollForRolls`)
