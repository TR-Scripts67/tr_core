-- A job's shared money (the boss menu's account) through the server's banking script.

---@class TRSociety
local society = {}
local bridge = TR.bridge('society')

local function whole(amount)
    return math.type(amount) == 'integer' and amount > 0
end

---@param job string
---@return integer? money nil when the job has no society account
function society.getMoney(job)
    if type(job) ~= 'string' then return end
    local money = bridge.getMoney(job)
    if type(money) ~= 'number' then return end
    return math.floor(money)
end

---Takes money from a job's society account, all or nothing.
---@param job string
---@param amount integer more than 0
---@param reason? string shown in the account's statement where the banking script keeps one
---@return boolean taken false when the account is missing or short
function society.removeMoney(job, amount, reason)
    if not whole(amount) then return false end
    local money = society.getMoney(job)
    if not money or money < amount then return false end
    return bridge.removeMoney(job, amount, reason or '') == true
end

---@param job string
---@param amount integer more than 0
---@param reason? string
---@return boolean added false when the account is missing
function society.addMoney(job, amount, reason)
    if not whole(amount) or not society.getMoney(job) then return false end
    return bridge.addMoney(job, amount, reason or '') == true
end

return society
