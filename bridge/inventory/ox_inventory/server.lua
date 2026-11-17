local ox = exports.ox_inventory

local bridge = {}

function bridge.addItem(src, item, count, metadata)
    local success, response = ox:AddItem(src, item, count, metadata)
    return success == true, not success and response or nil
end

function bridge.removeItem(src, item, count, metadata, slot)
    return ox:RemoveItem(src, item, count, metadata, slot) == true
end

function bridge.getCount(src, item, metadata)
    return ox:GetItemCount(src, item, metadata) or 0
end

function bridge.canCarry(src, item, count, metadata)
    return ox:CanCarryItem(src, item, count, metadata) == true
end

local function itemOf(item)
    return { name = item.name, label = item.label, weight = item.weight, stack = item.stack, description = item.description }
end

function bridge.getItem(name)
    local item = ox:Items(name)
    return item and itemOf(item)
end

function bridge.getItems()
    local items = {}
    for name, item in pairs(ox:Items()) do items[name] = itemOf(item) end
    return items
end

function bridge.getSlots(src, item)
    local slots = {}
    for _, data in pairs((item and ox:Search(src, 'slots', item) or not item and ox:GetInventoryItems(src)) or {}) do
        slots[#slots + 1] = { slot = data.slot, name = data.name, count = data.count, metadata = data.metadata or {} }
    end
    return slots
end

function bridge.setMetadata(src, slot, metadata)
    if not ox:GetSlot(src, slot) then return false end
    ox:SetMetadata(src, slot, metadata)
    return true
end

function bridge.registerStash(id, data)
    ox:RegisterStash(id, data.label, data.slots, data.weight, data.owner, data.groups, data.coords)
end

function bridge.openStash(src, id)
    ox:forceOpenInventory(src, 'stash', id)
end

local viewing = {} ---@type table<integer, integer | string> the inventory each player has open beside their own
AddEventHandler('ox_inventory:openedInventory', function(src, id) viewing[src] = id end)
AddEventHandler('ox_inventory:closedInventory', function(src) viewing[src] = nil end)

function bridge.openPlayer(src, target)
    return ox:forceOpenInventory(src, 'player', target) ~= nil
end

function bridge.isViewing(src, target)
    return viewing[src] == target
end

function bridge.closePlayer(src)
    TriggerClientEvent('ox_inventory:closeInventory', src)
end

function bridge.usedSlot(data)
    local slot = type(data) == 'table' and math.tointeger(tonumber(data.slot))
    if not slot then return end
    return { slot = slot, count = data.count, metadata = data.metadata or {} }
end

local WATCH_MS = 20000

function bridge.watchUse(items, handler)
    local watches = {} ---@type table<string, { src: integer, item: string, count: integer, ends: integer }>
    local polling = false

    local function poll()
        polling = true
        while next(watches) do
            Wait(500)
            local now = GetGameTimer()
            for key, watch in pairs(watches) do
                local count = GetPlayerName(watch.src) and bridge.getCount(watch.src, watch.item)
                if not count or now > watch.ends then
                    watches[key] = nil
                elseif count < watch.count then
                    watches[key] = nil
                    handler(watch.src, watch.item, 1)
                else
                    watch.count = count
                end
            end
        end
        polling = false
    end

    -- Fires on a press too, even with no script behind the item, so only a lower count proves a framework item was used.
    -- consume is only set on ox's own route, which has finished by now. usingItem is cleared right after this event.
    AddEventHandler('ox_inventory:usedItem', function(src, name, slot)
        if not items[name] then return end
        local inv = ox:GetInventory(src)
        local using = inv and inv.usingItem
        if not using then return end

        if using.consume then return handler(src, name, using.consume == 0 and 1 or using.consume) end

        local left = inv.items[slot]
        if not left or left.name ~= name or left.count < using.count then return handler(src, name, 1) end

        -- Its script may have only started a bar, and takes the item when that ends.
        watches[src .. ':' .. name] = { src = src, item = name, count = bridge.getCount(src, name), ends = GetGameTimer() + WATCH_MS }
        if not polling then CreateThread(poll) end
    end)

    local function hook()
        if GetResourceState('ox_inventory') ~= 'started' then return end
        local names = {}
        for name in pairs(items) do names[name] = true end

        -- A bar cancelled and the item then dropped or given isn't a use.
        ox:registerHook('swapItems', function(payload)
            if payload.fromInventory ~= payload.toInventory then
                watches[payload.source .. ':' .. payload.fromSlot.name] = nil
            end
        end, { itemFilter = names })
    end

    hook()
    AddEventHandler('onResourceStart', function(name)
        if name == 'ox_inventory' then hook() end
    end)
end

-- ox_inventory gives a serial to guns and the stun gun only, unless the metadata says registered = false.
function bridge.watchWeapons(handler)
    local function hook()
        if GetResourceState('ox_inventory') ~= 'started' then return end
        ox:registerHook('createItem', function(payload)
            local src, metadata = payload.inventoryId, payload.metadata
            if type(src) == 'number' and GetPlayerName(src) and payload.item.weapon and type(metadata.serial) == 'string' then
                handler(src, payload.item.name, metadata.serial, metadata)
            end
        end)
    end

    hook()
    AddEventHandler('onResourceStart', function(name)
        if name == 'ox_inventory' then hook() end
    end)
end

function bridge.watchMoves(items, handler)
    local function hook()
        if GetResourceState('ox_inventory') ~= 'started' then return end
        local names = {}
        for name in pairs(items) do names[name] = true end
        ox:registerHook('swapItems', function(payload)
            if payload.fromInventory == payload.toInventory then return end
            local from, to = payload.fromSlot, payload.toSlot
            if type(from) == 'table' and items[from.name] then handler(from.name, from.metadata or {}, payload.toType, payload.toInventory) end
            -- A swap sends what was in the other slot back the other way.
            if payload.action == 'swap' and type(to) == 'table' and items[to.name] then
                handler(to.name, to.metadata or {}, payload.fromType, payload.fromInventory)
            end
        end, { itemFilter = names })
    end

    hook()
    AddEventHandler('onResourceStart', function(name)
        if name == 'ox_inventory' then hook() end
    end)
end

return bridge
