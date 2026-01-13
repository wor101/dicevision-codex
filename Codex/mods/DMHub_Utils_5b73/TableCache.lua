local mod = dmhub.GetModLoading()

local g_tableCache = {}
local g_empty = {}

function GetTableCached(tableName)
    local result = g_tableCache[tableName]
    if not result then
        result = dmhub.GetTable(tableName)
        g_tableCache[tableName] = result
    end

    return result or g_empty
end

dmhub.RegisterEventHandler("refreshTables", function(keys)
    g_tableCache = {}
end)