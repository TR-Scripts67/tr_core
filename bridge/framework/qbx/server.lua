---@type string, TRFrameworkShared
local _, shared = ...
local qbx = exports.qbx_core

local bridge = {}

local accounts = { cash = 'cash', bank = 'bank' }

---Qbox has no dirty money account: it's ox_inventory's black_money item, one per dollar.
bridge.dirtyItem = { name = 'black_money' }

local function getPlayerData(src)
    local player = qbx:GetPlayer(src)
    return player and player.PlayerData
end

function bridge.isLoaded(src)
    return qbx:GetPlayer(src) ~= nil
end

function bridge.getIdentifier(src)
    local data = getPlayerData(src)
    return data and data.citizenid
end

function bridge.getName(src)
    local data = getPlayerData(src)
    local info = data and data.charinfo
    return info and ('%s %s'):format(info.firstname, info.lastname)
end

function bridge.getBirthDate(src)
    local data = getPlayerData(src)
    return data and data.charinfo and data.charinfo.birthdate
end

function bridge.getJob(src)
    local data = getPlayerData(src)
    return data and shared.qbJob(data.job)
end

function bridge.getJobs()
    return shared.qbJobs(qbx:GetJobs())
end

function bridge.setDuty(src, onDuty)
    if not qbx:GetPlayer(src) then return false end

    qbx:SetJobDuty(src, onDuty)
    return true
end

function bridge.setCuffed(src, cuffed)
    local player = qbx:GetPlayer(src)
    if not player then return false end

    player.Functions.SetMetaData('ishandcuffed', cuffed)
    return true
end

function bridge.isDowned(src) return shared.qbDowned(getPlayerData(src)) end

---Qbox keeps every job a character holds in player_groups, written right away, and one of them is their main job.
bridge.multiJob = true

function bridge.setJob(src, job, grade)
    return qbx:GetPlayer(src) ~= nil and qbx:SetJob(src, job, grade) == true
end

---SetJob takes a citizenid for offline characters too.
function bridge.setOfflineJob(identifier, job, grade)
    return qbx:SetJob(identifier, job, grade) == true
end

---Takes the job out of their list, which also ends it as their main job; online or not.
function bridge.removeJob(identifier, job)
    local held = TR.db.scalar('SELECT 1 FROM player_groups WHERE citizenid = ? AND type = ? AND `group` = ?', { identifier, 'job', job })
    return held ~= nil and qbx:RemovePlayerFromJob(identifier, job) == true
end

function bridge.getEmployees(job)
    local found = {}
    local rows = TR.db.query([[
        SELECT g.citizenid, g.grade, p.charinfo FROM player_groups g
        JOIN players p ON p.citizenid = g.citizenid
        WHERE g.`group` = ? AND g.type = ?
    ]], { job, 'job' })

    for _, row in ipairs(rows) do
        found[#found + 1] = { identifier = row.citizenid, name = shared.qbName(TR.utils.decode(row.charinfo)), grade = math.tointeger(row.grade) or 0 }
    end

    return found
end

function bridge.searchCharacters(text) return shared.qbSearch(text) end
bridge.listCharacters = shared.qbList

local function saved(identifier, column)
    return shared.qbSaved(qbx:GetPlayerByCitizenId(identifier), identifier, column)
end

function bridge.getCharacter(identifier) return shared.qbCharacter(identifier, saved(identifier, 'charinfo')) end

function bridge.getLicences(identifier) return shared.qbLicences(saved(identifier, 'metadata')) end

---SetMetadata doesn't save an offline character: SaveOffline does.
function bridge.setLicence(identifier, name, held)
    local online = qbx:GetPlayerByCitizenId(identifier)
    local player = online or qbx:GetOfflinePlayer(identifier)
    if not player then return false end

    local licences = TR.utils.copy(player.PlayerData.metadata.licences or {})
    licences[name] = held
    if online then
        qbx:SetMetadata(identifier, 'licences', licences)
    else
        player.PlayerData.metadata.licences = licences
        qbx:SaveOffline(player.PlayerData)
    end
    return true
end

bridge.getOwnedVehicles = shared.qbVehicles
bridge.getVehicleOwner = shared.qbVehicleOwner
bridge.searchVehicles = shared.qbSearchVehicles

function bridge.getGang(src)
    local data = getPlayerData(src)
    return data and shared.qbGang(data.gang)
end

function bridge.getGroup(src)
    return shared.aceGroup(src)
end

function bridge.isAdmin(src)
    return IsPlayerAceAllowed(src, 'admin') or IsPlayerAceAllowed(src, 'god')
end

function bridge.getMoney(src, account)
    local name = shared.account(accounts, account)
    if not name then return end

    local amount = qbx:GetMoney(src, name)
    return amount ~= false and amount or nil
end

function bridge.addMoney(src, account, amount, reason)
    local name = shared.account(accounts, account)
    if not name then return false end

    return qbx:AddMoney(src, name, amount, reason) == true
end

function bridge.removeMoney(src, account, amount, reason)
    local name = shared.account(accounts, account)
    if not name then return false end

    return qbx:RemoveMoney(src, name, amount, reason) == true
end

function bridge.getPlayers()
    local players = {}

    for _, data in ipairs(qbx:GetPlayersData()) do
        players[#players + 1] = data.source
    end

    return players
end

function bridge.getSource(identifier)
    local player = qbx:GetPlayerByCitizenId(identifier)
    return player and player.PlayerData.source
end

function bridge.registerEvents()
    local emit = shared.serverEmitter(bridge.getJob, bridge.getPlayers())

    AddEventHandler('QBCore:Server:PlayerLoaded', function(player) emit.loaded(player.PlayerData.source) end)
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) emit.unloaded(src) end)
    AddEventHandler('qbx_core:server:playerLoggedOut', function(src) emit.unloaded(src) end)
    AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job) emit.job(src, shared.qbJob(job)) end)
    AddEventHandler('QBCore:Server:SetDuty', function(src, onDuty)
        local job = bridge.getJob(src)
        if job then job.onDuty = onDuty == true end
        emit.job(src, job)
    end)
end

---ox_inventory passes the used slot ({ slot, count, metadata }).
function bridge.registerUsableItem(item, fn)
    qbx:CreateUseableItem(item, function(src, data) fn(src, data) end)
end

return bridge
