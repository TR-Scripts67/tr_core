-- Placing a prop: a see-through copy of it follows where the player aims onto anything flat in reach, its front (-Y)
-- towards them, while they walk around. Faint means it can't go there, and the hint bar says why. Scroll (or the arrow
-- keys) turns it, E or a left click puts it down, a right click or Backspace gives up. The words are the resource's own,
-- from its locale: ghost.place, ghost.turn, ghost.fine, ghost.cancel, ghost.keys.<same> and ghost.why.<reason>.

---@class TRPlace
local place = {}

local t = TR.locale.t
local placing ---@type { parts: integer[], owner?: string, gone?: true }?

local RANGE = 1.8           -- m from the player it may go, along the ground
local AIM = 7.0             -- m the aim reaches from the camera
local LOW, HIGH = 0.45, 1.25 -- m below and above the player's feet it may go
local FEET = 0.98           -- m a standing ped's position is above their feet
local FLAT = 0.94           -- how level the spot must be (1 is level)
local SUPPORT = 0.035       -- m a corner may be above or below the spot and still rest on it
local INSET = 0.85          -- corners checked this far out from the middle (rounded corners, feet)
local LIFT = 0.012          -- m over the surface the way to each corner must be clear
local ALPHA_OK, ALPHA_NO = 175, 70
local TURN, TURN_FINE = 15.0, 3.0 -- degrees a scroll turns it (with Shift held: fine)
local TURN_HELD = 120.0     -- degrees a second while an arrow key is held
local RAYS = 1 | 2 | 16     -- the world, vehicles and objects
local GROUND_RAYS = 1 | 16  -- under a car: the world and objects

local KEYS = {
    place = { 38, 24 },             -- E, left click
    cancel = { 25, 194, 200, 202 }, -- right click, Backspace, Esc
    left = 174, right = 175,        -- arrow keys
    up = 241, down = 242,           -- scroll
    fine = 21,                      -- Shift
}
-- Off while placing: attacking and aiming, the weapon wheel and its scroll, cover, reload, E, the pause menu.
local BLOCKED = { 14, 15, 16, 17, 24, 25, 37, 38, 44, 45, 140, 141, 142, 143, 174, 175, 194, 199, 200, 202, 241, 242, 257, 263, 264 }

local function hint(label, why)
    TR.ui.hud.set({ hint = {
        text = label,
        sub = why and t('ghost.why.' .. why) or nil,
        keys = {
            { key = t('ghost.keys.place'), label = t('ghost.place') },
            { key = t('ghost.keys.turn'), label = t('ghost.turn') },
            { key = t('ghost.keys.fine'), label = t('ghost.fine') },
            { key = t('ghost.keys.cancel'), label = t('ghost.cancel') },
        },
    } })
end

local function pressed(list)
    for _, key in ipairs(list) do
        if IsDisabledControlJustPressed(0, key) then return true end
    end
    return false
end

local function camDirection()
    local rot = GetGameplayCamRot(2)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x)), rot.z
end

local function probe(from, to, flags, ignore)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, flags, ignore, 7)
    local _, hit, at, normal, entity = GetShapeTestResult(ray)
    return hit == 1 or hit == true, at, normal, entity
end

---Every corner rests on the surface under `at` and nothing stands between it and the middle.
---@param at vector3
---@param heading number
---@param corners { [1]: number, [2]: number }[] x and y from `at`, before it is turned
---@param height number how far over the surface the way to each corner is checked
---@param ignore integer an entity the rays pass through (the player)
---@return boolean
---@return 'edge' | 'blocked' | nil why not
function place.fits(at, heading, corners, height, ignore)
    local a = math.rad(heading)
    local c, s = math.cos(a), math.sin(a)
    for _, corner in ipairs(corners) do
        local x, y = at.x + corner[1] * c - corner[2] * s, at.y + corner[1] * s + corner[2] * c
        local hit, under = probe(vector3(x, y, at.z + 0.08), vector3(x, y, at.z - 0.08), RAYS, ignore)
        if not hit or math.abs(under.z - at.z) > SUPPORT then return false, 'edge' end
        local from, to = vector3(at.x, at.y, at.z + LIFT + height), vector3(x, y, under.z + LIFT + height)
        if probe(from, to, RAYS, ignore) then return false, 'blocked' end
    end
    return true
end

---Where the player is aiming, and why it can't go there.
---@return table? spot
---@return string? why
local function find(ped, turn, opts)
    local from = GetGameplayCamCoord()
    local dir, camHeading = camDirection()
    local hit, at, normal, entity = probe(from, from + dir * AIM, RAYS, ped)
    if not hit then return nil, 'nothing' end

    local spot = { coords = at, heading = (camHeading + turn) % 360.0, entity = entity }
    local pos = GetEntityCoords(ped)
    local dx, dy = at.x - pos.x, at.y - pos.y
    if dx * dx + dy * dy > RANGE * RANGE then return spot, 'too_far' end
    local height = at.z - (pos.z - FEET)
    if height < -(opts.low or LOW) or height > HIGH then return spot, 'height' end
    if normal.z < FLAT then return spot, 'not_flat' end

    -- The map's own floors come back as a handle too (type 0).
    local kind = entity ~= 0 and GetEntityType(entity) or 0
    if kind == 1 then return spot, 'surface' end
    if kind == 2 then
        if not opts.cars or not NetworkGetEntityIsNetworked(entity) then return spot, 'surface' end
        spot.vehicle = entity
    end

    local hx, hy = opts.size.x / 2 * INSET, opts.size.y / 2 * INSET
    local ok, why = place.fits(at, spot.heading, { { -hx, -hy }, { hx, -hy }, { hx, hy }, { -hx, hy } }, opts.size.z / 2, ped)
    if not ok then return spot, why end
    if opts.check then
        ok, why = opts.check(spot)
        if not ok then return spot, why end
    end
    return spot
