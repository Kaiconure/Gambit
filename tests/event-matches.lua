local Matches=require('./lib/events/matches')
local values=require('./lib/variable-values')
for _,kind in ipairs({'buff','spell','job_ability','weapon_skill','pet_ability','enemy_spell','enemy_ability'}) do
    local event={kind=kind,id=15,name='dOoM'}
    Matches.attach(event)
    assert(event.matches('Doom') and event.matches('doom') and event.matches('DOOM'))
    assert(event.matches(15) and event.matches('15') and not event.matches('doomed'))
    assert(not event.matches(16) and not event.matches(nil) and not event.matches({}))
    assert(event.name=='dOoM')
end
local unknown={kind='buff',id=999}; Matches.attach(unknown)
assert(unknown.matches('999') and not unknown.matches('Unknown'))
local status={kind='status',category='battle',status=0,old_status=1,phase='leave'}
Matches.attach(status); assert(status.matches('BATTLE') and status.matches(1) and not status.matches(0))
local zone={kind='zone',zone=2,zone_name='New',old_zone=1,old_zone_name='Old',phase='leave'}
Matches.attach(zone); assert(zone.matches('OLD') and zone.matches('1') and not zone.matches(2))
zone.phase='enter'; Matches.attach(zone); assert(zone.matches('NEW') and zone.matches(2))
local piece={name="Eshmun's Ring"}
local original={Doom=piece,['15']={removed={}},[42]='Numeric',FALSE=false}
local lower=values.caseInsensitiveKeys(original)
assert(lower.doom==piece and lower['15']==original['15'] and lower[42]=='Numeric' and lower['false']==false)
assert(original.Doom==piece and lower.Doom==nil and piece.name=="Eshmun's Ring")
assert(not pcall(values.caseInsensitiveKeys,{Doom={},doom={}}))
assert(not pcall(values.caseInsensitiveKeys,{Doom=false,doom={}}))
assert(not pcall(values.caseInsensitiveKeys,nil))
print('PASS: event matching names/IDs, observational identity, unchanged names and general shallow key normalization')
