---@type TRPlayerShared
local shared = ...
local bridge = TR.bridge('framework')

---@class TRPlayer : TRPlayerShared
local player = setmetatable({}, { __index = shared })

---Only for tr_core internals; use the functions below.
player.bridge = bridge

local function isValidAmount(amount)
    return math.type(amount) == 'integer' and amount > 0
end

---An account set for 'dirty' in config.lua wins over the framework's item.
---@return { name: string, worth?: string }?
local function dirtyItem(account)
    if account ~= 'dirty' or not bridge.dirtyItem then return end
    local set = type(TR.config.accounts) == 'table' and TR.config.accounts.dirty
    if type(set) == 'string' and set ~= '' and set ~= 'auto' then return end
    return bridge.dirtyItem
end

local function bagWorth(dirty, slot)
    return math.floor(tonumber(slot.metadata[dirty.worth]) or 0)
end

local function countItemMoney(src, dirty)
    if not dirty.worth then return TR.inventory.getCount(src, dirty.name) end

    local total = 0
    for _, slot in ipairs(TR.inventory.getSlots(src, dirty.name)) do
        total = total + slot.count * bagWorth(dirty, slot)
    end
    return total
end

local function addItemMoney(src, dirty, amount)
    if not dirty.worth then return TR.inventory.addItem(src, dirty.name, amount) == true end
    return TR.inventory.addItem(src, dirty.name, 1, { [dirty.worth] = amount }) == true
end

