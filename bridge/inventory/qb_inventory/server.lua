local QBCore = exports['qb-core']:GetCoreObject()
local inv = exports['qb-inventory']

local bridge = {}
local stashes = {} ---@type table<string, TRStash>

local function itemDef(name)
    return QBCore.Shared.Items[name:lower()]
end

local function playerItems(src)
    local player = QBCore.Functions.GetPlayer(src)
    return player and player.PlayerData.items or {}
end

-- qb-inventory has no metadata filters, so match item.info against every given key.
local function matches(info, metadata)
    if not metadata then return true end
    if type(info) ~= 'table' then return false end

    for key, value in pairs(metadata) do
        if info[key] ~= value then return false end
    end

    return true
end

function bridge.getCount(src, item, metadata)
    if not metadata then return inv:GetItemCount(src, item) or 0 end

    local count = 0

    for _, data in pairs(playerItems(src)) do
        if data.name == item and matches(data.info, metadata) then count = count + data.amount end
    end

    return count
end

function bridge.canCarry(src, item, count)
    return inv:CanAddItem(src, item, count) == true
end

function bridge.addItem(src, item, count, metadata)
    local def = itemDef(item)
    if not def then return false, 'invalid_item' end

    if not inv:CanAddItem(src, item, count) then return false, 'inventory_full' end
    if not inv:AddItem(src, item, count, nil, metadata, TR.resource) then return false, 'failed' end

    TriggerClientEvent('qb-inventory:client:ItemBox', src, def, 'add', count)
    return true
end

