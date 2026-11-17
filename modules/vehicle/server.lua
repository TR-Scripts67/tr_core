-- Cars made by the server (they exist for everyone and stay when the player who asked for one leaves), and the cars
-- characters own.

---@class TRVehicle
local vehicle = {}

local TYPES = { automobile = true, bike = true, boat = true, heli = true, plane = true, submarine = true, trailer = true, train = true }
local WAIT_MS, STEP_MS = 5000, 10

---@param model string | integer
---@param coords vector3
---@param heading number
---@param kind? string GTA's vehicle type: 'automobile' (default), 'bike', 'boat', 'heli', 'plane', 'submarine', 'trailer' or 'train'.
---The server can't tell from a model, and the wrong one makes a car that falls apart, so ask a client (`TR.vehicle.typeOf`).
---@return integer? entity nil when it isn't there within 5 s
---@return integer? netId
function vehicle.spawn(model, coords, heading, kind)
    if kind ~= nil and not TYPES[kind] then return end
    local hash = type(model) == 'string' and joaat(model) or model
    local entity = CreateVehicleServerSetter(hash, kind or 'automobile', coords.x, coords.y, coords.z, heading + 0.0)
    local waited = 0
    while not DoesEntityExist(entity) and waited < WAIT_MS do
        Wait(STEP_MS)
        waited = waited + STEP_MS
    end
    if not DoesEntityExist(entity) then return end
    return entity, NetworkGetNetworkIdFromEntity(entity)
end

---@class TROwnedVehicle
---@field plate string
---@field model? string | integer QBCore's and Qbox's model name, ESX's model hash
---@field color? integer GTA's primary colour index

---Every car a character owns, online or not, from the framework's own tables.
---@param identifier string
---@return TROwnedVehicle[]
function vehicle.getOwned(identifier)
    if type(identifier) ~= 'string' or identifier == '' then return {} end
    return TR.player.bridge.getOwnedVehicles(identifier)
end

---@param plate string any case, spaces ignored
---@return string? identifier the character who owns the car with that plate
function vehicle.getOwner(plate)
    plate = type(plate) == 'string' and plate:gsub('%s+', ''):upper() or ''
    if plate == '' then return end
    return TR.player.bridge.getVehicleOwner(plate)
end

---Owned cars whose plate holds the text (spaces and case ignored), or every owned car without it, a page at a time.
---@param text? string
---@param offset? integer how many to skip, 0 by default
---@param limit? integer 50 by default, 100 at most
---@return TROwnedVehicle[] by plate, each with its owner's identifier as `owner`
function vehicle.searchOwned(text, offset, limit)
    text = type(text) == 'string' and text:gsub('%s+', ''):sub(1, 8) or ''
    offset = math.max(0, type(offset) == 'number' and math.floor(offset) or 0)
    limit = math.max(1, math.min(type(limit) == 'number' and math.floor(limit) or 50, 100))
    return TR.player.bridge.searchVehicles(text, offset, limit)
end

return vehicle
