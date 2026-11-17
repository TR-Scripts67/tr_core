local _, shared = ...
local ys = exports[shared.resourceOf(shared.YSERIES)]

return {
    number = function(src) return ys:GetPhoneNumberBySourceId(src) end,
    notify = function(src, note)
        ys:SendNotification({ app = note.app, title = note.title, text = note.text }, 'source', src)
    end,
}