end

local function unable(ped)
    return IsEntityDead(ped) or IsPedRagdoll(ped) or IsPedFalling(ped) or IsPedSwimming(ped) or IsPedInAnyVehicle(ped, false)
end

local function spawn(name, at)
    local hash = TR.stream.model(name)
    if not hash then return end
    local entity = CreateObjectNoOffset(hash, at.x, at.y, at.z, false, false, false)
    TR.stream.release('model', hash)
    FreezeEntityPosition(entity, true)
    SetEntityCollision(entity, false, false)
    SetEntityVisible(entity, false, false)
    return entity
end

local function remove(parts)
    for _, part in ipairs(parts) do
        if DoesEntityExist(part) then DeleteEntity(part) end
    end
end

---Lets the player place a see-through copy of a prop (its first model, the rest fixed to it); waits until they put it
---down or give up.
---`low`: m below their feet it may go (default 0.45). `cars`: it may go on a car others see too; the spot then has
---`vehicle` and `ground` (the z it falls to if the car drives off). `check(spot)`: the script's own rules, after these;
---a reason it gives is shown as ghost.why.<reason>. `owner`: the resource the models come from, if not this one:
---placing ends if it stops.
---@param opts { models: { name: string, offset?: vector3, rotation?: vector3 }[], size: vector3, label: string, turn?: number, low?: number, cars?: boolean, check?: fun(spot: table): boolean, string?, owner?: string }
---@return { coords: vector3, heading: number, entity: integer, vehicle?: integer, ground?: number }?
function place.prop(opts)
    local ped = PlayerPedId()
    local start = GetEntityCoords(ped)
    local parts = {}
    local this = { parts = parts, owner = opts.owner }
    placing = this
    for i, model in ipairs(opts.models) do
        local entity = spawn(model.name, start)
        if not entity or this.gone then
            if placing == this then placing = nil end
            remove(parts)
            return nil
        end
        if i > 1 then
            local at, rot = model.offset or vector3(0.0, 0.0, 0.0), model.rotation or vector3(0.0, 0.0, 0.0)
            AttachEntityToEntity(entity, parts[1], 0, at.x, at.y, at.z, rot.x, rot.y, rot.z, false, false, false, false, 2, true)
        end
        parts[i] = entity
    end

    local turn, alpha, visible, shownWhy = opts.turn or 0.0, nil, false, false
    local result

    while true do
        Wait(0)
        if this.gone then break end
        for _, key in ipairs(BLOCKED) do DisableControlAction(0, key, true) end
        if unable(ped) or pressed(KEYS.cancel) then break end

        local step = IsControlPressed(0, KEYS.fine) and TURN_FINE or TURN
        if IsDisabledControlJustPressed(0, KEYS.up) then turn = turn + step end
        if IsDisabledControlJustPressed(0, KEYS.down) then turn = turn - step end
        local held = (IsDisabledControlPressed(0, KEYS.left) and 1.0 or 0.0) - (IsDisabledControlPressed(0, KEYS.right) and 1.0 or 0.0)
        if held ~= 0.0 then turn = turn + held * TURN_HELD * GetFrameTime() end

        local spot, why = find(ped, turn, opts)
        if spot then
            SetEntityCoordsNoOffset(parts[1], spot.coords.x, spot.coords.y, spot.coords.z, false, false, false)
            SetEntityHeading(parts[1], spot.heading)
        end
        local want = spot and (why and ALPHA_NO or ALPHA_OK)
        if (spot ~= nil) ~= visible then
            visible = spot ~= nil
            for _, part in ipairs(parts) do SetEntityVisible(part, visible, false) end
        end
        if want and want ~= alpha then
            alpha = want
            for _, part in ipairs(parts) do SetEntityAlpha(part, alpha, false) end
        end
        if why ~= shownWhy then
            shownWhy = why
            hint(opts.label, why)
        end

        if pressed(KEYS.place) and spot and not why then
            result = spot
            break
        end
    end

    if placing == this then placing = nil end
    remove(parts)
    TR.ui.hud.hide()
    -- The key that ended it shouldn't also open the pause menu or swing a punch.
    CreateThread(function()
        local untilAt = GetGameTimer() + 300
        while GetGameTimer() < untilAt do
            for _, key in ipairs({ 24, 25, 140, 199, 200, 202 }) do DisableControlAction(0, key, true) end
            Wait(0)
        end
    end)

    if result and result.vehicle then
        local at = result.coords
        local hit, ground = probe(at, at - vector3(0.0, 0.0, 3.0), GROUND_RAYS, ped)
        result.ground = hit and ground.z or GetEntityCoords(ped).z - FEET
    end
    return result
end

-- The game drops a stopping resource's models straight after this event: the copy goes inside it.
AddEventHandler('onResourceStop', function(name)
    local p = placing
    if not p or (name ~= GetCurrentResourceName() and name ~= p.owner) then return end
    p.gone, placing = true, nil
    remove(p.parts)
end)

return place
