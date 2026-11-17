---@class TRFrameworkShared
local shared = {}

---Servers can map accounts in config.lua (accounts = { dirty = 'blackmoney' }); 'auto' keeps the default.
---@param defaults table<string, string?>
---@param name TRAccount
---@return string?
function shared.account(defaults, name)
    local accounts = TR.config.accounts
    local set = type(accounts) == 'table' and accounts[name]
    if type(set) == 'string' and set ~= '' and set ~= 'auto' then return set end
    return defaults[name]
end

---QBCore and Qbox staff groups come from aces (`add_ace group.admin admin allow`).
---@param src integer
---@return string
function shared.aceGroup(src)
    for _, group in ipairs({ 'god', 'admin', 'mod' }) do
        if IsPlayerAceAllowed(src, group) then return group end
    end
    return 'user'
end

---@return TRJob?
function shared.qbJob(job)
    if not job then return end

    local grade = job.grade or {}

    return {
        name = job.name,
        label = job.label,
        grade = grade.level or 0,
        gradeName = grade.name,
        gradeLabel = grade.name,
        salary = job.payment or grade.payment or 0,
        onDuty = job.onduty == true,
        isBoss = (job.isboss or grade.isboss) == true,
    }
end

---@return string? name QBCore's and Qbox's charinfo as 'First Last'
function shared.qbName(info)
    return type(info) == 'table' and info.firstname and ('%s %s'):format(info.firstname, info.lastname or '') or nil
end

---@param list TRJobGrade[]
---@return TRJobGrade[]
function shared.sortGrades(list)
    table.sort(list, function(a, b) return a.grade < b.grade end)
    return list
end

---QBCore keys grades by '0', '1', ...; Qbox by 0, 1, ...
---@return table<string, TRJobInfo>
function shared.qbJobs(jobs)
    local found = {}

    for name, job in pairs(jobs or {}) do
        local grades = {}

        for level, grade in pairs(job.grades or {}) do
            grades[#grades + 1] = {
                grade = math.tointeger(tonumber(level)) or 0,
                name = grade.name,
                label = grade.name,
                salary = grade.payment or 0,
                isBoss = grade.isboss == true,
            }
        end

        found[name] = { name = name, label = job.label, grades = shared.sortGrades(grades) }
    end

    return found
end

---@return TRGang?
function shared.qbGang(gang)
    if not gang or gang.name == 'none' then return end

    local grade = gang.grade or {}

    return {
        name = gang.name,
        label = gang.label,
        grade = grade.level or 0,
        gradeName = grade.name,
        isBoss = (gang.isboss or grade.isboss) == true,
    }
end

---QBCore's and Qbox's metadata: dead, or in last stand.
---@param data table? PlayerData
---@return boolean
function shared.qbDowned(data)
    local meta = data and data.metadata
    return meta ~= nil and (meta.isdead == true or meta.inlaststand == true)
end

---What a player typed as a LIKE pattern that finds it anywhere, lower case, its own % and _ taken as they are.
---@param text string
---@return string
function shared.contains(text)
    return '%' .. text:lower():gsub('[\\%%_]', '\\%0') .. '%'
end

