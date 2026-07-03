-- Minimal luci.jsonc mock for unit-testing the rpcd validate() gate.
-- Pure Lua, compatible with Lua 5.1+ (no goto, no //, no bit32, no math.type).
local M = {}

local function parse(s)
    local pos = 1
    local n = #s
    local function skip_ws()
        while pos <= n do
            local c = s:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then pos = pos + 1
            else break end
        end
    end
    local function parse_string()
        pos = pos + 1
        local out, i = {}, 1
        while pos <= n do
            local c = s:sub(pos, pos)
            if c == '"' then pos = pos + 1; return table.concat(out) end
            if c == "\\" then
                pos = pos + 1; local e = s:sub(pos, pos)
                local map = {['"']='"', ["\\"]='\\', ["/"]='/', b='\b', f='\f', n='\n', r='\r', t='\t'}
                out[i] = map[e] or e; i = i + 1
            else
                out[i] = c; i = i + 1
            end
            pos = pos + 1
        end
        error("unterminated string")
    end
    local function parse_number()
        local st = pos
        while pos <= n do
            local c = s:sub(pos, pos)
            if c:match("[%-%+eE%.0-9]") then pos = pos + 1 else break end
        end
        return tonumber(s:sub(st, pos - 1))
    end
    local parse_val
    local function parse_array()
        pos = pos + 1
        local arr, idx = {}, 1
        skip_ws()
        if s:sub(pos, pos) == "]" then pos = pos + 1; return arr end
        while true do
            arr[idx] = parse_val(); idx = idx + 1
            skip_ws()
            local c = s:sub(pos, pos)
            pos = pos + 1
            if c == "]" then return arr end
            if c ~= "," then error("expected , or ] in array") end
            skip_ws()
        end
    end
    local function parse_object()
        pos = pos + 1
        local obj = {}
        skip_ws()
        if s:sub(pos, pos) == "}" then pos = pos + 1; return obj end
        while true do
            skip_ws()
            local key = parse_string()
            skip_ws()
            if s:sub(pos, pos) ~= ":" then error("expected : in object") end
            pos = pos + 1
            obj[key] = parse_val()
            skip_ws()
            local c = s:sub(pos, pos)
            pos = pos + 1
            if c == "}" then return obj end
            if c ~= "," then error("expected , or } in object") end
            skip_ws()
        end
    end
    function parse_val()
        skip_ws()
        local c = s:sub(pos, pos)
        if c == '"' then return parse_string()
        elseif c == "{" then return parse_object()
        elseif c == "[" then return parse_array()
        elseif c == "t" then pos = pos + 4; return true
        elseif c == "f" then pos = pos + 5; return false
        elseif c == "n" then pos = pos + 4; return nil
        else return parse_number() end
    end
    return parse_val()
end

function M.parse(s)
    local ok, val = pcall(parse, s)
    if ok then return val else return nil end
end

local function stringify(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v)
    elseif t == "number" then return tostring(v)
    elseif t == "boolean" then return tostring(v)
    elseif v == nil then return "null"
    elseif t == "table" then
        local is_arr = true
        local maxn = 0
        for k, _ in pairs(v) do
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then is_arr = false; break end
            if k > maxn then maxn = k end
        end
        if is_arr and maxn > 0 then
            local parts = {}
            for i = 1, maxn do parts[i] = stringify(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            local i = 1
            for k, val in pairs(v) do
                parts[i] = string.format("%q:%s", tostring(k), stringify(val)); i = i + 1
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return "null"
    end
end

function M.stringify(v) return stringify(v) end

return M
