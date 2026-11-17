-- A job's money is the shared addon account esx_society registered for it (society_<job> unless a job says
-- otherwise). The events answer at once and are in every version; the exports are only in the newer ones.
local bridge = {}

local function account(job)
    local name = 'society_' .. job
    TriggerEvent('esx_society:getSociety', job, function(society)
        if society and society.account then name = society.account end
    end)
    local found
    TriggerEvent('esx_addonaccount:getSharedAccount', name, function(shared) found = shared end)
    return found
end

function bridge.getMoney(job)
    local shared = account(job)
    return shared and shared.money
end

-- Older versions return nothing from these; newer ones false when refused.
function bridge.removeMoney(job, amount)
    local shared = account(job)
    return shared ~= nil and shared.removeMoney(amount) ~= false
end

function bridge.addMoney(job, amount)
    local shared = account(job)
    return shared ~= nil and shared.addMoney(amount) ~= false
end

return bridge
