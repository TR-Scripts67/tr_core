-- Bridges get the filled-in alert: every field is set, street is '' when unknown, jobs is a list.

---@class TRDispatchShared
local shared = {}

function shared.heading(alert)
    return alert.code ~= '' and ('%s - %s'):format(alert.code, alert.title) or alert.title
end

function shared.details(alert)
    if alert.street == '' then return alert.message end
    if alert.message == '' then return alert.street end
    return ('%s - %s'):format(alert.message, alert.street)
end

---Dispatch scripts with their own duty check pass requireDuty false.
---@param jobs string[]
---@param requireDuty? boolean
---@return integer[]
function shared.players(jobs, requireDuty)
    local found = {}
    for _, src in ipairs(TR.player.getPlayers()) do
        if TR.player.hasJob(src, jobs, requireDuty) then found[#found + 1] = src end
    end
    return found
end

---cd_dispatch's notification (cd_dispatch3d takes it too).
function shared.codesign(alert)
    local heading = shared.heading(alert)
    return {
        job_table = alert.jobs,
        coords = alert.coords,
        title = heading,
        message = shared.details(alert),
        flash = alert.priority == 'high' and 1 or 0,
        sound = 1,
        blip = {
            sprite = alert.blip.sprite,
            scale = alert.blip.scale,
            colour = alert.blip.color,
            flashes = alert.blip.flash,
            text = heading,
            time = alert.time, -- minutes
            radius = alert.blip.radius,
        },
    }
end

return shared
