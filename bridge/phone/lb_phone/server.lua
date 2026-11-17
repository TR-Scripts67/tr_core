local lb = exports['lb-phone']

return {
    number = function(src) return lb:GetEquippedPhoneNumber(src) end,
    -- A source shows it once; a number would save it in the phone's list.
    notify = function(src, note)
        lb:SendNotification(src, { app = note.app, title = note.title, content = note.text })
    end,
}
