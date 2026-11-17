local keys = ...
local bridge = TR.bridge('keys')

---@class TRKeys : TRKeysShared
---@cast keys TRKeys

---@param src integer
---@param vehicle integer
---@return boolean
function keys.hasKeys(src, vehicle)
    if not DoesEntityExist(vehicle) then return false end
    return bridge.hasKeys(src, vehicle, keys.plate(vehicle)) == true
end

---@param src integer
---@param vehicle integer
function keys.giveKeys(src, vehicle)
    if not DoesEntityExist(vehicle) then return end
    bridge.giveKeys(src, vehicle, keys.plate(vehicle))
end

---@param src integer
---@param vehicle integer
function keys.removeKeys(src, vehicle)
    if not DoesEntityExist(vehicle) then return end
    bridge.removeKeys(src, vehicle, keys.plate(vehicle))
end

---Starts the engine without giving keys (a hotwire). false when the keys script can't do that.
---@param src integer
---@param vehicle integer
---@return boolean supported
function keys.startEngine(src, vehicle)
    if not DoesEntityExist(vehicle) or not bridge.startEngine then return false end
    bridge.startEngine(src, vehicle, keys.plate(vehicle))
    return true
end

return keys
