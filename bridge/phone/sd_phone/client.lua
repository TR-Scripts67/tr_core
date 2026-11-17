local sd = exports['sd-phone']
-- sd-phone fires this as it starts and on every restart, once it takes apps.
local bridge = { resource = 'sd-phone', readyEvent = 'sd-phone:ready' }

function bridge.add(app)
    local ok, err = sd:addCustomApp({
        identifier = app.id,
        name = app.name,
        description = app.description,
        defaultApp = app.preinstalled,
        ui = app.page,
        icon = app.icon,
        fixBlur = true,
        onOpen = app.onOpen,
        onClose = app.onClose,
    })
    if ok == false then error(err or 'refused', 0) end
end

function bridge.remove(id)
    sd:removeCustomApp(id)
end

function bridge.typing() end

return bridge
