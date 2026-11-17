local check = T.check

T.resource = 'tr_core'
T.boot('client', {})

-- The player stands at the middle, their feet at z 0, on a floor that ends at x 1. A car's roof is at z 0.8 over x -2..-1.
-- The camera's ray hits whatever `aim` says; a ray straight down lands on the highest surface it passes.
local PED, CRATE, PERSON, CAR = 1, 600, 601, 602
T.coords = { [PED] = vector3(0.0, 0.0, 0.98) }
local surfaces = {
    { x = { -10.0, 1.0 }, z = 0.0 },
    { x = { -2.0, -1.0 }, z = 0.8, car = true },
}
local aim ---@type { at: vector3, normal?: vector3, entity?: integer }?
local blocked = false
local kinds = { [PERSON] = 1, [CAR] = 2 }
local networked = { [CAR] = true }

local rays = {}
function GetGameplayCamCoord() return vector3(0.0, -1.0, 1.6) end
function GetGameplayCamRot() return vector3(-30.0, 0.0, 0.0) end
function StartExpensiveSynchronousShapeTestLosProbe(fx, fy, fz, tx, ty, tz, flags)
    rays[#rays + 1] = { from = vector3(fx, fy, fz), to = vector3(tx, ty, tz), flags = flags }
    return #rays
end
function GetShapeTestResult(id)
    local r = rays[id]
    if r.from == GetGameplayCamCoord() then
        if not aim then return 2, 0, vector3(0.0, 0.0, 0.0), vector3(0.0, 0.0, 0.0), 0 end
        return 2, 1, aim.at, aim.normal or vector3(0.0, 0.0, 1.0), aim.entity or 0
    end
    if r.from.x == r.to.x and r.from.y == r.to.y then
        local best
        for _, s in ipairs(surfaces) do
            local inside = r.from.x >= s.x[1] and r.from.x <= s.x[2] and s.z <= r.from.z and s.z >= r.to.z
            if inside and (r.flags & 2 ~= 0 or not s.car) and (not best or s.z > best) then best = s.z end
        end
        if not best then return 2, 0, vector3(0.0, 0.0, 0.0), vector3(0.0, 0.0, 0.0), 0 end
        return 2, 1, vector3(r.from.x, r.from.y, best), vector3(0.0, 0.0, 1.0), 0
    end
    return 2, blocked and 1 or 0, r.to, vector3(1.0, 0.0, 0.0), 0
end
function GetEntityType(entity) return kinds[entity] or 3 end
function NetworkGetEntityIsNetworked(entity) return networked[entity] == true end

local missing = {}
function joaat(name) return #name * 1000 + name:byte(1) end
function IsModelInCdimage(hash) return not missing[hash] end
function HasModelLoaded() return true end
function RequestModel() end
function SetModelAsNoLongerNeeded() end

local ents, made = {}, 600 + 100
function CreateObjectNoOffset(hash, x, y, z, networkedToo)
    made = made + 1
    ents[made] = { hash = hash, coords = vector3(x, y, z), networked = networkedToo, visible = true, collision = true }
    return made
end
function DoesEntityExist(entity) return ents[entity] ~= nil and not ents[entity].deleted end
function DeleteEntity(entity) ents[entity].deleted = true end
function FreezeEntityPosition(entity, on) ents[entity].frozen = on end
function SetEntityCollision(entity, on) ents[entity].collision = on end
function SetEntityVisible(entity, on) ents[entity].visible = on end
function SetEntityAlpha(entity, alpha) ents[entity].alpha = alpha end
function SetEntityCoordsNoOffset(entity, x, y, z) ents[entity].coords = vector3(x, y, z) end
function SetEntityHeading(entity, heading) ents[entity].heading = heading end
function AttachEntityToEntity(entity, to, _, x, y, z) ents[entity].attached = { to = to, at = vector3(x, y, z) } end

local just, held = {}, {}
function IsDisabledControlJustPressed(_, key) return just[key] == true end
function IsDisabledControlPressed(_, key) return held[key] == true end
function IsControlPressed(_, key) return held[key] == true end
function DisableControlAction() end
function GetFrameTime() return 0.016 end
local ragdoll = false
function IsEntityDead() return false end
function IsPedRagdoll() return ragdoll end
function IsPedFalling() return false end
function IsPedSwimming() return false end
function IsPedInAnyVehicle() return false end

local hud
TR.ui.hud = { set = function(state) hud = state end, hide = function() hud = nil end }

-- Each step is a frame: the placing waits a frame at a time.
function Wait() coroutine.yield() end
local co, result
local function start(opts)
    co, result = coroutine.create(function() return TR.place.prop(opts) end), nil
    local _, value = coroutine.resume(co)
    result = value
end
local function step(keys)
    just = {}
    for _, key in ipairs(keys or {}) do just[key] = true end
    T.timer = T.timer + 16
    local ok, value = coroutine.resume(co)
    if not ok then error(value, 0) end
    result = value
end
local function finish(keys)
    step(keys)
    while coroutine.status(co) ~= 'dead' do step() end
end
local function why(at)
    aim = at
    step()
    return hud and hud.hint.sub
end
local function newest(n)
    local list = {}
    for id = made - n + 1, made do list[#list + 1] = id end
    return table.unpack(list)
end

local fours = { { -0.1, -0.1 }, { 0.1, -0.1 }, { 0.1, 0.1 }, { -0.1, 0.1 } }
check('fits: on the floor', TR.place.fits(vector3(0.5, 0.0, 0.0), 0.0, fours, 0.05, PED) == true)
check('fits: a corner off the floor\'s end', select(2, TR.place.fits(vector3(0.95, 0.0, 0.0), 0.0, fours, 0.05, PED)) == 'edge')
check('fits: turned, the corners turn with it', TR.place.fits(vector3(0.88, 0.0, 0.0), 0.0, fours, 0.05, PED) == true
    and select(2, TR.place.fits(vector3(0.88, 0.0, 0.0), 45.0, fours, 0.05, PED)) == 'edge')
blocked = true
check('fits: something in the way', select(2, TR.place.fits(vector3(0.5, 0.0, 0.0), 0.0, fours, 0.05, PED)) == 'blocked')
blocked = false

local box = { models = { { name = 'crate' }, { name = 'lid', offset = vector3(0.0, 0.0, 0.1) } }, size = vector3(0.3, 0.2, 0.1), label = 'Crate' }
aim = nil
start(box)
local crate, lid = newest(2)
check('a local copy with no collision, the rest fixed to the first', ents[crate].networked == false and ents[crate].collision == false
    and ents[crate].frozen and ents[lid].attached.to == crate and ents[lid].attached.at == vector3(0.0, 0.0, 0.1))
step()
check('aimed at nothing: hidden, the bar says why', ents[crate].visible == false and hud.hint.text == 'Crate'
    and hud.hint.sub == 'ghost.why.nothing' and #hud.hint.keys == 4)
check('aimed at the floor: there, facing the camera, see-through', why({ at = vector3(0.5, 0.0, 0.0) }) == nil
    and ents[crate].visible and ents[lid].visible and ents[crate].coords == vector3(0.5, 0.0, 0.0) and ents[crate].heading == 0.0
    and ents[crate].alpha == 175)
check('too far: fainter, says why', why({ at = vector3(0.0, 2.5, 0.0) }) == 'ghost.why.too_far' and ents[crate].alpha == 70)
check('too low', why({ at = vector3(0.5, 0.0, -0.6) }) == 'ghost.why.height')
check('too high', why({ at = vector3(0.5, 0.0, 1.3) }) == 'ghost.why.height')
check('too steep', why({ at = vector3(0.5, 0.0, 0.0), normal = vector3(0.0, 0.6, 0.8) }) == 'ghost.why.not_flat')
check('on someone', why({ at = vector3(0.5, 0.0, 0.0), entity = PERSON }) == 'ghost.why.surface')
check('on a car, not asked for', why({ at = vector3(-1.5, 0.0, 0.8), entity = CAR }) == 'ghost.why.surface')
check('half off the floor', why({ at = vector3(0.95, 0.0, 0.0) }) == 'ghost.why.edge')
check('on a crate (an object) is fine', why({ at = vector3(0.5, 0.0, 0.0), entity = CRATE }) == nil)
step({ 241 })
check('scroll turns it', ents[crate].heading == 15.0)
held[21] = true
step({ 242 })
held[21] = nil
check('with Shift held, a little', ents[crate].heading == 12.0)
finish({ 38 })
check('E puts it down: where and which way, the copy and the bar gone', result and result.coords == vector3(0.5, 0.0, 0.0)
    and result.heading == 12.0 and result.entity == CRATE and result.vehicle == nil
    and ents[crate].deleted and ents[lid].deleted and hud == nil)

aim = { at = vector3(0.0, 2.5, 0.0) }
start(box)
step()
step({ 38 })
check('E where it can\'t go does nothing', coroutine.status(co) ~= 'dead')
finish({ 25 })

local seen
start({ models = { { name = 'crate' } }, size = vector3(0.3, 0.2, 0.1), label = 'Crate', turn = 90.0, low = 0.7, cars = true,
    check = function(spot) seen = spot return spot.coords.y >= 0.0, 'busy' end })
crate = newest(1)
check('low: lower than the default', why({ at = vector3(0.5, 0.0, -0.6) }) == 'ghost.why.edge')
check('starts turned', ents[crate].heading == 90.0)
check('its own check, after the rest', why({ at = vector3(0.5, -0.2, 0.0) }) == 'ghost.why.busy' and seen.coords == vector3(0.5, -0.2, 0.0))
networked[CAR] = false
check('cars: not one only this game has', why({ at = vector3(-1.5, 0.0, 0.8), entity = CAR }) == 'ghost.why.surface')
networked[CAR] = true
check('cars: on one', why({ at = vector3(-1.5, 0.0, 0.8), entity = CAR }) == nil)
finish({ 38 })
check('on a car: the car, and the ground under it', result and result.vehicle == CAR and result.ground == 0.0)

aim = { at = vector3(0.5, 0.0, 0.0) }
start(box)
crate, lid = newest(2)
finish({ 25 })
check('a right click gives up', result == nil and ents[crate].deleted and ents[lid].deleted and hud == nil)

start(box)
crate = newest(2)
ragdoll = true
finish()
ragdoll = false
check('knocked over: given up', result == nil and ents[crate].deleted)

start({ models = { { name = 'reader' } }, size = vector3(0.2, 0.05, 0.06), label = 'Reader', owner = 'tr_other' })
crate = newest(1)
step()
TriggerEvent('onResourceStop', 'tr_somewhere')
check('another resource stopping: still placing', not ents[crate].deleted)
TriggerEvent('onResourceStop', 'tr_other')
check('the models\' own resource stopping: the copy goes at once', ents[crate].deleted)
finish()
check('and placing ends', result == nil)

missing[joaat('lid')] = true
local before = made
start(box)
check('a model that isn\'t in the game: nothing left, nothing placed', coroutine.status(co) == 'dead' and result == nil
    and ents[before + 1].deleted and made == before + 1)

T.done('tr_core/place')
