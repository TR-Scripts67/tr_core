---@class TRFuelShared
local fuel = {}

---@param amount any
---@return number?
function fuel.clamp(amount)
    amount = tonumber(amount)
    if not amount or amount ~= amount then return end
    return math.max(0.0, math.min(100.0, amount + 0.0))
end

return fuel
