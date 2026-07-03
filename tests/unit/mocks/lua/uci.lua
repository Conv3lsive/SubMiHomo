-- Minimal uci mock for unit-testing the rpcd validate() gate.
local M = {}

function M.cursor()
    return {
        load = function() return true end,
        get = function() return nil end,
        set = function() return true end,
        commit = function() return true end,
        delete = function() return true end,
        add_list = function() return true end,
        foreach = function() return true end,
    }
end

return M
