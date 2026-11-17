-- zyke's engine follows the `engine` state bag; its own hotwire starts cars this way too.
local keys = exports.zyke_vehiclekeys
local bridge = {}

function bridge.hasKeys(src, vehicle, plate) return keys:HasKey(src, plate) end
function bridge.giveKeys(src, vehicle, plate) keys:GiveKey(src, plate, true) end
function bridge.removeKeys(src, vehicle, plate) keys:RemoveKey(src, plate) end
function bridge.startEngine(src, vehicle, plate) Entity(vehicle).state:set('engine', true, true) end

return bridge
