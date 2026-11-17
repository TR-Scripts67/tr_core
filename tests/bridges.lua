local check = T.check

-- awaitChecked passes through to await (the answer schema is tested in security.lua).
local function mockCallback(t)
    t.awaitChecked = function(name, src, _, ...) return t.await(name, src, ...) end
    return t
end

local function qbPlayerData()
    return {
        source = 1,
        citizenid = 'ABC123',
        charinfo = { firstname = 'John', lastname = 'Doe', birthdate = '1990-04-12' },
        job = { name = 'police', label = 'Police', onduty = true, payment = 50, isboss = false, grade = { name = 'Officer', level = 2 } },
        gang = { name = 'ballas', label = 'Ballas', grade = { name = 'OG', level = 3, isboss = true } },
        money = { cash = 100, bank = 1000, crypto = 5 },
        items = {
            [1] = { name = 'water', amount = 3, slot = 1, info = {} },
            [2] = { name = 'weed', amount = 2, slot = 2, info = { quality = 90 } },
            [5] = { name = 'weed', amount = 4, slot = 5, info = { quality = 90 } },
            [6] = { name = 'weed', amount = 1, slot = 6, info = { quality = 10 } },
        },
    }
end

local function qbMoneyFunctions(data)
    return {
        AddMoney = function(moneyType, amount)
            if not data.money[moneyType] then return false end
            data.money[moneyType] = data.money[moneyType] + amount
            return true
        end,
        RemoveMoney = function(moneyType, amount)
            if not data.money[moneyType] then return false end
            data.money[moneyType] = data.money[moneyType] - amount
            return true
        end,
    }
end

local function mockQBCore(data)
    local player = { PlayerData = data, Functions = qbMoneyFunctions(data) }
    player.Functions.SetJobDuty = function(onDuty) data.job.onduty = onDuty end
    player.Functions.SetMetaData = function(key, value) data.metadata = data.metadata or {}; data.metadata[key] = value end

    local QBCore = {
        Functions = {
            GetPlayer = function(src) return src == 1 and player or nil end,
            GetPlayers = function() return { 1 } end,
            GetPlayerByCitizenId = function(id) return id == data.citizenid and player or nil end,
            GetPlayerData = function() return data end,
            Notify = function(...) T.lastNotify = table.pack(...) end,
            CreateUseableItem = function(item, cb) T.usable[item] = cb end,
        },
        Shared = { Items = {
            water = { name = 'water', label = 'Water', weight = 500, unique = false, image = 'water_bottle.png' },
            weed = { name = 'weed', label = 'Weed', weight = 10, unique = false },
            phone = { name = 'phone', label = 'Phone', weight = 700, unique = true },
            markedbills = { name = 'markedbills', label = 'Marked Bills', weight = 1000, unique = false },
        },
        Jobs = {
            police = { label = 'Law Enforcement', grades = {
                ['1'] = { name = 'Officer', payment = 75 },
                ['0'] = { name = 'Recruit', payment = 50 },
                ['4'] = { name = 'Chief', isboss = true, payment = 150 },
            } },
        } },
    }

    T.exports['qb-core'] = { GetCoreObject = function() return QBCore end }
    T.usable = {}
    return player
end

