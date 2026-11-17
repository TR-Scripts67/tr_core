local gks = exports['gksphone']
local bridge = { resource = 'gksphone' }

-- GKS shows an app's `name` (its id) where labelLangs has nothing for the phone's language.
local LANGUAGES = { 'en', 'tr', 'de', 'fr', 'es', 'it', 'pt', 'pt-PT', 'pt-BR', 'nl', 'pl', 'ru', 'ar', 'cs', 'ro', 'hu', 'sv', 'da', 'fi', 'no', 'el', 'zh-CN', 'zh-TW', 'ja', 'ko' }

function bridge.add(app)
    local labels = {}
    for _, code in ipairs(LANGUAGES) do labels[code] = app.name end
    gks:AddCustomApp({
        name = app.id,
        appurl = app.url,
        icons = app.icon,
        description = app.description,
        show = true,
        startapp = app.preinstalled,
        signal = false,
        labelLangs = labels,
        onOpen = app.onOpen,
        onClose = app.onClose,
    })
end

-- GKS has no export for it: it closes the app when the resource stops.
function bridge.remove() end

function bridge.typing(on)
    gks:InputChange(on)
end

return bridge
