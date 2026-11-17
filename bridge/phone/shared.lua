---@class TRPhoneShared
local shared = {}

---The first of `names` that is started, else the first that is installed.
---@param names string[]
---@return string
function shared.resourceOf(names)
    for _, name in ipairs(names) do
        if GetResourceState(name) == 'started' then return name end
    end
    for _, name in ipairs(names) do
        if GetResourceState(name) ~= 'missing' then return name end
    end
    return names[1]
end

-- YSeries runs as yseries (the bundle), yphone or yflip-phone, with the same exports.
shared.YSERIES = { 'yseries', 'yphone', 'yflip-phone' }

return shared
