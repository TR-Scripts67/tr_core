local gks = exports['gksphone']

return {
    number = function(src) return gks:GetPhoneBySource(src) end,
    notify = function(src, note)
        gks:sendNotification(src, { title = note.title, message = note.text, duration = 5000 })
    end,
}
