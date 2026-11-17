local check = T.check

T.resource = 'tr_core'

function joaat(name)
    local hash = 0
    for i = 1, #name do hash = (hash * 31 + name:byte(i)) % 4294967296 end
    return math.tointeger(hash)
end

-- server: the car shows up after a few waits; one that never does gives nothing
local made, exists = {}, {}
function CreateVehicleServerSetter(hash, kind, x, y, z, heading)
    made[#made + 1] = { hash = hash, kind = kind, x = x, heading = heading }
    return 500 + #made
end
function DoesEntityExist(entity) return exists[entity] ~= nil and exists[entity] <= 0 or false end
function NetworkGetNetworkIdFromEntity(entity) return entity * 2 end
function Wait()
    for entity, waits in pairs(exists) do exists[entity] = waits - 1 end
end

T.boot('server', {})
exists[501] = 3
local entity, netId = TR.vehicle.spawn('police', vector3(1.0, 2.0, 3.0), 90)
check('spawn: waits for the car, gives it and its net id', entity == 501 and netId == 1002)
check('spawn: by hash, as an automobile, the heading a float', made[1].hash == joaat('police') and made[1].kind == 'automobile'
    and math.type(made[1].heading) == 'float')
TR.vehicle.spawn(joaat('policeb'), vector3(0.0, 0.0, 0.0), 0.0, 'bike')
check('spawn: a model hash and a type', made[2].hash == joaat('policeb') and made[2].kind == 'bike')
check('spawn: nothing when it never shows', TR.vehicle.spawn('police', vector3(0.0, 0.0, 0.0), 0.0) == nil)
check('spawn: an unknown type is refused before anything is made', TR.vehicle.spawn('police', vector3(0.0, 0.0, 0.0), 0.0, 'tank') == nil
    and #made == 3)

-- client: the look
local car = { livery = 2, mod = -1, extras = { [1] = true, [2] = false }, colours = { 111, 0 }, custom = {}, paintType = {} }
local calls = {}
function GetVehicleColours() return car.colours[1], car.colours[2] end
function GetIsVehiclePrimaryColourCustom() return car.custom[1] ~= nil end
function GetIsVehicleSecondaryColourCustom() return car.custom[2] ~= nil end
function GetVehicleCustomPrimaryColour() return table.unpack(car.custom[1]) end
function GetVehicleCustomSecondaryColour() return table.unpack(car.custom[2]) end
function SetVehicleModColor_1(_, paintType) car.paintType[1] = paintType end
function SetVehicleModColor_2(_, paintType) car.paintType[2] = paintType end
function SetVehicleCustomPrimaryColour(_, r, g, b) car.custom[1] = { r, g, b } end
function SetVehicleCustomSecondaryColour(_, r, g, b) car.custom[2] = { r, g, b } end
function GetVehicleLivery() return car.livery end
function GetVehicleMod(_, slot) return slot == 48 and car.mod or -1 end
function DoesExtraExist(_, id) return car.extras[id] ~= nil end
function IsVehicleExtraTurnedOn(_, id) return car.extras[id] end
function SetVehicleLivery(_, livery) car.livery = livery end
function SetVehicleModKit(_, kit) calls.kit = kit end
function SetVehicleMod(_, slot, index) if slot == 48 then car.mod = index end end
function SetVehicleExtra(_, id, disable) car.extras[id] = not disable end

T.boot('client', {})
local look = TR.vehicle.getLook(7)
check('getLook: livery, the extras that are on, no colours while the car has its own', look.livery == 2 and look.modLivery == nil
    and #look.extras == 1 and look.extras[1] == 1 and next(look.colours) == nil)
TR.vehicle.setLook(7, { modLivery = 3, extras = { 2, 9 }, colours = { primary = '#1a2B3c' } })
check('setLook: a mod livery through the mod kit', car.mod == 3 and calls.kit == 0)
check('setLook: the listed extras on, the rest off, one the car lacks left alone', car.extras[1] == false and car.extras[2] == true and car.extras[9] == nil)
check('setLook: a custom metallic colour; what the look leaves out stays', car.custom[1][1] == 26 and car.custom[1][2] == 43 and car.custom[1][3] == 60
    and car.paintType[1] == 1 and car.custom[2] == nil and car.livery == 2)
TR.vehicle.setLook(7, { colours = { primary = 111, secondary = '#ffffff' } })
check('setLook: a colour that isn\'t #rrggbb is left alone', car.custom[1][1] == 26 and car.custom[2][1] == 255 and car.paintType[2] == 1)
look = TR.vehicle.getLook(7)
check('getLook: custom colours as #rrggbb', look.colours.primary == '#1a2b3c' and look.colours.secondary == '#ffffff')

function GetVehicleLiveryCount() return 3 end
function GetLiveryName(_, i) return ({ [0] = 'LSPD_LIV', [1] = 'NOPE', [2] = nil })[i] end
function GetNumVehicleMods(_, slot) return slot == 48 and 1 or 0 end
function GetModTextLabel(_, slot, i) return slot == 48 and i == 0 and 'SHERIFF_LIV' or nil end
function GetLabelText(label) return ({ LSPD_LIV = 'Los Santos', SHERIFF_LIV = 'Sheriff' })[label] or 'NULL' end
car.extras = { [1] = true, [2] = false, [5] = true }
local options = TR.vehicle.lookOptions(7)
check('lookOptions: liveries by the game\'s name, none where it has none', #options.liveries == 3 and options.liveries[1] == 'Los Santos'
    and options.liveries[2] == '' and options.liveries[3] == '')
check('lookOptions: mod liveries, every extra the car has, its own paints', #options.modLiveries == 1 and options.modLiveries[1] == 'Sheriff'
    and #options.extras == 3 and options.extras[1] == 1 and options.extras[3] == 5 and options.paints[1] == 111 and options.paints[2] == 0)
function GetVehicleLiveryCount() return -1 end
check('lookOptions: a car without liveries', #TR.vehicle.lookOptions(7).liveries == 0)

local models = {
    [joaat('police')] = 'car', [joaat('policeb')] = 'bike', [joaat('polmav')] = 'heli', [joaat('predator')] = 'boat', [joaat('submersible')] = 'car',
}
function IsModelInCdimage(hash) return models[hash] ~= nil end
function IsModelAVehicle(hash) return models[hash] ~= nil end
function IsThisModelABike(hash) return models[hash] == 'bike' end
function IsThisModelABicycle() return false end
function IsThisModelAHeli(hash) return models[hash] == 'heli' end
function IsThisModelAPlane() return false end
function IsThisModelABoat(hash) return models[hash] == 'boat' end
function IsThisModelAJetski() return false end
function IsThisModelATrain() return false end
check('typeOf: car, bike, heli, boat, submarine', TR.vehicle.typeOf('police') == 'automobile' and TR.vehicle.typeOf('policeb') == 'bike'
    and TR.vehicle.typeOf('polmav') == 'heli' and TR.vehicle.typeOf(joaat('predator')) == 'boat' and TR.vehicle.typeOf('submersible') == 'submarine')
check('typeOf: nothing for a model the game lacks', TR.vehicle.typeOf('nope') == nil)

T.done('tr_core/vehicle')
