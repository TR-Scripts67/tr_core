local ox = exports.ox_inventory

local bridge = {}

function bridge.getCount(item, metadata)
    return ox:GetItemCount(item, metadata) or 0
end

function bridge.getItem(name)
    local item = ox:Items(name)
    if not item then return end

    return { name = item.name, label = item.label, weight = item.weight, stack = item.stack, description = item.description }
end

-- As ox_inventory's own page picks it: the item's client.image (already a full link), else <imagepath>/<name>.png.
function bridge.getImage(name)
    local item = ox:Items(name)
    if not item then return end
    return item.client and item.client.image or ('%s/%s.png'):format(GetConvar('inventory:imagepath', 'nui://ox_inventory/web/images'), item.name)
end

function bridge.openStash(id)
    return ox:openInventory('stash', id)
end

function bridge.close()
    ox:closeInventory()
end

---ox_inventory's own flag: while it is set nothing opens and the hotbar uses nothing.
function bridge.setBusy(busy)
    LocalPlayer.state:set('invBusy', busy, true)
end

return bridge
