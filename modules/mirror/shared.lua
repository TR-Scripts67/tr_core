-- Configure it when the resource starts, on both sides, so its events exist before anyone plays.

---@class TRMirror
local Mirror = {
    options = {
        range = 30.0,      -- metres within which players see the props (server)
        soundRange = 12.0, -- metres the sounds carry, quieter the further away (client)
        rate = 100,        -- ms between updates the playing player sends (client)
        volume = 0.8,      -- sound volume right next to the scene, 0..1 (client)
    },
}

---@param options { range?: number, soundRange?: number, rate?: integer, volume?: number }
function Mirror.configure(options)
    for key, value in pairs(options) do Mirror.options[key] = value end
end

return Mirror
