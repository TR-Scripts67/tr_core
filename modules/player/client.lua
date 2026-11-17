---@type TRPlayerShared
local shared = ...
local bridge = TR.bridge('framework')

---@class TRPlayerClient : TRPlayerShared
local player = setmetatable({}, { __index = shared })

---Only for tr_core internals; use the functions below.
player.bridge = bridge

---@return boolean
function player.isLoaded() return bridge.isLoaded() end

---@return string?
function player.getIdentifier() return bridge.getIdentifier() end

---Whether this player is down, dead or in last stand: as their death script has it (its state bag, ESX's `dead`, QBCore's
---and Qbox's `isdead` / `inlaststand` metadata), or dead to the game.
---@return boolean
function player.isDowned()
    return shared.downedState(LocalPlayer.state) or bridge.isDowned() or IsPedFatallyInjured(PlayerPedId())
end

-- The job, kept between tr_core's job events (they reach every resource): asking the framework copies the whole player
-- data across resources (0.17 ms on ESX), and scripts ask every tick. false: asked, no job.
local job ---@type TRJob|false|nil
AddEventHandler('tr:jobUpdated', function(newJob) job = newJob or false end)
AddEventHandler('tr:playerLoaded', function() job = nil end)
AddEventHandler('tr:playerUnloaded', function() job = nil end)

local function currentJob()
    if job == nil then job = bridge.getJob() or false end
    return job or nil
end

---@return TRJob?
function player.getJob()
    local current = currentJob()
    return current and TR.utils.copy(current) or nil
end

---@param filter TRJobFilter
---@param requireDuty? boolean
---@return boolean
function player.hasJob(filter, requireDuty)
    return shared.matchJob(currentJob(), filter, requireDuty)
end

---@return TRGang?
function player.getGang() return bridge.getGang() end

---@param filter TRJobFilter
---@return boolean
function player.hasGang(filter)
    return shared.matchJob(bridge.getGang(), filter)
end

---Display only. Never trust client-side money for anything that matters.
---@param account TRAccount
---@return integer
function player.getMoney(account)
    assert(shared.accounts[account], ('invalid account "%s"'):format(account))
    return bridge.getMoney(account) or 0
end

---Also runs right away if the character is already loaded.
---@param cb fun()
function player.onLoaded(cb)
    AddEventHandler('tr:playerLoaded', cb)
    if bridge.isLoaded() then CreateThread(cb) end
end

---@param cb fun()
function player.onUnloaded(cb)
    AddEventHandler('tr:playerUnloaded', cb)
end

---@param cb fun(job: TRJob, lastJob: TRJob?)
function player.onJobUpdated(cb)
    AddEventHandler('tr:jobUpdated', cb)
end

---Keeps track of the players whose state bag `key` is set, so a thread can sleep while nobody has it: the returned
---function says whether anyone does, and `onSet(serverId, value)` runs each time a player sets it.
---@param key string
---@param onSet? fun(serverId: integer, value: any)
---@return fun(): boolean
function player.watchState(key, onSet)
    local holders = {} ---@type table<integer, integer> server id -> GetGameTimer() when set
    AddStateBagChangeHandler(key, nil, function(bag, _, value)
        local id = tonumber(bag:match('^player:(%d+)$'))
        if not id then return end
        holders[id] = value ~= nil and GetGameTimer() or nil
        if value ~= nil and onSet then onSet(id, value) end
    end)
    for _, playerId in ipairs(GetActivePlayers()) do
        local id = GetPlayerServerId(playerId)
        if Player(id).state[key] ~= nil then holders[id] = 0 end
    end
    return function()
        local now = GetGameTimer()
        for id, at in pairs(holders) do
            -- The bag reads the new value only after its handlers ran, and a player who leaves takes theirs along unset.
            if now - at > 1000 and Player(id).state[key] == nil then holders[id] = nil end
        end
        return next(holders) ~= nil
    end
end

return player
