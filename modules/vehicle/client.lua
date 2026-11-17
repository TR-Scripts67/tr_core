-- A car's look (livery, extras, colours) read and set, e.g. a garage's car as an admin set it up.

---@class TRVehicleLook
---@field livery? integer the model's own livery (SetVehicleLivery)
---@field modLivery? integer a livery fitted as a mod (slot 48), as most add-on cars have them
---@field extras? integer[] the extras turned on; every other one the car has is turned off
---@field colours? { primary?: string, secondary?: string } custom metallic paint, '#rrggbb'; one left out keeps the car's own

---@class TRVehicleClient
local vehicle = {}

local LIVERY_MOD = 48
local MOST_EXTRAS = 20
local METALLIC = 1 -- SetVehicleModColor's paint type
-- No native tells a submarine: GTA's own are these.
local SUBMARINES = { 'submersible', 'submersible2', 'kosatka', 'avisa' }

---@param model string | integer
---@return string? kind GTA's vehicle type for `TR.vehicle.spawn` on the server; nil: not a vehicle
function vehicle.typeOf(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return end
    for _, name in ipairs(SUBMARINES) do
        if joaat(name) == hash then return 'submarine' end
    end
    if IsThisModelABike(hash) or IsThisModelABicycle(hash) then return 'bike' end
    if IsThisModelAHeli(hash) then return 'heli' end
    if IsThisModelAPlane(hash) then return 'plane' end
    if IsThisModelABoat(hash) or IsThisModelAJetski(hash) then return 'boat' end
    if IsThisModelATrain(hash) then return 'train' end
    return 'automobile'
end

---@param r integer
---@param g integer
---@param b integer
local function hexOf(r, g, b)
    return ('#%02x%02x%02x'):format(r, g, b)
end

---@param hex any
---@return integer?, integer?, integer?
local function rgbOf(hex)
    if type(hex) ~= 'string' or not hex:match('^#%x%x%x%x%x%x$') then return end
    return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

---@param entity integer
---@return TRVehicleLook
function vehicle.getLook(entity)
    local look = { extras = {}, colours = {} }
    if GetIsVehiclePrimaryColourCustom(entity) then look.colours.primary = hexOf(GetVehicleCustomPrimaryColour(entity)) end
    if GetIsVehicleSecondaryColourCustom(entity) then look.colours.secondary = hexOf(GetVehicleCustomSecondaryColour(entity)) end
    local livery = GetVehicleLivery(entity)
    if livery >= 0 then look.livery = livery end
    local modLivery = GetVehicleMod(entity, LIVERY_MOD)
    if modLivery >= 0 then look.modLivery = modLivery end
    for id = 0, MOST_EXTRAS do
        if DoesExtraExist(entity, id) and IsVehicleExtraTurnedOn(entity, id) then look.extras[#look.extras + 1] = id end
    end
    return look
end

---Only what `look` holds is changed. The car needs to be ours on the network for it to show to others.
---@param entity integer
---@param look TRVehicleLook
function vehicle.setLook(entity, look)
    if look.livery then SetVehicleLivery(entity, look.livery) end
    if look.modLivery then
        SetVehicleModKit(entity, 0)
        SetVehicleMod(entity, LIVERY_MOD, look.modLivery, false)
    end
    if look.extras then
        local on = {}
        for _, id in ipairs(look.extras) do on[id] = true end
        for id = 0, MOST_EXTRAS do
            -- The native's last argument is "disable"
            if DoesExtraExist(entity, id) then SetVehicleExtra(entity, id, not on[id]) end
        end
    end
    local colours = type(look.colours) == 'table' and look.colours or {}
    local r, g, b = rgbOf(colours.primary)
    if r then
        SetVehicleModKit(entity, 0)
        SetVehicleModColor_1(entity, METALLIC, 0, 0)
        SetVehicleCustomPrimaryColour(entity, r, g, b)
    end
    r, g, b = rgbOf(colours.secondary)
    if r then
        SetVehicleModKit(entity, 0)
        SetVehicleModColor_2(entity, METALLIC, 0)
        SetVehicleCustomSecondaryColour(entity, r, g, b)
    end
end

---@param label string?
local function named(label)
    local text = label and label ~= '' and GetLabelText(label)
    return text and text ~= 'NULL' and text or ''
end

---What a car can wear, for a look editor. Names are the game's, '' where it has none; the first livery is livery 0.
---`paints` are its own colours (GTA's ids, primary and secondary), what it has where the look sets no colour.
---@param entity integer
---@return { liveries: string[], modLiveries: string[], extras: integer[], paints: integer[] }
function vehicle.lookOptions(entity)
    local options = { liveries = {}, modLiveries = {}, extras = {}, paints = { GetVehicleColours(entity) } }
    for i = 0, GetVehicleLiveryCount(entity) - 1 do options.liveries[#options.liveries + 1] = named(GetLiveryName(entity, i)) end
    SetVehicleModKit(entity, 0)
    for i = 0, GetNumVehicleMods(entity, LIVERY_MOD) - 1 do
        options.modLiveries[#options.modLiveries + 1] = named(GetModTextLabel(entity, LIVERY_MOD, i))
    end
    for id = 0, MOST_EXTRAS do
        if DoesExtraExist(entity, id) then options.extras[#options.extras + 1] = id end
    end
    return options
end

return vehicle
