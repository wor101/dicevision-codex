std = "lua51"
max_line_length = false

-- Ignore vendored dependencies installed by luarocks
exclude_files = {
    ".luarocks/**",
}

-- Suppress unused argument warnings (common in callback-heavy Codex engine code)
unused_args = false
-- Allow _prefixed variables as intentionally unused (e.g. local _originalPrint = print)
unused_secondaries = false

-- Codex engine globals used by source files
-- RollDialog is writable because the mod sets RollDialog.OnBeforeRoll
globals = {
    "DiceVision",
    "DiceRollLogic",
    "DiceVisionRollMessage",
    "CreateDiceVisionPanel",
    "Commands",
    "RollDialog",
}

read_globals = {
    "dmhub",
    "RegisterGameType",
    "DockablePanel",
    "GameSystem",
    "chat",
    "net",
    "gui",
    "printf",
}

-- Test file overrides
files["tests/**/*.lua"] = {
    std = "+busted",
    globals = {
        "DiceVision",
        "DiceRollLogic",
        "DiceVisionRollMessage",
        "dmhub",
        "RollDialog",
        "Commands",
        "RegisterGameType",
        "chat",
        "net",
        "gui",
        "printf",
        "GameSystem",
        "resetStubs",
        "resetPrintLog",
        "loadDiceVision",
        "resetDiceVisionState",
    },
}
