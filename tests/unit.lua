local check = T.check

T.boot('server', { es_extended = 'started', ox_inventory = 'started' })
check('TR global', TR ~= nil and TR.context == 'server')
check('system detect', TR.system('framework') == 'esx' and TR.system('inventory') == 'ox_inventory')
check('unknown module errors', not pcall(function() return TR.nope end))
check('path traversal ignored', TR['../x'] == nil)

local u = TR.utils
check('round', u.round(1.25, 1) == 1.3 and u.round(2.5) == 3 and math.type(u.round(2.4)) == 'integer')
check('formatNumber', u.formatNumber(1234567) == '1,234,567' and u.formatNumber(-1234.5) == '-1,234.5' and u.formatNumber(999) == '999')
check('formatMoney', u.formatMoney(1500) == '$1,500')
check('merge', (function()
    local m = u.merge({ a = 1, b = { c = 1, d = 2 }, l = { 1, 2, 3 } }, { b = { c = 9 }, l = { 7 } })
    return m.a == 1 and m.b.c == 9 and m.b.d == 2 and #m.l == 1
end)())
check('split', (function() local p = u.split('a,b,,c', ',') return #p == 4 and p[3] == '' and p[4] == 'c' end)())
check('trim', u.trim('  hi  ') == 'hi')
check('uuid', #u.uuid() == 36)
check('isArray', u.isArray({ 1, 2 }) and not u.isArray({ a = 1 }))
check('contains/count/keys', u.contains({ 1, 2 }, 2) and u.count({ a = 1, b = 2 }) == 2 and #u.keys({ a = 1 }) == 1)
check('formatMoney decimals', u.formatMoney(1284.886, nil, 2) == '$1,284.89' and u.formatMoney(5, '', 2) == '5.00')
check('copy is shallow', (function() local inner = {} local c = u.copy({ a = 1, t = inner }) return c.a == 1 and c.t == inner end)())
check('chance', u.chance(100) and not u.chance(0))
check('pick', u.pick({ 'x' }) == 'x' and u.pick({}) == nil)
check('randomRange', (function()
    for _ = 1, 50 do
        local i, f = u.randomRange({ min = 1, max = 3 }), u.randomRange({ 0.5, 1.5 })
        if math.type(i) ~= 'integer' or i < 1 or i > 3 or f < 0.5 or f > 1.5 then return false end
    end
    return true
end)())
check('shuffle keeps every item', (function() local l = u.shuffle({ 1, 2, 3, 4 }) table.sort(l) return #l == 4 and l[1] == 1 and l[4] == 4 end)())
check('decode', u.decode('{"a":1}').a == 1 and u.decode('not json') == nil and u.decode('') == nil and u.decode(nil) == nil)
check('READABLE has no 0, O, 1 or I', not u.READABLE:find('[0O1I]'))
check('toBase64', u.toBase64('Man') == 'TWFu' and u.toBase64('Ma') == 'TWE=' and u.toBase64('M') == 'TQ==' and u.toBase64('') == '')
check('fromBase64', u.fromBase64('TWFu') == 'Man' and u.fromBase64('TWE=') == 'Ma' and u.fromBase64('TQ==') == 'M' and u.fromBase64('TW\nFu') == 'Man')
check('base64 keeps every byte', (function()
    local all = {}
    for i = 0, 255 do all[#all + 1] = string.char(i) end
    local bytes = table.concat(all) .. '\0\255'
    return u.fromBase64(u.toBase64(bytes)) == bytes and u.toBase64('\255\254\253') == '//79'
end)())

local m = TR.math
check('smoothstep', m.smoothstep(0) == 0 and m.smoothstep(1) == 1 and m.smoothstep(0.5) == 0.5 and m.smoothstep(2) == 1)
check('smootherstep', m.smootherstep(0) == 0 and m.smootherstep(1) == 1 and m.smootherstep(0.5) == 0.5)
check('approach', m.approach(0, 1, 0.3) == 0.3 and m.approach(1, 0, 0.3) == 0.7 and m.approach(0.9, 1, 0.3) == 1)
check('rotateZ', (function() local v = m.Vec.rotateZ(vec3(1.0, 0.0, 2.0), 90) return math.abs(v.x) < 1e-9 and math.abs(v.y - 1) < 1e-9 and v.z == 2 end)())
check('fromRotation', (function() local d = m.Vec.fromRotation(vec3(0.0, 0.0, 0.0)) return math.abs(d.y - 1) < 1e-9 and math.abs(d.x) < 1e-9 end)())
check('flat', m.Vec.flat(vec3(0.0, 0.0, 0.0), vec3(3.0, 4.0, 9.0)) == 5)

local v = TR.validate
check('v number', v.value('number', 5))
check('v NaN', not v.value('number', 0 / 0))
check('v inf', not v.value('number', math.huge))
check('v integer', v.value('integer', 5) and not v.value('integer', 5.5))
check('v optional', v.value('string?', nil) and not v.value('string', nil))
check('v range', not v.value({ type = 'integer', min = 1, max = 10 }, 11) and v.value({ type = 'integer', min = 1, max = 10 }, 10))
check('v str len', not v.value({ type = 'string', max = 3 }, 'abcd'))
check('v pattern', v.value({ type = 'string', pattern = '^%a+$' }, 'abc') and not v.value({ type = 'string', pattern = '^%a+$' }, 'a1'))
check('v enum', v.value({ type = 'string', enum = { 'cash', 'bank' } }, 'bank') and not v.value({ type = 'string', enum = { 'cash' } }, 'x'))
check('v fields', v.value({ type = 'table', fields = { a = 'integer' } }, { a = 1 }) and not v.value({ type = 'table', fields = { a = 'integer' } }, { a = 'x' }))
check('v strict', not v.value({ type = 'table', fields = { a = 'integer' }, strict = true }, { a = 1, b = 2 }))
check('v array', v.value({ type = 'array', items = 'integer', max = 3 }, { 1, 2 }) and not v.value({ type = 'array', items = 'integer' }, { 1, 'x' }))
check('v sparse array', not v.value({ type = 'array' }, { [1] = 1, [5] = 2 }))
check('v array max', not v.value({ type = 'array', max = 1 }, { 1, 2 }))
check('v wrong type', not v.value('table', 'x') and not v.value('boolean', 1))
check('v args', v.args({ 'integer', 'string?' }, 1) and not v.args({ 'integer' }, 1, 2) and not v.args({ 'integer' }, 'x'))
check('v empty schema', v.args({}) and not v.args({}, 1))
local _, err = v.value({ type = 'table', fields = { amount = 'integer' } }, { amount = 'x' }, 'data')
check('v error path', err == 'data.amount must be an integer')

local g = TR.guard
local allowed = 0
for _ = 1, 5 do if g.ratelimit(1, 'k', 3) then allowed = allowed + 1 end end
check('ratelimit burst', allowed == 3)
T.timer = 400
check('ratelimit partial refill', g.ratelimit(1, 'k', 3) == true and g.ratelimit(1, 'k', 3) == false)
T.timer = 2000
check('ratelimit refilled', g.ratelimit(1, 'k', 3))
check('ratelimit per player', g.ratelimit(2, 'k', 3))
check('ratelimit window', g.ratelimit(3, 'w', { max = 1, window = 5000 }) and not g.ratelimit(3, 'w', { max = 1, window = 5000 }))

T.fromClient(1, 'playerDropped')
check('ratelimit cleanup', g.ratelimit(1, 'k', 1))

local shared = load(LoadResourceFile('tr_core', 'modules/player/shared.lua'))()
local job = { name = 'police', grade = 2, onDuty = true }
check('job string', shared.matchJob(job, 'police') and not shared.matchJob(job, 'ems'))
check('job list', shared.matchJob(job, { 'ems', 'police' }))
check('job grade', shared.matchJob(job, { police = 2 }) and not shared.matchJob(job, { police = 3 }))
check('job duty', not shared.matchJob({ name = 'police', grade = 0, onDuty = false }, 'police', true))
check('job nil', not shared.matchJob(nil, 'police'))

-- Reads the template resource's locales/en.json.
check('locale', TR.locale.t('reward_claimed') == 'You claimed your reward.')
check('locale missing key', TR.locale.t('nope') == 'nope')
check('locale has', TR.locale.has('reward_claimed') and not TR.locale.has('nope'))
check('locale section: only keys under it', next(TR.locale.section('reward')) == nil and next(TR.locale.section('nope')) == nil)

TR.log.info('hello %s', 'world')
TR.log.debug('hidden')
check('log info', T.logs[#T.logs]:find('hello world', 1, true) ~= nil)
check('log debug filtered', not T.logs[#T.logs]:find('hidden', 1, true))

T.done('unit')
