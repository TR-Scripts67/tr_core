-- A job's account is named after the job (qb-banking makes one for every job). qb-management keeps no money of its
-- own: its boss menu uses these.
local bank = exports['qb-banking']
local bridge = {}

---qb-banking answers with the rows its query changed, or false when there is no such account.
local function changed(result)
    return result == true or (type(result) == 'number' and result > 0)
end

function bridge.getMoney(job)
    local account = bank:GetAccount(job)
    return account and account.account_balance
end

function bridge.removeMoney(job, amount, reason) return changed(bank:RemoveMoney(job, amount, reason ~= '' and reason or nil)) end
function bridge.addMoney(job, amount, reason) return changed(bank:AddMoney(job, amount, reason ~= '' and reason or nil)) end

return bridge
