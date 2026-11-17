local bridge = TR.bridge('inventory')

---Display only; the server decides.
---@class TRInventoryClient
local inventory = {}

---@param item string
---@param metadata? table
---@return integer
function inventory.getCount(item, metadata) return bridge.getCount(item, metadata) end

---@param item string
---@param count? integer default 1
---@param metadata? table
---@return boolean
function inventory.hasItem(item, count, metadata)
    return bridge.getCount(item, metadata) >= (count or 1)
end

---@param name string
---@return TRItem?
function inventory.getItem(name) return bridge.getItem(name) end

---The picture the inventory shows for an item, for a NUI page's <img>.
---@param name string
---@return string? url nil when the item isn't there or has no picture
function inventory.getImage(name) return bridge.getImage(name) end

---The stash must be registered on the server (TR.inventory.registerStash).
---@param id string
function inventory.openStash(id) return bridge.openStash(id) end

function inventory.close() bridge.close() end

---Keeps the inventory shut and its items from being used, e.g. while cuffed. qb-inventory goes by the framework's
---cuffed flag instead (TR.player.setCuffed), so there it does nothing.
---@param busy boolean
function inventory.setBusy(busy) bridge.setBusy(busy == true) end

return inventory
