# DiceVision for MCDM Codex

Physical dice integration for MCDM's Codex VTT (Draw Steel).

## What is DiceVision?

DiceVision lets you roll real, physical dice and have those results used in your Codex game instead of virtual dice. Point your camera at your dice, and DiceVision's recognition system reads the values and sends them to Codex.

## Features

- **Two operating modes**: Off (virtual dice) or Replace (physical dice replace virtual)
- **Dockable panel UI**: Connect, pause/resume, and configure everything without touching chat commands
- **Settings popup**: A gear icon opens connection diagnostics plus a full dice-rules editor (clamp, keep-selection, value mappings)
- **Full Edge/Bane support**: Single edge/bane modifiers and double edge/bane tier shifts, with the modifier shown in the Action Log
- **Random table rolls**: Physical dice drive Codex random-table lookups (e.g. 1d100, 1d20), not just ability rolls
- **Custom dice display**: Physical dice results shown in chat with dice icons; dropped dice (keep highest/lowest) are dimmed in the Action Log
- **Multi-target roll support**: Works with attacks targeting multiple creatures

## Requirements

- [MCDM Codex VTT](https://github.com/VerisimLLC/draw-steel-codex)
- DiceVision account and session at [dicevision.dirtyowlbear.com](https://dicevision.dirtyowlbear.com)

## Installation

Install through Codex's built-in mod manager:

1. Open Codex and go to the mod manager
2. Search for "DiceVision"
3. Enable the mod

Replace mode uses RollDialog callbacks built into Codex (`OnBeforeRoll` for ability rolls, `OnBeforeReroll` for rerolls, and `OnBeforeTableRoll` for random tables). No additional setup is needed beyond installing the mod — DiceVision registers its callbacks automatically. If a Codex update removes or renames a hook, that roll type silently falls back to virtual dice; run `/dv status` to see which hooks are present and `/dv refresh` to re-probe after an update.

## Quick Start

1. Start a DiceVision session at [dicevision.dirtyowlbear.com](https://dicevision.dirtyowlbear.com)
2. Connect to your session, either:
   - From the panel: click the blue **Connect...** button and enter your session code, or
   - From chat: `/dv connect <session-code>`
3. The panel toggle turns green (**Active**) — replace mode is now on
4. When you make a roll in Codex, it will wait for your physical dice
5. Roll your dice in view of the camera
6. DiceVision reads the result and sends it to Codex

To temporarily pause without disconnecting, click the toggle button (**Active** -> **Paused**). Click again to resume.

## Panel UI

The dockable DiceVision panel gives you everything the chat commands do:

- **Dice button**: Your roll status at a glance (Disconnected / Paused / waiting / result).
- **State toggle button**:
  - While disconnected, it's a blue **Connect...** call-to-action that opens the connect popup.
  - Once connected, it becomes the pause/resume toggle — green **Active** (replace mode) or amber **Paused** (off).
- **Settings gear** (top-right): Opens a popup with:
  - **Connection / diagnostics**: live status (connected / mode / session / missing hooks) plus **Disconnect**, **Refresh** hooks, and **Test** connection.
  - **Dice rules**: clamp on/off, keep-selection (Auto / Highest / Lowest + count), and an add/remove value-mapping editor (e.g. `d10: 0 -> 10`).

Panel settings are in-memory only and reset on reload, matching the chat-command behavior.

## Commands

| Command | Description |
|---------|-------------|
| `/dv connect <code>` | Connect to DiceVision session |
| `/dv disconnect` | Disconnect from session |
| `/dv status` | Show connection status (includes Codex hook state) |
| `/dv mode <off\|replace>` | Set operation mode |
| `/dv refresh` | Re-probe Codex hooks (use after a Codex update) |
| `/dv test` | Test API connection |
| `/dv rules` | Configure dice processing rules |

Running `/dv` with no subcommand (or an unrecognized one) prints the command list.

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

All of these are also available in the settings popup.

### Default Rules

- **d10 value mapping**: 0 -> 10 (standard d10 behavior where 0 reads as 10)

Two physical d10s rolling "00" + "0" are detected as a percentile pair and map to 100.

### Value Clamping

When enabled with `/dv rules clamp on`, any dice value outside the 0-10 range is clamped to 1. This helps handle misread dice where DiceVision might return an invalid value like 14 or -3.

## Operating Modes

| Mode | Behavior |
|------|----------|
| `off` | DiceVision disabled, virtual dice used normally |
| `replace` | Physical dice replace virtual dice entirely |

## Draw Steel Edge/Bane Rules

DiceVision fully supports Draw Steel's edge and bane system. Edges and banes cancel 1-for-1; effects apply based on the net:

| Situation | Effect |
|-----------|--------|
| Net +1 edge | +2 to roll |
| Net -1 bane | -2 to roll |
| Net +2 or more edges | +1 tier shift (no modifier) |
| Net -2 or more banes | -1 tier shift (no modifier) |
| Equal edges and banes | Cancel out (no effect) |

The edge/bane modifier is combined with the base ability modifier in the Action Log display (e.g. `+2` base + `+2` edge = `+4` shown).

**Tier Thresholds**: Tier 1 (1-11), Tier 2 (12-16), Tier 3 (17+)

## How It Works

1. You click "Roll Dice" (or trigger a random table) in Codex
2. Codex calls the matching RollDialog hook — DiceVision intercepts the roll (in replace mode)
3. Codex displays "Waiting for physical dice..."
4. You roll your physical dice
5. DiceVision's API sends the dice values to the mod
6. The mod calculates the total with modifiers and edge/bane effects (table rolls skip edge/bane math and pass the raw total)
7. Results appear in chat with dice icons showing each die
8. Codex processes the roll with correct tier/damage

## Known Limitations

- Requires an active DiceVision API connection
- Only works with Draw Steel roll dialogs and random tables
- On timeout or error, ability rolls fall back to virtual dice, but table rolls are abandoned with a chat notice (re-trigger to retry) — Codex's table-roll callback requires a final integer, so no synchronous fallback is possible
- Panel/rules settings are in-memory and reset on reload

## Technical Documentation

For implementation details and developer documentation, see [HANDOFF.md](HANDOFF.md).

## License

Apache 2.0
