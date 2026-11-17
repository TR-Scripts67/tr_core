local npwd = exports['npwd']

return {
    number = function(src)
        local player = npwd:getPlayerData({ source = src })
        return player and player.phoneNumber
    end,
    -- Its notifications are client exports.
    notify = function(src, note)
        TriggerClientEvent(GetCurrentResourceName() .. ':tr_phone:notify', src, note)
    end,
}
