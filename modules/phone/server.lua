---@class TRPhoneNote
---@field title string
---@field text? string
---@field app? string your app's id, so the phone shows it as yours

---@class TRPhoneServer
local phone = {}

local bridge = TR.bridge('phone')

---The number of the phone the player has, or nil without one.
---@param src integer
---@return string?
function phone.number(src)
    local ok, number = pcall(bridge.number, src)
    if not ok then
        TR.log.error('phone number from %s failed: %s', TR.system('phone'), number)
        return nil
    end
    if number == nil or number == false or number == '' then return nil end
    return tostring(number)
end

---A notification on the player's phone.
---@param src integer
---@param note TRPhoneNote
function phone.notify(src, note)
    assert(type(note) == 'table' and type(note.title) == 'string', 'TR.phone.notify needs a title')
    local ok, err = pcall(bridge.notify, src, { title = note.title, text = note.text or '', app = note.app })
    if not ok then TR.log.error('phone notification through %s failed: %s', TR.system('phone'), err) end
end

return phone
