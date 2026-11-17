---@type string, TRFrameworkShared
local _, shared = ...
local ESX = exports.es_extended:getSharedObject()

local bridge = {}

local accounts = { cash = 'money', bank = 'bank', dirty = 'black_money' }

---@return TRJob?
local function normalizeJob(job)
    if not job then return end

    return {
        name = job.name,
        label = job.label,
        grade = job.grade,
        gradeName = job.grade_name,
        gradeLabel = job.grade_label,
        salary = job.grade_salary or 0,
        onDuty = job.onDuty ~= false,
        isBoss = job.grade_name == 'boss',
    }
end

local function getPlayer(src)
    return ESX.GetPlayerFromId(src)
end

function bridge.isLoaded(src)
    return getPlayer(src) ~= nil
end

function bridge.getIdentifier(src)
    local xPlayer = getPlayer(src)
    return xPlayer and xPlayer.getIdentifier()
end

function bridge.getName(src)
    local xPlayer = getPlayer(src)
    return xPlayer and xPlayer.getName()
end

function bridge.getBirthDate(src)
    local xPlayer = getPlayer(src)
    return xPlayer and xPlayer.get('dateofbirth')
end

function bridge.getJob(src)
    local xPlayer = getPlayer(src)
    return xPlayer and normalizeJob(xPlayer.getJob())
end

function bridge.getJobs()
    local found = {}

    for name, job in pairs(ESX.GetJobs()) do
        local grades = {}

        for _, grade in pairs(job.grades) do
            grades[#grades + 1] = {
                grade = grade.grade,
                name = grade.name,
                label = grade.label,
                salary = grade.salary or 0,
                isBoss = grade.name == 'boss',
            }
        end

        found[name] = { name = name, label = job.label, grades = shared.sortGrades(grades) }
    end

    return found
end

---ESX keeps duty in the job, so it is set with setJob (which fires esx:setJob).
function bridge.setDuty(src, onDuty)
    local xPlayer = getPlayer(src)
    local job = xPlayer and xPlayer.getJob()
    if not job or job.onDuty == nil then return false end

    xPlayer.setJob(job.name, job.grade, onDuty)
    return xPlayer.getJob().onDuty == onDuty
end

---ESX has no shared flag; esx_policejob's own event toggles, so it could go the wrong way.
function bridge.setCuffed() return false end

---ESX keeps no dead flag on the server: its death scripts set the isDead state bag.
function bridge.isDowned() return false end

function bridge.setJob(src, job, grade)
    local xPlayer = getPlayer(src)
    if not xPlayer then return false end

    xPlayer.setJob(job, grade)
    local now = xPlayer.getJob()
    return now.name == job and now.grade == grade
end

---`from`: only while they still have that job (firing).
function bridge.setOfflineJob(identifier, job, grade, from)
    if from then
        return TR.db.update('UPDATE users SET job = ?, job_grade = ? WHERE identifier = ? AND job = ?', { job, grade, identifier, from }) > 0
    end
    return TR.db.update('UPDATE users SET job = ?, job_grade = ? WHERE identifier = ?', { job, grade, identifier }) > 0
end