---A birth date as 'YYYY-MM-DD' when it reads as one: YYYY-MM-DD, YYYY/MM/DD or DD/MM/YYYY (esx_identity's default;
---MM/DD/YYYY when the second number can't be a month). Anything else comes back as stored.
---@param raw any
---@return string?
function shared.birthDate(raw)
    if type(raw) ~= 'string' or raw == '' then return end
    local y, m, d = raw:match('^(%d%d%d%d)[-/.](%d%d?)[-/.](%d%d?)')
    if not y then
        d, m, y = raw:match('^(%d%d?)[-/.](%d%d?)[-/.](%d%d%d%d)$')
        if not y then return raw end
        if tonumber(m) > 12 and tonumber(d) <= 12 then d, m = m, d end
    end
    m, d = tonumber(m), tonumber(d)
    if m < 1 or m > 12 or d < 1 or d > 31 then return raw end
    return ('%s-%02d-%02d'):format(y, m, d)
end

---Whether a character is the one typed: exactly its identifier, or a name, "first last" or phone number holding it.
---@param character TRCharacter
---@param text string
---@return boolean
function shared.isMatch(character, text)
    local lower = text:lower()
    if character.identifier:lower() == lower then return true end
    for _, value in ipairs({ character.firstname, character.lastname, character.firstname .. ' ' .. character.lastname, character.phone or '' }) do
        if value:lower():find(lower, 1, true) then return true end
    end
    return false
end

---@param identifier string
---@param info table? QBCore's and Qbox's charinfo
---@return TRCharacter?
function shared.qbCharacter(identifier, info)
    if type(info) ~= 'table' then return end
    local gender = tonumber(info.gender)
    return {
        identifier = identifier,
        firstname = TR.utils.trim(info.firstname or ''),
        lastname = TR.utils.trim(info.lastname or ''),
        birthDate = shared.birthDate(info.birthdate),
        sex = gender == 0 and 'male' or gender == 1 and 'female' or nil,
        phone = info.phone and info.phone ~= '' and tostring(info.phone) or nil,
    }
end

---QBCore and Qbox: the charinfo JSON holds every word typed (the SQL), then the fields themselves are checked.
---@param text string
---@return TRCharacter[]
function shared.qbSearch(text)
    local where, params = {}, { text }
    for word in text:gmatch('%S+') do
        if #where == 4 then break end
        where[#where + 1] = 'LOWER(charinfo) LIKE ?'
        params[#params + 1] = shared.contains(word)
    end

    local found = {}
    local sql = ('SELECT citizenid, charinfo FROM players WHERE citizenid = ? OR (%s) LIMIT 200'):format(table.concat(where, ' AND '))
    for _, row in ipairs(TR.db.query(sql, params) or {}) do
        local character = shared.qbCharacter(row.citizenid, TR.utils.decode(row.charinfo))
        if character and shared.isMatch(character, text) then found[#found + 1] = character end
    end
    return found
end

---QBCore and Qbox: the players table by the names in charinfo.
---@param offset integer
---@param limit integer
---@return TRCharacter[]
function shared.qbList(offset, limit)
    local found = {}
    local sql = [[SELECT citizenid, charinfo FROM players ORDER BY LOWER(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))),
        LOWER(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname'))) LIMIT ? OFFSET ?]]
    for _, row in ipairs(TR.db.query(sql, { limit, offset }) or {}) do
        local character = shared.qbCharacter(row.citizenid, TR.utils.decode(row.charinfo))
        if character then found[#found + 1] = character end
    end
    return found
end

---QBCore and Qbox: a players column (charinfo, metadata) of an online character as it is now, else as last saved.
---@param player table? the online player
---@param identifier string
---@param column 'charinfo' | 'metadata'
---@return table?
function shared.qbSaved(player, identifier, column)
    if player then return player.PlayerData[column] end
    return TR.utils.decode(TR.db.scalar(('SELECT %s FROM players WHERE citizenid = ?'):format(column), { identifier }))
end

---@param metadata table? QBCore's and Qbox's player metadata
---@return table<string, boolean>
function shared.qbLicences(metadata)
    local held = {}
    for name, has in pairs(type(metadata) == 'table' and type(metadata.licences) == 'table' and metadata.licences or {}) do
        held[name] = has == true
    end
    return held
end

local function colorOf(value)
    return type(value) == 'number' and math.tointeger(value) or nil
end

---@param identifier string
---@return TROwnedVehicle[]
function shared.qbVehicles(identifier)
    local found = {}
    for _, row in ipairs(TR.db.query('SELECT plate, vehicle, hash, mods FROM player_vehicles WHERE citizenid = ?', { identifier }) or {}) do
        local mods = TR.utils.decode(row.mods) or {}
        local hash = tonumber(row.hash)
        found[#found + 1] = { plate = TR.utils.trim(row.plate), model = row.vehicle or (hash and math.tointeger(hash)), color = colorOf(mods.color1) }
    end
    return found
end

---@param plate string trimmed, upper case
---@return string? citizenid
function shared.qbVehicleOwner(plate)
    return TR.db.scalar("SELECT citizenid FROM player_vehicles WHERE UPPER(REPLACE(plate, ' ', '')) = ? LIMIT 1", { plate })
end

---@param text string spaces left out
---@param offset integer
---@param limit integer
---@return TROwnedVehicle[]
function shared.qbSearchVehicles(text, offset, limit)
    local found = {}
    local sql = [[SELECT citizenid, plate, vehicle, hash, mods FROM player_vehicles WHERE LOWER(REPLACE(plate, ' ', '')) LIKE ?
        ORDER BY TRIM(plate) LIMIT ? OFFSET ?]]
    for _, row in ipairs(TR.db.query(sql, { shared.contains(text), limit, offset }) or {}) do
        local mods = TR.utils.decode(row.mods) or {}
        local hash = tonumber(row.hash)
        found[#found + 1] = { plate = TR.utils.trim(row.plate), model = row.vehicle or (hash and math.tointeger(hash)), color = colorOf(mods.color1),
            owner = row.citizenid }
    end
    return found
end

---ESX's vehicle properties: the model hash and primary colour.
---@param props table?
---@return string|integer? model
---@return integer? color
function shared.esxVehicle(props)
    if type(props) ~= 'table' then return end
    return type(props.model) == 'number' and math.tointeger(props.model) or props.model, colorOf(props.color1)
end

local function sameJob(a, b)
    if a == nil or b == nil then return a == b end
    return a.name == b.name and a.grade == b.grade and a.onDuty == b.onDuty
end

---Frameworks fire overlapping events (logout + drop, repeated job syncs); this emits each tr:* event once.
---@param getJob fun(src: integer): TRJob?
---@param loadedPlayers integer[] players already loaded when tr_core starts
function shared.serverEmitter(getJob, loadedPlayers)
    local jobs, loaded = {}, {}

    for _, src in ipairs(loadedPlayers) do
        loaded[src] = true
        jobs[src] = getJob(src)
    end

    local emitter = {}

    function emitter.loaded(src)
        if loaded[src] then return end
        loaded[src] = true
        jobs[src] = getJob(src)
        TriggerEvent('tr:playerLoaded', src)
    end

    function emitter.unloaded(src)
        if not loaded[src] then return end
        loaded[src], jobs[src] = nil, nil
        TriggerEvent('tr:playerUnloaded', src)
    end

    ---@param job TRJob?
    function emitter.job(src, job)
        if not loaded[src] or sameJob(job, jobs[src]) then return end
        local last = jobs[src]
        jobs[src] = job
        TriggerEvent('tr:jobUpdated', src, job, last)
    end

    AddEventHandler('playerDropped', function()
        emitter.unloaded(source)
    end)

    return emitter
end

---@param getJob fun(): TRJob?
---@param isLoaded fun(): boolean
function shared.clientEmitter(getJob, isLoaded)
    local loaded = isLoaded()
    local job = loaded and getJob() or nil
    local emitter = {}

    function emitter.loaded()
        -- The framework updates its player data in its own handler for the same event; wait for it.
        TR.utils.waitFor(isLoaded, 10000)
        if loaded then return end
        loaded, job = true, getJob()
        TriggerEvent('tr:playerLoaded')
    end

    function emitter.unloaded()
        if not loaded then return end
        loaded, job = false, nil
        TriggerEvent('tr:playerUnloaded')
    end

    ---@param newJob TRJob?
    function emitter.job(newJob)
        if not loaded or sameJob(newJob, job) then return end
        local last = job
        job = newJob
        TriggerEvent('tr:jobUpdated', newJob, last)
    end

    return emitter
end

return shared
