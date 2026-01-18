# DiceVision for MCDM Codex

Physical dice integration for MCDM's Codex VTT (Draw Steel).

## What is DiceVision?

DiceVision lets you roll real, physical dice and have those results used in your Codex game instead of virtual dice. Point your camera at your dice, and DiceVision's recognition system reads the values and sends them to Codex.

## Features

- **Three operating modes**: Off, Chat (display alongside virtual), or Replace (use instead of virtual)
- **Full Edge/Bane support**: Single edge/bane modifiers and double edge/bane tier shifts
- **Custom dice display**: Physical dice results shown in chat with dice icons
- **Multi-target roll support**: Works with attacks targeting multiple creatures

## Requirements

- MCDM Codex VTT
- DiceVision account and session at [dicevision.dirtyowlbear.com](https://dicevision.dirtyowlbear.com)

## Installation

This mod is installed through Codex's built-in mod manager:

1. Open Codex and go to the mod manager
2. Search for "DiceVision"
3. Enable the mod

## Quick Start

1. Start a DiceVision session at [dicevision.dirtyowlbear.com](https://dicevision.dirtyowlbear.com)
2. In Codex chat, connect with your session code: `/dv connect <session-code>`
3. Set replace mode: `/dv mode replace`
4. When you make a roll in Codex, it will wait for your physical dice
5. Roll your dice in view of the camera
6. DiceVision reads the result and sends it to Codex

## Commands

| Command | Description |
|---------|-------------|
| `/dv connect <code>` | Connect to DiceVision session |
| `/dv disconnect` | Disconnect from session |
| `/dv status` | Show connection status |
| `/dv mode <off\|chat\|replace>` | Set operation mode |
| `/dv test` | Test API connection |
| `/dv help` | Show available commands |

## Operating Modes

| Mode | Behavior |
|------|----------|
| `off` | DiceVision disabled, virtual dice used normally |
| `chat` | Physical dice results shown in chat alongside virtual dice |
| `replace` | Physical dice replace virtual dice entirely |

## Draw Steel Edge/Bane Rules

DiceVision fully supports Draw Steel's edge and bane system:

| Situation | Effect |
|-----------|--------|
| 1 edge, 0 banes | +2 to roll |
| 0 edges, 1 bane | -2 to roll |
| 2+ edges, 0 banes | +1 tier shift |
| 0 edges, 2+ banes | -1 tier shift |
| Edges > banes | +2 to roll |
| Banes > edges | -2 to roll |
| Equal edges and banes | Cancel out |

**Tier Thresholds**: Tier 1 (1-11), Tier 2 (12-16), Tier 3 (17+)

## How It Works

1. You click "Roll Dice" in Codex
2. DiceVision intercepts the roll (in replace mode)
3. Codex displays "Waiting for physical dice..."
4. You roll your physical dice
5. DiceVision's API sends the dice values to the mod
6. The mod calculates the total with modifiers and edge/bane effects
7. Results appear in chat with dice icons showing each die
8. Codex processes the roll with correct tier/damage

## Known Limitations

- Action Log shows the calculated total rather than individual dice values (the chat display shows individual dice)
- Requires active DiceVision API connection
- Only works with Draw Steel roll dialogs

## Technical Documentation

For implementation details and developer documentation, see [HANDOFF.md](Codex/mods/New_Mod_5237/HANDOFF.md).

## License

Apache 2.0
