local Adapter=require('./lib/events/abyssea')
local Weakness=require('./lib/abyssea-weakness')
local now,zone=0,218
local mob={id=17670575,index=431,spawn_type=16,hpp=95,status=1}
local listeners,sent={},{}
local notifications={}
local packet
local service={deps={clock=function() return now end,
    notifyWeakness=function(message) notifications[#notifications+1]=message end,
    packets={parse=function() return packet end},
    windower={ffxi={get_info=function() return {zone=zone} end,
        get_mob_by_id=function(id) if id==mob.id then return mob end end},
        send_ipc_message=function(message) sent[#sent+1]=message end}}}
Adapter.attach(service,function(name,fn) listeners[name]=fn end)
local function incoming(message,param,raw)
    packet={Player=mob.id,['Player Index']=mob.index,['Message ID']=message,['Param 1']=param}
    service.weaknessIncoming(0x02A,raw or '',nil,false)
end
-- Values and trailing actor bytes retained from the Altepa discovery captures.
incoming(40115,8)
assert(Weakness.get(zone,mob).red.element=='darkness' and #sent==1)
service.weaknessText('The fiend appears vulnerable to darkness elemental weapon skills!')
assert(#sent==1,'packet and text must deduplicate')
incoming(40109,218,string.rep('\0',30)..'Aidelle\0\0\0')
incoming(40112,218)
assert(Weakness.get(zone,mob).red.triggered and Weakness.get(zone,mob).red.actor=='Aidelle')
assert(#sent==2)
-- Receiving a peer observation never rebroadcasts it.
listeners['ipc message'](sent[2]); assert(#sent==2)
service.weaknessClear()
incoming(40115,7)
assert(Weakness.get(zone,mob).red.element=='light' and not Weakness.get(zone,mob).red.triggered)
incoming(40115,99)
assert(Weakness.get(zone,mob).red.element=='light','unknown numbers must not narrow candidates')
mob.hpp=0; service.weaknessTick(); mob.hpp=100
assert(not Weakness.get(zone,mob),'death must clear observations even when the entity ID is reused')
-- Zone-specific message IDs cannot leak into other zones. Text must be tied
-- to a recent packet whose explicit subject is a monster, never the cursor.
zone=215; incoming(40115,8)
assert(not Weakness.get(zone,mob))
service.weaknessText('The fiend appears vulnerable to wind elemental weapon skills!')
assert(Weakness.get(zone,mob).red.element=='wind')
service.weaknessText("Aidelle's attack staggers the fiend!")
assert(not Weakness.get(zone,mob).red.triggered,'generic stagger is not a red confirmation')
service.weaknessText('The fiend is frozen in its tracks.')
assert(Weakness.get(zone,mob).red.triggered)
service.weaknessClear(); incoming(1,0); now=2
service.weaknessText('The fiend appears vulnerable to fire elemental weapon skills!')
assert(not Weakness.get(zone,mob),'stale packet must not attribute hints')
zone=1; incoming(40115,7)
assert(not Weakness.get(zone,mob))
-- The same mechanics apply to ordinary monsters in every Abyssea zone.
-- Verify both zone-text offsets and all eight parameter values without chat.
mob.name='Canyon Eft'; mob.is_nm=false
local expectedBases={[15]=7341,[45]=7341,[132]=7341,[215]=7240,[216]=7341,
    [217]=7341,[218]=7341,[253]=7240,[254]=7341}
local expectedElements={'fire','ice','wind','earth','lightning','water','light','darkness'}
for z,base in pairs(expectedBases) do
    zone=z
    for index,element in ipairs(expectedElements) do
        service.weaknessClear()
        incoming(base+6+32768,index)
        assert(Weakness.get(zone,mob).red.element==element)
    end
    incoming(base+32768,218,string.rep('\0',30)..'Aidelle\0')
    incoming(base+1+32768,218) -- yellow stagger
    incoming(base+2+32768,218) -- blue stagger
    assert(not Weakness.get(zone,mob).red.triggered,'only red stagger should stop red search')
    incoming(base+3+32768,218)
    assert(Weakness.get(zone,mob).red.triggered)
    for index,element in ipairs(expectedElements) do
        service.weaknessClear();incoming(base+4+32768,index)
        assert(Weakness.get(zone,mob).yellow.element==element)
        assert(not Weakness.get(zone,mob).red.element)
    end
    incoming(base+32768,218,string.rep('\0',30)..'Miyajima\0')
    incoming(base+2+32768,218)
    assert(not Weakness.get(zone,mob).yellow.triggered)
    incoming(base+1+32768,218)
    assert(Weakness.get(zone,mob).yellow.triggered and Weakness.get(zone,mob).yellow.actor=='Miyajima')
    for index=1,14 do
        service.weaknessClear();incoming(base+5+32768,index)
        local weapon=Weakness.weaponType(index)
        local record=Weakness.get(zone,mob)
        assert(record.blue.weapon_type==weapon and not record.red.element and not record.yellow.element)
        local update=sent[#sent];local count=#sent
        service.weaknessClear();listeners['ipc message'](update)
        assert(Weakness.get(zone,mob).blue.weapon_type==weapon and #sent==count,'blue IPC round trip/dedup')
    end
    incoming(base+32768,218,string.rep('\0',30)..'Tester\0')
    incoming(base+1+32768,218);incoming(base+3+32768,218)
    assert(not Weakness.get(zone,mob).blue.triggered)
    incoming(base+2+32768,218)
    assert(Weakness.get(zone,mob).blue.triggered and Weakness.get(zone,mob).blue.actor=='Tester')
end
-- Replay the actual observed packets/text, independent of private settings files.
local json=require('./lib/jsonlua')
local file=assert(io.open('tests/fixtures/abyssea-observations.json'))
local fixtures=json.parse(file:read('*a')); file:close()
for i,fixture in ipairs(fixtures) do
    service.weaknessClear(); mob=fixture.mob; zone=fixture.zone
    for _,entry in ipairs(fixture.entries) do
        now=entry.time
        if entry.kind=='packet' then
            packet=entry.fields
            local raw=entry.hex:gsub('%x%x',function(value) return string.char(tonumber(value,16)) end)
            service.weaknessIncoming(0x02A,raw,nil,false)
        else service.weaknessText(entry.original) end
    end
    local record=Weakness.get(zone,mob)
    if i==1 then assert(record.red.element=='darkness' and record.red.triggered and record.red.actor=='Aidelle')
    elseif i==2 then assert(record.red.triggered and record.red.actor=='Aidelle' and not record.red.element)
    elseif i==3 then assert(record.red.element=='light' and not record.red.triggered)
    else assert(not record) end
end
print('PASS: red hint mappings, red-only success, deduplication, IPC, target attribution, zone/death reset')
file=assert(io.open('tests/fixtures/abyssea-yellow-observations.json'))
local yellowFixtures=json.parse(file:read('*a'));file:close()
for i,fixture in ipairs(yellowFixtures) do
    service.weaknessClear();mob=fixture.mob;zone=fixture.zone
    local sentBefore=#sent
    local noticesBefore=#notifications
    for _,entry in ipairs(fixture.entries) do
        now=entry.time
        if entry.kind=='packet' then
            packet=entry.fields
            service.weaknessIncoming(0x02A,entry.hex:gsub('%x%x',function(value)
                return string.char(tonumber(value,16)) end),nil,false)
        else service.weaknessText(entry.original) end
    end
    local record=Weakness.get(zone,mob)
    assert(not record.red.triggered and not record.red.element,'yellow must never alter red observations')
    if i==1 then
        assert(record.yellow.triggered and record.yellow.actor=='Miyajima' and not record.yellow.element)
        assert(#notifications==noticesBefore+1 and notifications[#notifications]:find('YELLOW PROC confirmed on Ansherekh by Miyajima.',1,true))
    else
        assert(record.yellow.element=='fire' and not record.yellow.triggered)
        assert(#sent==sentBefore+1,'repeated hint packets/text must deduplicate')
        assert(#notifications==noticesBefore+1 and notifications[#notifications]:find('YELLOW PROC search: fire (Sharabha).',1,true),
            'hint logging must be immediate and deduplicated, independent of search actions')
    end
    local update=sent[#sent];local count=#sent
    service.weaknessClear();listeners['ipc message'](update)
    assert(#sent==count,'received yellow updates must not be rebroadcast')
    local remote=Weakness.get(zone,mob)
    assert(remote.yellow.triggered==record.yellow.triggered and remote.yellow.element==record.yellow.element)
    assert(notifications[#notifications]:find('[IPC]',1,true))
    local notices=#notifications;listeners['ipc message'](update)
    assert(#notifications==notices,'duplicate IPC must not repeat detection output')
end
print('PASS: recovered fire hint and Stonega III yellow stagger captures, color isolation and IPC sharing')
