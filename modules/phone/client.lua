---@class TRPhoneApp
---@field id string letters, digits, _ and -
---@field name string
---@field description? string
---@field icon string a file in your resource
---@field page string the app's page, a file in your resource that loads tr_core/web/phone/app.js
---@field preinstalled? boolean on the phone without installing it from the phone's store (default true)
---@field onOpen? fun()
---@field onClose? fun()

---@class TRPhoneClient
local phone = {}

local bridge = TR.bridge('phone')
local resource = GetCurrentResourceName()
local apps = {} ---@type table<string, table>

local function add(app)
    local ok, err = pcall(bridge.add, app)
    if not ok then TR.log.error('the %s app could not be put on %s: %s', app.id, TR.system('phone'), err) end
end

local function addAll()
    for _, app in pairs(apps) do add(app) end
end

local function phoneStarted()
    return bridge.resource ~= nil and GetResourceState(bridge.resource) == 'started'
end

---Puts your app on the player's phone, again each time the phone script restarts, and takes it off when your
---resource stops. Messages for its page go through `send`.
---@param app TRPhoneApp
function phone.app(app)
    assert(type(app) == 'table' and type(app.id) == 'string' and app.id:match('^[%w_%-]+$'), 'TR.phone.app needs an id')
    assert(type(app.name) == 'string' and type(app.icon) == 'string' and type(app.page) == 'string', 'TR.phone.app needs a name, icon and page')

    local entry = {
        id = app.id,
        name = app.name,
        description = app.description or '',
        icon = ('https://cfx-nui-%s/%s'):format(resource, app.icon),
        page = ('%s/%s'):format(resource, app.page),
        url = ('https://cfx-nui-%s/%s'):format(resource, app.page),
        preinstalled = app.preinstalled ~= false,
        onOpen = app.onOpen,
        onClose = app.onClose,
    }
    apps[app.id] = entry
    if phoneStarted() then CreateThread(function() add(entry) end) end
end

---A message for the app's page, as `{ action, data }` on its window (useNuiEvent). It goes through your
---resource's own page, which loads tr_core/web/phone/host.js.
---@param id string
---@param action string
---@param data? any
function phone.send(id, action, data)
    SendNUIMessage({ trPhone = id, action = action, data = data })
end

if bridge.readyEvent then
    AddEventHandler(bridge.readyEvent, function()
        if next(apps) then CreateThread(addAll) end
    end)
end

AddEventHandler('onClientResourceStart', function(name)
    if name ~= bridge.resource or bridge.readyEvent or not next(apps) then return end
    -- Phones take their apps a moment after they start (lb-phone asks for 500 ms).
    CreateThread(function()
        Wait(500)
        addAll()
    end)
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= resource then return end
    for id in pairs(apps) do pcall(bridge.remove, id) end
end)

RegisterNUICallback('tr_phone:typing', function(data, cb)
    cb({})
    pcall(bridge.typing, type(data) == 'table' and data.on == true)
end)

if bridge.notify then
    RegisterNetEvent(resource .. ':tr_phone:notify', function(note)
        if type(note) == 'table' then pcall(bridge.notify, note) end
    end)
end

return phone
