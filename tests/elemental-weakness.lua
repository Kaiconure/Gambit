local tracker=dofile('lib/elemental-weakness.lua')
local function bytes(hex) return (hex:gsub('..',function(h)return string.char(tonumber(h,16))end)) end
local mob={id=17911879,name='Plouton',hpp=88}
local packet=bytes('2A101006475011010300000000000000000000003C01000047002FA106000000')
local event=assert(tracker.message(packet,277,mob))
assert(event.element=='earth' and event.kind=='confirmed')
assert(not tracker.message(packet,275,mob))
assert(not tracker.message(packet:sub(1,20),277,mob))
assert(not tracker.message(packet,277,{id=1,name='Plouton',hpp=80}))
-- Decode the first result of the captured Thunder packet independently.
local data=bytes('2814AE051F58400C00011029000040000000C011544440005200E0FFC00100000000003B323B3800')
local function bits(pos,n)
 local v=0
 for i=0,n-1 do v=v+math.floor(data:byte(math.floor((pos+i)/8)+1)/2^((pos+i)%8))%2*2^i end
 return v
end
local result={param=bits(213,17),message=bits(230,10)}
local action={category=bits(82,4),param=bits(86,16),targets={{id=bits(150,32),actions={result}}}}
assert(action.param==164 and result.message==7 and result.param==2047)
local spells={[164]={element=4,type='BlackMagic'}}
event=assert(tracker.action(action,277,mob,spells))
assert(event.element=='earth' and event.absorbed=='thunder' and event.kind=='inferred')
spells[164].type='WhiteMagic';assert(not tracker.action(action,277,mob,spells))
spells[164].type='BlackMagic';result.message=2;result.param=100
assert(not tracker.action(action,277,mob,spells,'thunder'))
result.param=0;assert(tracker.action(action,277,mob,spells,'thunder').kind=='unknown')
print('PASS: captured confirmation and absorption packets, encounter scope, malformed packets, cure exclusion, zero-damage invalidation')
