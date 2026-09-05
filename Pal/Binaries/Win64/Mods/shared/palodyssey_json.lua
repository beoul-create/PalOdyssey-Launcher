-- Small dependency-free JSON codec for UE4SS Lua 5.4.  The Palworld UE4SS
-- build does not expose JSON/json globals, so gameplay mods must not rely on
-- them being present.
local Json = {}

local function decode_error(source, pos, message)
    error(string.format("JSON decode error at byte %d: %s", pos, message), 0)
end

local function utf8_char(codepoint)
    if codepoint <= 0x7F then
        return string.char(codepoint)
    elseif codepoint <= 0x7FF then
        return string.char(0xC0 + math.floor(codepoint / 0x40), 0x80 + codepoint % 0x40)
    elseif codepoint <= 0xFFFF then
        return string.char(0xE0 + math.floor(codepoint / 0x1000),
            0x80 + math.floor(codepoint / 0x40) % 0x40, 0x80 + codepoint % 0x40)
    end
    return string.char(0xF0 + math.floor(codepoint / 0x40000),
        0x80 + math.floor(codepoint / 0x1000) % 0x40,
        0x80 + math.floor(codepoint / 0x40) % 0x40, 0x80 + codepoint % 0x40)
end

function Json.decode(source)
    if type(source) ~= "string" then error("JSON input must be a string", 0) end
    local pos, length = 1, #source

    local function skip_space()
        while pos <= length and source:sub(pos, pos):match("%s") do pos = pos + 1 end
    end

    local parse_value
    local function parse_string()
        pos = pos + 1
        local parts, start = {}, pos
        while pos <= length do
            local ch = source:sub(pos, pos)
            if ch == '"' then
                parts[#parts + 1] = source:sub(start, pos - 1)
                pos = pos + 1
                return table.concat(parts)
            elseif ch == "\\" then
                parts[#parts + 1] = source:sub(start, pos - 1)
                local esc = source:sub(pos + 1, pos + 1)
                local replacements = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
                    b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
                if replacements[esc] then
                    parts[#parts + 1] = replacements[esc]
                    pos = pos + 2
                elseif esc == "u" then
                    local hex = source:sub(pos + 2, pos + 5)
                    local codepoint = tonumber(hex, 16)
                    if not codepoint or #hex ~= 4 then decode_error(source, pos, "invalid unicode escape") end
                    pos = pos + 6
                    if codepoint >= 0xD800 and codepoint <= 0xDBFF and source:sub(pos, pos + 1) == "\\u" then
                        local low = tonumber(source:sub(pos + 2, pos + 5), 16)
                        if low and low >= 0xDC00 and low <= 0xDFFF then
                            codepoint = 0x10000 + (codepoint - 0xD800) * 0x400 + low - 0xDC00
                            pos = pos + 6
                        end
                    end
                    parts[#parts + 1] = utf8_char(codepoint)
                else
                    decode_error(source, pos, "invalid escape")
                end
                start = pos
            elseif ch:byte() < 0x20 then
                decode_error(source, pos, "control character in string")
            else
                pos = pos + 1
            end
        end
        decode_error(source, pos, "unterminated string")
    end

    local function parse_array()
        pos = pos + 1
        local result = {}
        skip_space()
        if source:sub(pos, pos) == "]" then pos = pos + 1; return result end
        while true do
            result[#result + 1] = parse_value()
            skip_space()
            local ch = source:sub(pos, pos)
            if ch == "]" then pos = pos + 1; return result end
            if ch ~= "," then decode_error(source, pos, "expected ',' or ']'") end
            pos = pos + 1
        end
    end

    local function parse_object()
        pos = pos + 1
        local result = {}
        skip_space()
        if source:sub(pos, pos) == "}" then pos = pos + 1; return result end
        while true do
            skip_space()
            if source:sub(pos, pos) ~= '"' then decode_error(source, pos, "expected object key") end
            local key = parse_string()
            skip_space()
            if source:sub(pos, pos) ~= ":" then decode_error(source, pos, "expected ':'") end
            pos = pos + 1
            result[key] = parse_value()
            skip_space()
            local ch = source:sub(pos, pos)
            if ch == "}" then pos = pos + 1; return result end
            if ch ~= "," then decode_error(source, pos, "expected ',' or '}'") end
            pos = pos + 1
        end
    end

    function parse_value()
        skip_space()
        local ch = source:sub(pos, pos)
        if ch == '"' then return parse_string() end
        if ch == "{" then return parse_object() end
        if ch == "[" then return parse_array() end
        if source:sub(pos, pos + 3) == "true" then pos = pos + 4; return true end
        if source:sub(pos, pos + 4) == "false" then pos = pos + 5; return false end
        if source:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil end
        local token = source:sub(pos):match("^-?%d+%.?%d*[eE]?[+-]?%d*")
        if token and token ~= "" then
            local number = tonumber(token)
            if number then pos = pos + #token; return number end
        end
        decode_error(source, pos, "unexpected token")
    end

    local result = parse_value()
    skip_space()
    if pos <= length then decode_error(source, pos, "trailing content") end
    return result
end

local function escape_string(value)
    return '"' .. value:gsub("[\\\"%z\1-\31]", function(ch)
        local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b",
            ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
        return map[ch] or string.format("\\u%04x", ch:byte())
    end) .. '"'
end

function Json.encode(value, seen)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" or kind == "number" then return tostring(value) end
    if kind == "string" then return escape_string(value) end
    if kind ~= "table" then error("cannot encode JSON type " .. kind, 0) end
    seen = seen or {}
    if seen[value] then error("cannot encode cyclic table", 0) end
    seen[value] = true
    local isArray, max = true, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then isArray = false; break end
        if key > max then max = key end
    end
    local parts = {}
    if isArray then
        for i = 1, max do parts[#parts + 1] = Json.encode(value[i], seen) end
        seen[value] = nil
        return "[" .. table.concat(parts, ",") .. "]"
    end
    for key, item in pairs(value) do
        parts[#parts + 1] = escape_string(tostring(key)) .. ":" .. Json.encode(item, seen)
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

return Json
