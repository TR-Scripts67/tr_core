local keys = exports.qbx_vehiclekeys
local bridge = {}

function bridge.hasKeys(vehicle, plate) return keys:HasKeys(vehicle) end

return bridge
