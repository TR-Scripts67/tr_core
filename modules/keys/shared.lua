---@class TRKeysShared
local keys = {}

---Plate text without the padding GTA adds.
---@param vehicle integer
---@return string
function keys.plate(vehicle)
    return TR.utils.trim(GetVehicleNumberPlateText(vehicle) or '')
end

return keys
