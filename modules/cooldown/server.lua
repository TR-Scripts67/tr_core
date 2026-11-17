-- A player id is keyed by their character, so logging out or reconnecting doesn't reset it.
-- Seconds are wall-clock (os.time); persist keeps them across restarts in the resource's KVP.

---@class TRCooldownModule
local cooldown = {}

local SWEEP_EVERY = 256 -- starts between sweeps of the cooldowns that are over

local defined = {} ---@type table<string, true>

---@class TRCooldown
---@field name string
---@field seconds number
---@field persist boolean
local Cooldown = {}
Cooldown.__index = Cooldown

---@return string? key nil for a player id that isn't connected
local function ownerKey(owner)
    if owner == nil then return '*' end
    if type(owner) == 'string' then return 's:' .. owner end
    local src = type(owner) == 'number' and math.tointeger(owner)
    if not src then error('a cooldown owner is a player id, a string or nil', 3) end

    local identifier = TR.player.getIdentifier(src)
    if identifier then return 'c:' .. identifier end

    -- No character loaded yet (character menu): their license.
    local license = GetPlayerIdentifierByType(tostring(src), 'license')
    return license and 'l:' .. license or nil
end

local function kvpKey(cd, key) return ('tr_cd:%s:%s'):format(cd.name, key) end

local function forget(cd, key)
    cd.ends[key] = nil
    if cd.persist then DeleteResourceKvp(kvpKey(cd, key)) end
end

local function remaining(cd, key, now)
    local ends = cd.ends[key]
    if not ends then return 0 end
    if ends > now then return ends - now end
    forget(cd, key)
    return 0
end

local function set(cd, key, seconds)
    -- 0, a negative time or NaN would quietly mean no cooldown at all.
    if type(seconds) ~= 'number' or not (seconds > 0) or seconds == math.huge then
        error('cooldown seconds must be a number above 0', 3)
    end
    local now = os.time()
    local ends = now + math.ceil(seconds)
    cd.ends[key] = ends
    if cd.persist then SetResourceKvp(kvpKey(cd, key), tostring(ends)) end

    cd.starts = cd.starts + 1
    if cd.starts % SWEEP_EVERY == 0 then
        for k in pairs(cd.ends) do remaining(cd, k, now) end
    end
end

---@param owner? integer|string
---@return integer
function Cooldown:left(owner)
    local key = ownerKey(owner)
    return key and remaining(self, key, os.time()) or 0
end

---false and the seconds to go if it's running; false alone for a player id that isn't connected.
---@param owner? integer|string
---@param seconds? number this time instead of the cooldown's own
---@return boolean ok
---@return integer? left
function Cooldown:take(owner, seconds)
    local key = ownerKey(owner)
    if not key then return false end

    local left = remaining(self, key, os.time())
    if left > 0 then return false, left end

    set(self, key, seconds or self.seconds)
    return true
end

---Restarts it if it's running.
---@param owner? integer|string
---@param seconds? number this time instead of the cooldown's own
---@return boolean ok false for a player id that isn't connected
function Cooldown:start(owner, seconds)
    local key = ownerKey(owner)
    if not key then return false end
    set(self, key, seconds or self.seconds)
    return true
end

---@param owner? integer|string
function Cooldown:clear(owner)
    local key = ownerKey(owner)
    if key and self.ends[key] then forget(self, key) end
end

local function restore(cd)
    local prefix = kvpKey(cd, '')
    local now, keys = os.time(), {}

    local handle = StartFindKvp(prefix)
    if handle == -1 then return end
    repeat
        local kvp = FindKvp(handle)
        if kvp then keys[#keys + 1] = kvp end
    until not kvp
    EndFindKvp(handle)

    for _, kvp in ipairs(keys) do
        local ends = math.tointeger(tonumber(GetResourceKvpString(kvp)))
        if ends and ends > now then
            cd.ends[kvp:sub(#prefix + 1)] = ends
        else
            DeleteResourceKvp(kvp)
        end
    end
end

---One per name in a resource.
---@param name string letters, digits and _ - . (it is part of the KVP key)
---@param options { seconds: number, persist?: boolean }
---@return TRCooldown
function cooldown.new(name, options)
    assert(type(name) == 'string' and #name <= 64 and name:match('^[%w_%-%.]+$'), 'cooldown name: up to 64 letters, digits, _ - .')
    assert(not defined[name], ('cooldown "%s" already exists'):format(name))
    assert(type(options) == 'table' and type(options.seconds) == 'number' and options.seconds > 0 and options.seconds < math.huge, 'cooldown needs seconds > 0')

    defined[name] = true
    local self = setmetatable({ name = name, seconds = options.seconds, persist = options.persist == true, ends = {}, starts = 0 }, Cooldown)
    if self.persist then restore(self) end
    return self
end

return cooldown