function bridge.getEmployees(job)
    local found = {}

    for _, row in ipairs(TR.db.query('SELECT identifier, firstname, lastname, job_grade FROM users WHERE job = ?', { job })) do
        local name = row.firstname and ('%s %s'):format(row.firstname, row.lastname or '') or nil
        found[#found + 1] = { identifier = row.identifier, name = name, grade = math.tointeger(row.job_grade) or 0 }
    end

    return found
end

local present = {}

---Whether the database has the table (and column): ESX Legacy has no phone_number, user_licenses comes with esx_license.
local function has(name, column)
    local key = name .. '.' .. (column or '')
    if present[key] == nil then
        present[key] = TR.db.scalar(column
            and 'SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?'
            or 'SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { name, column }) ~= nil
    end
    return present[key]
end

local function characterOf(row)
    local sex = type(row.sex) == 'string' and row.sex:lower()
    return {
        identifier = row.identifier,
        firstname = TR.utils.trim(row.firstname or ''),
        lastname = TR.utils.trim(row.lastname or ''),
        birthDate = shared.birthDate(row.dateofbirth),
        sex = sex == 'm' and 'male' or sex == 'f' and 'female' or nil,
        phone = row.phone_number and row.phone_number ~= '' and tostring(row.phone_number) or nil,
    }
end

local function columns()
    return 'identifier, firstname, lastname, dateofbirth, sex' .. (has('users', 'phone_number') and ', phone_number' or '')
end

function bridge.searchCharacters(text, limit)
    local like = shared.contains(text)
    local params = { text, like, like, like }
    local phone = has('users', 'phone_number')
    if phone then params[#params + 1] = like end
    params[#params + 1] = limit

    local found = {}
    local sql = ([[SELECT %s FROM users WHERE identifier = ? OR LOWER(firstname) LIKE ? OR LOWER(lastname) LIKE ?
        OR LOWER(CONCAT_WS(' ', TRIM(firstname), TRIM(lastname))) LIKE ?%s ORDER BY lastname, firstname LIMIT ?]]):format(columns(), phone and ' OR phone_number LIKE ?' or '')
    for _, row in ipairs(TR.db.query(sql, params) or {}) do
        found[#found + 1] = characterOf(row)
    end
    return found
end

function bridge.listCharacters(offset, limit)
    local found = {}
    local sql = ([[SELECT %s FROM users WHERE firstname IS NOT NULL AND firstname <> ''
        ORDER BY LOWER(lastname), LOWER(firstname) LIMIT ? OFFSET ?]]):format(columns())
    for _, row in ipairs(TR.db.query(sql, { limit, offset }) or {}) do
        found[#found + 1] = characterOf(row)
    end
    return found
end

function bridge.getCharacter(identifier)
    local row = TR.db.single(('SELECT %s FROM users WHERE identifier = ?'):format(columns()), { identifier })
    return row and characterOf(row)
end

---esx_license's types as they are, except 'drive', which is 'driver' as on QBCore.
function bridge.getLicences(identifier)
    local held = {}
    if not has('user_licenses') then return held end

    for _, row in ipairs(TR.db.query('SELECT type FROM user_licenses WHERE owner = ?', { identifier }) or {}) do
        held[row.type == 'drive' and 'driver' or row.type] = true
    end
    return held
end

function bridge.setLicence(identifier, name, held)
    if not has('user_licenses') or not TR.db.scalar('SELECT 1 FROM users WHERE identifier = ?', { identifier }) then return false end
    local kind = name == 'driver' and 'drive' or name
    TR.db.update('DELETE FROM user_licenses WHERE type = ? AND owner = ?', { kind, identifier })
    if held then TR.db.insert('INSERT INTO user_licenses (type, owner) VALUES (?, ?)', { kind, identifier }) end
    return true
end

function bridge.getOwnedVehicles(identifier)
    local found = {}
    for _, row in ipairs(TR.db.query('SELECT plate, vehicle FROM owned_vehicles WHERE owner = ?', { identifier }) or {}) do
        local model, color = shared.esxVehicle(TR.utils.decode(row.vehicle))
        found[#found + 1] = { plate = TR.utils.trim(row.plate), model = model, color = color }
    end
    return found
end

function bridge.getVehicleOwner(plate)
    return TR.db.scalar("SELECT owner FROM owned_vehicles WHERE UPPER(REPLACE(plate, ' ', '')) = ? LIMIT 1", { plate })
end

function bridge.searchVehicles(text, offset, limit)
    local found = {}
    local sql = [[SELECT owner, plate, vehicle FROM owned_vehicles WHERE LOWER(REPLACE(plate, ' ', '')) LIKE ?
        ORDER BY TRIM(plate) LIMIT ? OFFSET ?]]
    for _, row in ipairs(TR.db.query(sql, { shared.contains(text), limit, offset }) or {}) do
        local model, color = shared.esxVehicle(TR.utils.decode(row.vehicle))
        found[#found + 1] = { plate = TR.utils.trim(row.plate), model = model, color = color, owner = row.owner }
    end
    return found
end

function bridge.getGang() end

function bridge.getGroup(src)
    local xPlayer = getPlayer(src)
    return xPlayer and xPlayer.getGroup()
end

function bridge.isAdmin(src)
    local group = bridge.getGroup(src)
    return group == 'admin' or group == 'superadmin'
end

function bridge.getMoney(src, account)
    local name = shared.account(accounts, account)
    local xPlayer = name and getPlayer(src)
    local data = xPlayer and xPlayer.getAccount(name)
    return data and data.money
end

function bridge.addMoney(src, account, amount, reason)
    local name = shared.account(accounts, account)
    local xPlayer = name and getPlayer(src)
    if not xPlayer then return false end

    xPlayer.addAccountMoney(name, amount, reason)
    return true
end

function bridge.removeMoney(src, account, amount, reason)
    local name = shared.account(accounts, account)
    local xPlayer = name and getPlayer(src)
    if not xPlayer then return false end

    xPlayer.removeAccountMoney(name, amount, reason)
    return true
end

function bridge.getPlayers()
    local players = {}

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        players[#players + 1] = xPlayer.source
    end

    return players
end

function bridge.getSource(identifier)
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    return xPlayer and xPlayer.source
end

function bridge.registerEvents()
    local emit = shared.serverEmitter(bridge.getJob, bridge.getPlayers())

    AddEventHandler('esx:playerLoaded', function(src) emit.loaded(src) end)

    -- esx:playerLogout (multicharacter) fires this too.
    AddEventHandler('esx:playerDropped', function(src) emit.unloaded(src) end)

    AddEventHandler('esx:setJob', function(src, job) emit.job(src, normalizeJob(job)) end)
end

---ox_inventory passes the used slot as the third argument ({ slot, count, metadata }).
function bridge.registerUsableItem(item, fn)
    ESX.RegisterUsableItem(item, function(src, _, data) fn(src, data) end)
end

return bridge