function bridge.removeItem(src, item, count, metadata, slot)
    local removed

    if not metadata or slot then
        removed = inv:RemoveItem(src, item, count, slot, TR.resource) == true
    else
        -- All or nothing: plan across the matching slots first, put back what came out if a slot refuses.
        local plan, remaining, held = {}, count, 0

        for _, data in pairs(playerItems(src)) do
            if data.name == item and matches(data.info, metadata) then
                plan[#plan + 1] = data
                held = held + data.amount
            end
        end
        table.sort(plan, function(a, b) return a.slot < b.slot end)

        local taken = {}
        for _, data in ipairs(held >= count and plan or {}) do
            if remaining <= 0 then break end
            local amount = math.min(data.amount, remaining)
            if not inv:RemoveItem(src, item, amount, data.slot, TR.resource) then break end
            taken[#taken + 1] = { slot = data.slot, amount = amount, info = data.info }
            remaining = remaining - amount
        end

        removed = remaining == 0
        if not removed then
            for _, back in ipairs(taken) do
                inv:AddItem(src, item, back.amount, back.slot, back.info, TR.resource)
            end
        end
    end

    if removed then
        TriggerClientEvent('qb-inventory:client:ItemBox', src, itemDef(item), 'remove', count)
    end

    return removed
end

local function itemOf(def)
    return { name = def.name, label = def.label, weight = def.weight, stack = not def.unique, description = def.description }
end

function bridge.getItem(name)
    local def = itemDef(name)
    return def and itemOf(def)
end

function bridge.getItems()
    local items = {}
    for name, def in pairs(QBCore.Shared.Items) do items[name] = itemOf(def) end
    return items
end

function bridge.getSlots(src, item)
    local slots = {}
    for _, data in pairs(playerItems(src)) do
        if not item or data.name == item:lower() then
            slots[#slots + 1] = { slot = data.slot, name = data.name, count = data.amount, metadata = type(data.info) == 'table' and data.info or {} }
        end
    end
    return slots
end

-- qb-inventory has no metadata setter by slot: change the item's info and save the item list.
function bridge.setMetadata(src, slot, metadata)
    local player = QBCore.Functions.GetPlayer(src)
    local items = player and player.PlayerData.items
    if not items or not items[slot] then return false end

    items[slot].info = metadata
    player.Functions.SetPlayerData('items', items)
    return true
end

function bridge.registerStash(id, data)
    stashes[id] = data
end

---@return string? inventoryId
local function resolveStash(src, id)
    local stash = stashes[id]
    if not stash then return end

    if stash.groups and not (TR.player.hasJob(src, stash.groups) or TR.player.hasGang(src, stash.groups)) then return end

    local owner = stash.owner
    if not owner then return id end

    local identifier = TR.player.getIdentifier(src)
    if not identifier then return end

    if owner == true then
        return ('%s:%s'):format(id, identifier)
    elseif owner == identifier then
        return ('%s:%s'):format(id, owner)
    end
end

function bridge.openStash(src, id)
    local inventoryId = resolveStash(src, id)
    if not inventoryId then return end

    local stash = stashes[id]
    inv:OpenInventory(src, inventoryId, { label = stash.label, maxweight = stash.weight, slots = stash.slots })
end

-- qb-inventory opens stashes from the server only. Per resource, as each keeps its own stashes.
TR.net.on(('%s:tr_openStash'):format(TR.resource), function(src, id)
    local stash = stashes[id]
    if not stash then return end
    if stash.coords and not TR.guard.isNear(src, stash.coords, 5.0) then return end

    bridge.openStash(src, id)
end, { schema = { { type = 'string', max = 128 } }, rateLimit = 2 })

-- It shows 1.5 s later, and keeps the target's inv_busy set while it is open.
function bridge.openPlayer(src, target)
    inv:OpenInventoryById(src, target)
    return true
end

function bridge.isViewing(_, target)
    return Player(target).state.inv_busy == true
end

function bridge.closePlayer(src)
    inv:CloseInventory(src)
end

TR.net.on(('%s:tr_closeInventory'):format(TR.resource), function(src)
    inv:CloseInventory(src)
end, { schema = {}, rateLimit = 2 })

function bridge.usedSlot(data)
    local slot = type(data) == 'table' and math.tointeger(tonumber(data.slot))
    if not slot then return end
    return { slot = slot, count = data.amount, metadata = data.info or {} }
end

local USE_WINDOW_MS = 20000

local NOT_USED = {
    ['dropped item'] = true,
    ['qb-drugs:server:sellCornerDrugs'] = true,
    ['qb-drugs:server:robCornerDrugs'] = true,
    ['qb-drugs:server:updateDealerItems'] = true,
    ['qb-drugs:server:successDelivery'] = true,
}

local AFTER_THE_BAR = {
    ['consumables:server:useCokeBaggy'] = 'cokebaggy',
    ['consumables:server:useCrackBaggy'] = 'crack_baggy',
    ['consumables:server:useXTCBaggy'] = 'xtcbaggy',
    ['consumables:server:useOxy'] = 'oxy',
    ['consumables:server:useMeth'] = 'meth',
}

function bridge.watchUse(items, handler)
    local used = {} ---@type table<string, integer> 'src:item' -> when it was used
    local listeningOld = false

    -- A hook, as a listener runs after the item's callback, which may have taken the item already. Returning nothing never blocks the use.
    local function listen()
        inv:AddHook('ItemUsed', function(_, payload)
            if items[payload.item.name] then used[payload.source .. ':' .. payload.item.name] = GetGameTimer() end
        end)

        inv:AddListener('ItemRemoved', function(_, payload)
            local reason = payload.reason or ''
            if payload.fromType ~= 'player' or NOT_USED[reason] or reason:find('Item given to ID #', 1, true) == 1 then return end

            local key = payload.fromId .. ':' .. payload.item.name
            local at = used[key]
            if not at then return end

            used[key] = nil
            if GetGameTimer() - at <= USE_WINDOW_MS then handler(tonumber(payload.fromId), payload.item.name, 1) end
        end)
    end

    -- qb-inventory before 2.1.0 has no hooks, so qb-smallresources' own events are all there is.
    local function listenOld()
        if listeningOld then return end
        listeningOld = true

        local function seen(src, item)
            if items[item] and TR.guard.ratelimit(src, 'tr_watchUse', { max = 3, window = 10000 }) then handler(src, item, 1) end
        end

        RegisterNetEvent('consumables:server:drinkAlcohol', function(item)
            if type(item) == 'string' then seen(source, item) end
        end)

        for event, item in pairs(AFTER_THE_BAR) do
            RegisterNetEvent(event, function() seen(source, item) end)
        end

        -- 2.0.0 logs the reason, and the joint sends nothing else. Names are free text, so the last id in the line is the player's.
        AddEventHandler('qb-log:server:CreateLog', function(_, title, _, message)
            if title ~= 'Item Removed' or not items.joint or type(message) ~= 'string' then return end
            if not message:find('**Reason:** qb-smallresources:joint', 1, true) then return end

            local src
            for id in message:gmatch('%((%d+)%) %(Slot:') do src = tonumber(id) end
            if src then handler(src, 'joint', 1) end
        end)
    end

    local function start()
        if GetResourceState('qb-inventory') ~= 'started' then return end
        if not pcall(listen) then listenOld() end
    end

    start()
    AddEventHandler('onResourceStart', function(name)
        if name == 'qb-inventory' then start() end
    end)
end

-- qb-inventory numbers every weapon, knives and bats too; only guns and the stun gun count, as with ox_inventory.
function bridge.watchWeapons(handler)
    local function listen()
        inv:AddListener('ItemAdded', function(_, payload)
            local item = payload.item
            local info, def = type(item) == 'table' and item.info, type(item) == 'table' and itemDef(item.name)
            if payload.toType ~= 'player' or type(info) ~= 'table' or type(info.serie) ~= 'string' then return end
            if not def or def.type ~= 'weapon' or not (def.ammotype or item.name:lower() == 'weapon_stungun') then return end
            handler(tonumber(payload.toId), item.name, info.serie, info)
        end)
    end

    local function start()
        if GetResourceState('qb-inventory') ~= 'started' then return end
        if not pcall(listen) then TR.log.warn('watchWeapons: qb-inventory before 2.1.0 tells no script about new weapons') end
    end

    start()
    AddEventHandler('onResourceStart', function(name)
        if name == 'qb-inventory' then start() end
    end)
end

-- Every add, a new item too: the handler only sees where it is now.
function bridge.watchMoves(items, handler)
    local function listen()
        inv:AddListener('ItemAdded', function(_, payload)
            local item = payload.item
            if type(item) ~= 'table' or not items[item.name] then return end
            local to = payload.toType == 'player' and tonumber(payload.toId) or payload.toId
            handler(item.name, type(item.info) == 'table' and item.info or {}, payload.toType, to)
        end)
    end

    local function start()
        if GetResourceState('qb-inventory') ~= 'started' then return end
        if not pcall(listen) then TR.log.warn('watchMoves: qb-inventory before 2.1.0 tells no script where items go') end
    end

    start()
    AddEventHandler('onResourceStart', function(name)
        if name == 'qb-inventory' then start() end
    end)
end

return bridge
