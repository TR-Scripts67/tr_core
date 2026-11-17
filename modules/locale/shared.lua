-- Missing keys fall back to en.json. Nested keys are flattened: { garage = { title } } -> 'garage.title'.
-- The resource needs 'locales/*.json' in its `files` so clients can read them.

---@class TRLocale
local locale = {}

local resource = GetCurrentResourceName()
local language = tostring(TR.config.locale or 'en')
local strings

local function flatten(source, prefix, target)
    for key, value in pairs(source) do
        local path = prefix and ('%s.%s'):format(prefix, key) or key

        if type(value) == 'table' then
            flatten(value, path, target)
        else
            target[path] = value
        end
    end
    return target
end

local function loadLanguage(lang)
    local raw = LoadResourceFile(resource, ('locales/%s.json'):format(lang))
    if not raw then return end

    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then
        TR.log.error('locales/%s.json is not valid JSON', lang)
        return
    end

    return flatten(data, nil, {})
end

local function ensureLoaded()
    if strings then return end

    strings = loadLanguage('en') or {}

    if language ~= 'en' then
        local translated = loadLanguage(language)

        if translated then
            for key, value in pairs(translated) do strings[key] = value end
        else
            TR.log.warn('missing locales/%s.json, using en', language)
        end
    end
end

---Replaces {placeholders} with `vars`. Returns the key itself when it's missing.
---@param key string
---@param vars? table<string, any>
---@return string
function locale.t(key, vars)
    ensureLoaded()

    local str = strings[key]
    if str == nil then return key end

    str = tostring(str)
    if not vars then return str end

    return (str:gsub('{([%w_]+)}', function(name)
        local value = vars[name]
        return value ~= nil and tostring(value) or nil
    end))
end

---@param key string
---@return boolean
function locale.has(key)
    ensureLoaded()
    return strings[key] ~= nil
end

---Every key under `prefix`, without it, for a page that shows the text: section('creator') -> { title = ..., ['error.no_job'] = ... }
---@param prefix string
---@return table<string, string>
function locale.section(prefix)
    ensureLoaded()

    local found, start = {}, #prefix + 2
    for key, value in pairs(strings) do
        if key:sub(1, start - 1) == prefix .. '.' then found[key:sub(start)] = tostring(value) end
    end
    return found
end

---@return string
function locale.language()
    return language
end

return locale