-- Bags go whole, so what is paid over comes back as one bag of the change.
local function removeItemMoney(src, dirty, amount)
    if not dirty.worth then return TR.inventory.removeItem(src, dirty.name, amount) end

    local taken, paid = {}, 0
    for _, slot in ipairs(TR.inventory.getSlots(src, dirty.name)) do
        if paid >= amount then break end
        local worth = bagWorth(dirty, slot)
        if worth > 0 then
            local bags = math.min(slot.count, (amount - paid + worth - 1) // worth)
            if not TR.inventory.removeItem(src, dirty.name, bags, nil, slot.slot) then
                for _, back in ipairs(taken) do TR.inventory.addItem(src, dirty.name, back.bags, back.metadata) end
                return false
            end
            taken[#taken + 1] = { bags = bags, metadata = slot.metadata }
            paid = paid + bags * worth
        end
    end

    if paid > amount then addItemMoney(src, dirty, paid - amount) end
    return true
end

---@param src integer
---@return boolean
function player.isLoaded(src) return bridge.isLoaded(src) end

---@param src integer
---@return string? identifier persistent character identifier
function player.getIdentifier(src) return bridge.getIdentifier(src) end

---@param src integer
---@return string? name character name
function player.getName(src) return bridge.getName(src) end

---@param src integer
---@return string? birthDate the character's date of birth, as the framework keeps it ('1990-04-12', '12/04/1990')
function player.getBirthDate(src) return bridge.getBirthDate(src) end

---@param src integer
---@return TRJob?
function player.getJob(src) return bridge.getJob(src) end

---@param src integer
---@param filter TRJobFilter
---@param requireDuty? boolean
---@return boolean
function player.hasJob(src, filter, requireDuty)
    return shared.matchJob(bridge.getJob(src), filter, requireDuty)
end

---@return table<string, TRJobInfo> jobs every job the framework has, by name
function player.getJobs() return bridge.getJobs() end

---@param src integer
---@param onDuty boolean
---@return boolean set false when the player isn't loaded, or on an older ESX that has no duty
function player.setDuty(src, onDuty) return bridge.setDuty(src, onDuty == true) end

---Tells the framework's own scripts a player is cuffed or free: QBCore's and Qbox's `ishandcuffed` metadata, which
---their inventories, phones and radial menus read.
---@param src integer
---@param cuffed boolean
---@return boolean set false when the player isn't loaded, or on ESX, which has no such flag
function player.setCuffed(src, cuffed) return bridge.setCuffed(src, cuffed == true) end

local DEAD_HEALTH = 100 -- GTA's fatally injured threshold: a ped at or under it is dead

---Whether a player is down, dead or in last stand: as their death script has it (its state bag, or QBCore's and Qbox's
---`isdead` / `inlaststand` metadata), or dead to the game (ESX without one).
---@param src integer
---@return boolean
function player.isDowned(src)
    if shared.downedState(Player(src).state) or bridge.isDowned(src) then return true end
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetEntityHealth(ped) <= DEAD_HEALTH
end

local function hasGrade(job, grade)
    if math.type(grade) ~= 'integer' then return false end
    if job == 'unemployed' then return grade == 0 end

    local info = bridge.getJobs()[job]
    for _, known in ipairs(info and info.grades or {}) do
        if known.grade == grade then return true end
    end
    return false
end

---Hires, promotes or demotes a player who is online. Someone who stays in the same job keeps their duty.
---@param src integer
---@param job string
---@param grade integer
---@return boolean set false when the player isn't loaded or the job has no such grade
function player.setJob(src, job, grade)
    if not hasGrade(job, grade) then
        TR.log.error('setJob: job %s has no grade %s', job, grade)
        return false
    end

    local before = bridge.getJob(src)
    if not before or not bridge.setJob(src, job, grade) then return false end

    -- Frameworks put duty back to the job's default on every job change, a promotion too.
    local after = bridge.getJob(src)
    if before.name == job and after and after.onDuty ~= before.onDuty then bridge.setDuty(src, before.onDuty) end
    return true
end

---Promotes or demotes a character who may be offline (a boss menu's list).
---@param identifier string
---@param job string
---@param grade integer
---@return boolean set false when there is no such character or the job has no such grade
function player.setOfflineJob(identifier, job, grade)
    local src = bridge.getSource(identifier)
    if src then return player.setJob(src, job, grade) end

    if not hasGrade(job, grade) then
        TR.log.error('setOfflineJob: job %s has no grade %s', job, grade)
        return false
    end
    return bridge.setOfflineJob(identifier, job, grade)
end

---Fires a character, online or not. Someone who has moved to another job since keeps it.
---@param identifier string
---@param job string
---@return boolean removed false when they weren't in the job
function player.removeJob(identifier, job)
    if bridge.removeJob then return bridge.removeJob(identifier, job) end

    local src = bridge.getSource(identifier)
    if not src then return bridge.setOfflineJob(identifier, 'unemployed', 0, job) end

    local current = bridge.getJob(src)
    return current ~= nil and current.name == job and player.setJob(src, 'unemployed', 0)
end

local function employee(src, identifier, job)
    return { identifier = identifier, name = bridge.getName(src), grade = job.grade, source = src, onDuty = job.onDuty }
end

---Everyone with the job, online or not, from the framework's own tables. Online players are as they are now, not as
---last saved.
---@param job string
---@return TREmployee[]
function player.getEmployees(job)
    local found, seen = {}, {}
    local function add(entry)
        seen[entry.identifier] = true
        found[#found + 1] = entry
    end

    for _, row in ipairs(bridge.getEmployees(job)) do
        local src = bridge.getSource(row.identifier)
        local now = src and bridge.getJob(src)
        if not src then
            add(row)
        elseif now and now.name == job then
            add(employee(src, row.identifier, now))
        elseif bridge.multiJob then
            -- Qbox: the job is one they hold besides their main one, so not on duty in it.
            row.source, row.onDuty = src, false
            add(row)
        end
    end

    -- Hired since the framework last saved them.
    for _, src in ipairs(player.getPlayersWithJob(job)) do
        local identifier = bridge.getIdentifier(src)
        if identifier and not seen[identifier] then add(employee(src, identifier, bridge.getJob(src))) end
    end

    return found
end

local function byName(a, b)
    local x, y = a.lastname:lower(), b.lastname:lower()
    if x ~= y then return x < y end
    return a.firstname:lower() < b.firstname:lower()
end

---Characters, online or not, whose first name, last name, "first last" or phone number holds the text, or whose
---identifier is exactly it (any case).
---@param text string
---@param limit? integer 20 by default, 50 at most
---@return TRCharacter[] by last name, then first name
function player.searchCharacters(text, limit)
    text = type(text) == 'string' and TR.utils.trim(text):gsub('%s+', ' '):sub(1, 64) or ''
    if text == '' then return {} end
    limit = math.max(1, math.min(type(limit) == 'number' and math.floor(limit) or 20, 50))

    local found = bridge.searchCharacters(text, limit)
    table.sort(found, byName)
    for i = #found, limit + 1, -1 do found[i] = nil end
    return found
end

---Every character, online or not, a page at a time.
---@param offset? integer how many to skip, 0 by default
---@param limit? integer 50 by default, 100 at most
---@return TRCharacter[] by last name, then first name
function player.listCharacters(offset, limit)
    offset = math.max(0, type(offset) == 'number' and math.floor(offset) or 0)
    limit = math.max(1, math.min(type(limit) == 'number' and math.floor(limit) or 50, 100))
    return bridge.listCharacters(offset, limit)
end

---@param identifier string
---@return TRCharacter? character online or not; nil when there is no such character
function player.getCharacter(identifier)
    if type(identifier) ~= 'string' or identifier == '' then return end
    return bridge.getCharacter(identifier)
end

---Licences as the framework keeps them: QBCore's and Qbox's metadata (driver, weapon, business, ...), ESX's
---esx_license types (dmv, weapon, drive_bike, ...; drive is called driver).
---@param identifier string
---@return table<string, boolean> licences name -> held; empty when the framework keeps none
function player.getLicences(identifier)
    if type(identifier) ~= 'string' or identifier == '' then return {} end
    return bridge.getLicences(identifier)
end

---Gives or takes a licence, online or not, where getLicences reads it.
---@param identifier string
---@param name string a licence as getLicences names it ('driver', 'weapon', ...)
---@param held boolean
---@return boolean done false for no such character, or with nowhere to keep it (ESX without esx_license)
function player.setLicence(identifier, name, held)
    if type(identifier) ~= 'string' or identifier == '' or type(name) ~= 'string' or not name:match('^[%w_]+$') then return false end
    return bridge.setLicence(identifier, name, held == true)
end

---@param src integer
---@return TRGang?
function player.getGang(src) return bridge.getGang(src) end

---@param src integer
---@param filter TRJobFilter
---@return boolean
function player.hasGang(src, filter)
    return shared.matchJob(bridge.getGang(src), filter)
end

---@param src integer
---@return string? group staff group: 'user', 'mod', 'admin', ... (framework dependent)
function player.getGroup(src) return bridge.getGroup(src) end

---True for the framework's admins, or anyone with the `tr.admin` ace.
---@param src integer
---@return boolean
function player.isAdmin(src)
    return IsPlayerAceAllowed(src, 'tr.admin') or bridge.isAdmin(src)
end

---@param src integer
---@param account TRAccount
---@return integer
function player.getMoney(src, account)
    assert(shared.accounts[account], ('invalid account "%s"'):format(account))
    local dirty = dirtyItem(account)
    if dirty then return countItemMoney(src, dirty) end
    return bridge.getMoney(src, account) or 0
end

---@param src integer
---@param account TRAccount
---@param amount integer
---@return boolean
function player.canAfford(src, account, amount)
    return player.getMoney(src, account) >= amount
end

---@param src integer
---@param account TRAccount
---@param amount integer positive integer
---@param reason? string shown in framework logs
---@return boolean success
function player.addMoney(src, account, amount, reason)
    assert(shared.accounts[account], ('invalid account "%s"'):format(account))

    if not isValidAmount(amount) then
        TR.log.error('addMoney: invalid amount %s for %d', amount, src)
        return false
    end

    local dirty = dirtyItem(account)
    if dirty then return addItemMoney(src, dirty, amount) end
    return bridge.addMoney(src, account, amount, reason or TR.resource)
end

---Removes money only when the player has enough.
---@param src integer
---@param account TRAccount
---@param amount integer positive integer
---@param reason? string shown in framework logs
---@return boolean success
function player.removeMoney(src, account, amount, reason)
    assert(shared.accounts[account], ('invalid account "%s"'):format(account))

    if not isValidAmount(amount) then
        TR.log.error('removeMoney: invalid amount %s for %d', amount, src)
        return false
    end

    if not player.canAfford(src, account, amount) then return false end

    local dirty = dirtyItem(account)
    if dirty then return removeItemMoney(src, dirty, amount) end
    return bridge.removeMoney(src, account, amount, reason or TR.resource)
end

---@return integer[] sources of all loaded players
function player.getPlayers() return bridge.getPlayers() end

---@param filter TRJobFilter
---@param requireDuty? boolean only those on duty
---@return integer[] sources
function player.getPlayersWithJob(filter, requireDuty)
    local found = {}
    for _, src in ipairs(bridge.getPlayers()) do
        if shared.matchJob(bridge.getJob(src), filter, requireDuty) then found[#found + 1] = src end
    end
    return found
end

---@param filter TRJobFilter
---@param requireDuty? boolean only those on duty
---@return integer
function player.countJob(filter, requireDuty)
    return #player.getPlayersWithJob(filter, requireDuty)
end

---@param identifier string
---@return integer? src
function player.getSource(identifier) return bridge.getSource(identifier) end

---Also runs for players already loaded unless skipExisting, so a resource restart acts like a fresh join.
---@param cb fun(src: integer)
---@param skipExisting? boolean
function player.onLoaded(cb, skipExisting)
    AddEventHandler('tr:playerLoaded', cb)

    if not skipExisting then
        for _, src in ipairs(bridge.getPlayers()) do
            CreateThread(function() cb(src) end)
        end
    end
end

---On logout, or when the player drops.
---@param cb fun(src: integer)
function player.onUnloaded(cb)
    AddEventHandler('tr:playerUnloaded', cb)
end

---Also on a grade or duty change.
---@param cb fun(src: integer, job: TRJob, lastJob: TRJob?)
function player.onJobUpdated(cb)
    AddEventHandler('tr:jobUpdated', cb)
end

return player
