---@class TRUtils
local utils = {}

---@param value number
---@param decimals? integer
---@return number
function utils.round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    local rounded = math.floor(value * mult + 0.5) / mult
    return decimals and decimals > 0 and rounded or math.tointeger(rounded) or rounded
end

---@param value number
---@param min number
---@param max number
---@return number
function utils.clamp(value, min, max)
    return value < min and min or value > max and max or value
end

---@param value number
---@param separator? string
---@return string
function utils.formatNumber(value, separator)
    separator = separator or ','
    local sign, int, frac = tostring(value):match('^([-]?)(%d+)(%.?%d*)$')
    if not int then return tostring(value) end

    int = int:reverse():gsub('(%d%d%d)', '%1' .. separator):reverse()
    if int:sub(1, #separator) == separator then int = int:sub(#separator + 1) end

    return sign .. int .. frac
end

---@param value number
---@param symbol? string
---@param decimals? integer
---@return string
function utils.formatMoney(value, symbol, decimals)
    local amount = decimals and ('%.' .. decimals .. 'f'):format(value) or utils.round(value)
    return (symbol or '$') .. utils.formatNumber(amount)
end

---@generic T
---@param value T
---@return T
function utils.deepCopy(value)
    if type(value) ~= 'table' then return value end

    local copy = {}
    for k, v in pairs(value) do copy[k] = utils.deepCopy(v) end

    return setmetatable(copy, getmetatable(value))
end

---@generic T: table
---@param tbl T
---@return T
function utils.copy(tbl)
    local copy = {}
    for k, v in pairs(tbl) do copy[k] = v end
    return copy
end

---Into a copy of `base`; arrays are replaced, not merged.
---@param base table
---@param override? table
---@return table
function utils.merge(base, override)
    local result = utils.deepCopy(base)
    if not override then return result end

    for k, v in pairs(override) do
        if type(v) == 'table' and type(result[k]) == 'table' and not utils.isArray(v) then
            result[k] = utils.merge(result[k], v)
        else
            result[k] = utils.deepCopy(v)
        end
    end

    return result
end

---@param tbl table
---@return boolean
function utils.isArray(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count == #tbl
end

---@param list table
---@param value any
---@return boolean
function utils.contains(list, value)
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

---@param tbl table
---@return integer
function utils.count(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

---@param tbl table
---@return any[]
function utils.keys(tbl)
    local keys, n = {}, 0
    for k in pairs(tbl) do
        n = n + 1
        keys[n] = k
    end
    return keys
end

---@param str string
---@return string
function utils.trim(str)
    return (str:gsub('^%s+', ''):gsub('%s+$', ''))
end

---@param str string
---@param separator string plain-text separator
---@return string[]
function utils.split(str, separator)
    local parts, n, start = {}, 0, 1

    while true do
        local i, j = str:find(separator, start, true)
        n = n + 1

        if not i then
            parts[n] = str:sub(start)
            return parts
        end

        parts[n] = str:sub(start, i - 1)
        start = j + 1
    end
end

local alphanumeric = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'

-- No 0/O, 1/I: for ids players read and type.
utils.READABLE = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

---@param length integer
---@param charset? string
---@return string
function utils.randomString(length, charset)
    charset = charset or alphanumeric
    local out, size = {}, #charset

    for i = 1, length do
        local n = math.random(size)
        out[i] = charset:sub(n, n)
    end

    return table.concat(out)
end

---@param percent number 0..100
---@return boolean
function utils.chance(percent)
    return math.random() * 100 < percent
end

---@generic T
---@param list T[]
---@return T?
function utils.pick(list)
    if #list == 0 then return nil end
    return list[math.random(#list)]
end

---A whole number when both ends are, else a decimal.
---@param range { min: number, max: number } | number[]
---@return number
function utils.randomRange(range)
    local min, max = range.min or range[1], range.max or range[2]
    if math.type(min) == 'integer' and math.type(max) == 'integer' then return math.random(min, max) end
    return min + math.random() * (max - min)
end

---In place.
---@generic T
---@param list T[]
---@return T[]
function utils.shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

---@param text string?
---@return table?
function utils.decode(text)
    if type(text) ~= 'string' or text == '' then return nil end
    local ok, data = pcall(json.decode, text)
    return ok and type(data) == 'table' and data or nil
end

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local toPair, fromPair = {}, {} -- 12 bits <-> two base64 characters, so each 3 bytes are two lookups
for bits = 0, 4095 do
    local pair = B64:sub((bits >> 6) + 1, (bits >> 6) + 1) .. B64:sub((bits & 63) + 1, (bits & 63) + 1)
    toPair[bits], fromPair[pair] = pair, bits
end

---Bytes (a file) as base64 text, e.g. for a NUI page.
---@param bytes string
---@return string
function utils.toBase64(bytes)
    local tail = #bytes % 3
    local text = bytes:sub(1, #bytes - tail):gsub('...', function(three)
        local bits = string.unpack('>I3', three)
        return toPair[bits >> 12] .. toPair[bits & 4095]
    end)
    if tail == 0 then return text end
    local bits = string.unpack('>I3', bytes:sub(-tail) .. ('\0'):rep(3 - tail))
    return text .. (toPair[bits >> 12] .. toPair[bits & 4095]):sub(1, tail + 1) .. ('='):rep(3 - tail)
end

---Base64 text back to its bytes; padding and anything not base64 are skipped.
---@param text string
---@return string
function utils.fromBase64(text)
    text = text:gsub('[^%w%+/]', '')
    local tail = #text % 4
    local bytes = text:sub(1, #text - tail):gsub('....', function(four)
        return string.pack('>I3', fromPair[four:sub(1, 2)] << 12 | fromPair[four:sub(3, 4)])
    end)
    if tail < 2 then return bytes end
    local four = text:sub(-tail) .. ('A'):rep(4 - tail)
    return bytes .. string.pack('>I3', fromPair[four:sub(1, 2)] << 12 | fromPair[four:sub(3, 4)]):sub(1, tail - 1)
end

---@return string
function utils.uuid()
    return (('xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'):gsub('[xy]', function(c)
        local v = c == 'x' and math.random(0, 15) or math.random(8, 11)
        return ('%x'):format(v)
    end))
end

---@param value vector3 | vector4 | { x: number, y: number, z: number } | number[]
---@return vector3
function utils.toVector3(value)
    if type(value) == 'vector3' then return value end
    return vector3(value.x or value[1], value.y or value[2], value.z or value[3])
end

---Yields. Returns nil on timeout.
---@generic T
---@param check fun(): T?
---@param timeout? integer milliseconds, default 5000; false to wait forever
---@param interval? integer milliseconds between checks, default 0
---@return T?
function utils.waitFor(check, timeout, interval)
    local deadline = timeout ~= false and GetGameTimer() + (timeout or 5000)

    while true do
        local value = check()
        if value then return value end
        if deadline and GetGameTimer() > deadline then return nil end
        Wait(interval or 0)
    end
end

---A thread that runs only while it has work, so it costs nothing in between. Each call to the returned `wake` starts it
---if it isn't running; from the next frame it runs `step`, which returns the milliseconds until its next run (0: every
---frame), or nil to stop until the next `wake`.
---@param step fun(): integer?
---@return fun() wake
function utils.loop(step)
    local running = false
    return function()
        if running then return end
        running = true
        CreateThread(function()
            local ms = 0
            repeat
                Wait(ms)
                ms = step()
            until not ms
            running = false
        end)
    end
end

return utils
