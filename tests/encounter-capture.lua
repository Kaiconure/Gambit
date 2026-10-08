-- Run from the addon directory: lua tests/encounter-capture.lua
local events, records, logs = {}, {}, {}
local now, writes, closes = 100, 0, 0
local writeFails, oversized = false, false
local mob = {id=123, name='Plouton', valid_target=true, hpp=90}
local env = setmetatable({
    os = {time=function() return now end, clock=function() return now end,
        date=function() return 'test' end},
    windower = {addon_path='test/', register_event=function(name, fn) events[name]=fn end,
        ffxi={get_info=function() return {zone=275} end,
            get_player=function() return {name='Tester',main_job='BLM'} end,
            get_mob_by_name=function() return mob end}},
    files = {create_path=function(path)
        assert(path == '.data/encounter-capture/')
        return true
    end},
    json = {stringify=function(row)
        records[#records+1] = row
        return oversized and string.rep('x', 32*1024*1024) or '{}'
    end},
    io = {open=function(path, mode)
        if mode == 'r' then return nil end
        return {write=function()
            if writeFails then return nil, 'disk failure' end
            writes=writes+1; return true
        end, flush=function() return true end,
        close=function() closes=closes+1 end}
    end},
    writeMessage=function(message) logs[#logs+1]=message end,
}, {__index=_G})
local module = assert(loadfile('lib/encounter-capture.lua'))
setfenv(module, env)
local capture = module()
assert(not capture.getState().active)
assert(capture.start():find('started'))
assert(capture.start():find('already'))
assert(not capture.getState().weakness_known)
local casts = {}
local probeContext = {me={main_job='BLM'},spell={id=144},
    findByName=function() return {id=mob.id,hpp=mob.hpp,has_claim=true} end,
    canUseSpell=function(name) casts.selected=name;return true end,
    useSpell=function() casts[#casts+1]=casts.selected end}
capture.command({'cycle','on','8'})
assert(capture.probeDue())
capture.probe(probeContext);assert(casts[1]=='Fire')
capture.probe(probeContext);assert(#casts==1)
for _,spell in ipairs({'Blizzard','Aero','Stone','Thunder','Water','Fire'}) do
    now=now+8;capture.probe(probeContext);assert(casts[#casts]==spell)
end
capture.command({'cycle','off'});now=now+8;assert(not capture.probeDue())
capture.command({'cycle','on','8'})
probeContext.canUseSpell=function() return false end
capture.probe(probeContext);assert(records[#records].kind=='probe_skipped')
now=now+8;mob.id=999;capture.probe(probeContext);assert(not capture.probeDue())
mob.id=123
capture.command({'element', 'thunder'})
assert(capture.getState().weak_element == 'thunder')
assert(capture.getState().source == 'manual')
now = now + 20
assert(not capture.getState().weakness_known)
capture.command({'element', 'ice'})
mob.id = 456
assert(not capture.getState().weakness_known)
capture.command({'element', 'fire'})
capture.command({'mark', 'visible', 'proc'})
assert(records[#records].kind == 'manual_mark')
assert(capture.getState().weak_element == 'fire')
capture.command({'unknown'})
assert(not capture.getState().weakness_known)
local before = writes
assert(events['incoming chunk'](0x029, string.char(0,10,255), nil, false, true) == nil)
assert(writes == before+1)
assert(records[#records].data.hex == '000AFF')
assert(records[#records].data.blocked)
events['incoming chunk'](0x029, 'data', nil, true, false)
events['incoming chunk'](0x00E, 'data', nil, false, false)
assert(writes == before+1)
assert(events['incoming text']('message', 'modified', 1, 1, false) == nil)
assert(records[#records].data.text == 'message')
capture.command({'element', 'wind'})
events['zone change']()
assert(not capture.getState().active and not capture.getState().weakness_known)
assert(closes == 1)
capture.start()
env.windower.ffxi.get_info=function() return {zone=277} end
mob.id=17911879
capture.command({'adaptive','on','8'})
local confirmation=('2A101006475011010300000000000000000000003C01000047002FA106000000'):gsub('..',function(h)return string.char(tonumber(h,16))end)
events['incoming chunk'](0x02A,confirmation,nil,false,false)
assert(capture.getState().source=='message_8495')
probeContext.canUseSpell=function(name) casts.selected=name;return true end
capture.probe(probeContext)
assert(casts[#casts]=='Stone IV')
env.resources={spells={[164]={element=4,type='BlackMagic'}}}
env.windower.packets={parse_action=function() return {category=4,param=164,targets={{id=mob.id,actions={{message=7,param=2000}}}}} end}
events['incoming chunk'](0x028,'packet',nil,false,false)
assert(not capture.getState().weakness_known)
now=now+8;capture.probe(probeContext);assert(casts[#casts]=='Stone')
events['incoming chunk'](0x02A,confirmation,nil,false,false)
now=now+21;capture.probe(probeContext);assert(casts[#casts]~='Stone IV')
capture.command({'cycle','off'});assert(not capture.probeDue())
writeFails = true
events['incoming text']('disk error', nil, 1)
assert(not capture.getState().active and #logs == 1)
writeFails = false
capture.start()
oversized = true
events['incoming text']('limit', nil, 1)
assert(not capture.getState().active and #logs == 2)
print('PASS: opt-in capture, manual-only state, expiration, target reset, markers, raw bytes, passive callbacks, zoning, write failure, size limit')
