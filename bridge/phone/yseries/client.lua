local _, shared = ...
local name = shared.resourceOf(shared.YSERIES)
local ys = exports[name]
local bridge = { resource = name }

local LOAD_MS = 10000

function bridge.add(app)
    -- Its own app template waits for this before adding one.
    local waited = 0
    while waited < LOAD_MS do
        local ok, loaded = pcall(function() return ys:GetDataLoaded() end)
        if not ok or loaded then break end
        Wait(250)
        waited = waited + 250
    end
    ys:AddCustomApp({
        key = app.id,
        name = app.name,
        defaultApp = app.preinstalled,
        ui = app.url,
        icon = { yos = app.icon, humanoid = app.icon },
    })
end

function bridge.remove(id)
    ys:RemoveCustomApp(id)
end

-- Its export takes whether the game keeps the keys: not while typing.
function bridge.typing(on)
    ys:SetNuiFocusKeepInput(not on)
end

return bridge
