---@type string, TRFrameworkShared
local _, shared = ...
local QBCore = exports['qb-core']:GetCoreObject()

local bridge = {}

local accounts = { cash = 'cash', bank = 'bank' }

---QBCore's dirty money is markedbills bags, each with its worth in the info.
bridge.dirtyItem = { name = 'markedbills', worth = 'worth' }

local function getPlayerData(src)
    local player = QBCore.Functions.GetPlayer(src)
    return player and player.PlayerData
end

function bridge.isLoaded(src)
    return QBCore.Functions.GetPlayer(src) ~= nil
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
    return shared.qbJobs(QBCore.Shared.Jobs)
end

---Fires the same events as qb-core's own QBCore:ToggleDuty, which SetJobDuty doesn't.
function bridge.setDuty(src, onDuty)
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return false end

    player.Functions.SetJobDuty(onDuty)
    TriggerEvent('QBCore:Server:SetDuty', src, onDuty)
    TriggerClientEvent('QBCore:Client:SetDuty', src, onDuty)
    return true
end

function bridge.setCuffed(src, cuffed)
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return false end

    player.Functions.SetMetaData('ishandcuffed', cuffed)
    return true
end

function bridge.isDowned(src) return shared.qbDowned(getPlayerData(src)) end

function bridge.setJob(src, job, grade)
    local player = QBCore.Functions.GetPlayer(src)
    return player ~= nil and player.Functions.SetJob(job, tostring(grade)) == true
end

---`from`: only while they still have that job (firing).
function bridge.setOfflineJob(identifier, job, grade, from)
    local player = QBCore.Functions.GetOfflinePlayerByCitizenId(identifier)
    if not player or (from and player.PlayerData.job.name ~= from) then return false end
    if player.Functions.SetJob(job, tostring(grade)) ~= true then return false end

    player.Functions.Save()
    return true
end

---The job is a JSON column: LIKE finds the rows it could be in, the decoded name decides.
function bridge.getEmployees(job)
    local found = {}

    for _, row in ipairs(TR.db.query('SELECT citizenid, charinfo, job FROM players WHERE job LIKE ?', { ('%%%s%%'):format(job) })) do
        local current = TR.utils.decode(row.job)
        if current and current.name == job then
            local grade = type(current.grade) == 'table' and current.grade.level
            found[#found + 1] = { identifier = row.citizenid, name = shared.qbName(TR.utils.decode(row.charinfo)), grade = math.tointeger(tonumber(grade)) or 0 }
        end
    end

    return found
end

function bridge.searchCharacters(text) return shared.qbSearch(text) end
bridge.listCharacters = shared.qbList

local function saved(identifier, column)
    return shared.qbSaved(QBCore.Functions.GetPlayerByCitizenId(identifier), identifier, column)
end

function bridge.getCharacter(identifier) return shared.qbCharacter(identifier, saved(identifier, 'charinfo')) end

function bridge.getLicences(identifier) return shared.qbLicences(saved(identifier, 'metadata')) end

---An offline player's metadata is only kept by its Save.
function bridge.setLicence(identifier, name, held)
    local player = QBCore.Functions.GetPlayerByCitizenId(identifier) or QBCore.Functions.GetOfflinePlayerByCitizenId(identifier)
    if not player then return false end

    local licences = TR.utils.copy(player.PlayerData.metadata.licences or {})
    licences[name] = held
    player.Functions.SetMetaData('licences', licences)
    if player.Offline then player.Functions.Save() end
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
    local data = name and getPlayerData(src)
    return data and data.money[name]
end

function bridge.addMoney(src, account, amount, reason)
    local name = shared.account(accounts, account)
    local player = name and QBCore.Functions.GetPlayer(src)
    if not player then return false end

    return player.Functions.AddMoney(name, amount, reason) == true
end

function bridge.removeMoney(src, account, amount, reason)
    local name = shared.account(accounts, account)
    local player = name and QBCore.Functions.GetPlayer(src)
    if not player then return false end

    return player.Functions.RemoveMoney(name, amount, reason) == true
end

function bridge.getPlayers()
    return QBCore.Functions.GetPlayers()
end

function bridge.getSource(identifier)
    local player = QBCore.Functions.GetPlayerByCitizenId(identifier)
    return player and player.PlayerData.source
end

function bridge.registerEvents()
    local emit = shared.serverEmitter(bridge.getJob, bridge.getPlayers())

    AddEventHandler('QBCore:Server:PlayerLoaded', function(player) emit.loaded(player.PlayerData.source) end)
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) emit.unloaded(src) end)
    AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job) emit.job(src, shared.qbJob(job)) end)
    AddEventHandler('QBCore:Server:SetDuty', function(src, onDuty)
        local job = bridge.getJob(src)
        if job then job.onDuty = onDuty == true end
        emit.job(src, job)
    end)
end

---qb-inventory passes the used slot's item ({ slot, amount, info }).
function bridge.registerUsableItem(item, fn)
    QBCore.Functions.CreateUseableItem(item, function(src, data) fn(src, data) end)
end

return bridge
