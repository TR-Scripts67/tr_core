-- Load with shared_script '@tr_core/init.lua'. A module loads the first time TR.<name> is used.

if TR ~= nil then return end

local CORE = 'tr_core'
local resource = GetCurrentResourceName()
local context = IsDuplicityVersion() and 'server' or 'client'

if resource ~= CORE then
    local state = GetResourceState(CORE)

    if state ~= 'started' and state ~= 'starting' then
        error(('^1%s requires %s to be started first (current state: %s)^0'):format(resource, CORE, state), 0)
    end

    -- Fails now with a clear error instead of later on whatever the older tr_core lacks.
    local needs = GetResourceMetadata(resource, 'tr_core_version', 0)
    local has = GetResourceMetadata(CORE, 'version', 0) or '0'
    if needs then
        local function parts(v)
            local out = {}
            for n in tostring(v):gmatch('%d+') do out[#out + 1] = tonumber(n) end
            return out
        end
        local a, b = parts(has), parts(needs)
        for i = 1, math.max(#a, #b) do
            local x, y = a[i] or 0, b[i] or 0
            if x > y then break end
            if x < y then
                local msg = ('^1%s needs %s %s or newer, but this server has %s %s: update %s^0'):format(resource, CORE, needs, CORE, has, CORE)
                -- So the resource's other files fail with this too, not on a missing TR.
                TR = setmetatable({}, { __index = function() error(msg, 0) end })
                error(msg, 0)
            end
        end
    end
end

---@param path string
---@return function?
local function loadChunk(path)
    local code = LoadResourceFile(CORE, path)
    if not code then return end

    local fn, err = load(code, ('@@%s/%s'):format(CORE, path))

    if not fn then
        error(('^1[tr_core] failed to load %s: %s^0'):format(path, err), 0)
    end

    return fn
end

local config = loadChunk('config.lua')
config = config and config() or {}
if type(config) ~= 'table' then error('^1[tr_core] config.lua must return a table^0', 0) end

-- In detection order. qbx_core and ox_target `provide` qb-core / qb-target, so they come first.
local providers = {
    framework = {
        { resource = 'qbx_core', name = 'qbx' },
        { resource = 'es_extended', name = 'esx' },
        { resource = 'qb-core', name = 'qb' },
    },
    inventory = {
        { resource = 'ox_inventory', name = 'ox_inventory' },
        { resource = 'qb-inventory', name = 'qb_inventory' },
    },
    target = {
        { resource = 'ox_target', name = 'ox_target' },
        { resource = 'qb-target', name = 'qb_target' },
    },
    -- zyke_vehiclekeys provides qbx_vehiclekeys, qb-vehiclekeys and wasabi_carlock, so it's first.
    -- qb-vehiclekeys is last: qbx_vehiclekeys provides it and qb servers often keep a stopped copy.
    keys = {
        { resource = 'zyke_vehiclekeys', name = 'zyke_vehiclekeys' },
        { resource = 'qbx_vehiclekeys', name = 'qbx_vehiclekeys' },
        { resource = 'wasabi_carlock', name = 'wasabi_carlock' },
        { resource = 'MrNewbVehicleKeys', name = 'mrnewb_vehiclekeys' },
        { resource = 'Renewed-Vehiclekeys', name = 'renewed_vehiclekeys' },
        { resource = 'qb-vehiclekeys', name = 'qb_vehiclekeys' },
    },
    -- lc_fuel provides LegacyFuel, so LegacyFuel comes last.
    fuel = {
        { resource = 'ox_fuel', name = 'ox_fuel' },
        { resource = 'lc_fuel', name = 'lc_fuel' },
        { resource = 'cdn-fuel', name = 'cdn_fuel' },
        { resource = 'ps-fuel', name = 'ps_fuel' },
        { resource = 'LegacyFuel', name = 'legacyfuel' },
    },
    -- tk_dispatch provides ps-dispatch, qs-dispatch and cd_dispatch, so it's first. cd_dispatch3d takes
    -- cd_dispatch's alerts. MDTs are last: a server that also runs a dispatch script wants the alerts there.
    dispatch = {
        { resource = 'tk_dispatch', name = 'tk_dispatch' },
        { resource = 'cd_dispatch3d', name = 'cd_dispatch3d' },
        { resource = 'rcore_dispatch', name = 'rcore_dispatch' },
        { resource = 'core_dispatch', name = 'core_dispatch' },
        { resource = 'qs-dispatch', name = 'qs_dispatch' },
        { resource = 'cd_dispatch', name = 'cd_dispatch' },
        { resource = 'ps-dispatch', name = 'ps_dispatch' },
        { resource = 'origen_police', name = 'origen_police' },
        { resource = 'lb-tablet', name = 'lb_tablet' },
    },
    -- Renewed-Banking runs on every framework, so a server that has it keeps its job accounts there.
    society = {
        { resource = 'Renewed-Banking', name = 'renewed_banking' },
        { resource = 'qb-banking', name = 'qb_banking' },
        { resource = 'esx_addonaccount', name = 'esx_addonaccount' },
    },
    -- sd-phone is first in case it provides lb-phone for lb's apps.
    phone = {
        { resource = 'sd-phone', name = 'sd_phone' },
        { resource = 'lb-phone', name = 'lb_phone' },
        { resource = 'gksphone', name = 'gksphone' },
        { resource = 'yseries', name = 'yseries' },
        { resource = 'yphone', name = 'yseries' },
        { resource = 'yflip-phone', name = 'yseries' },
        { resource = 'npwd', name = 'npwd' },
    },
}

-- Kinds without a fallback are required.
local fallbacks = {
    keys = 'none',
    fuel = 'none',
    dispatch = 'none',
    society = 'none',
    phone = 'none',
    target = 'tr_core',
}

local detected = {}

local running = { started = true, starting = true }

---A running provider wins over one that's only installed, which is still used as it may start after us.
---@param kind string
---@return string
local function system(kind)
    if detected[kind] then return detected[kind] end

    local list = providers[kind]
    if not list then error(('unknown system kind "%s"'):format(kind), 2) end

    local forced = tostring(config[kind] or 'auto')

    if forced ~= 'auto' then
        -- The resource's own name works too ('qb-target', 'es_extended').
        for i = 1, #list do
            if list[i].resource == forced then forced = list[i].name end
        end
        detected[kind] = forced
        return forced
    end

    for i = 1, #list do
        if running[GetResourceState(list[i].resource)] then
            detected[kind] = list[i].name
            return list[i].name
        end
    end

    for i = 1, #list do
        if GetResourceState(list[i].resource) ~= 'missing' then
            detected[kind] = list[i].name
            return list[i].name
        end
    end

    if fallbacks[kind] then
        detected[kind] = fallbacks[kind]
        return fallbacks[kind]
    end

    error(('no supported %s resource found'):format(kind), 2)
end

---@type TR
local TR = {
    name = CORE,
    resource = resource,
    context = context,
    version = GetResourceMetadata(CORE, 'version', 0),
    system = system,
    config = config,
}

local bridgeShared = {}

---Provider files get (provider, shared), shared being bridge/<kind>/shared.lua if there is one.
---@param kind string
---@return table
function TR.bridge(kind)
    local provider = system(kind)
    local path = ('bridge/%s/%s/%s.lua'):format(kind, provider, context)
    local fn = loadChunk(path)

    if not fn then
        error(('%s provider "%s" has no %s implementation'):format(kind, provider, context), 2)
    end

    if bridgeShared[kind] == nil then
        local sharedFn = loadChunk(('bridge/%s/shared.lua'):format(kind))
        bridgeShared[kind] = sharedFn and sharedFn() or false
    end

    return fn(provider, bridgeShared[kind] or nil)
end

setmetatable(TR, {
    __index = function(self, name)
        if type(name) ~= 'string' or not name:match('^[%w_]+$') then return end

        local dir = ('modules/%s'):format(name)
        local shared = loadChunk(dir .. '/shared.lua')
        local side = loadChunk(('%s/%s.lua'):format(dir, context))

        if not shared and not side then
            error(('TR.%s does not exist in the %s context'):format(name, context), 2)
        end

        local module = shared and shared() or nil
        if side then module = side(module) end

        rawset(self, name, module)
        return module
    end,
})

_ENV.TR = TR