local function testPlayerServer(label)
    local p = TR.player
    check(label .. ' identifier', p.getIdentifier(1) == 'ABC123')
    check(label .. ' name', p.getName(1) == 'John Doe')
    check(label .. ' birth date', p.getBirthDate(1) == '1990-04-12')

    local job = p.getJob(1)
    check(label .. ' job normalized', job.name == 'police' and job.grade == 2 and job.gradeName == 'Officer'
        and job.salary == 50 and job.onDuty == true and job.isBoss == false)
    check(label .. ' hasJob', p.hasJob(1, { police = 2 }) and not p.hasJob(1, { police = 3 }) and p.hasJob(1, 'police', true))

    local gang = p.getGang(1)
    check(label .. ' gang', gang.name == 'ballas' and gang.grade == 3 and gang.isBoss == true)
    check(label .. ' hasGang', p.hasGang(1, { 'ballas' }) and not p.hasGang(1, 'vagos'))

    check(label .. ' getMoney', p.getMoney(1, 'cash') == 100 and p.getMoney(1, 'bank') == 1000)
    check(label .. ' addMoney', p.addMoney(1, 'bank', 50) and p.getMoney(1, 'bank') == 1050)
    check(label .. ' removeMoney', p.removeMoney(1, 'cash', 40) and p.getMoney(1, 'cash') == 60)
    check(label .. ' removeMoney insufficient', not p.removeMoney(1, 'cash', 1000) and p.getMoney(1, 'cash') == 60)
    check(label .. ' offline player', p.getMoney(2, 'cash') == 0 and not p.isLoaded(2) and p.getJob(2) == nil)
    check(label .. ' getPlayers', #p.getPlayers() == 1 and p.getPlayers()[1] == 1)
    check(label .. ' getSource', p.getSource('ABC123') == 1 and p.getSource('nope') == nil)

    T.aces[1] = { admin = true }
    check(label .. ' isAdmin', p.isAdmin(1) and p.getGroup(1) == 'admin')
    T.aces[1] = {}
    check(label .. ' not admin', not p.isAdmin(1) and p.getGroup(1) == 'user')
    T.aces[1] = { ['tr.admin'] = true }
    check(label .. ' tr.admin ace', p.isAdmin(1))
    T.aces[1] = nil
end

do
    local data = qbPlayerData()
    local player = mockQBCore(data)
    T.boot('server', { ['qb-core'] = 'started', ['qb-inventory'] = 'started' })
    check('qb detected', TR.system('framework') == 'qb' and TR.system('inventory') == 'qb_inventory')

    testPlayerServer('qb')

    TR.config.accounts = { dirty = 'crypto' }
    check('qb dirty mapped by config.lua', TR.player.getMoney(1, 'dirty') == 5)
    TR.config.accounts = { dirty = 'auto' }

    -- player 1 is already loaded when tr_core registers the events
    TR.player.bridge.registerEvents()
    TriggerEvent('QBCore:Server:PlayerLoaded', player)
    check('qb no duplicate load for seeded player', T.count('tr:playerLoaded') == 0)

    TriggerEvent('QBCore:Server:OnJobUpdate', 1, data.job)
    check('qb identical job sync ignored', T.count('tr:jobUpdated') == 0)

    data.job = { name = 'police', label = 'Police', onduty = true, payment = 80, grade = { name = 'Sergeant', level = 3 } }
    TriggerEvent('QBCore:Server:OnJobUpdate', 1, data.job)
    local fired = T.fired['tr:jobUpdated']
    check('qb job change', T.count('tr:jobUpdated') == 1 and fired[1][2].grade == 3 and fired[1][3].grade == 2)

    TriggerEvent('QBCore:Server:SetDuty', 1, false)
    check('qb duty change', T.count('tr:jobUpdated') == 2 and T.fired['tr:jobUpdated'][2][2].onDuty == false)

    TriggerEvent('QBCore:Server:OnPlayerUnload', 1)
    T.fromClient(1, 'playerDropped')
    check('qb unload once', T.count('tr:playerUnloaded') == 1)

    TriggerEvent('QBCore:Server:PlayerLoaded', player)
    check('qb load after unload', T.count('tr:playerLoaded') == 1)

    local police = TR.player.getJobs().police
    check('qb getJobs: grades by number, lowest first', police.label == 'Law Enforcement' and #police.grades == 3
        and police.grades[1].grade == 0 and police.grades[3].grade == 4 and police.grades[3].isBoss
        and police.grades[2].label == 'Officer' and police.grades[2].salary == 75)

    local updates = T.count('tr:jobUpdated')
    check('qb setDuty', TR.player.setDuty(1, false) and data.job.onduty == false
        and T.count('tr:jobUpdated') == updates + 1 and T.fired['tr:jobUpdated'][updates + 1][2].onDuty == false)
    check('qb setDuty tells the client', T.clientEvents[#T.clientEvents].name == 'QBCore:Client:SetDuty')
    check('qb setDuty offline', not TR.player.setDuty(2, true))
    check('qb setCuffed: the ishandcuffed metadata', TR.player.setCuffed(1, true) and data.metadata.ishandcuffed == true
        and TR.player.setCuffed(1, false) and data.metadata.ishandcuffed == false and not TR.player.setCuffed(2, true))
    data.metadata = { isdead = false, inlaststand = false }
    check('qb isDowned: up', not TR.player.isDowned(1))
    data.metadata = { inlaststand = true }
    check('qb isDowned: in last stand', TR.player.isDowned(1))
    data.metadata = { isdead = true }
    check('qb isDowned: dead', TR.player.isDowned(1) and not TR.player.isDowned(2))
    data.metadata = nil

    local invCalls = {}
    local slots = data.items
    local refuseSlot -- a slot qb-inventory won't take items out of
    T.exports['qb-inventory'] = {
        GetItemCount = function(_, src, item)
            local n = 0
            for _, s in pairs(slots) do if s.name == item then n = n + s.amount end end
            return n
        end,
        CanAddItem = function(_, src, item, amount) return amount <= 10 end,
        AddItem = function(_, src, item, amount, slot, info, reason)
            invCalls[#invCalls + 1] = { 'add', item, amount, info, reason, slot }
            return true
        end,
        RemoveItem = function(_, src, item, amount, slot)
            invCalls[#invCalls + 1] = { 'remove', item, amount, slot }
            if slot and slot == refuseSlot then return false end
            if slot then slots[slot].amount = slots[slot].amount - amount end
            return true
        end,
        OpenInventory = function(_, src, id, stashData) invCalls[#invCalls + 1] = { 'open', id, stashData } end,
        CloseInventory = function(_, src) invCalls[#invCalls + 1] = { 'close', src } end,
        OpenInventoryById = function(_, src, target) invCalls[#invCalls + 1] = { 'openPlayer', src, target } end,
    }

    slots[7] = { name = 'markedbills', amount = 2, slot = 7, info = { worth = 300 } }
    slots[8] = { name = 'markedbills', amount = 1, slot = 8, info = { worth = 150 } }
    check('qb dirty money: markedbills by worth', TR.player.getMoney(1, 'dirty') == 750)
    check('qb dirty pay: whole bags, the change in one', TR.player.removeMoney(1, 'dirty', 400) and slots[7].amount == 0
        and invCalls[1][1] == 'remove' and invCalls[1][3] == 2 and invCalls[1][4] == 7
        and invCalls[2][1] == 'add' and invCalls[2][2] == 'markedbills' and invCalls[2][3] == 1 and invCalls[2][4].worth == 200)
    invCalls = {}
    check('qb dirty pay short: nothing taken', not TR.player.removeMoney(1, 'dirty', 1000) and #invCalls == 0)
    check('qb dirty add: one bag worth it', TR.player.addMoney(1, 'dirty', 80) and invCalls[1][3] == 1 and invCalls[1][4].worth == 80)
    slots[7], slots[8], invCalls = nil, nil, {}

    local inv = TR.inventory
    check('qbinv count', inv.getCount(1, 'water') == 3 and inv.getCount(1, 'weed') == 7)
    check('qbinv count metadata', inv.getCount(1, 'weed', { quality = 90 }) == 6)
    check('qbinv canCarry', inv.canCarry(1, 'water', 5) and not inv.canCarry(1, 'water', 50))

    local ok = inv.addItem(1, 'water', 2, { purity = 1 })
    check('qbinv addItem', ok and invCalls[1][1] == 'add' and invCalls[1][4].purity == 1 and invCalls[1][5] == 'tr_example')
    check('qbinv addItem itembox', T.clientEvents[#T.clientEvents].name == 'qb-inventory:client:ItemBox')

    local full, reason = inv.addItem(1, 'water', 50)
    check('qbinv addItem full', not full and reason == 'inventory_full')
    local bad, badReason = inv.addItem(1, 'nope', 1)
    check('qbinv addItem unknown', not bad and badReason == 'invalid_item')

    invCalls = {}
    check('qbinv removeItem metadata spans slots', inv.removeItem(1, 'weed', 5, { quality = 90 })
        and #invCalls == 2 and slots[2].amount + slots[5].amount == 1)
    invCalls = {}
    check('qbinv removeItem not enough: nothing touched', not inv.removeItem(1, 'weed', 50, { quality = 90 }) and #invCalls == 0)
    check('qbinv removeItem not enough', not inv.removeItem(1, 'weed', 50))

    slots[2].amount, slots[5].amount, refuseSlot, invCalls = 2, 4, 5, {}
    local boxes = #T.clientEvents
    local partial = inv.removeItem(1, 'weed', 5, { quality = 90 })
    local back = invCalls[#invCalls]
    check('qbinv removeItem all or nothing', not partial and #invCalls == 3 and invCalls[1][4] == 2 and invCalls[2][4] == 5
        and back[1] == 'add' and back[2] == 'weed' and back[3] == 2 and back[6] == 2 and back[4].quality == 90)
    check('qbinv removeItem refused: no item box', #T.clientEvents == boxes)
    refuseSlot = nil
    check('qbinv getItem', inv.getItem('phone').stack == false and inv.getItem('water').label == 'Water')
    local all = inv.getItems()
    check('qbinv getItems', all.phone.stack == false and all.water.stack == true and all.weed.label == 'Weed' and all.markedbills ~= nil)

    -- qb item names are lowercase; the item list is saved with SetPlayerData
    local saved
    player.Functions.SetPlayerData = function(key, value) saved = { key, value } end
    local weed = inv.getSlots(1, 'WEED')
    check('qbinv getSlots', #weed == 3 and weed[1].slot == 2 and weed[3].slot == 6 and weed[3].metadata.quality == 10)
    check('qbinv getSlots none', #inv.getSlots(1, 'phone') == 0)
    check('qbinv setMetadata', inv.setMetadata(1, 6, { quality = 55 }) and slots[6].info.quality == 55 and saved[1] == 'items')
    check('qbinv setMetadata empty slot', inv.setMetadata(1, 9, {}) == false and inv.setMetadata(1, 'x', {}) == false)

    local used
    inv.onUse('laptop', function(src, slot) used = { src, slot } end)
    T.usable.laptop(1, { name = 'laptop', slot = 4, amount = 1, info = { serial = 'TR-1' } })
    check('qbinv onUse: the slot and its info', used and used[1] == 1 and used[2].slot == 4 and used[2].count == 1
        and used[2].metadata.serial == 'TR-1')

    invCalls = {}
    inv.registerStash('evidence', { label = 'Evidence', slots = 50, weight = 100000, groups = { police = 0 }, coords = vector3(10, 0, 0) })
    inv.registerStash('locker', { label = 'Locker', slots = 10, weight = 5000, owner = true })
    inv.openStash(1, 'locker')
    check('qbinv personal stash id', invCalls[1][2] == 'locker:ABC123' and invCalls[1][3].maxweight == 5000)

    T.coords = { [1] = vector3(100, 0, 0) }
    T.timer = T.timer + 1000
    T.fromClient(1, 'tr_example:tr_openStash', 'evidence')
    check('qbinv stash too far', #invCalls == 1)
    T.coords = { [1] = vector3(11, 0, 0) }
    T.timer = T.timer + 1000
    T.fromClient(1, 'tr_example:tr_openStash', 'evidence')
    check('qbinv stash open near', #invCalls == 2 and invCalls[2][2] == 'evidence')

    data.job = { name = 'ems', label = 'EMS', onduty = true, grade = { name = 'Medic', level = 0 } }
    data.gang = { name = 'none' }
    T.timer = T.timer + 1000
    T.fromClient(1, 'tr_example:tr_openStash', 'evidence')
    check('qbinv stash wrong job', #invCalls == 2)

    T.timer = T.timer + 1000
    T.fromClient(1, 'tr_example:tr_openStash', 12345)
    check('qbinv stash invalid payload flagged', #invCalls == 2 and T.count('tr:playerFlagged') == 1)

    do
        local threads, createThread, wait = {}, CreateThread, Wait
        CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end
        Wait = function() coroutine.yield() end
        local function step()
            for _, co in ipairs(threads) do if coroutine.status(co) ~= 'dead' then coroutine.resume(co) end end
        end
        local function watching() return coroutine.status(threads[#threads]) ~= 'dead' end
        invCalls, T.coords, T.bags = {}, { [1] = vector3(0, 0, 0), [2] = vector3(1, 0, 0) }, { [2] = {} }
        check('qbinv openPlayer', inv.openPlayer(1, 2) and invCalls[1][1] == 'openPlayer' and invCalls[1][2] == 1 and invCalls[1][3] == 2)
        step()
        check('qbinv openPlayer: waits for it to show', watching())
        T.bags[2].inv_busy = true
        step()
        T.coords[2] = vector3(5, 0, 0)
        step()
        check('qbinv openPlayer: closed once they are apart', not watching() and invCalls[2][1] == 'close' and invCalls[2][2] == 1)
        T.coords[2], T.bags[2].inv_busy = vector3(1, 0, 0), nil
        inv.openPlayer(1, 2)
        step()
        T.timer = T.timer + 3001
        step()
        check('qbinv openPlayer: never shown, no watch left', not watching() and #invCalls == 3)
        CreateThread, Wait, T.coords, T.bags = createThread, wait, nil, nil
    end

    -- Like qb-core: SetJob puts duty back to the job's default (none set here: off).
    local QBCore = T.exports['qb-core'].GetCoreObject()
    local function setJobOn(target)
        return function(name, grade)
            local info = QBCore.Shared.Jobs[name]
            if not info then return false end
            local level = info.grades[grade] and tonumber(grade) or 0
            target.job = { name = name, label = info.label, onduty = info.defaultDuty, grade = { name = info.grades[grade] and info.grades[grade].name, level = level } }
            return true
        end
    end
    QBCore.Shared.Jobs.unemployed = { label = 'Civilian', grades = { ['0'] = { name = 'Freelancer', payment = 10 } } }
    player.Functions.SetJob = setJobOn(data)
    local offline = { citizenid = 'XYZ789', job = { name = 'police', grade = { name = 'Recruit', level = 0 } }, metadata = {} }
    local savedOffline = 0
    QBCore.Functions.GetOfflinePlayerByCitizenId = function(id)
        if id ~= 'XYZ789' then return nil end
        return { PlayerData = offline, Offline = true, Functions = { SetJob = setJobOn(offline), Save = function() savedOffline = savedOffline + 1 end,
            SetMetaData = function(key, value) offline.metadata = offline.metadata or {}; offline.metadata[key] = value end } }
    end

    data.job = { name = 'police', label = 'Police', onduty = true, grade = { name = 'Recruit', level = 0 } }
    local p = TR.player
    check('qb setJob: a promotion keeps duty', p.setJob(1, 'police', 4) and data.job.grade.level == 4 and data.job.onduty == true)
    check('qb setJob: no such grade', not p.setJob(1, 'police', 2) and data.job.grade.level == 4)
    check('qb setOfflineJob: offline, then saved', p.setOfflineJob('XYZ789', 'police', 1) and offline.job.grade.level == 1 and savedOffline == 1)
    check('qb setOfflineJob: no such character', not p.setOfflineJob('NOPE00', 'police', 1))

    local asked
    TR.db.query = function(query, params)
        asked = params[1]
        return {
            { citizenid = 'ABC123', charinfo = '{"firstname":"John","lastname":"Doe"}', job = '{"name":"police","grade":{"name":"Recruit","level":0}}' },
            { citizenid = 'XYZ789', charinfo = '{"firstname":"Sam","lastname":"Lee"}', job = '{"name":"police","grade":{"name":"Officer","level":1}}' },
            { citizenid = 'EMS001', charinfo = '{"firstname":"Ana","lastname":"Cruz"}', job = '{"name":"ems","grade":{"name":"police","level":0}}' },
        }
    end
    local staff = p.getEmployees('police')
    check('qb getEmployees: the job decoded, online as they are now', #staff == 2 and asked == '%police%'
        and staff[1].source == 1 and staff[1].grade == 4 and staff[1].onDuty == true
        and staff[2].identifier == 'XYZ789' and staff[2].name == 'Sam Lee' and staff[2].grade == 1 and staff[2].source == nil)

    check('qb removeJob offline', p.removeJob('XYZ789', 'police') and offline.job.name == 'unemployed' and savedOffline == 2)
    check('qb removeJob offline: someone who moved on keeps their job', not p.removeJob('XYZ789', 'police') and savedOffline == 2)
    check('qb removeJob online', p.removeJob('ABC123', 'police') and data.job.name == 'unemployed')

    data.charinfo.gender, data.charinfo.phone = 1, '5550142'
    data.metadata = { licences = { driver = true, weapon = false } }
    local queries = {}
    TR.db.query = function(query, params)
        queries[#queries + 1] = { query, params }
        if query:find('FROM players', 1, true) then
            return {
                { citizenid = 'Q1', charinfo = '{"firstname":"Jo","lastname":"Smith","nationality":"Doe"}' },
                { citizenid = 'XYZ789', charinfo = '{"firstname":"Sam","lastname":"Doelittle","gender":0}' },
                { citizenid = 'ABC123', charinfo = '{"firstname":"John ","lastname":"Doe","phone":"5550142","gender":1}' },
            }
        end
        return {
            { citizenid = 'ABC123', plate = ' AB12CD34 ', vehicle = 'sultan', hash = '970598228', mods = '{"color1":12}' },
            { plate = 'XY', hash = '-1', mods = '{"color1":{"r":1,"g":2,"b":3}}' },
        }
    end
    TR.db.scalar = function(query, params)
        if query:find('player_vehicles', 1, true) then return params[1] == 'AB12CD34' and 'ABC123' or nil end
        local saved = {
            charinfo = {
                XYZ789 = '{"firstname":"Sam","lastname":"Lee","birthdate":"03/12/1994","gender":0}',
                Q2 = '{"firstname":"Ana","lastname":"Cruz","birthdate":"12/25/1994","gender":"1"}',
                Q3 = '{"firstname":"Al","lastname":"Bo","birthdate":"long ago"}',
            },
            metadata = { XYZ789 = '{"licences":{"driver":false,"weapon":true}}' },
        }
        return saved[query:match('SELECT (%w+)')][params[1]]
    end

    local found = p.searchCharacters('  Doe ')
    check('qb searchCharacters: charinfo LIKE, then the fields; by last name', #found == 2 and found[1].identifier == 'ABC123'
        and found[2].lastname == 'Doelittle' and queries[1][2][1] == 'Doe' and queries[1][2][2] == '%doe%')
    found = p.searchCharacters('john doe')
    check('qb searchCharacters: every word in the JSON, "first last" in the trimmed fields', #found == 1 and found[1].identifier == 'ABC123'
        and found[1].firstname == 'John'
        and #queries[2][2] == 3 and queries[2][1]:find('AND', 1, true))
    check('qb searchCharacters: by phone and by exact citizenid', p.searchCharacters('0142')[1].identifier == 'ABC123'
        and #p.searchCharacters('xyz789') == 1)
    p.searchCharacters('a_b%')
    check('qb searchCharacters: the typed % and _ are plain', queries[#queries][2][2] == '%a\\_b\\%%')
    check('qb searchCharacters: nothing typed asks nothing', #p.searchCharacters('   ') == 0 and #queries == 5)
    local page = p.listCharacters(40, 500)
    check('qb listCharacters: the players table by the names in charinfo, a page of 100 at most', #page == 3 and page[3].identifier == 'ABC123'
        and queries[6][1]:find("'$.lastname'", 1, true) and queries[6][2][1] == 100 and queries[6][2][2] == 40)

    local john = p.getCharacter('ABC123')
    check('qb getCharacter: online as now', john.firstname == 'John' and john.birthDate == '1990-04-12' and john.sex == 'female'
        and john.phone == '5550142')
    local sam = p.getCharacter('XYZ789')
    check('qb getCharacter: offline as saved, DD/MM/YYYY', sam.lastname == 'Lee' and sam.birthDate == '1994-12-03' and sam.sex == 'male'
        and sam.phone == nil)
    check('qb getCharacter: MM/DD/YYYY when the day is over 12, gender as text', p.getCharacter('Q2').birthDate == '1994-12-25'
        and p.getCharacter('Q2').sex == 'female')
    check('qb getCharacter: a birth date that is no date comes back as stored', p.getCharacter('Q3').birthDate == 'long ago'
        and p.getCharacter('Q3').sex == nil)
    check('qb getCharacter: no such character', p.getCharacter('NOPE00') == nil and p.getCharacter('') == nil)

    local held = p.getLicences('ABC123')
    check('qb getLicences: online from the live metadata', held.driver == true and held.weapon == false)
    held = p.getLicences('XYZ789')
    check('qb getLicences: offline as saved', held.driver == false and held.weapon == true and next(p.getLicences('NOPE00')) == nil)
    check('qb setLicence: online, into the live metadata, the others kept', p.setLicence('ABC123', 'weapon', true)
        and data.metadata.licences.weapon == true and data.metadata.licences.driver == true)
    local saves = savedOffline
    check('qb setLicence: offline, then saved', p.setLicence('XYZ789', 'driver', false) and offline.metadata.licences.driver == false
        and savedOffline == saves + 1)
    check('qb setLicence: no such character, no odd names', not p.setLicence('NOPE00', 'driver', true) and not p.setLicence('ABC123', 'a.b', true))

    local cars = TR.vehicle.getOwned('ABC123')
    check('qb getOwned: plate trimmed, model name, colour index', #cars == 2 and cars[1].plate == 'AB12CD34' and cars[1].model == 'sultan'
        and cars[1].color == 12 and queries[#queries][2][1] == 'ABC123')
    check('qb getOwned: the hash without a model name, no index for a custom colour', cars[2].model == -1 and cars[2].color == nil)
    check('qb getOwner: any case, spaces ignored', TR.vehicle.getOwner(' ab12cd34 ') == 'ABC123' and TR.vehicle.getOwner('AB12 CD34') == 'ABC123'
        and TR.vehicle.getOwner('ZZ') == nil
        and TR.vehicle.getOwner('  ') == nil)
    cars = TR.vehicle.searchOwned(' ab 1_', 10, 500)
    local asked = queries[#queries]
    check('qb searchOwned: part of a plate without its spaces, LIKE characters escaped, a page', #cars == 2 and cars[1].owner == 'ABC123'
        and cars[1].plate == 'AB12CD34' and cars[1].model == 'sultan' and asked[1]:find('player_vehicles', 1, true)
        and asked[2][1] == '%ab1\\_%' and asked[2][2] == 100 and asked[2][3] == 10)
end

do
    local data = qbPlayerData()
    local player = { PlayerData = data, Functions = { SetMetaData = function(key, value) data.metadata = data.metadata or {}; data.metadata[key] = value end } }
    local money = qbMoneyFunctions(data)

    T.exports.qbx_core = {
        GetPlayer = function(_, src) return src == 1 and player or nil end,
        GetMoney = function(_, src, moneyType)
            if src ~= 1 then return false end
            return data.money[moneyType] or false
        end,
        AddMoney = function(_, src, moneyType, amount) return src == 1 and money.AddMoney(moneyType, amount) end,
        RemoveMoney = function(_, src, moneyType, amount) return src == 1 and money.RemoveMoney(moneyType, amount) end,
        GetPlayersData = function() return { data } end,
        GetPlayerByCitizenId = function(_, id) return id == data.citizenid and player or nil end,
        CreateUseableItem = function(_, item, cb) T.usable[item] = cb end,
        GetJobs = function() return { police = { label = 'Police', grades = {
            [2] = { name = 'Sergeant', payment = 100 },
            [0] = { name = 'Recruit', payment = 50 },
        } } } end,
        SetJobDuty = function(_, src, onDuty) data.job.onduty = onDuty end,
    }
    T.usable = {}

    local blackMoney, oxCalls = 120, {}
    T.exports.ox_inventory = {
        GetItemCount = function(_, src, item) return item == 'black_money' and blackMoney or 0 end,
        AddItem = function(_, src, item, count) oxCalls[#oxCalls + 1] = { 'add', item, count }; return true end,
        RemoveItem = function(_, src, item, count)
            oxCalls[#oxCalls + 1] = { 'remove', item, count }
            blackMoney = blackMoney - count
            return true
        end,
    }

    -- qbx_core `provide`s qb-core, so both can look started; Qbox must win.
    T.boot('server', { qbx_core = 'started', ['qb-core'] = 'started', ox_inventory = 'started' })
    check('qbx detected first', TR.system('framework') == 'qbx')

    testPlayerServer('qbx')

    local qbxPolice = TR.player.getJobs().police
    check('qbx getJobs', #qbxPolice.grades == 2 and qbxPolice.grades[1].grade == 0 and qbxPolice.grades[2].name == 'Sergeant')
    check('qbx setDuty', TR.player.setDuty(1, false) and data.job.onduty == false and not TR.player.setDuty(2, true))
    check('qbx setCuffed: the ishandcuffed metadata', TR.player.setCuffed(1, true) and data.metadata.ishandcuffed == true
        and not TR.player.setCuffed(2, true))
    data.metadata = { isdead = true }
    check('qbx isDowned: the isdead metadata', TR.player.isDowned(1) and not TR.player.isDowned(2))
    data.metadata = nil
    data.job.onduty = true

    check('qbx dirty money: the black_money item', TR.player.getMoney(1, 'dirty') == 120)
    check('qbx dirty pay', TR.player.removeMoney(1, 'dirty', 20) and blackMoney == 100 and oxCalls[1][2] == 'black_money')
    check('qbx dirty pay short', not TR.player.removeMoney(1, 'dirty', 500) and #oxCalls == 1)
    check('qbx dirty add', TR.player.addMoney(1, 'dirty', 5) and oxCalls[2][1] == 'add' and oxCalls[2][3] == 5)

    local used
    TR.inventory.onUse('laptop', function(src, slot) used = { src, slot } end)
    T.usable.laptop(1, { name = 'laptop', label = 'Laptop', slot = 7, count = 1, metadata = { serial = 'TR-7' }, weight = 2000 })
    check('qbx onUse: the slot and its metadata', used and used[1] == 1 and used[2].slot == 7 and used[2].metadata.serial == 'TR-7')

    local calls = {}
    T.exports.qbx_core.SetJob = function(_, id, name, grade)
        calls[#calls + 1] = { 'set', id, name, grade }
        if id == 1 then data.job = { name = name, label = 'Police', onduty = false, grade = { name = 'Sergeant', level = grade } } end
        return true
    end
    T.exports.qbx_core.RemovePlayerFromJob = function(_, id, name)
        calls[#calls + 1] = { 'remove', id, name }
        return true
    end
    TR.db.scalar = function(query, params) return params[1] == 'OFF001' and params[3] == 'police' and 1 or nil end
    TR.db.query = function(query, params)
        return params[1] == 'ems' and { { citizenid = 'ABC123', grade = 0, charinfo = '{"firstname":"John","lastname":"Doe"}' } } or {
            { citizenid = 'ABC123', grade = 2, charinfo = '{"firstname":"John","lastname":"Doe"}' },
            { citizenid = 'OFF001', grade = 0, charinfo = '{"firstname":"Sam","lastname":"Lee"}' },
        }
    end

    local p = TR.player
    check('qbx setJob: a promotion keeps duty', p.setJob(1, 'police', 2) and calls[1][2] == 1 and calls[1][4] == 2
        and data.job.grade.level == 2 and data.job.onduty == true)
    check('qbx setOfflineJob: by citizenid', p.setOfflineJob('OFF001', 'police', 0) and calls[2][2] == 'OFF001' and calls[2][3] == 'police')
    check('qbx setOfflineJob: no such grade', not p.setOfflineJob('OFF001', 'police', 1) and #calls == 2)

    local staff = p.getEmployees('police')
    check('qbx getEmployees', #staff == 2 and staff[1].source == 1 and staff[1].grade == 2 and staff[1].onDuty == true
        and staff[2].name == 'Sam Lee' and staff[2].source == nil)
    local medics = p.getEmployees('ems')
    check('qbx getEmployees: a job held besides the main one', #medics == 1 and medics[1].source == 1 and medics[1].grade == 0
        and medics[1].onDuty == false)

    check('qbx removeJob: out of the job list, online or not', p.removeJob('OFF001', 'police') and calls[3][1] == 'remove'
        and calls[3][2] == 'OFF001' and calls[3][3] == 'police')
    check('qbx removeJob: not in the job', not p.removeJob('OFF002', 'police') and #calls == 3)

    check('qbx searchCharacters: the players table, then the fields', #p.searchCharacters('lee') == 1
        and p.searchCharacters('lee')[1].identifier == 'OFF001')
    TR.db.scalar = function(query, params)
        if params[1] ~= 'OFF001' then return end
        return query:find('charinfo', 1, true) and '{"firstname":"Sam","lastname":"Lee","gender":0}' or '{"licences":{"weapon":true}}'
    end
    data.metadata = { licences = { driver = true } }
    check('qbx getCharacter: online as now, offline as saved', p.getCharacter('ABC123').firstname == 'John'
        and p.getCharacter('OFF001').sex == 'male' and p.getCharacter('OFF002') == nil)
    check('qbx getLicences: online and offline', p.getLicences('ABC123').driver == true and p.getLicences('OFF001').weapon == true)
    local metaSet, offlineSaved
    T.exports.qbx_core.SetMetadata = function(_, id, key, value) metaSet = { id, key, value } end
    T.exports.qbx_core.GetOfflinePlayer = function(_, id)
        return id == 'OFF001' and { PlayerData = { metadata = { licences = { weapon = true } } } } or nil
    end
    T.exports.qbx_core.SaveOffline = function(_, playerData) offlineSaved = playerData end
    check('qbx setLicence: online through SetMetadata, the others kept', p.setLicence('ABC123', 'weapon', true) and metaSet[1] == 'ABC123'
        and metaSet[2] == 'licences' and metaSet[3].weapon == true and metaSet[3].driver == true)
    check('qbx setLicence: offline, saved by SaveOffline', p.setLicence('OFF001', 'driver', true) and offlineSaved.metadata.licences.driver == true
        and offlineSaved.metadata.licences.weapon == true and not p.setLicence('OFF002', 'driver', true))
    data.metadata = nil

    TR.player.bridge.registerEvents()
    TriggerEvent('qbx_core:server:playerLoggedOut', 1)
    TriggerEvent('QBCore:Server:OnPlayerUnload', 1)
    check('qbx logout + unload fires once', T.count('tr:playerUnloaded') == 1)
end

do
    local job = { name = 'police', label = 'Police', grade = 1, grade_name = 'boss', grade_label = 'Chief', grade_salary = 200 }
    local xPlayer = {
        source = 1,
        getIdentifier = function() return 'char1:abc' end,
        getName = function() return 'Jane Roe' end,
        get = function(key) return ({ dateofbirth = '12/04/1990' })[key] end,
        getJob = function() return job end,
        getGroup = function() return 'admin' end,
        getAccount = function(name) return ({ money = { money = 10 }, bank = { money = 20 }, black_money = { money = 30 } })[name] end,
        -- Like ESX: without onDuty a job change goes to the default duty (on).
        setJob = function(name, grade, onDuty)
            if onDuty == nil then onDuty = true end
            job = { name = name, label = 'Police', grade = grade, grade_name = 'boss', grade_label = 'Chief', grade_salary = 200, onDuty = onDuty }
        end,
    }

    T.exports.es_extended = { getSharedObject = function() return {
        GetPlayerFromId = function(src) return src == 1 and xPlayer or nil end,
        GetExtendedPlayers = function() return { xPlayer } end,
        GetPlayerFromIdentifier = function(id) return id == 'char1:abc' and xPlayer or nil end,
        RegisterUsableItem = function(item, cb) T.usable[item] = cb end,
        GetJobs = function() return { police = { name = 'police', label = 'LSPD', grades = {
            ['1'] = { job_name = 'police', grade = 1, name = 'boss', label = 'Chief', salary = 200 },
            ['0'] = { job_name = 'police', grade = 0, name = 'recruit', label = 'Recruit', salary = 20 },
        } } } end,
    } end }
    T.usable = {}

    T.boot('server', { es_extended = 'started', ox_inventory = 'started' })
    local p = TR.player

    local used
    TR.inventory.onUse('laptop', function(src, slot) used = { src, slot } end)
    T.usable.laptop(1, 'laptop', { name = 'laptop', slot = 2, count = 1, metadata = { serial = 'TR-2' } })
    check('esx onUse: the slot and its metadata', used and used[1] == 1 and used[2].slot == 2 and used[2].metadata.serial == 'TR-2')
    used = nil
    T.usable.laptop(1, 'laptop', { name = 'laptop', slot = 3, count = 1 })
    check('esx onUse: no metadata is an empty table', used and used[2].slot == 3 and next(used[2].metadata) == nil)
    used = nil
    T.usable.laptop(1, 'laptop') -- an inventory that doesn't say which slot
    check('esx onUse: without a slot the handler is not called', used == nil)
    check('esx job boss', p.getJob(1).isBoss and p.getJob(1).gradeLabel == 'Chief')
    check('esx no gang', p.getGang(1) == nil and not p.hasGang(1, 'ballas'))
    check('esx dirty money', p.getMoney(1, 'dirty') == 30)
    check('esx admin', p.isAdmin(1))
    check('esx birth date', p.getBirthDate(1) == '12/04/1990')

    local esxPolice = p.getJobs().police
    check('esx getJobs', esxPolice.label == 'LSPD' and esxPolice.grades[1].label == 'Recruit' and esxPolice.grades[2].isBoss
        and esxPolice.grades[2].salary == 200 and not esxPolice.grades[1].isBoss)
    check('esx setDuty: an ESX without duty', not p.setDuty(1, false) and job.onDuty == nil)
    job.onDuty = true
    check('esx setDuty', p.setDuty(1, false) and job.onDuty == false and job.grade == 1)
    check('esx setDuty offline', not p.setDuty(2, true))
    check('esx setCuffed: ESX has no such flag', not p.setCuffed(1, true))
    check('esx isDowned: up', not p.isDowned(1))
    T.health = { [1] = 0 }
    check('esx isDowned: dead to the game', p.isDowned(1))
    T.health = nil
    for _, state in ipairs({ { isDead = true }, { isDead = 2 }, { dead = true }, { dead = 'laststand' } }) do
        T.bags = { [1] = state }
        check('esx isDowned: a death script\'s state bag', p.isDowned(1))
    end
    T.bags = { [1] = { isDead = false, dead = false } }
    check('esx isDowned: state bags that say up', not p.isDowned(1))
    T.bags = { [1] = { isDead = 0 } }
    check('esx isDowned: wasabi_ambulance\'s death state 0 is up', not p.isDowned(1))
    T.bags = nil

    local sql = {}
    TR.db.update = function(query, params)
        sql[#sql + 1] = { query, params }
        return params[3] == 'char2:def' and 1 or 0
    end
    TR.db.query = function(query, params)
        sql[#sql + 1] = { query, params }
        return {
            { identifier = 'char1:abc', firstname = 'Jane', lastname = 'Roe', job_grade = 0 },
            { identifier = 'char2:def', firstname = 'Sam', lastname = 'Lee', job_grade = 1 },
        }
    end

    job.onDuty = false
    check('esx setJob: a promotion keeps duty', p.setJob(1, 'police', 0) and job.grade == 0 and job.onDuty == false)
    check('esx setJob: no such grade or job', not p.setJob(1, 'police', 7) and not p.setJob(1, 'nope', 0) and not p.setJob(1, 'police', 0.5)
        and job.grade == 0)
    check('esx setJob: player not online', not p.setJob(2, 'police', 1))
    check('esx setOfflineJob: someone online goes through setJob', p.setOfflineJob('char1:abc', 'police', 1) and job.grade == 1
        and job.onDuty == false and #sql == 0)
    check('esx setOfflineJob: the users table', p.setOfflineJob('char2:def', 'police', 0) and sql[1][1]:find('UPDATE users', 1, true)
        and sql[1][2][1] == 'police' and sql[1][2][2] == 0 and sql[1][2][3] == 'char2:def')
    check('esx setOfflineJob: no such character', not p.setOfflineJob('char9:zzz', 'police', 0))
    check('esx setOfflineJob: no such grade, nothing written', not p.setOfflineJob('char2:def', 'police', 3) and #sql == 2)

    sql = {}
    check('esx removeJob offline: only while they still have the job', p.removeJob('char2:def', 'police')
        and sql[1][2][1] == 'unemployed' and sql[1][2][2] == 0 and sql[1][2][4] == 'police' and sql[1][1]:find('AND job = ?', 1, true))

    local staff = p.getEmployees('police')
    check('esx getEmployees: online as they are now, offline as saved', #staff == 2 and staff[1].source == 1 and staff[1].grade == 1
        and staff[1].name == 'Jane Roe' and staff[1].onDuty == false and staff[2].identifier == 'char2:def'
        and staff[2].name == 'Sam Lee' and staff[2].grade == 1 and staff[2].source == nil and sql[#sql][2][1] == 'police')

    check('esx removeJob online', p.removeJob('char1:abc', 'police') and job.name == 'unemployed' and job.grade == 0)
    check('esx removeJob: not in that job', not p.removeJob('char1:abc', 'police'))
    staff = p.getEmployees('police')
    check('esx getEmployees: someone online who left since the last save is gone', #staff == 1 and staff[1].identifier == 'char2:def')

    p.bridge.registerEvents()
    TriggerEvent('esx:playerDropped', 1)
    T.fromClient(1, 'playerDropped')
    check('esx drop fires once', T.count('tr:playerUnloaded') == 1)
end

do
    local schema, sql = {}, {}
    local function boot(present)
        T.exports.es_extended = { getSharedObject = function() return {
            GetPlayerFromId = function() end,
            GetExtendedPlayers = function() return {} end,
            GetPlayerFromIdentifier = function() end,
        } end }
        T.boot('server', { es_extended = 'started', ox_inventory = 'started' })
        schema, sql = present, {}
        TR.db.scalar = function(query, params)
            sql[#sql + 1] = { query, params }
            if query:find('information_schema', 1, true) then return schema[params[1] .. '.' .. (params[2] or '')] end
            if query:find('FROM users', 1, true) then return params[1] == 'char1:abc' and 1 or nil end
            return params[1] == 'AB12CD34' and 'char1:abc' or nil
        end
        TR.db.single = function(query, params)
            sql[#sql + 1] = { query, params }
            return ({
                ['char1:abc'] = { identifier = 'char1:abc', firstname = 'Marcus', lastname = 'Reyes', dateofbirth = '12/03/1994', sex = 'm', phone_number = '555-0142' },
                ['char2:def'] = { identifier = 'char2:def', firstname = 'Ana', lastname = 'Cruz', dateofbirth = '03/25/1994', sex = 'f' },
                ['char3:ghi'] = { identifier = 'char3:ghi' },
            })[params[1]]
        end
        TR.db.query = function(query, params)
            sql[#sql + 1] = { query, params }
            if query:find('FROM users', 1, true) then
                return { { identifier = 'char1:abc', firstname = 'Marcus ', lastname = 'Reyes', dateofbirth = '1994/03/12', sex = 'M', phone_number = '' } }
            end
            if query:find('user_licenses', 1, true) then return { { type = 'drive' }, { type = 'weapon' } } end
            return { { owner = 'char1:abc', plate = 'AB12CD34 ', vehicle = '{"model":-1930048799,"color1":12.0}' }, { plate = ' XY ', vehicle = 'oops' } }
        end
    end

    boot({ ['users.phone_number'] = 1, ['user_licenses.'] = 1 })
    local p = TR.player

    local found = p.searchCharacters('Reyes', 500)
    local asked = sql[#sql]
    check('esx searchCharacters: users by name, "first last", phone or identifier', #found == 1 and found[1].identifier == 'char1:abc'
        and found[1].birthDate == '1994-03-12' and found[1].sex == 'male' and found[1].phone == nil
        and asked[1]:find('phone_number LIKE ?', 1, true) and asked[1]:find('CONCAT_WS', 1, true) and asked[2][1] == 'Reyes'
        and asked[2][2] == '%reyes%' and #asked[2] == 6 and asked[2][6] == 50)
    p.searchCharacters('x', 0)
    check('esx searchCharacters: at least one', sql[#sql][2][6] == 1)
    p.searchCharacters(' Marcus   Reyes ')
    check('esx searchCharacters: "first last" from trimmed names, the typed spaces as one', sql[#sql][2][4] == '%marcus reyes%'
        and sql[#sql][1]:find("CONCAT_WS(' ', TRIM(firstname), TRIM(lastname))", 1, true))
    local everyone = p.listCharacters()
    check('esx listCharacters: users with an identity by name, 50 from the start', everyone[1].firstname == 'Marcus'
        and sql[#sql][1]:find("firstname <> ''", 1, true) and sql[#sql][1]:find('ORDER BY LOWER(lastname)', 1, true)
        and sql[#sql][2][1] == 50 and sql[#sql][2][2] == 0)
    p.listCharacters(-5, 0)
    check('esx listCharacters: from the start, at least one', sql[#sql][2][1] == 1 and sql[#sql][2][2] == 0)

    local marcus = p.getCharacter('char1:abc')
    check('esx getCharacter: DD/MM/YYYY, esx_identity\'s default', marcus.firstname == 'Marcus' and marcus.birthDate == '1994-03-12'
        and marcus.sex == 'male' and marcus.phone == '555-0142' and sql[#sql][1]:find('phone_number', 1, true))
    local ana = p.getCharacter('char2:def')
    check('esx getCharacter: MM/DD/YYYY when the day is over 12', ana.birthDate == '1994-03-25' and ana.sex == 'female' and ana.phone == nil)
    local blank = p.getCharacter('char3:ghi')
    check('esx getCharacter: a character without an identity yet', blank.firstname == '' and blank.lastname == '' and blank.birthDate == nil
        and blank.sex == nil)
    check('esx getCharacter: no such character', p.getCharacter('char9:zzz') == nil)

    local held = p.getLicences('char1:abc')
    check('esx getLicences: esx_license types, drive as driver', held.driver == true and held.weapon == true and held.drive == nil)
    local wrote = {}
    TR.db.update = function(query, params) wrote[#wrote + 1] = { query, params } return 1 end
    TR.db.insert = function(query, params) wrote[#wrote + 1] = { query, params } return 1 end
    check('esx setLicence: driver kept as drive, taken then given', p.setLicence('char1:abc', 'driver', true) and #wrote == 2
        and wrote[1][1]:find('DELETE FROM user_licenses', 1, true) and wrote[1][2][1] == 'drive' and wrote[2][1]:find('INSERT', 1, true)
        and wrote[2][2][1] == 'drive' and wrote[2][2][2] == 'char1:abc')
    check('esx setLicence: taken away only', p.setLicence('char1:abc', 'weapon', false) and #wrote == 3 and wrote[3][2][1] == 'weapon')
    check('esx setLicence: no such character', not p.setLicence('char9:zzz', 'weapon', true) and #wrote == 3)

    local cars = TR.vehicle.getOwned('char1:abc')
    check('esx getOwned: owned_vehicles, the model hash and colour from the properties', #cars == 2 and cars[1].plate == 'AB12CD34'
        and cars[1].model == -1930048799 and math.type(cars[1].model) == 'integer' and cars[1].color == 12
        and cars[2].plate == 'XY' and cars[2].model == nil)
    check('esx getOwner: any case, spaces ignored', TR.vehicle.getOwner(' ab12 cd34 ') == 'char1:abc' and sql[#sql][2][1] == 'AB12CD34'
        and sql[#sql][1]:find("REPLACE(plate, ' ', '')", 1, true)
        and TR.vehicle.getOwner('ZZ') == nil)
    cars = TR.vehicle.searchOwned()
    check('esx searchOwned: every owned car without a text, 50 at a time', #cars == 2 and cars[1].owner == 'char1:abc'
        and cars[1].model == -1930048799 and sql[#sql][1]:find('FROM owned_vehicles', 1, true) and sql[#sql][2][1] == '%%'
        and sql[#sql][2][2] == 50 and sql[#sql][2][3] == 0)

    local looked = 0
    for _, entry in ipairs(sql) do
        if entry[1]:find('information_schema', 1, true) then looked = looked + 1 end
    end
    check('esx: the schema is looked up once per table or column', looked == 2)

    boot({})
    p = TR.player
    p.searchCharacters('Reyes')
    check('esx searchCharacters: no phone_number column', not sql[#sql][1]:find('phone_number', 1, true) and #sql[#sql][2] == 5)
    check('esx getCharacter: no phone_number column', p.getCharacter('char1:abc').firstname == 'Marcus'
        and not sql[#sql][1]:find('phone_number', 1, true))
    local before = #sql
    check('esx getLicences: no user_licenses table', next(p.getLicences('char1:abc')) == nil and not sql[#sql][1]:find('user_licenses', 1, true)
        and #sql == before + 1)
end

do
    local data = qbPlayerData()
    mockQBCore(data)
    LocalPlayer.state.isLoggedIn = true

    T.boot('client', { ['qb-core'] = 'started', ['qb-inventory'] = 'started', ['qb-target'] = 'started' }, nil, { target = 'qb_target' })
    local p = TR.player
    check('qb client job', p.getJob().grade == 2 and p.hasJob('police'))
    check('qb client gang', p.hasGang({ ballas = 3 }))
    check('qb client money', p.getMoney('bank') == 1000 and p.getMoney('dirty') == 0)
    check('qb client isDowned: up', not p.isDowned())
    data.metadata = { inlaststand = true }
    check('qb client isDowned: in last stand', p.isDowned())
    data.metadata = nil

    TR.notify.send({ title = 'Bank', description = 'Paid', type = 'warning' })
    check('qb client notify', T.lastNotify[1] == 'Bank: Paid' and T.lastNotify[2] == 'primary')

    check('qbinv client count', TR.inventory.getCount('weed') == 7 and TR.inventory.hasItem('weed', 5, { quality = 90 }))
    TR.inventory.openStash('locker')
    check('qbinv client open request', T.serverEvents[1].name == 'tr_example:tr_openStash')
    TR.inventory.setBusy(true)
    check('qbinv client setBusy: nothing, qb-inventory goes by ishandcuffed', LocalPlayer.state.invBusy == nil)
    check('qbinv client image: qb-inventory\'s images folder', TR.inventory.getImage('Water') == 'nui://qb-inventory/html/images/water_bottle.png'
        and not TR.inventory.getImage('weed') and TR.inventory.getImage('nothing') == nil)

    p.bridge.registerEvents()
    TriggerEvent('QBCore:Client:OnPlayerLoaded')
    check('qb client no duplicate load', T.count('tr:playerLoaded') == 0)
    TriggerEvent('QBCore:Client:SetDuty', false)
    check('qb client duty', T.count('tr:jobUpdated') == 1 and T.fired['tr:jobUpdated'][1][1].onDuty == false)

    local calls = {}
    T.exports['qb-target'] = setmetatable({}, { __index = function(_, name)
        return function(_, ...) calls[#calls + 1] = { name = name, args = table.pack(...) } end
    end })

    local selected
    local zone = TR.target.addBoxZone({
        coords = vector3(10, 20, 30), size = vector3(2, 4, 6), rotation = 90,
        options = {
            { name = 'tr_example:open', label = 'Open', icon = 'fa-solid fa-box', distance = 3.0,
              groups = { 'police', 'ems' }, items = { lockpick = 1 },
              onSelect = function(d) selected = d end },
        },
    })

    local box = calls[1].args
    check('qbt box zone', calls[1].name == 'AddBoxZone' and box[1] == zone and box[3] == 4 and box[4] == 2
        and box[5].heading == 90 and box[5].minZ == 27 and box[5].maxZ == 33)

    local option = box[6].options[1]
    check('qbt option converted', box[6].distance == 3.0 and option.label == 'Open'
        and option.job.police == 0 and option.job.ems == 0 and option.item[1] == 'lockpick')

    option.action(5)
    check('qbt onSelect', selected and selected.entity == 5 and selected.name == 'tr_example:open')

    TR.target.addModel('prop_atm_01', { { name = 'tr_example:atm', label = 'Use ATM', serverEvent = 'tr_example:atm' } })
    check('qbt model server event', calls[2].name == 'AddTargetModel' and calls[2].args[2].options[1].type == 'server')

    TR.target.removeModel('prop_atm_01', 'tr_example:atm')
    check('qbt remove by name -> label', calls[3].name == 'RemoveTargetModel' and calls[3].args[2] == 'Use ATM')

    TR.target.addEntity(7, { label = 'Talk', event = 'tr_example:talk' })
    check('qbt netId -> entity', calls[4].name == 'AddTargetEntity' and calls[4].args[1][1] == 1007)

    TR.target.addGlobalVehicle({ { label = 'Lock', command = 'lock' } })
    check('qbt global', calls[5].name == 'AddGlobalVehicle' and calls[5].args[1].options[1].type == 'command')

    TR.target.allow(false)
    check('qbt allow', calls[6].name == 'AllowTargeting' and calls[6].args[1] == false)

    local before = #calls
    TriggerEvent('onResourceStop', 'other_resource')
    check('qbt ignores other resource stop', #calls == before)

    TriggerEvent('onResourceStop', 'tr_example')
    local removed = {}
    for i = before + 1, #calls do removed[calls[i].name] = true end
    check('qbt cleanup on stop', removed.RemoveZone and removed.RemoveTargetModel and removed.RemoveTargetEntity and removed.RemoveGlobalVehicle)
end

do
    local data = qbPlayerData()
    T.exports.qbx_core = {
        GetPlayerData = function() return data end,
        Notify = function(_, ...) T.lastNotify = table.pack(...) end,
    }
    LocalPlayer.state.isLoggedIn = true

    T.boot('client', { qbx_core = 'started', ox_inventory = 'started', ox_target = 'started' }, nil, { target = 'ox_target' })
    check('qbx client job', TR.player.getJob().name == 'police' and TR.player.getIdentifier() == 'ABC123')

    local asked = 0
    T.exports.qbx_core.GetPlayerData = function() asked = asked + 1 return data end
    for _ = 1, 5 do TR.player.hasJob('police') end
    TR.player.getJob().grade = 99
    check('client job kept, not asked of the framework every time', asked == 0 and TR.player.getJob().grade == 2)
    TriggerEvent('tr:jobUpdated', { name = 'ambulance', grade = 1, onDuty = false })
    check('client job: a job event replaces it', TR.player.hasJob('ambulance') and not TR.player.hasJob('ambulance', true)
        and not TR.player.hasJob('police') and asked == 0)
    TriggerEvent('tr:playerLoaded')
    check('client job: asked again after a load', TR.player.hasJob('police') and asked == 1)
    TriggerEvent('tr:playerUnloaded')
    TR.player.getJob()
    check('client job: and after an unload', asked == 2)

    TR.notify.send({ title = 'Bank', description = 'Paid', type = 'info' })
    check('qbx client notify', T.lastNotify[1] == 'Bank' and T.lastNotify[2] == 'inform' and T.lastNotify[4] == 'Paid')

    TR.notify.send('Hello')
    check('qbx client notify string', T.lastNotify[1] == 'Hello' and T.lastNotify[4] == nil)

    local off
    T.exports.ox_target = { disableTargeting = function(_, value) off = value end }
    TR.target.allow(false)
    check('ox_target allow', off == true)
    TR.target.allow(true)
    check('ox_target allow again', off == false)
    T.exports.ox_target = nil
end

do
    local data, was = { dead = false }, T.exports.es_extended
    T.exports.es_extended = { getSharedObject = function() return { GetPlayerData = function() return data end } end }
    T.boot('client', { es_extended = 'started', ox_inventory = 'started', ox_target = 'started' })
    check('esx client isDowned: up', not TR.player.isDowned())
    data.dead = true
    check('esx client isDowned: ESX\'s dead flag', TR.player.isDowned())
    data.dead = false
    LocalPlayer.state.isDead = true
    check('esx client isDowned: a death script\'s state bag', TR.player.isDowned())
    LocalPlayer.state.isDead = nil
    T.health = { [1] = 0 }
    check('esx client isDowned: dead to the game', TR.player.isDowned())
    T.health = nil
    T.exports.es_extended = was
end

do
    GetVehicleNumberPlateText = function() return ' TR 123 ' end

    T.boot('server', { es_extended = 'started', ox_inventory = 'started' })
    check('keys falls back to none', TR.system('keys') == 'none')
    check('keys none: everyone has keys', TR.keys.hasKeys(1, 5000) == true)
    check('keys plate trimmed', TR.keys.plate(5000) == 'TR 123')
    TR.keys.giveKeys(1, 5000)
    check('keys missing vehicle', TR.keys.hasKeys(1, 0) == false)

    T.boot('client', { es_extended = 'started', ox_inventory = 'started', ox_target = 'started' })
    check('keys client none', TR.keys.hasKeys(5000) == true)
end

do
    GetVehicleNumberPlateText = function(vehicle) return vehicle == 5000 and ' TR 123 ' or 'OTHER' end

    -- [1] resource, [2] provider, [3] client has, [4] server has, [5] give, [6] remove,
    -- [7] true when the script takes the vehicle entity instead of the plate.
    local scripts = {
        { 'zyke_vehiclekeys', 'zyke_vehiclekeys', 'HasKey', 'HasKey', 'GiveKey', 'RemoveKey' },
        { 'qbx_vehiclekeys', 'qbx_vehiclekeys', 'HasKeys', 'HasKeys', 'GiveKeys', 'RemoveKeys', true },
        { 'wasabi_carlock', 'wasabi_carlock', 'HasKey', 'HasKey', 'GiveKey', 'RemoveKey' },
        { 'MrNewbVehicleKeys', 'mrnewb_vehiclekeys', 'HasKeysByPlate', 'HasKeysByPlate', 'GiveKeysByPlate', 'RemoveKeysByPlate' },
        { 'Renewed-Vehiclekeys', 'renewed_vehiclekeys', 'hasKey', 'hasKey', 'addKey', 'removeKey' },
        { 'qb-vehiclekeys', 'qb_vehiclekeys', 'HasKeys', 'HasKeys', 'GiveKeys', 'RemoveKeys' },
    }

    for _, s in ipairs(scripts) do
        local resource, provider, clientHas, serverHas, give, remove, byEntity = table.unpack(s)
        local target = byEntity and 5000 or 'TR 123'
        local calls = {}

        local function mock(context)
            local fns = {}
            fns[context == 'client' and clientHas or serverHas] = function(_, ...)
                local args = { ... }
                local key = context == 'client' and args[1] or args[2]
                return key == target
            end
            fns[give] = function(_, ...) calls[#calls + 1] = { give, ... } end
            fns[remove] = function(_, ...) calls[#calls + 1] = { remove, ... } end
            T.exports[resource] = fns
        end

        mock('server')
        T.boot('server', { es_extended = 'started', ox_inventory = 'started', [resource] = 'started', ['qb-vehiclekeys'] = 'stopped' })
        check(provider .. ' detected', TR.system('keys') == provider)
        check(provider .. ' server has keys', TR.keys.hasKeys(1, 5000) == true and TR.keys.hasKeys(1, 5001) == false)

        TR.keys.giveKeys(1, 5000)
        TR.keys.removeKeys(1, 5000)
        check(provider .. ' give', calls[1] and calls[1][1] == give and calls[1][2] == 1 and calls[1][3] == target)
        check(provider .. ' remove', calls[2] and calls[2][1] == remove and calls[2][2] == 1 and calls[2][3] == target)

        mock('client')
        T.boot('client', { es_extended = 'started', ox_inventory = 'started', ox_target = 'started', [resource] = 'started' })
        check(provider .. ' client has keys', TR.keys.hasKeys(5000) == true and TR.keys.hasKeys(5001) == false)
        T.exports[resource] = nil
    end

    T.boot('server', { es_extended = 'started', ox_inventory = 'started', ['qb-vehiclekeys'] = 'started' }, nil, { keys = 'wasabi_carlock' })
    check('keys set in config.lua', TR.system('keys') == 'wasabi_carlock')
end

do
    local inventory = { [3] = { slot = 3, name = 'WEAPON_PETROLCAN', count = 1, metadata = { durability = 40, ammo = 40 } },
        [1] = { slot = 1, name = 'WEAPON_PETROLCAN', count = 1 } }
    T.exports.ox_inventory = {
        Search = function(_, src, kind, item)
            local found = {}
            for _, data in pairs(inventory) do if kind == 'slots' and data.name == item then found[#found + 1] = data end end
            return found
        end,
        GetSlot = function(_, src, slot) return inventory[slot] end,
        GetInventoryItems = function(_, src) return inventory end,
        SetMetadata = function(_, src, slot, metadata) inventory[slot].metadata = metadata end,
    }
    inventory[2] = { slot = 2, name = 'water', count = 3 }
    T.boot('server', { es_extended = 'started', ox_inventory = 'started' })
    local all = TR.inventory.getSlots(1)
    check('ox getSlots without an item: every slot, with its name', #all == 3 and all[2].name == 'water' and all[2].count == 3 and all[3].name == 'WEAPON_PETROLCAN')
    inventory[2] = nil
    local cans = TR.inventory.getSlots(1, 'WEAPON_PETROLCAN')
    check('ox getSlots in slot order', #cans == 2 and cans[1].slot == 1 and cans[2].metadata.durability == 40)
    check('ox getSlots no metadata', next(cans[1].metadata) == nil)
    check('ox setMetadata', TR.inventory.setMetadata(1, 3, { durability = 90, ammo = 90 }) and inventory[3].metadata.ammo == 90)
    check('ox setMetadata empty slot', TR.inventory.setMetadata(1, 7, {}) == false)
    T.exports.ox_inventory = nil
end

do
    local opened, threads = {}, {}
    T.exports.ox_inventory = {
        forceOpenInventory = function(_, src, kind, target)
            opened[#opened + 1] = { src, kind, target }
            if target == 3 then return nil end -- someone else has it open
            TriggerEvent('ox_inventory:openedInventory', src, target)
            return target
        end,
    }
    T.boot('server', { es_extended = 'started', ox_inventory = 'started' })
    local createThread, wait = CreateThread, Wait
    CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end
    Wait = function() coroutine.yield() end
    local function step()
        for _, co in ipairs(threads) do if coroutine.status(co) ~= 'dead' then coroutine.resume(co) end end
    end
    local function watching() return coroutine.status(threads[#threads]) ~= 'dead' end
    T.coords = { [1] = vector3(0, 0, 0), [2] = vector3(1, 0, 0), [3] = vector3(1, 0, 0), [4] = vector3(9, 0, 0) }
    local inv = TR.inventory
    check('ox openPlayer: too far or their own, not asked', not inv.openPlayer(1, 4) and not inv.openPlayer(1, 1) and #opened == 0)
    check('ox openPlayer: someone else has it open', not inv.openPlayer(1, 3) and #threads == 0)
    check('ox openPlayer', inv.openPlayer(1, 2) and opened[2][1] == 1 and opened[2][2] == 'player' and opened[2][3] == 2)
    step()
    check('ox openPlayer: open while they are near', watching())
    T.coords[2] = vector3(5, 0, 0)
    local sent = #T.clientEvents
    step()
    check('ox openPlayer: closed once they are apart', not watching() and #T.clientEvents == sent + 1
        and T.clientEvents[sent + 1].name == 'ox_inventory:closeInventory' and T.clientEvents[sent + 1].target == 1)
    T.coords[2] = vector3(1, 0, 0)
    inv.openPlayer(1, 2)
    step()
    TriggerEvent('ox_inventory:closedInventory', 1, 2)
    sent = #T.clientEvents
    step()
    check('ox openPlayer: closed by the player, the watch ends', not watching() and #T.clientEvents == sent)
    CreateThread, Wait, T.coords, T.exports.ox_inventory = createThread, wait, nil, nil
end

do
    local bags, native = {}, {}
    Entity = function(vehicle)
        bags[vehicle] = bags[vehicle] or {}
        local state = setmetatable({}, { __index = bags[vehicle] })
        function state:set(key, value, replicate) bags[vehicle][key] = value; bags[vehicle].__replicated = replicate end
        return { state = state }
    end
    GetVehicleFuelLevel = function(vehicle) return native[vehicle] or 65.0 end
    SetVehicleFuelLevel = function(vehicle, value) native[vehicle] = value end
    NetworkGetEntityOwner = function(vehicle) return vehicle == 5000 and 7 or -1 end
    NetworkGetNetworkIdFromEntity = function(vehicle) return vehicle - 1000 end
    NetworkDoesEntityExistWithNetworkId = function(id) return id > 0 end

    T.boot('server', { es_extended = 'started', ox_inventory = 'started' })
    check('fuel falls back to none', TR.system('fuel') == 'none')
    check('fuel none starts full', TR.fuel.get(5000) == 100.0)
    check('fuel none take', TR.fuel.take(5000, 30) == 30.0 and TR.fuel.get(5000) == 70.0)
    check('fuel none replicated', bags[5000].__replicated == true)
    check('fuel take stops at empty', TR.fuel.take(5000, 500) == 70.0 and TR.fuel.get(5000) == 0.0)
    check('fuel take from empty', TR.fuel.take(5000, 5) == 0.0)
    check('fuel set clamps', TR.fuel.set(5000, 150) and TR.fuel.get(5000) == 100.0)
    check('fuel set rejects junk', TR.fuel.set(5000, 'lots') == false and TR.fuel.get(5000) == 100.0)
    check('fuel missing vehicle', TR.fuel.get(0) == nil and TR.fuel.set(0, 10) == false and TR.fuel.take(0, 10) == 0.0)

    T.boot('client', { es_extended = 'started', ox_inventory = 'started', ox_target = 'started' })
    bags[5002] = nil
    check('fuel client none starts full', TR.fuel.get(5002) == 100.0)
    TR.fuel.set(5002, 42)
    check('fuel client none sets bag and car', bags[5002].fuel == 42.0 and native[5002] == 42.0)

    bags = {}
    T.boot('server', { es_extended = 'started', ox_inventory = 'started', ox_fuel = 'started' })
    check('ox_fuel detected', TR.system('fuel') == 'ox_fuel')
    rawset(TR, 'callback', mockCallback { await = function(name, src, netId) return src == 7 and 65.0 or nil end })
    check('ox_fuel server unset asks the owner', TR.fuel.get(5000) == 65.0 and TR.fuel.get(5001) == nil)
    check('ox_fuel server set', TR.fuel.set(5000, 55.5) and bags[5000].fuel == 55.5)
    check('ox_fuel server take', TR.fuel.take(5000, 5.5) == 5.5 and bags[5000].fuel == 50.0)
    T.boot('client', { es_extended = 'started', ox_inventory = 'started', ox_target = 'started', ox_fuel = 'started' })
    check('ox_fuel client reads bag', TR.fuel.get(5000) == 50.0)
    check('ox_fuel client unset reads car', TR.fuel.get(5003) == 65.0)

    local scripts = {
        { 'lc_fuel', 'lc_fuel' }, { 'cdn-fuel', 'cdn_fuel' }, { 'ps-fuel', 'ps_fuel' }, { 'LegacyFuel', 'legacyfuel' },
    }
    for _, s in ipairs(scripts) do
        local resource, provider = s[1], s[2]
        local levels = { [5000] = 80.0 }
        T.exports[resource] = {
            GetFuel = function(_, vehicle) return levels[vehicle] end,
            SetFuel = function(_, vehicle, value) levels[vehicle] = value end,
        }

        local started = { es_extended = 'started', ox_inventory = 'started', [resource] = 'started' }
        if resource == 'lc_fuel' then started.LegacyFuel = 'started' end   -- lc_fuel provides LegacyFuel
        T.boot('client', setmetatable({ ox_target = 'started' }, { __index = started }))
        for k, v in pairs(started) do T.resources[k] = v end
        check(provider .. ' detected', TR.system('fuel') == provider)
        check(provider .. ' client get', TR.fuel.get(5000) == 80.0)
        TR.fuel.set(5000, 60)
        check(provider .. ' client set', levels[5000] == 60.0)

        T.boot('server', started)
        local asked
        rawset(TR, 'callback', mockCallback { await = function(name, src, netId)
            asked = { name, src, netId }
            return levels[netId + 1000]
        end })
        check(provider .. ' server asks the owner', TR.fuel.get(5000) == 60.0 and asked[1] == 'tr_core:fuel:get' and asked[2] == 7 and asked[3] == 4000)
        check(provider .. ' server take', TR.fuel.take(5000, 10) == 10.0)
        local sent = T.clientEvents[#T.clientEvents]
        check(provider .. ' server set goes to the owner', sent.name == 'tr_core:fuel:set' and sent.target == 7 and sent.args[1] == 4000 and sent.args[2] == 50.0)
        check(provider .. ' server no owner', TR.fuel.get(5001) == nil and TR.fuel.set(5001, 10) == false)
        T.exports[resource] = nil
    end

    T.boot('server', { es_extended = 'started', ox_inventory = 'started', ox_fuel = 'started' }, nil, { fuel = 'legacyfuel' })
    check('fuel set in config.lua', TR.system('fuel') == 'legacyfuel')
end

do
    -- 1: police on duty, 2: police off duty, 3: mechanic on duty
    local jobs = { { 'police', true }, { 'police', false }, { 'mechanic', true } }
    local asked
    local function boot(started, config)
        local resources = { es_extended = 'started', ox_inventory = 'started' }
        for name, state in pairs(started) do resources[name] = state end
        T.boot('server', resources, nil, config)
        rawset(TR, 'player', {
            getPlayers = function() return { 1, 2, 3 } end,
            hasJob = function(src, filter, requireDuty)
                if requireDuty and not jobs[src][2] then return false end
                for _, job in ipairs(filter) do if job == jobs[src][1] then return true end end
                return false
            end,
        })
        asked = nil
        rawset(TR, 'callback', mockCallback { await = function(name, src, coords)
            asked = { name, src, coords }
            return '<img src=x onerror=alert(1)>Alta St / Route 68'
        end })
    end
    local function alert(extra)
        local a = { coords = vector3(10, 20, 30), title = 'Suspicious activity', message = 'A laptop online', code = '10-90', name = 'tr_test', source = 1 }
        for k, v in pairs(extra or {}) do a[k] = v end
        return a
    end
    local function fired(name) local list = T.fired[name]; return list and list[#list][1] end

    boot({})
    check('dispatch falls back to none', TR.system('dispatch') == 'none')
    TR.dispatch.alert(alert())
    local sent = T.clientEvents
    check('none: only on-duty police', #sent == 1 and sent[1].name == 'tr_core:dispatch' and sent[1].target == 1)
    local payload = sent[1].args[1]
    check('none: street asked from the player', asked[1] == 'tr_core:dispatch:street' and asked[2] == 1 and asked[3] == vector3(10, 20, 30))
    check('none: street cleaned of markup', not payload.message:find('[<>=()]') and payload.message:find('Alta St / Route 68', 1, true) ~= nil)
    check('none: code before the title', payload.title == '10-90 - Suspicious activity' and payload.message:sub(1, 18) == 'A laptop online - ')
    check('none: blip defaults', payload.blip.sprite == 161 and payload.blip.color == 1 and payload.blip.radius == 0 and payload.blip.flash == false and payload.time == 5)

    T.clientEvents, asked = {}, nil
    TR.dispatch.alert(alert({ street = 'Vinewood Blvd', priority = 'high', jobs = 'mechanic', code = false, blip = { sprite = 52 } }))
    payload = T.clientEvents[1] and T.clientEvents[1].args[1]
    check('none: a given street is not asked for', asked == nil and payload.message == 'A laptop online - Vinewood Blvd')
    check('none: one job as a string', #T.clientEvents == 1 and T.clientEvents[1].target == 3)
    check('none: high priority flashes, own sprite', payload.blip.flash == true and payload.blip.sprite == 52)

    T.clientEvents, asked = {}, nil
    TR.dispatch.alert(alert({ source = false, code = false, message = false }))
    payload = T.clientEvents[1].args[1]
    check('none: no source, no street', asked == nil and payload.title == 'Suspicious activity' and payload.message == '')
    check('dispatch needs coords and a title', not pcall(TR.dispatch.alert, { title = 'x' }) and not pcall(TR.dispatch.alert, { coords = vector3(0, 0, 0) }))

    local metadata = GetResourceMetadata
    local psVersion = '2.2.2'
    GetResourceMetadata = function(resource, key)
        if resource == 'ps-dispatch' and key == 'version' then return psVersion end
        return metadata(resource, key)
    end
    boot({ ['ps-dispatch'] = 'started' })
    TR.dispatch.alert(alert({ street = 'Alta St' }))
    local data = fired('ps-dispatch:server:notify')
    check('ps 2: notify event', TR.system('dispatch') == 'ps_dispatch' and data ~= nil)
    check('ps 2: title, details, code', data.message == 'Suspicious activity' and data.information == 'A laptop online' and data.code == '10-90'
        and data.codeName == 'tr_test' and data.street == 'Alta St')
    check('ps 2: jobs, priority, blip', data.jobs[1] == 'police' and data.priority == 2 and data.alert.length == 5 and data.alert.sprite == 161
        and data.alert.sound == 'Lose_1st')

    psVersion = '3.0.0'
    local targeted
    T.exports['ps-dispatch'] = { SendTargetedAlert = function(_, targets, d) targeted = { targets, d } end }
    boot({ ['ps-dispatch'] = 'started' })
    TR.dispatch.alert(alert({ priority = 'high' }))
    check('ps 3: targeted at the job', targeted and #targeted[1] == 2 and targeted[1][1] == 1 and targeted[1][2] == 2 and T.count('ps-dispatch:server:notify') == 0)
    check('ps 3: listed, red', targeted[2].addToList == true and targeted[2].priority == 1 and targeted[2].alert.flash == true)
    targeted = nil
    TR.dispatch.alert(alert({ jobs = { 'ambulance' } }))
    check('ps 3: nobody with the job, nothing sent', targeted == nil)
    GetResourceMetadata = metadata
    T.exports['ps-dispatch'] = nil

    boot({ cd_dispatch = 'started' })
    TR.dispatch.alert(alert({ street = 'Alta St' }))
    sent = T.clientEvents
    data = sent[1] and sent[1].args[1]
    check('cd: to the job', #sent == 2 and sent[1].name == 'cd_dispatch:AddNotification' and sent[1].target == 1 and sent[2].target == 2)
    check('cd: shape', data.job_table[1] == 'police' and data.title == '10-90 - Suspicious activity' and data.message == 'A laptop online - Alta St'
        and data.flash == 0 and type(data.unique_id) == 'string' and data.blip.time == 5 and data.blip.colour == 1)

    boot({ cd_dispatch3d = 'started', cd_dispatch = 'started' })
    TR.dispatch.alert(alert({ street = 'Alta St' }))
    data = fired('cd_dispatch:AddNotification')
    check('cd3d: detected first', TR.system('dispatch') == 'cd_dispatch3d')
    check('cd3d: server event', data and data.title == '10-90 - Suspicious activity' and #T.clientEvents == 0)

    boot({ ['qs-dispatch'] = 'started' })
    TR.dispatch.alert(alert({ street = 'Alta St', time = 2 }))
    data = fired('qs-dispatch:server:CreateDispatchCall')
    check('qs: shape', data and data.job[1] == 'police' and data.callLocation == vector3(10, 20, 30) and data.callCode.code == '10-90'
        and data.callCode.snippet == 'Suspicious activity' and data.message == 'A laptop online - Alta St' and data.blip.time == 120000)

    boot({ rcore_dispatch = 'started' })
    TR.dispatch.alert(alert({ street = 'Alta St', priority = 'low' }))
    data = fired('rcore_dispatch:server:sendAlert')
    check('rcore: shape', data and data.code == '10-90' and data.default_priority == 'low' and data.type == 'alerts' and data.blip_time == 300
        and data.text == 'Suspicious activity - A laptop online - Alta St' and data.job[1] == 'police')

    local core
    T.exports.core_dispatch = { sendAlert = function(_, d) core = d end }
    boot({ core_dispatch = 'started' })
    TR.dispatch.alert(alert({ street = 'Alta St', priority = 'high' }))
    check('core: shape', core and core.message == 'Suspicious activity' and core.code == '10-90' and core.priority == true and core.blip == 161
        and #core.extraInfo == 2 and core.extraInfo[2].info == 'Alta St')
    T.exports.core_dispatch = nil

    local tablet = {}
    T.exports['lb-tablet'] = { AddDispatch = function(_, d) tablet[#tablet + 1] = d end }
    boot({ ['lb-tablet'] = 'started' })
    TR.dispatch.alert(alert({ street = 'Alta St', jobs = { 'police', 'sheriff' }, blip = { radius = 80 } }))
    check('lb-tablet: once per job', #tablet == 2 and tablet[1].job == 'police' and tablet[2].job == 'sheriff')
    check('lb-tablet: shape', tablet[1].time == 300 and tablet[1].location.label == 'Alta St' and tablet[1].location.coords.x == 10
        and tablet[1].priority == 'medium' and tablet[1].blip.type == 'radius' and tablet[1].blip.radius == 80)
    T.exports['lb-tablet'] = nil

    local tk
    T.exports.tk_dispatch = { addCall = function(_, d) tk = d end }
    boot({ tk_dispatch = 'started', ['ps-dispatch'] = 'started', ['qs-dispatch'] = 'started', cd_dispatch = 'started' })
    TR.dispatch.alert(alert({ street = 'Alta St' }))
    check('tk: detected over what it provides', TR.system('dispatch') == 'tk_dispatch')
    check('tk: shape', tk and tk.title == 'Suspicious activity' and tk.location == 'Alta St' and tk.removeTime == 300000 and tk.jobs[1] == 'police'
        and tk.blip.radius == nil)

    T.exports.tk_dispatch = { addCall = function() error('boom') end }
    boot({ tk_dispatch = 'started' })
    check('dispatch error is caught', pcall(TR.dispatch.alert, alert()))
    check('dispatch error is logged', tostring(T.logs[#T.logs]):find('tk_dispatch', 1, true) ~= nil)
    T.exports.tk_dispatch = nil

    local origen = {}
    T.exports.origen_police = { SendAlert = function(_, d) origen[#origen + 1] = d end }
    boot({ origen_police = 'started' })
    TR.dispatch.alert(alert({ street = 'Alta St', jobs = { 'police', 'sheriff' } }))
    check('origen: once per job', #origen == 2 and origen[2].job == 'sheriff' and origen[1].type == 'GENERAL'
        and origen[1].title == '10-90 - Suspicious activity' and origen[1].message == 'A laptop online - Alta St')
    T.exports.origen_police = nil

    boot({ ['ps-dispatch'] = 'stopped', cd_dispatch = 'started' })
    check('dispatch: running over a stopped copy', TR.system('dispatch') == 'cd_dispatch')
    boot({ ['ps-dispatch'] = 'stopped' })
    check('dispatch: installed but not started yet', TR.system('dispatch') == 'ps_dispatch')
    boot({ ['lb-tablet'] = 'started', origen_police = 'started', ['ps-dispatch'] = 'started' })
    check('dispatch: dispatch script over an MDT', TR.system('dispatch') == 'ps_dispatch')
    boot({ ['ps-dispatch'] = 'started' }, { dispatch = 'none' })
    check('dispatch set in config.lua', TR.system('dispatch') == 'none')
end

do
    local started = { es_extended = 'started', ox_inventory = 'started', ox_target = 'started' }

    T.boot('client', started)
    check('config.lua as shipped: every system found', TR.system('target') == 'ox_target' and TR.system('framework') == 'esx'
        and TR.config.locale == 'en' and TR.config.logLevel == 'info' and TR.config.accounts.dirty == 'auto')
    T.boot('client', { es_extended = 'started', ox_inventory = 'started' }, nil, { target = 'auto' })
    check('auto without a target script: tr_core\'s own', TR.system('target') == 'tr_core')

    T.boot('client', started, nil, { target = 'tr_core' })
    check('config.lua picks tr_core\'s own over ox_target', TR.system('target') == 'tr_core')
    T.boot('client', { ['qb-core'] = 'started', ['qb-inventory'] = 'started' }, nil, { target = 'qb-target', framework = 'es_extended' })
    check('config.lua takes resource names', TR.system('target') == 'qb_target' and TR.system('framework') == 'esx')
    T.boot('client', started, { ['tr:target'] = 'qb_target' }, {})
    check('convars are not read', TR.system('target') == 'ox_target')
    T.boot('client', started, nil, {})
    check('missing from config.lua: auto', TR.system('target') == 'ox_target' and TR.system('framework') == 'esx')
end

do
    local inventory, count, hooks, seen = {}, 3, {}, {}
    T.exports.ox_inventory = {
        GetInventory = function() return inventory end,
        GetItemCount = function() return count end,
        registerHook = function(_, event, fn, options) hooks[event] = { fn = fn, options = options } end,
    }
    T.boot('server', { qbx_core = 'started', ox_inventory = 'started' })
    TR.inventory.watchUse({ beer = true }, function(src, item, amount) seen[#seen + 1] = { src, item, amount } end)
    check('ox watchUse: the swap hook only for its items', hooks.swapItems.options.itemFilter.beer == true and hooks.swapItems.options.itemFilter.water == nil)

    local function use(using, left)
        seen = {}
        inventory = { usingItem = using, items = { [2] = left } }
        TriggerEvent('ox_inventory:usedItem', 1, 'beer', 2)
    end

    use({ name = 'beer', count = 3, consume = 1 }, { name = 'beer', count = 2 })
    check('ox watchUse: own route counts at once', #seen == 1 and seen[1][1] == 1 and seen[1][2] == 'beer' and seen[1][3] == 1)
    use({ name = 'beer', count = 1, consume = 0.2 }, { name = 'beer', count = 1 })
    check('ox watchUse: a sip is part of one', #seen == 1 and seen[1][3] == 0.2)
    use({ name = 'beer', count = 1, consume = 0 }, { name = 'beer', count = 1 })
    check('ox watchUse: consume 0 is one use', #seen == 1 and seen[1][3] == 1)
    use({ name = 'beer', count = 3 }, { name = 'beer', count = 2 })
    check('ox watchUse: taken from the slot already', #seen == 1 and seen[1][3] == 1)
    use({ name = 'beer', count = 1 }, nil)
    check('ox watchUse: the last one gone', #seen == 1)
    use({ name = 'beer', count = 1 }, { name = 'water', count = 1 })
    check('ox watchUse: something else in the slot', #seen == 1)
    use(nil, { name = 'beer', count = 3 })
    check('ox watchUse: nothing being used', #seen == 0)

    seen = {}
    inventory = { usingItem = { name = 'water', count = 3, consume = 1 }, items = {} }
    TriggerEvent('ox_inventory:usedItem', 1, 'water', 2)
    check('ox watchUse: other items', #seen == 0)

    local stub = Wait
    local function during(step)
        local started = T.timer
        Wait = function(ms)
            T.timer = T.timer + ms
            step(T.timer - started)
        end
    end

    count = 3
    during(function() end)
    use({ name = 'beer', count = 3 }, { name = 'beer', count = 3 })
    check('ox watchUse: a press with nothing taken is no use', #seen == 0)

    count = 3
    during(function(ms) if ms == 3000 then count = 2 end end)
    use({ name = 'beer', count = 3 }, { name = 'beer', count = 3 })
    check('ox watchUse: taken after a bar', #seen == 1 and seen[1][3] == 1)

    count = 3
    during(function(ms) if ms == 1000 then count = 5 elseif ms == 2000 then count = 4 end end)
    use({ name = 'beer', count = 3 }, { name = 'beer', count = 3 })
    check('ox watchUse: given more, then one used', #seen == 1)

    count = 3
    during(function(ms) if ms == 21000 then count = 2 end end)
    use({ name = 'beer', count = 3 }, { name = 'beer', count = 3 })
    check('ox watchUse: too long after the press', #seen == 0)

    count = 3
    during(function(ms)
        if ms == 1000 then
            hooks.swapItems.fn({ source = 1, fromInventory = 1, toInventory = 'drop-1', fromSlot = { name = 'beer' } })
            count = 2
        end
    end)
    use({ name = 'beer', count = 3 }, { name = 'beer', count = 3 })
    check('ox watchUse: dropped after a cancelled bar', #seen == 0)

    count = 3
    during(function(ms)
        if ms == 1000 then hooks.swapItems.fn({ source = 1, fromInventory = 1, toInventory = 1, fromSlot = { name = 'beer' } }) end
        if ms == 2000 then count = 2 end
    end)
    use({ name = 'beer', count = 3 }, { name = 'beer', count = 3 })
    check('ox watchUse: moved in the inventory, then used', #seen == 1)

    Wait = stub
    hooks.swapItems = nil
    TriggerEvent('onResourceStart', 'ox_inventory')
    check('ox watchUse: the hook comes back with ox_inventory', hooks.swapItems ~= nil)
end

do
    local inv, seen = {}, {}
    local handlers = {}
    inv.AddHook = function(_, event, fn) handlers[event] = fn end
    inv.AddListener = function(_, event, fn) handlers[event] = fn end
    T.exports['qb-inventory'] = inv
    T.exports['qb-core'] = { GetCoreObject = function() return { Shared = { Items = {} }, Functions = {} } end }
    T.boot('server', { ['qb-core'] = 'started', ['qb-inventory'] = 'started' })
    TR.inventory.watchUse({ joint = true, beer = true }, function(src, item, amount) seen[#seen + 1] = { src, item, amount } end)

    local function pressed(item) handlers.ItemUsed('item', { source = 1, item = { name = item } }) end
    local function removed(item, reason, fromType)
        seen = {}
        handlers.ItemRemoved('item', { fromId = 1, fromType = fromType or 'player', item = { name = item }, reason = reason })
    end

    removed('joint', 'qb-smallresources:joint')
    check('qb watchUse: removed without a use', #seen == 0)
    pressed('joint')
    check('qb watchUse: a press alone is no use', #seen == 0)
    removed('joint', 'qb-smallresources:joint')
    check('qb watchUse: pressed and removed', #seen == 1 and seen[1][1] == 1 and seen[1][2] == 'joint' and seen[1][3] == 1)
    removed('joint', 'qb-smallresources:joint')
    check('qb watchUse: one removal for one use', #seen == 0)

    for _, reason in ipairs({ 'dropped item', 'Item given to ID #4', 'qb-drugs:server:sellCornerDrugs', 'qb-drugs:server:successDelivery' }) do
        pressed('joint')
        removed('joint', reason)
        check('qb watchUse: not a use: ' .. reason, #seen == 0)
    end

    pressed('beer')
    removed('beer', 'consumables:server:drinkAlcohol', 'trunk')
    check('qb watchUse: out of a trunk', #seen == 0)
    pressed('water')
    removed('water', 'x')
    check('qb watchUse: other items', #seen == 0)

    pressed('beer')
    T.timer = T.timer + 21000
    removed('beer', 'consumables:server:drinkAlcohol')
    check('qb watchUse: too long after the press', #seen == 0)

    handlers = {}
    TriggerEvent('onResourceStart', 'qb-inventory')
    check('qb watchUse: listens again after a qb-inventory restart', handlers.ItemUsed ~= nil and handlers.ItemRemoved ~= nil)
    check('qb watchUse: the old events stay off', T.handlers['consumables:server:drinkAlcohol'] == nil)
end

do
    local seen = {}
    T.exports['qb-inventory'] = {}
    T.exports['qb-core'] = { GetCoreObject = function() return { Shared = { Items = {} }, Functions = {} } end }
    T.boot('server', { ['qb-core'] = 'started', ['qb-inventory'] = 'started' })
    TR.inventory.watchUse({ beer = true, cokebaggy = true, joint = true }, function(src, item, amount) seen[#seen + 1] = { src, item, amount } end)

    T.fromClient(2, 'consumables:server:drinkAlcohol', 'beer')
    check('old qb watchUse: a drink', #seen == 1 and seen[1][1] == 2 and seen[1][2] == 'beer')
    seen = {}
    T.fromClient(2, 'consumables:server:drinkAlcohol', 'water')
    T.fromClient(2, 'consumables:server:drinkAlcohol', { 'beer' })
    check('old qb watchUse: not one of ours', #seen == 0)
    T.fromClient(2, 'consumables:server:useCokeBaggy')
    check('old qb watchUse: after the bar', #seen == 1 and seen[1][2] == 'cokebaggy')
    seen = {}
    for _ = 1, 5 do T.fromClient(3, 'consumables:server:drinkAlcohol', 'beer') end
    check('old qb watchUse: rate limited', #seen == 3)

    seen = {}
    local line = '**Inventory:** Evil (9) (Slot: 1) Name (4) (Slot: 2)\n**Item:** joint\n**Amount:** 1\n**Reason:** qb-smallresources:joint'
    TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'Item Removed', 'red', line)
    check('old qb watchUse: the joint, by the last id', #seen == 1 and seen[1][1] == 4 and seen[1][2] == 'joint')
    seen = {}
    TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'Item Removed', 'red', '**Inventory:** Name (4) (Slot: 2)\n**Reason:** dropped item')
    TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'Item Added', 'green', line)
    check('old qb watchUse: other log lines', #seen == 0)
end

do
    local hooks, seen = {}, {}
    T.exports.ox_inventory = { registerHook = function(_, event, fn) hooks[event] = fn end }
    T.boot('server', { qbx_core = 'started', ox_inventory = 'started' })
    TR.inventory.watchWeapons(function(src, item, serial, metadata) seen[#seen + 1] = { src, item, serial, metadata } end)

    local function made(inventory, item, metadata)
        seen = {}
        return hooks.createItem({ inventoryId = inventory, item = item, metadata = metadata })
    end
    check('ox watchWeapons: a gun made for a player, the metadata left as it is',
        made(1, { name = 'WEAPON_PISTOL', weapon = true }, { serial = '482913ABC104857', registered = 'Marcus Reyes' }) == nil
        and #seen == 1 and seen[1][1] == 1 and seen[1][2] == 'WEAPON_PISTOL' and seen[1][3] == '482913ABC104857' and seen[1][4].registered == 'Marcus Reyes')
    made('police_locker', { name = 'WEAPON_PISTOL', weapon = true }, { serial = '482913ABC104858' })
    check('ox watchWeapons: not into a stash', #seen == 0)
    made(1, { name = 'WEAPON_BAT', weapon = true }, {})
    check('ox watchWeapons: no serial (a bat, or registered = false)', #seen == 0)
    made(1, { name = 'water' }, { serial = 'ABC' })
    check('ox watchWeapons: not a weapon', #seen == 0)

    hooks.createItem = nil
    TriggerEvent('onResourceStart', 'ox_inventory')
    check('ox watchWeapons: the hook comes back with ox_inventory', hooks.createItem ~= nil)
end

do
    local listeners, seen = {}, {}
    local inv = { AddListener = function(_, event, fn) listeners[event] = fn end }
    T.exports['qb-inventory'] = inv
    T.exports['qb-core'] = { GetCoreObject = function() return { Shared = { Items = {
        weapon_pistol = { name = 'weapon_pistol', type = 'weapon', ammotype = 'AMMO_PISTOL' },
        weapon_stungun = { name = 'weapon_stungun', type = 'weapon' },
        weapon_knife = { name = 'weapon_knife', type = 'weapon' },
        water = { name = 'water', type = 'item' },
    } }, Functions = {} } end }
    T.boot('server', { ['qb-core'] = 'started', ['qb-inventory'] = 'started' })
    TR.inventory.watchWeapons(function(src, item, serial, metadata) seen[#seen + 1] = { src, item, serial, metadata } end)

    local function added(to, kind, name, info)
        seen = {}
        listeners.ItemAdded('weapon', { toId = to, toType = kind, item = { name = name, info = info } })
    end
    added(2, 'player', 'weapon_pistol', { serie = '21ABC4DE567FGHI', quality = 100 })
    check('qb watchWeapons: a gun added to a player', #seen == 1 and seen[1][1] == 2 and seen[1][2] == 'weapon_pistol'
        and seen[1][3] == '21ABC4DE567FGHI' and seen[1][4].quality == 100)
    added(2, 'player', 'weapon_stungun', { serie = '21ABC4DE567FGHJ' })
    check('qb watchWeapons: the stun gun', #seen == 1)
    added(2, 'player', 'weapon_knife', { serie = '21ABC4DE567FGHK' })
    check('qb watchWeapons: not a knife', #seen == 0)
    added('trunk-46KTR812', 'trunk', 'weapon_pistol', { serie = '21ABC4DE567FGHL' })
    check('qb watchWeapons: not into a trunk', #seen == 0)
    added(2, 'player', 'water', { serie = 'X' })
    check('qb watchWeapons: not an item', #seen == 0)

    listeners = {}
    TriggerEvent('onResourceStart', 'qb-inventory')
    check('qb watchWeapons: listens again after a qb-inventory restart', listeners.ItemAdded ~= nil)

    listeners, seen = {}, {}
    TR.inventory.watchMoves({ evidence_bag = true }, function(item, metadata, kind, to) seen[#seen + 1] = { item, metadata, kind, to } end)
    listeners.ItemAdded('evidence_bag', { toId = '3', toType = 'player', item = { name = 'evidence_bag', info = { evidence = 7 } } })
    listeners.ItemAdded('evidence_bag', { toId = 'trunk-46KTR812', toType = 'trunk', item = { name = 'evidence_bag', info = { evidence = 7 } } })
    listeners.ItemAdded('water', { toId = 3, toType = 'player', item = { name = 'water', info = {} } })
    check('qb watchMoves: to a player by server id, to a trunk by its id, not other items', #seen == 2 and seen[1][3] == 'player' and seen[1][4] == 3
        and seen[1][2].evidence == 7 and seen[2][3] == 'trunk' and seen[2][4] == 'trunk-46KTR812')
end

do
    local hooks, seen = {}, {}
    T.exports.ox_inventory = { registerHook = function(_, event, fn, options) hooks[event] = { fn = fn, options = options } end }
    T.boot('server', { es_extended = 'started', ox_inventory = 'started' })
    TR.inventory.watchMoves({ evidence_bag = true }, function(item, metadata, kind, to) seen[#seen + 1] = { item, metadata, kind, to } end)
    local bag = { name = 'evidence_bag', metadata = { evidence = 7 } }
    local function moved(payload)
        seen = {}
        local answer = hooks.swapItems.fn(payload)
        return answer
    end
    check('ox watchMoves: only the items watched', hooks.swapItems.options.itemFilter.evidence_bag == true)
    check('ox watchMoves: given to a player, the move let through', moved({ action = 'give', fromInventory = 1, fromType = 'player', toInventory = 3,
        toType = 'player', fromSlot = bag }) == nil and #seen == 1 and seen[1][1] == 'evidence_bag' and seen[1][2].evidence == 7 and seen[1][3] == 'player' and seen[1][4] == 3)
    moved({ action = 'move', fromInventory = 1, fromType = 'player', toInventory = 'newdrop', toType = 'drop', fromSlot = bag })
    check('ox watchMoves: dropped', #seen == 1 and seen[1][3] == 'drop')
    moved({ action = 'move', fromInventory = 1, fromType = 'player', toInventory = 1, toType = 'player', fromSlot = bag, toSlot = 4 })
    check('ox watchMoves: not within one inventory', #seen == 0)
    moved({ action = 'swap', fromInventory = 'evidence-1', fromType = 'stash', toInventory = 1, toType = 'player', fromSlot = { name = 'water' }, toSlot = bag })
    check('ox watchMoves: swapped out of a player into a stash', #seen == 1 and seen[1][3] == 'stash' and seen[1][4] == 'evidence-1')
end

do
    T.exports.ox_inventory = {
        Items = function(_, name)
            local list = {
                water = { name = 'water', label = 'Water', weight = 500, stack = true, close = true },
                armour = { name = 'armour', label = 'Body Armour', weight = 3000, stack = false, description = 'Level II' },
            }
            if name then return list[name] end
            return list
        end,
    }
    T.boot('server', { es_extended = 'started', ox_inventory = 'started' })
    local all = TR.inventory.getItems()
    check('ox getItems', all.water.label == 'Water' and all.water.stack == true and all.armour.stack == false
        and all.armour.description == 'Level II' and all.water.close == nil)
end

do
    local accounts, calls
    local function boot(started, config)
        accounts, calls = { police = 5000 }, {}
        local resources = { es_extended = 'started', ox_inventory = 'started' }
        for name, state in pairs(started) do resources[name] = state end
        T.boot('server', resources, nil, config)
    end

    boot({})
    check('society falls back to none', TR.system('society') == 'none')
    check('none: no account', TR.society.getMoney('police') == nil and not TR.society.removeMoney('police', 10)
        and not TR.society.addMoney('police', 10))

    T.exports['Renewed-Banking'] = {
        getAccountMoney = function(_, job) return accounts[job] or false end,
        removeAccountMoney = function(_, job, amount)
            if not accounts[job] or accounts[job] < amount then return false end
            accounts[job] = accounts[job] - amount
            return true
        end,
        addAccountMoney = function(_, job, amount)
            if not accounts[job] then return false end
            accounts[job] = accounts[job] + amount
            return true
        end,
        handleTransaction = function(_, ...) calls[#calls + 1] = table.pack(...) end,
    }
    T.exports['qb-banking'] = {
        GetAccount = function(_, name) return accounts[name] and { account_name = name, account_balance = accounts[name] } or false end,
        RemoveMoney = function(_, name, amount, reason)
            if not accounts[name] then return false end
            accounts[name] = accounts[name] - amount
            calls[#calls + 1] = { 'remove', name, amount, reason }
            return 1
        end,
        AddMoney = function(_, name, amount, reason)
            if not accounts[name] then return false end
            accounts[name] = accounts[name] + amount
            calls[#calls + 1] = { 'add', name, amount, reason }
            return 1
        end,
    }

    boot({ ['Renewed-Banking'] = 'started', ['qb-banking'] = 'started', esx_addonaccount = 'started' })
    check('renewed: detected first', TR.system('society') == 'renewed_banking')
    local s = TR.society
    check('renewed: money', s.getMoney('police') == 5000 and s.getMoney('ambulance') == nil)
    check('renewed: remove', s.removeMoney('police', 1200, 'Armoury: pistol') and accounts.police == 3800)
    local t = calls[1]
    check('renewed: in the statement', #calls == 1 and t[1] == 'police' and t[2] == 'Armoury: pistol' and t[3] == 1200
        and t[7] == 'withdraw')
    check('renewed: short is refused', not s.removeMoney('police', 3801) and accounts.police == 3800)
    check('renewed: add without a reason, no statement line', s.addMoney('police', 200) and accounts.police == 4000 and #calls == 1)
    check('renewed: no account', not s.removeMoney('ambulance', 10) and not s.addMoney('ambulance', 10))
    check('only whole amounts over 0', not s.removeMoney('police', 0) and not s.removeMoney('police', -5)
        and not s.removeMoney('police', 1.5) and not s.addMoney('police', 0) and not s.addMoney('police', '10')
        and accounts.police == 4000)
    check('getMoney needs a job name', s.getMoney(nil) == nil and s.getMoney(5) == nil)

    boot({ ['Renewed-Banking'] = 'started', ['qb-banking'] = 'started' }, { society = 'qb-banking' })
    check('config picks the provider by its resource name', TR.system('society') == 'qb_banking')
    s = TR.society
    check('qb: money', s.getMoney('police') == 5000 and s.getMoney('ambulance') == nil)
    check('qb: remove', s.removeMoney('police', 300, 'Armoury') and accounts.police == 4700
        and calls[1][1] == 'remove' and calls[1][4] == 'Armoury')
    check('qb: short is refused before qb-banking', not s.removeMoney('police', 5000) and #calls == 1)
    check('qb: add, no reason', s.addMoney('police', 300) and accounts.police == 5000 and calls[2][4] == nil)

    local function shared(name, money, modern)
        local account = { name = name, money = money }
        function account.removeMoney(amount)
            if modern and amount > account.money then return false end
            account.money = account.money - amount
            if modern then return true end
        end
        function account.addMoney(amount)
            account.money = account.money + amount
            if modern then return true end
        end
        return account
    end
    local function esx(list, societies)
        boot({ esx_addonaccount = 'started' })
        AddEventHandler('esx_addonaccount:getSharedAccount', function(name, cb) cb(list[name]) end)
        AddEventHandler('esx_society:getSociety', function(job, cb) cb(societies[job]) end)
        return TR.society
    end

    local old = { society_police = shared('society_police', 900) }
    s = esx(old, {})
    check('esx: detected', TR.system('society') == 'esx_addonaccount')
    check('esx: society_<job> without esx_society', s.getMoney('police') == 900 and s.getMoney('ambulance') == nil)
    check('esx old: remove returns nothing, still taken', s.removeMoney('police', 400) and old.society_police.money == 500)
    check('esx old: add', s.addMoney('police', 100) and old.society_police.money == 600)
    check('esx: short is refused', not s.removeMoney('police', 601) and old.society_police.money == 600)

    local modern = { lspd_funds = shared('lspd_funds', 2000, true), society_police = shared('society_police', 1) }
    s = esx(modern, { police = { name = 'police', account = 'lspd_funds' } })
    check('esx: the account esx_society names', s.getMoney('police') == 2000 and s.removeMoney('police', 500)
        and modern.lspd_funds.money == 1500 and modern.society_police.money == 1)
end

do
    local list = {
        WEAPON_PISTOL = { name = 'WEAPON_PISTOL', label = 'Pistol' },
        burger = { name = 'burger', label = 'Burger', client = { image = 'https://cdn.example/burger.webp' } },
    }
    T.exports.ox_inventory = { Items = function(_, name) return list[name] end }
    T.boot('client', { es_extended = 'started', ox_inventory = 'started', ox_target = 'started' })
    check('ox client image: <imagepath>/<name>.png, its own when set', TR.inventory.getImage('WEAPON_PISTOL') == 'nui://ox_inventory/web/images/WEAPON_PISTOL.png'
        and TR.inventory.getImage('burger') == 'https://cdn.example/burger.webp' and TR.inventory.getImage('nothing') == nil)
    T.boot('client', { es_extended = 'started', ox_inventory = 'started', ox_target = 'started' }, { ['inventory:imagepath'] = 'https://cdn.example/items' })
    check('ox client image: the server\'s inventory:imagepath', TR.inventory.getImage('WEAPON_PISTOL') == 'https://cdn.example/items/WEAPON_PISTOL.png')
    LocalPlayer.state.set = function(bag, key, value) rawset(bag, key, value) end
    TR.inventory.setBusy(true)
    local busy = LocalPlayer.state.invBusy
    TR.inventory.setBusy(false)
    check('ox client setBusy: its own invBusy', busy == true and LocalPlayer.state.invBusy == false)
    LocalPlayer.state.set, LocalPlayer.state.invBusy = nil, nil
end

do
    local base = { es_extended = 'started', ox_inventory = 'started', ox_target = 'started' }
    local function boot(context, started, config)
        local resources = {}
        for name, state in pairs(base) do resources[name] = state end
        for name, state in pairs(started) do resources[name] = state end
        T.nuiMessages, T.nuiCallbacks = {}, {}
        T.boot(context, resources, nil, config)
    end
    local APP = { id = 'tr_example', name = 'Burner', icon = 'web/icon.png', page = 'web/app.html' }

    boot('server', {})
    check('phone falls back to none', TR.system('phone') == 'none' and TR.phone.number(1) == nil)
    boot('client', {})
    TR.phone.app(APP)
    check('none: app goes nowhere, no error', #T.logs == 0 or not T.logs[#T.logs]:find('could not'))

    local added, removed, typing = {}, {}, {}
    local function phoneExports(adder, remover, typer, extra)
        local fns = extra or {}
        fns[adder] = function(_, app) added[#added + 1] = app; return true end
        if remover then fns[remover] = function(_, id) removed[#removed + 1] = id end end
        if typer then fns[typer] = function(_, on) typing[#typing + 1] = on end end
        return fns
    end

    added, removed, typing = {}, {}, {}
    T.exports['lb-phone'] = phoneExports('AddCustomApp', 'RemoveCustomApp')
    boot('client', { ['lb-phone'] = 'started' })
    check('lb-phone detected', TR.system('phone') == 'lb_phone')
    TR.phone.app({ id = 'tr_example', name = 'Burner', description = 'Texts', icon = 'web/icon.png', page = 'web/app.html', preinstalled = false })
    local a = added[1]
    check('lb: app as lb takes it', a and a.identifier == 'tr_example' and a.name == 'Burner' and a.description == 'Texts'
        and a.ui == 'tr_example/web/app.html' and a.icon == 'https://cfx-nui-tr_example/web/icon.png' and a.defaultApp == false and a.fixBlur == true)
    for _, fn in ipairs(T.handlers.onClientResourceStart or {}) do fn('lb-phone') end
    check('lb: back on when the phone restarts', #added == 2 and added[2].identifier == 'tr_example')
    for _, fn in ipairs(T.handlers.onClientResourceStart or {}) do fn('something_else') end
    check('lb: not for other resources starting', #added == 2)
    for _, fn in ipairs(T.handlers.onResourceStop or {}) do fn('tr_example') end
    check('lb: off when the resource stops', removed[1] == 'tr_example')
    T.nui('tr_phone:typing', { on = true })
    check('lb: typing does nothing', #typing == 0)
    TR.phone.send('tr_example', 'push', { kind = 'data' })
    local sent = T.nuiMessages[#T.nuiMessages]
    check('send: to the own page, for the app', sent.trPhone == 'tr_example' and sent.action == 'push' and sent.data.kind == 'data')

    local refused = 0
    T.exports['lb-phone'] = { AddCustomApp = function() refused = refused + 1; return false, 'identifier taken' end }
    boot('client', { ['lb-phone'] = 'started' })
    T.logs = {}
    TR.phone.app(APP)
    check('lb: a refusal is logged', refused == 1 and T.logs[1] and T.logs[1]:find('identifier taken') ~= nil)

    local notes = {}
    T.exports['lb-phone'] = {
        GetEquippedPhoneNumber = function(_, src) return src == 1 and '5551234' or nil end,
        SendNotification = function(_, target, data) notes[#notes + 1] = { target, data } end,
    }
    boot('server', { ['lb-phone'] = 'started' })
    check('lb: number, none without a phone', TR.phone.number(1) == '5551234' and TR.phone.number(2) == nil)
    TR.phone.notify(1, { title = 'Linda', text = 'ok here it is', app = 'tr_example' })
    check('lb: notify to the source', notes[1][1] == 1 and notes[1][2].app == 'tr_example' and notes[1][2].title == 'Linda'
        and notes[1][2].content == 'ok here it is')
    T.exports['lb-phone'] = { GetEquippedPhoneNumber = function() error('lb-phone stopped') end }
    boot('server', { ['lb-phone'] = 'started' })
    T.logs = {}
    check('number: a failing export is no phone', TR.phone.number(1) == nil and T.logs[1]:find('lb-phone stopped', 1, true) ~= nil)
    T.exports['lb-phone'] = nil

    added, removed, typing = {}, {}, {}
    T.exports['sd-phone'] = phoneExports('addCustomApp', 'removeCustomApp')
    T.exports['lb-phone'] = phoneExports('AddCustomApp', 'RemoveCustomApp')
    boot('client', { ['sd-phone'] = 'started', ['lb-phone'] = 'started' })
    check('sd-phone before lb-phone', TR.system('phone') == 'sd_phone')
    TR.phone.app(APP)
    check('sd: app as sd takes it', added[1] and added[1].identifier == 'tr_example' and added[1].ui == 'tr_example/web/app.html'
        and added[1].defaultApp == true and #added == 1)
    for _, fn in ipairs(T.handlers.onClientResourceStart or {}) do fn('sd-phone') end
    check('sd: waits for its ready event, not the start', #added == 1)
    for _, fn in ipairs(T.handlers['sd-phone:ready'] or {}) do fn() end
    check('sd: back on when it says it is ready', #added == 2)
    T.exports['lb-phone'] = nil

    notes = {}
    T.exports['sd-phone'] = {
        getPhoneNumber = function(_, src) return src == 1 and '555-0101' or nil end,
        notify = function(_, src, data) notes[#notes + 1] = { src, data } end,
    }
    boot('server', { ['sd-phone'] = 'started' })
    TR.phone.notify(1, { title = 'Linda', text = 'hi', app = 'tr_example' })
    check('sd: number and notify', TR.phone.number(1) == '555-0101' and notes[1][2].body == 'hi' and notes[1][2].appId == 'tr_example')
    T.exports['sd-phone'] = nil

    added, removed, typing = {}, {}, {}
    T.exports.gksphone = phoneExports('AddCustomApp', nil, 'InputChange')
    boot('client', { gksphone = 'started' })
    check('gksphone detected', TR.system('phone') == 'gksphone')
    local opened = 0
    TR.phone.app({ id = 'tr_example', name = 'Burner', icon = 'web/icon.png', page = 'web/app.html', onOpen = function() opened = opened + 1 end })
    a = added[1]
    check('gks: app as gks takes it', a and a.name == 'tr_example' and a.appurl == 'https://cfx-nui-tr_example/web/app.html'
        and a.icons == 'https://cfx-nui-tr_example/web/icon.png' and a.show == true and a.startapp == true and a.labelLangs.en == 'Burner'
        and a.labelLangs.de == 'Burner')
    a.onOpen('phone-id', '555')
    check('gks: onOpen passed on', opened == 1)
    T.nui('tr_phone:typing', { on = true })
    T.nui('tr_phone:typing', {})
    check('gks: typing through InputChange', typing[1] == true and typing[2] == false)
    for _, fn in ipairs(T.handlers.onResourceStop or {}) do fn('tr_example') end
    check('gks: nothing to remove, no error', true)

    notes = {}
    T.exports.gksphone = {
        GetPhoneBySource = function(_, src) return src == 1 and 5550123 or nil end,
        sendNotification = function(_, src, data) notes[#notes + 1] = { src, data } end,
    }
    boot('server', { gksphone = 'started' })
    TR.phone.notify(1, { title = 'Linda', text = 'hi' })
    check('gks: number as text, notify', TR.phone.number(1) == '5550123' and notes[1][2].title == 'Linda' and notes[1][2].message == 'hi')
    T.exports.gksphone = nil

    added, removed, typing = {}, {}, {}
    local loadedAfter = 2
    T.exports.yphone = phoneExports('AddCustomApp', 'RemoveCustomApp', 'SetNuiFocusKeepInput', {
        GetDataLoaded = function() loadedAfter = loadedAfter - 1; return loadedAfter <= 0 end,
    })
    boot('client', { yphone = 'started' })
    check('yphone is yseries', TR.system('phone') == 'yseries')
    TR.phone.app(APP)
    a = added[1]
    check('yseries: waits for its data, app as it takes it', loadedAfter == 0 and a and a.key == 'tr_example'
        and a.ui == 'https://cfx-nui-tr_example/web/app.html' and a.icon.yos == a.icon.humanoid and a.defaultApp == true)
    T.nui('tr_phone:typing', { on = true })
    check('yseries: no game keys while typing', typing[1] == false)
    for _, fn in ipairs(T.handlers.onResourceStop or {}) do fn('tr_example') end
    check('yseries: off when the resource stops', removed[1] == 'tr_example')

    notes = {}
    T.exports.yphone = {
        GetPhoneNumberBySourceId = function(_, src) return src == 1 and '5559999' or nil end,
        SendNotification = function(_, data, kind, to) notes[#notes + 1] = { data, kind, to } end,
    }
    boot('server', { yphone = 'started' })
    TR.phone.notify(1, { title = 'Linda', text = 'hi', app = 'tr_example' })
    check('yseries: number, notify by source', TR.phone.number(1) == '5559999' and notes[1][1].text == 'hi' and notes[1][2] == 'source'
        and notes[1][3] == 1)
    T.exports.yphone = nil

    local created = {}
    T.exports.npwd = {
        getPlayerData = function(_, q) return q.source == 1 and { phoneNumber = '555-4242' } or nil end,
        createNotification = function(_, data) created[#created + 1] = data end,
    }
    boot('server', { npwd = 'started' })
    check('npwd detected, number from getPlayerData', TR.system('phone') == 'npwd' and TR.phone.number(1) == '555-4242'
        and TR.phone.number(2) == nil)
    TR.phone.notify(1, { title = 'Linda', text = 'hi', app = 'tr_example' })
    local event = T.clientEvents[#T.clientEvents]
    check('npwd: notify goes to the client', event.name == 'tr_example:tr_phone:notify' and event.target == 1 and event.args[1].title == 'Linda')
    boot('client', { npwd = 'started' })
    T.logs = {}
    TR.phone.app(APP)
    check('npwd: says to list the resource in config.json', T.logs[1] and T.logs[1]:find('config.json') ~= nil)
    for _, fn in ipairs(T.handlers['tr_example:tr_phone:notify'] or {}) do fn(event.args[1]) end
    check('npwd: the client shows it', created[1] and created[1].appId == 'tr_example' and created[1].secondaryTitle == 'Linda'
        and created[1].content == 'hi')
    T.exports.npwd = nil

    boot('server', { ['lb-phone'] = 'started', gksphone = 'started' }, { phone = 'gksphone' })
    check('config picks the phone', TR.system('phone') == 'gksphone')
    boot('server', { yseries = 'stopped', ['yflip-phone'] = 'started' }, { phone = 'yflip-phone' })
    check('config by resource name', TR.system('phone') == 'yseries')
end

T.done('bridges')
