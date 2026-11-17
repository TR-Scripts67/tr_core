---@class TRLog
local log = ...

---@class TRDiscordEmbed
---@field title? string
---@field description? string
---@field color? integer
---@field fields? { name: string, value: string, inline?: boolean }[]

---Sends to webhooks.<channel> in server_config.lua, else webhooks.default.
---@param channel string e.g. 'money', 'admin', 'security'
---@param embed TRDiscordEmbed
function log.discord(channel, embed)
    exports.tr_core:discord(channel, embed, GetCurrentResourceName())
end

return log
