-- Options use the ox_target format (https://overextended.dev/ox_target) and are removed when the
-- resource that added them stops.

---@class TRTarget
---@field addBoxZone fun(data: table): integer | string zone id (opaque: number on ox_target, name on qb-target)
---@field addSphereZone fun(data: table): integer | string zone id
---@field addPolyZone fun(data: table): integer | string zone id
---@field removeZone fun(id: integer | string)
---@field addModel fun(models: number | string | (number | string)[], options: table | table[])
---@field removeModel fun(models: number | string | (number | string)[], names?: string | string[])
---@field addEntity fun(netIds: integer | integer[], options: table | table[])
---@field removeEntity fun(netIds: integer | integer[], names?: string | string[])
---@field addLocalEntity fun(entities: integer | integer[], options: table | table[])
---@field removeLocalEntity fun(entities: integer | integer[], names?: string | string[])
---@field addGlobalPed fun(options: table | table[])
---@field removeGlobalPed fun(names: string | string[])
---@field addGlobalVehicle fun(options: table | table[])
---@field removeGlobalVehicle fun(names: string | string[])
---@field addGlobalObject fun(options: table | table[])
---@field removeGlobalObject fun(names: string | string[])
---@field addGlobalPlayer fun(options: table | table[])
---@field removeGlobalPlayer fun(names: string | string[])
---@field allow fun(on: boolean) the third eye on or off (ox_target, qb-target), e.g. while its key means something else; tr_core's own interaction is left as it is
local target = TR.bridge('target')

return target
