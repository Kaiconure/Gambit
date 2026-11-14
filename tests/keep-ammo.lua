local json=require('./lib/jsonlua')
local file=assert(io.open('actions/lib/keep-ammo.json'))
local document=json.parse(file:read('*a'));file:close()
assert(#document.actions==2)
local equip=document.actions[1]
local pouch=document.actions[2]
assert(equip.when[2]=='not canRangedAttack()' and pouch.when[3]=='not canRangedAttack()')
assert(equip.when[3]==pouch.when[4])
local compatible=assert(loadstring('return '..equip.when[3]))

local function matches(rangeType,ammoType)
    local env={vars={keep_ammo={ammo='Configured Ammo'}}}
    env.itemInfo=function(name)
        assert(name=='Configured Ammo')
        env.item_info={ammo_type=ammoType}
        return env.item_info
    end
    env.slotInfo=function(slot)
        assert(slot=='range')
        if not rangeType then return nil end
        env.slot_info={item={range_type=rangeType}}
        return env.slot_info
    end
    setfenv(compatible,env)
    return not not compatible()
end

assert(matches('Bow','Arrow'))
assert(matches('Crossbow','Bolt'))
assert(matches('Gun','Bullet'))
assert(not matches('Bow','Bolt'))
assert(not matches('Crossbow','Bullet'))
assert(not matches('Gun','Arrow'))
assert(not matches(nil,'Bullet'))
print('PASS: keep-ammo gates equipping and pouch use by ranged weapon/ammunition type')
