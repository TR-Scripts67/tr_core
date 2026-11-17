-- A resource with its own ui_page gets TR.ui drawn there (it mounts <Overlays /> from @tr/ui) and doesn't need
-- tr_ui; the rest use tr_ui's. Menu item fields are documented in tr_ui/client/menu.lua.

---@class TRUi
local ui = {}

---@param level? integer where the error points, for error()
local function tr_ui(level)
    local state = GetResourceState('tr_ui')
    if state ~= 'started' and state ~= 'starting' then
        error('tr_ui is not running', level or 3)
    end
    return exports.tr_ui
end

local RESOURCE = GetCurrentResourceName()
-- tr_ui draws for itself through its exports.
local ownPage = RESOURCE ~= 'tr_ui' and GetResourceMetadata(RESOURCE, 'ui_page', 0) ~= nil
-- Any page, tr_ui's too, shares the one prompt stack.
local hasPage = GetResourceMetadata(RESOURCE, 'ui_page', 0) ~= nil

-- What was last sent, so per-frame calls that change nothing don't cross into another resource (that copies
-- the arguments every time and costs far more than comparing here). Forgotten when tr_ui (re)starts.
local HUD_REFRESH = 1000 -- ms: the same HUD is sent again this often (another resource may have taken it)
local sent = { hud = nil, hudAt = 0, blocks = false, loops = {}, texts = {} }
local sounds -- this resource's own sound files: on its page, else registered again when tr_ui restarts

local function onPage(name) return ownPage and sounds ~= nil and sounds[name] ~= nil end

AddEventHandler('onClientResourceStart', function(name)
    if name ~= 'tr_ui' then return end
    sent.hud, sent.texts = nil, {}
    for id, l in pairs(sent.loops) do
        if not onPage(l.name) then sent.loops[id] = nil end
    end
    if sounds and not ownPage then exports.tr_ui:registerSounds(sounds) end
end)

local function copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

local function same(a, b)
    if a == b then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- The page's own code mustn't use these NUI names: menu:*, hud:*, textui:*, sound:*, capture:*, tr:hello, tr:ready.

local page = {}
local pageReady, pageQueue = false, {}
local menus, openMenu = {}, nil ---@type table<string, TRMenu>, string?
local prompts = {} ---@type table<string, number> shown prompts: when each appeared (stamp)
local lastAt = 0

---On the game timer (one clock for every resource) and never the same twice: pages stack prompts in this order.
local function stamp()
    lastAt = math.max(GetGameTimer() + 0.0, lastAt + 0.001)
    return lastAt
end

