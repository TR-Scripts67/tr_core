-- A job's account is named after the job.
local bank = exports['Renewed-Banking']
local bridge = {}

---The account's statement; Renewed-Banking keeps it apart from the money.
local function record(job, amount, reason, kind)
    if reason ~= '' then bank:handleTransaction(job, reason, amount, reason, GetCurrentResourceName(), job, kind) end
end

function bridge.getMoney(job) return bank:getAccountMoney(job) or nil end

function bridge.removeMoney(job, amount, reason)
    if bank:removeAccountMoney(job, amount) ~= true then return false end
    record(job, amount, reason, 'withdraw')
    return true
end

function bridge.addMoney(job, amount, reason)
    if bank:addAccountMoney(job, amount) ~= true then return false end
    record(job, amount, reason, 'deposit')
    return true
end

return bridge
