# DiceVision Mod for MCDM Codex

## Project Overview
This repository contains a mod that integrates physical dice recognition (DiceVision) with MCDM's Codex VTT for Draw Steel. Players can roll physical dice and have those results used in-game instead of virtual dice.

## Key Files

| File | Purpose |
|------|---------|
| `Codex/mods/New_Mod_5237/DiceVision.lua` | Main mod - API polling, roll interception, chat display |
| `Codex/mods/Draw_Steel_UI_bd58/DSRollDialog.lua` | Codex's roll dialog - we added a hook at line 3207 |
| `Codex/mods/New_Mod_5237/HANDOFF.md` | **Detailed technical documentation** - read this for implementation details |

## Architecture (High-Level)
1. User clicks "Roll Dice" in Codex
2. `RollDialog_BeforeRoll` hook intercepts (if DiceVision connected in replace mode)
3. DiceVision waits for physical dice from API
4. `handlePendingRoll()` processes result and calls `dmhub.Roll()` with deterministic total

## Draw Steel Edge/Bane Rules (Critical)

| Situation | Effect |
|-----------|--------|
| 1 edge, 0 banes | +2 to roll |
| 0 edges, 1 bane | -2 to roll |
| 2+ edges, 0 banes | +1 tier shift |
| 0 edges, 2+ banes | -1 tier shift |
| Mixed (unequal) | +2 or -2 based on which is greater |
| Equal | Cancel out |

**Tier Thresholds**: T1 (1-11), T2 (12-16), T3 (17+)

## Commands
- `/dv connect <code>` - Connect to DiceVision session
- `/dv disconnect` - Disconnect
- `/dv status` - Show connection status
- `/dv mode <off|chat|replace>` - Set operation mode

## Common Tasks
- **Debugging roll issues**: Check `handlePendingRoll()` in DiceVision.lua (lines 658-790)
- **Edge/bane problems**: Two code paths exist - targeted vs non-targeted rolls
- **API issues**: Check polling logic (lines 527-571, 880-921)