local function toPage(action, data)
    if not pageReady then
        pageQueue[#pageQueue + 1] = { action = action, data = data }
        return
    end
    SendNUIMessage({ action = action, data = data })
end

local function run(fn, ...)
    if not fn then return end
    local ok, err = pcall(fn, ...)
    if not ok then TR.log.error('menu callback failed: %s', err) end
end

---JSON numbers from the page may arrive as floats.
local function toIndex(value)
    value = tonumber(value)
    if not value or value ~= math.floor(value) or value < 0 then return end
    return math.tointeger(value) + 1
end

function page:registerMenu(id, data)
    assert(type(id) == 'string', 'menu id must be a string')
    assert(type(data) == 'table' and type(data.title) == 'string' and type(data.items) == 'table', 'menu needs a title and items')
    menus[id] = data
end

function page:showMenu(id)
    local menu = menus[id]
    if not menu then return TR.log.error('menu "%s" is not registered', id) end

    local items = {}
    for i, item in ipairs(menu.items) do
        items[i] = {
            label = tostring(item.label),
            detail = item.detail ~= nil and tostring(item.detail) or nil,
            icon = type(item.icon) == 'string' and item.icon or nil,
        }
    end

    openMenu = id
    toPage('menu:open', { id = id, title = menu.title, items = items, closeLabel = menu.closeLabel })
    SetNuiFocus(true, true)
end

function page:hideMenu(runOnClose)
    if not openMenu then return end
    local menu = menus[openMenu]
    openMenu = nil

    toPage('menu:close')
    SetNuiFocus(false, false)
    if runOnClose ~= false and menu then run(menu.onClose) end
end

function page:getOpenMenu() return openMenu end

function page:setHud(state) toPage('hud:set', state) end
function page:hideHud() toPage('hud:hide') end

function page:flashHud(text, tone, duration)
    if type(text) ~= 'string' then return end
    toPage('hud:flash', { text = text, tone = tone or 'default', duration = math.type(duration) == 'integer' and duration or 1600 })
end

function page:showTextUI(id, data)
    if type(id) ~= 'string' or type(data) ~= 'table' or type(data.text) ~= 'string' then return end
    prompts[id] = prompts[id] or stamp()
    toPage('textui:show', {
        id = id,
        at = prompts[id],
        text = data.text,
        key = data.key ~= nil and tostring(data.key) or nil,
        sub = type(data.sub) == 'string' and data.sub or nil,
    })
end

function page:hideTextUI(id)
    prompts[id] = nil
    toPage('textui:hide', { id = id })
end

function page:isTextUIShown(id) return prompts[id] ~= nil end

local AUDIO = { ogg = true, wav = true, mp3 = true, flac = true, opus = true, webm = true }

---A sound marked custom has no files: the page plays it with code of its own.
function page:registerSounds(list)
    local out = {}
    for name, sound in pairs(list) do
        local files = {}
        local custom = type(name) == 'string' and type(sound) == 'table' and sound.custom == true
        if custom then
            out[name] = { files = files, custom = true }
        elseif type(name) == 'string' and type(sound) == 'table' and type(sound.files) == 'table' then
            for _, file in ipairs(sound.files) do
                local ext = type(file) == 'string' and not file:find('..', 1, true) and file:match('%.(%w+)$')
                if ext and AUDIO[ext:lower()] then files[#files + 1] = file end
            end
        end
        if #files > 0 then
            out[name] = { files = files, level = tonumber(sound.level), variance = tonumber(sound.variance), loop = sound.loop == true }
        elseif not custom then
            TR.log.warn('sound %s has no audio files it can play', tostring(name))
        end
    end
    toPage('sound:register', { resource = RESOURCE, sounds = out })
end

function page:playSound(name, volume) toPage('sound:play', { name = name, volume = tonumber(volume) }) end

function page:loopSound(id, name, params, volume)
    toPage('sound:loop', { id = id, name = name, params = params, volume = tonumber(volume) })
end

function page:stopSound(id) toPage('sound:stop', { id = id }) end

local probes, nextProbe = {}, 0 ---@type table<integer, promise>, integer

local function probed(id, hits)
    local p = probes[id]
    if not p then return end
    probes[id] = nil
    p:resolve(hits)
end

function page:probeFrame(points)
    nextProbe = nextProbe + 1
    toPage('capture:probe', { id = nextProbe, points = points })
    return nextProbe
end

if ownPage then
    -- The page says it's loaded when it mounts, and again when asked: this file may load after it did.
    RegisterNUICallback('tr:ready', function(_, cb)
        cb({})
        pageReady = true
        for i = 1, #pageQueue do SendNUIMessage(pageQueue[i]) end
        pageQueue = {}
    end)
    SendNUIMessage({ action = 'tr:hello' })

    RegisterNUICallback('menu:select', function(data, cb)
        cb({})
        local menu = openMenu and menus[openMenu]
        local index = toIndex(data.index)
        local item = menu and index and menu.items[index]
        if not item then return end

        run(item.onSelect, item.args)
        if item.close then page:hideMenu() end
    end)

    RegisterNUICallback('menu:close', function(_, cb)
        cb({})
        page:hideMenu()
    end)

    RegisterNUICallback('capture:result', function(data, cb)
        cb({})
        local id = type(data) == 'table' and tonumber(data.id)
        if id then probed(math.tointeger(id) or id, type(data.hits) == 'string' and data.hits or false) end
    end)

    -- Stopping with the menu open mustn't leave the mouse stuck on a page that's gone.
    AddEventHandler('onResourceStop', function(name)
        if name == RESOURCE and openMenu then SetNuiFocus(false, false) end
    end)
end

-- Pages draw prompts on the right edge, so two pages' prompts would overlap: each reports its own
-- (textui:layout) and leaves room for the others' (textui:others), one stack in the order they appeared.

local STACK_MAX = 32 -- prompts a page may report
local stack = { mine = {}, others = {}, seen = false } -- others: resource -> its prompts

local function cleanLayout(items)
    local out = {}
    if type(items) ~= 'table' then return out end

    for _, item in ipairs(items) do
        if #out >= STACK_MAX then break end
        if type(item) == 'table' and type(item.id) == 'string' and #item.id <= 128 then
            local at, h = tonumber(item.at), tonumber(item.h)
            if at and h and h >= 0 and h <= 400 then out[#out + 1] = { id = item.id, at = at, h = h } end
        end
    end
    return out
end

local function othersList()
    local out = {}
    for resource, items in pairs(stack.others) do
        for _, item in ipairs(items) do
            out[#out + 1] = { resource = resource, id = item.id, at = item.at, h = item.h }
        end
    end
    return out
end

local function pushOthers()
    if stack.seen then SendNUIMessage({ action = 'textui:others', data = { items = othersList() } }) end
end

if hasPage then
    RegisterNUICallback('textui:layout', function(data, cb)
        stack.seen = true
        local items = cleanLayout(type(data) == 'table' and data.items)
        if not same(items, stack.mine) then
            stack.mine = items
            TriggerEvent('tr:textui:layout', RESOURCE, items)
        end
        cb({ others = othersList() })
    end)

    AddEventHandler('tr:textui:layout', function(resource, items)
        if type(resource) ~= 'string' or resource == RESOURCE then return end
        items = cleanLayout(items)
        if #items == 0 then items = nil end
        if same(items, stack.others[resource]) then return end
        stack.others[resource] = items
        pushOthers()
    end)

    AddEventHandler('tr:textui:hello', function(resource)
        if resource ~= RESOURCE and #stack.mine > 0 then TriggerEvent('tr:textui:layout', RESOURCE, stack.mine) end
    end)

    AddEventHandler('onClientResourceStop', function(name)
        if not stack.others[name] then return end
        stack.others[name] = nil
        pushOthers()
    end)

    TriggerEvent('tr:textui:hello', RESOURCE)
end

local function backend()
    if ownPage then return page end
    return tr_ui(4)
end

---@class TRUiMenu
ui.menu = {}

---Use 'resource:name' ids.
---@param id string
---@param data TRMenu
function ui.menu.register(id, data)
    -- The text beside Esc, from the resource's locale when it has menu.close.
    if type(data) == 'table' and data.closeLabel == nil then
        local text = TR.locale.t('menu.close')
        if text ~= 'menu.close' then data.closeLabel = text end
    end
    backend():registerMenu(id, data)
end

---@param id string
function ui.menu.show(id) backend():showMenu(id) end

---Its onClose runs unless runOnClose is false.
---@param runOnClose? boolean
function ui.menu.hide(runOnClose) backend():hideMenu(runOnClose) end

---@return string? id
function ui.menu.getOpen() return backend():getOpenMenu() end

---Display only. Fields are documented in tr_ui/client/hud.lua.
---@class TRUiHud
ui.hud = {}

---Call every frame with the whole state; only changes are sent to the UI.
---@param state TRHudState
function ui.hud.set(state)
    local now = GetGameTimer()
    if sent.hud and now - sent.hudAt < HUD_REFRESH and same(state, sent.hud) then return end
    -- An activity has started: tr_core's interaction keeps out of its way (its key would clash). Not for a tool
    -- that's only held ready (interact = true), which is used on what the interaction picks.
    local blocks = not state.interact
    if blocks ~= sent.blocks then TriggerEvent('tr:hud', RESOURCE, blocks) end
    sent.hud, sent.hudAt, sent.blocks = copy(state), now, blocks
    backend():setHud(state)
end

function ui.hud.hide()
    if sent.hud == false then return end
    if sent.blocks then TriggerEvent('tr:hud', RESOURCE, false) end
    sent.hud, sent.blocks = false, false
    backend():hideHud()
end

---@param text string
---@param tone? 'default' | 'success' | 'error' | 'muted'
---@param duration? integer ms, default 1600
function ui.hud.flash(text, tone, duration) backend():flashHud(text, tone, duration) end

---Fields are documented in tr_ui/client/textui.lua.
---@class TRUiTextUI
ui.textui = {}

---Call when it should appear, not every frame. Use 'resource:name' ids.
---@param id string
---@param data { text: string, key?: string, sub?: string }
function ui.textui.show(id, data)
    if same(data, sent.texts[id]) then return end
    sent.texts[id] = copy(data)
    backend():showTextUI(id, data)
end

---@param id string
function ui.textui.hide(id)
    if sent.texts[id] == nil then return end
    sent.texts[id] = nil
    backend():hideTextUI(id)
end

---@param id string
---@return boolean
function ui.textui.isShown(id) return backend():isTextUIShown(id) end

---As a short label ('G', 'E'); keys without one (mouse buttons, some special keys) give `fallback`.
---@param command string
---@param fallback? string
---@return string?
function ui.keyOf(command, fallback)
    local button = GetControlInstructionalButton(0, (joaat(command) | 0x80000000) & 0xFFFFFFFF, true)
    if type(button) == 'string' and button:find('^t_.') then return button:sub(3) end
    return fallback
end

---tr_ui's own (names in tr_ui/client/sound.lua) and the ones a resource ships (register).
---@class TRUiSound
ui.sound = {}

local function player(name)
    if onPage(name) then return page end
    return tr_ui(4)
end

---Call once when the resource starts, and list the files in its fxmanifest `files`. Prefix the names:
---tr_ui's own can't be replaced. files: one is picked at random each play. level: 0..1 (default 0.7).
---variance: a small random pitch change (e.g. 0.05). loop: play it with sound.loop.
---custom: the page plays it with its own code; no files, and the page mounts <Overlays sounds={false} />.
---@param list table<string, { files?: string[], level?: number, variance?: number, loop?: boolean, custom?: boolean }>
function ui.sound.register(list)
    sounds = list
    if ownPage then return page:registerSounds(list) end
    tr_ui():registerSounds(list)
end

---@param name string
---@param volume? number 0..1
function ui.sound.play(name, volume) player(name):playSound(name, volume) end

---Call every frame while it should play.
---@param id string
---@param name string
---@param params? table
---@param volume? number 0..1
function ui.sound.loop(id, name, params, volume)
    local last = sent.loops[id]
    if last and last.name == name and last.volume == volume and same(params, last.params) then return end
    sent.loops[id] = { name = name, volume = volume, params = copy(params) }
    player(name):loopSound(id, name, params, volume)
end

---@param id string
function ui.sound.stop(id)
    local last = sent.loops[id]
    if not last then return end
    sent.loops[id] = nil
    player(last.name):stopSound(id)
end

local listening = false

---Which screen points show a magenta marker (DrawMarker 255, 0, 255) this frame. Yields a frame or two;
---keep drawing the markers until it returns.
---@param points number[] flat x, y pairs, 0..1 from the top left (GetScreenCoordFromWorldCoord)
---@param timeout? integer ms, default 2000
---@return string|false hits '1' / '0' per point, or false if the frame couldn't be read
function ui.probeFrame(points, timeout)
    if not ownPage and not listening then
        listening = true
        AddEventHandler('tr_ui:frameProbed', probed)
    end

    local id = backend():probeFrame(points)
    local p = promise.new()
    probes[id] = p
    SetTimeout(timeout or 2000, function()
        if probes[id] then
            probes[id] = nil
            p:resolve(false)
        end
    end)
    return Citizen.Await(p)
end

return ui
