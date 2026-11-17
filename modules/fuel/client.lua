local fuel = ...
local bridge = TR.bridge('fuel')

---@class TRFuelClient : TRFuelShared
---@cast fuel TRFuelClient

---@param vehicle integer
---@return number?
function fuel.get(vehicle)
    if not DoesEntityExist(vehicle) then return end
    return fuel.clamp(bridge.get(vehicle))
end

---Only sticks on the client that controls the car; prefer the server's TR.fuel.set.
---@param vehicle integer
---@param amount number
function fuel.set(vehicle, amount)
    amount = fuel.clamp(amount)
    if not amount or not DoesEntityExist(vehicle) then return end
    bridge.set(vehicle, amount)
end

return fuel
