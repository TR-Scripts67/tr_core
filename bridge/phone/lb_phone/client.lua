local lb = exports['lb-phone']
local bridge = { resource = 'lb-phone' }

function bridge.add(app)
    local ok, err = lb:AddCustomApp({
        identifier = app.id,
        name = app.name,
        description = app.description,
        ui = app.page,
        icon = app.icon,
        defaultApp = app.preinstalled,
        fixBlur = true, -- pages sized in em, as lb asks for it
        onOpen = app.onOpen,
        onClose = app.onClose,
    })
    if ok == false then error(err or 'refused', 0) end
end

function bridge.remove(id)
    lb:RemoveCustomApp(id)
end

function bridge.typing() end

return bridge
