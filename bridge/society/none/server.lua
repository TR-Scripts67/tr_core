local bridge = {}

function bridge.getMoney(job) end
function bridge.removeMoney(job, amount, reason) return false end
function bridge.addMoney(job, amount, reason) return false end

return bridge
