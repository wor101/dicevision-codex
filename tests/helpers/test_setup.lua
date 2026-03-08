--[[
    Test setup helper for DiceRollLogic specs.
    Loads DiceRollLogic.lua into the global scope and stubs globals
    that the non-pure functions depend on (DiceVision, dmhub, print).
]]

-- Stub DiceVision global (used by getEffectiveRules and applyDiceRules)
DiceVision = {
    rules = {
        valueMappings = {},
        diceSelection = nil,
        clampOutOfRange = false,
    },
}

-- Stub dmhub global (used by detectDiceSelection)
dmhub = {
    ParseRoll = function(rollStr, creature)
        return nil
    end,
}

-- Capture print calls for testing output without polluting test results
_G._printLog = {}
local _originalPrint = print -- luacheck: ignore (kept for potential future restore)
_G.print = function(...)
    local args = {...}
    local parts = {}
    for i, v in ipairs(args) do
        parts[i] = tostring(v)
    end
    table.insert(_G._printLog, table.concat(parts, "\t"))
end

-- Restore print for busted output (busted needs real print)
-- We override only at module load time, then busted's own IO takes over
local function resetPrintLog()
    _G._printLog = {}
end

-- Load DiceRollLogic into global scope
local projectRoot = os.getenv("PWD") or "."
dofile(projectRoot .. "/Codex/mods/DiceVision_5554/DiceRollLogic.lua")

-- Export helpers for use in specs
_G.resetPrintLog = resetPrintLog
_G.resetStubs = function()
    resetPrintLog()
    DiceVision.rules = {
        valueMappings = {},
        diceSelection = nil,
        clampOutOfRange = false,
    }
    dmhub.ParseRoll = function(rollStr, creature)
        return nil
    end
end

-- ============================================================================
-- DiceVision.lua Test Helpers
-- ============================================================================

-- Loads the full DiceVision.lua module, setting up all required global stubs.
-- Call once per spec file (in setup()), not per test.
_G.loadDiceVision = function()
    -- Chat capture log
    _G._chatLog = {}
    _G._dmhubRollLog = {}

    -- dmhub stubs (load-time + runtime)
    dmhub.GetModLoading = function() return {} end
    dmhub.Roll = function(rollArgs) table.insert(_G._dmhubRollLog, rollArgs) end
    dmhub.Time = function() return 0 end
    dmhub.GetDiceStyling = function() return {} end
    dmhub.GetSettingValue = function() return "" end
    dmhub.GetCharacterById = function() return nil end
    dmhub.LookupTokenId = function() return nil end

    -- RegisterGameType stub: returns a table with .new constructor
    _G.RegisterGameType = function(name)
        local gameType = {}
        gameType.new = function(fields)
            local instance = setmetatable({}, {__index = gameType})
            if fields then
                for k, v in pairs(fields) do
                    instance[k] = v
                end
            end
            instance.try_get = function(self, key)
                return self[key]
            end
            return instance
        end
        return gameType
    end

    -- Command handler table
    _G.Commands = {}

    -- RollDialog stub (guarded nil check at line 1049)
    _G.RollDialog = { OnBeforeRoll = false }

    -- Chat stubs: capture messages for assertions
    _G.chat = {
        Send = function(msg) table.insert(_G._chatLog, {type = "send", message = msg}) end,
        SendCustom = function(msg) table.insert(_G._chatLog, {type = "custom", message = msg}) end,
    }

    -- Network stub (not tested, must exist)
    _G.net = {
        Get = function() end,
    }

    -- GUI stubs (not tested, must exist for function definitions)
    _G.gui = setmetatable({}, {
        __index = function(t, k)
            return function(props)
                local panel = props or {}
                panel.AddChild = function(self, child) end
                return panel
            end
        end,
    })

    -- printf stub (used in longPollForRolls error path)
    _G.printf = function(fmt, ...)
        _G.print(string.format(fmt, ...))
    end

    -- GameSystem not available in test env
    _G.GameSystem = nil

    -- Load DiceVision.lua
    dofile(projectRoot .. "/Codex/mods/DiceVision_5554/DiceVision.lua")
end

-- Resets DiceVision state between tests. Call in before_each().
_G.resetDiceVisionState = function()
    -- Reset connection & polling state
    DiceVision.sessionCode = nil
    DiceVision.connected = false
    DiceVision.mode = "off"
    DiceVision.isPolling = false
    DiceVision.lastPollTime = 0

    -- Reset pending roll state
    DiceVision.pendingRoll = nil
    DiceVision.waitingForRoll = false
    DiceVision.rollStartTime = 0
    DiceVision.currentRequestId = nil

    -- Reset panel state
    DiceVision.panelWaitingForRoll = false
    DiceVision.panelPollStartTime = 0
    DiceVision.panelRequestId = nil
    DiceVision.panelTokenId = nil

    -- Reset rules to defaults (d10: 0->10)
    DiceVision.rules = {
        valueMappings = {
            ["d10"] = {[0] = 10},
        },
        diceSelection = nil,
        clampOutOfRange = false,
    }

    -- Reset RollDialog
    RollDialog.OnBeforeRoll = false

    -- Reset dmhub runtime stubs
    dmhub.Roll = function(rollArgs) table.insert(_G._dmhubRollLog, rollArgs) end
    dmhub.Time = function() return 0 end

    -- Clear capture logs
    _G._chatLog = {}
    _G._dmhubRollLog = {}
    _G._printLog = {}
end
