local sd = exports['sd-phone']

return {
    number = function(src) return sd:getPhoneNumber(src) end,
    notify = function(src, note)
        sd:notify(src, { title = note.title, body = note.text, appId = note.app })
    end,
}
