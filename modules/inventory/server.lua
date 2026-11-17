local bridge = TR.bridge('inventory')

---@class TRItem
---@field name string
---@field label string
---@field weight number
---@field stack boolean
---@field description? string

---@class TRUsedSlot
---@field slot integer
---@field count integer
---@field metadata table qb-inventory: info

---@class TRStash
---@field label string
---@field slots integer
---@field weight integer max weight in grams
---@field owner? string | boolean true = one stash per player, string = specific identifier
---@field groups? table<string, integer> jobs allowed to open it, with minimum grade
---@field coords? vector3

---@class TRInventory
local inventory = {}

local function isValidCount(count)
    return math.type(count) == 'integer' and count > 0
end

---@param src integer
---@param item string
---@param count integer
---@param metadata? table
---@return boolean success
---@return string? reason e.g. 'inventory_full'
function inventory.addItem(src, item, count, metadata)
    if not isValidCount(count) then
        TR.log.error('addItem: invalid count %s for %s', count, item)
        return false, 'invalid_count'
    end

    return bridge.addItem(src, item, count, metadata)
end

---Only removes when the player has enough.
---@param src integer
---@param item string
---@param count integer
---@param metadata? table
---@param slot? integer
---@return boolean success
function inventory.removeItem(src, item, count, metadata, slot)
    if not isValidCount(count) then
        TR.log.error('removeItem: invalid count %s for %s', count, item)
        return false
    end

    if bridge.getCount(src, item, metadata) < count then return false end

    return bridge.removeItem(src, item, count, metadata, slot)
end

---@param src integer
---@param item string
---@param metadata? table
---@return integer
function inventory.getCount(src, item, metadata) return bridge.getCount(src, item, metadata) end

---@param src integer
---@param item string
---@param count? integer default 1
---@param metadata? table
---@return boolean
function inventory.hasItem(src, item, count, metadata)
    return bridge.getCount(src, item, metadata) >= (count or 1)
end

---@param src integer
---@param item string
---@param count integer
---@param metadata? table
---@return boolean
function inventory.canCarry(src, item, count, metadata) return bridge.canCarry(src, item, count, metadata) end

---@class TRSlot
---@field slot integer
---@field name string
---@field count integer
---@field metadata table

---In slot order. Without `item`, every slot the player has filled.
---@param src integer
---@param item? string
---@return TRSlot[]
function inventory.getSlots(src, item)
    local slots = bridge.getSlots(src, item) or {}
    table.sort(slots, function(a, b) return a.slot < b.slot end)
    return slots
end

---Replaces the item's whole metadata.
---@param src integer
---@param slot integer
---@param metadata table
---@return boolean success
function inventory.setMetadata(src, slot, metadata)
    if math.type(slot) ~= 'integer' or type(metadata) ~= 'table' then return false end
    return bridge.setMetadata(src, slot, metadata) == true
end

---@param name string
---@return TRItem?
function inventory.getItem(name) return bridge.getItem(name) end

---Every item the inventory knows (e.g. for an item picker).
---@return table<string, TRItem> items by name
function inventory.getItems() return bridge.getItems() end

---@param id string
---@param data TRStash
function inventory.registerStash(id, data) bridge.registerStash(id, data) end

---@param src integer
---@param id string
function inventory.openStash(src, id) bridge.openStash(src, id) end

local PLAYER_REACH = 3.0 -- m apart another player's inventory closes at
local OPENING_MS = 3000 -- qb-inventory shows it 1.5 s after it is asked for

local function apart(a, b)
    if not GetPlayerName(a) or not GetPlayerName(b) then return math.huge end
    return #(GetEntityCoords(GetPlayerPed(a)) - GetEntityCoords(GetPlayerPed(b)))
end

---Opens `target`'s inventory beside `src`'s own, as a search does: items are taken by dragging them over. The inventory
---script's own checks (job, distance) are skipped, so check first; it closes once they are more than 3 m apart.
---@param src integer
---@param target integer
---@return boolean opened false when they are too far apart, or someone else has it open
function inventory.openPlayer(src, target)
    if src == target or apart(src, target) > PLAYER_REACH then return false end
    if not bridge.openPlayer(src, target) then return false end
    CreateThread(function()
        local opening = GetGameTimer() + OPENING_MS
        while not bridge.isViewing(src, target) and GetGameTimer() < opening do Wait(250) end
        while bridge.isViewing(src, target) do
            if apart(src, target) > PLAYER_REACH then
                if GetPlayerName(src) then bridge.closePlayer(src) end
                return
            end
            Wait(500)
        end
    end)
    return true
end

local framework

---`used` is the slot it was used from; check it still holds the item before acting on it later.
---ox_inventory items need no consume, client.export, client.status, client.usetime or server.export,
---as ox_inventory handles those itself and never tells the framework.
---@param item string
---@param handler fun(src: integer, used: TRUsedSlot)
function inventory.onUse(item, handler)
    framework = framework or TR.bridge('framework')
    framework.registerUsableItem(item, function(src, data)
        local used = bridge.usedSlot(data)
        if not used then
            return TR.log.warn('onUse: %s was used without its slot (%s)', item, type(data))
        end
        handler(tonumber(src), used)
    end)
end

---Sees uses without taking them over, so the item's own script keeps working. Unlike onUse, any number of scripts can
---watch one item. amount is 1, or the part of an item a sip took (ox_inventory consume).
---@param items table<string, any> keyed by item name
---@param handler fun(src: integer, item: string, amount: number)
function inventory.watchUse(items, handler) bridge.watchUse(items, handler) end

---Sees each gun (and stun gun) with a serial number as it reaches a player: with ox_inventory when it is made for them (a
---shop, a script, an admin), with qb-inventory 2.1.0+ every time one is added, so the same serial can come again.
---@param handler fun(src: integer, item: string, serial: string, metadata: table)
function inventory.watchWeapons(handler)
    -- The inventory calls in while it adds the item, where nothing may wait.
    bridge.watchWeapons(function(src, item, serial, metadata)
        CreateThread(function() handler(src, item, serial, metadata) end)
    end)
end

---Sees one of `items` moved by a player into another inventory: given, dropped, put in a stash or a car, taken from
---someone. `to` is the player's server id when `kind` is 'player', else that inventory's id ('stash', 'trunk',
---'glovebox', 'drop', ...). ox_inventory tells before the move and it can still fail: check it got there first.
---@param items table<string, any> keyed by item name
---@param handler fun(item: string, metadata: table, kind: string, to: integer | string)
function inventory.watchMoves(items, handler)
    bridge.watchMoves(items, function(item, metadata, kind, to)
        CreateThread(function()
            Wait(0)
            handler(item, metadata, kind, to)
        end)
    end)
end

return inventory
