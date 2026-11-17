-- NPWD 3.x has no export for adding an app: it loads web/dist/remoteEntry.js of each resource listed in
-- its config.json `apps`. That resource ships the remote, which frames the app's page.
local npwd = exports['npwd']
local bridge = { resource = 'npwd' }

local function listed(resource)
    local config = TR.utils.decode(LoadResourceFile('npwd', 'config.json'))
    local apps = config and config.apps
    if type(apps) ~= 'table' then return false end
    for _, name in ipairs(apps) do
        if name == resource then return true end
    end
    return false
end

local warned = false
function bridge.add()
    local resource = GetCurrentResourceName()
    if warned or listed(resource) then return end
    warned = true
    TR.log.warn('add "%s" to "apps" in npwd/config.json, then restart npwd, to put its app on the phone', resource)
end

function bridge.remove() end

function bridge.typing() end

function bridge.notify(note)
    npwd:createNotification({
        notisId = ('%s:%d'):format(GetCurrentResourceName(), GetGameTimer()),
        appId = note.app,
        secondaryTitle = note.title,
        content = note.text,
        duration = 5000,
    })
end

return bridge
