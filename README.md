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

- [MCDM Codex VTT](https://github.com/VerisimLLC/draw-steel-codex)
- DiceVision account and session at [dicevision.dirtyowlbear.com](https://dicevision.dirtyowlbear.com)

## Installation

### Basic Install (Chat/Off Modes)

Install through Codex's built-in mod manager:

1. Open Codex and go to the mod manager
2. Search for "DiceVision"
3. Enable the mod

### Replace Mode

Replace mode uses the official `RollDialog.OnBeforeRoll` callback built into Codex's DSRollDialog.lua. No additional setup is needed beyond installing the mod — DiceVision registers its callback automatically when you connect to a session.

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
| `/dv rules` | Configure dice processing rules |
| `/dv help` | Show available commands |

## Dice Rules

DiceVision includes a rules system for processing physical dice values:

### Rules Commands

| Command | Description |
|---------|-------------|
| `/dv rules show` | Show current rules |
| `/dv rules map <die> <from> <to>` | Map die value (e.g., `/dv rules map d10 0 10`) |
| `/dv rules keep <highest\|lowest> <count>` | Keep highest/lowest N dice |
| `/dv rules keep auto` | Auto-detect from roll context |
| `/dv rules clamp <on\|off>` | Clamp values outside 0-10 to 1 |
| `/dv rules clear` | Reset rules to defaults |
| `/dv rules clear all` | Clear all rules (including defaults) |

### Default Rules

- **d10 value mapping**: 0 → 10 (standard d10 behavior where 0 reads as 10)

### Value Clamping

When enabled with `/dv rules clamp on`, any dice value outside the 0-10 range is clamped to 1. This helps handle misread dice where DiceVision might return an invalid value like 14 or -3.

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
2. Codex calls `RollDialog.OnBeforeRoll` — DiceVision intercepts the roll (in replace mode)
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

For implementation details and developer documentation, see [HANDOFF.md](HANDOFF.md).

## License

Apache 2.0
