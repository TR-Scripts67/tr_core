---'dirty' is black_money on ESX, markedbills bags on QBCore and the black_money item on Qbox
---(server side), unless accounts.dirty in config.lua names a money type.
---@alias TRAccount 'cash' | 'bank' | 'dirty'

---@class TRJob
---@field name string
---@field label string
---@field grade integer
---@field gradeName string
---@field gradeLabel string
---@field salary integer
---@field onDuty boolean
---@field isBoss boolean

---@class TRJobGrade
---@field grade integer
---@field name string
---@field label string
---@field salary integer
---@field isBoss boolean

---@class TRJobInfo
---@field name string
---@field label string
---@field grades TRJobGrade[] lowest grade first

---@class TREmployee
---@field identifier string
---@field name? string character name (nil when the framework keeps none)
---@field grade integer
---@field source? integer when online
---@field onDuty? boolean when online

---@class TRCharacter
---@field identifier string
---@field firstname string '' when the character has none yet
---@field lastname string
---@field birthDate? string 'YYYY-MM-DD', or as the framework stored it when that doesn't read as a date
---@field sex? 'male' | 'female'
---@field phone? string

---QBCore and Qbox only; getGang returns nil on ESX.
---@class TRGang
---@field name string
---@field label string
---@field grade integer
---@field gradeName string
---@field isBoss boolean

---'police', { 'police', 'sheriff' } (any grade) or { police = 2, sheriff = 0 } (minimum grades).
---@alias TRJobFilter string | string[] | table<string, integer>

---@class TRPlayerShared
local player = {}

player.accounts = { cash = true, bank = true, dirty = true }

---@param job TRJob | TRGang | nil
---@param filter TRJobFilter
---@param requireDuty? boolean ignored for gangs
---@return boolean
function player.matchJob(job, filter, requireDuty)
    if not job then return false end
    if requireDuty and not job.onDuty then return false end

    if type(filter) == 'string' then return job.name == filter end

    if filter[1] then
        for i = 1, #filter do
            if filter[i] == job.name then return true end
        end
        return false
    end

    local minGrade = filter[job.name]
    return minGrade ~= nil and job.grade >= minGrade
end

---Whether a player's state bag says they are down: `isDead` (esx_death, esx_ambulancejob, qbx_medical, wasabi_ambulance:
---true, or a death state above 0) or `dead` (ars_ambulancejob, wasabi_ambulance v1: true, 'dead' or 'laststand').
---@param state table
---@return boolean
function player.downedState(state)
    local dead = state.isDead
    if dead == true or (type(dead) == 'number' and dead > 0) then return true end
    return state.dead ~= nil and state.dead ~= false
end

return player
