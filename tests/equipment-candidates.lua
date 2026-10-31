local inventory=require('./lib/inventory')
local Service=require('./lib/equipment/init')
local function resource(id,name,slots) return {id=id,name=name,flags={Equippable=true},slots=slots,type=4} end
resources={items={
    [1]=resource(1,'Better Mantle',{[15]=true}),[2]=resource(2,'Fallback Mantle',{[15]=true}),
    [3]=resource(3,'Original Mantle',{[15]=true}),[4]=resource(4,'Better Ring',{[13]=true,[14]=true}),
    [5]=resource(5,'Fallback Ring',{[13]=true,[14]=true}),[6]=resource(6,'Augmented Ring',{[13]=true,[14]=true}),
}}
findItem=function(query)
    if type(query)=='table' then query=query.id or query.name end
    if type(query)=='number' then return resources.items[query] end
    for _,item in pairs(resources.items) do if item.name==query then return item end end
end
extdata={decode=function(item) return {augments=item.augments or {}} end}
arrayAppend=function(t,value) t[#t+1]=value end
tableAll=function(t,fn) local result={}; for _,value in pairs(t or {}) do if fn(value) then result[#result+1]=value end end; return result end
local items,sent,reads,manager
windower={ffxi={get_items=function() reads=reads+1; return items end,
    set_equip=function(index,slot,bag) sent[#sent+1]={index=index,slot=slot,bag=bag} end},
    register_event=function(name) return name end,unregister_event=function() end}
local function reset()
    if manager then manager:destroy() end
    items={equipment={back=3,back_bag=8,left_ring=0,left_ring_bag=0,right_ring=0,right_ring_bag=0},
        wardrobe={[2]={id=2,slot=2,count=1,status=0},[3]={id=3,slot=3,count=1,status=5}}}
    sent={}; reads=0
    manager=Service.new({windower=windower,inventory=inventory,report=function(err) error(err) end})
    inventory.equipment_manager=manager
    reads=0
end
local file=assert(io.open('lib/action-context.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match('(    context.equip = function.-)%s*%-%- Push a stop request'))
local function context()
    local ctx={vars={_={eq_stack={}}}}
    local fn=assert(loadstring(body))
    setfenv(fn,setmetatable({context=ctx,inventory=inventory,varargs=function(args) return args end},{__index=_G}))
    fn(); return ctx
end
local function ack(slot,index)
    local item=items.wardrobe[index]
    manager.queue:ack(slot,{localId=index,bagId=index==0 and 0 or 8,id=item and item.id or 0})
end
reset()
local ctx=context()
local set={back={{name='Better Mantle'},{name='Fallback Mantle'}},meta={stop=true}}
assert(ctx.equipMany(set)==1 and sent[1].index==2)
assert(reads==2) -- One resolution snapshot plus queue submission's identity validation.
assert(ctx.equipment_set==set and set.meta.stop)
assert(ctx.equipMany(set)==nil and #sent==1) -- Queued fallback counts as already worn.
ack(15,2)
assert(ctx.equipMany(set)==nil and #sent==1)
items.wardrobe[1]={id=1,slot=1,count=1,status=0}
assert(ctx.equipMany(set)==1 and sent[2].index==1) -- Upgrade when better gear appears.
assert(ctx.equipMany(set)==nil and #sent==2)
ack(15,1)
items.wardrobe[4]={id=1,slot=4,count=1,status=0}
assert(ctx.equipMany(set)==nil and #sent==2) -- Spare duplicate must not cause a swap.
ack(15,4)
assert(ctx.equipMany(set)==nil and #sent==2) -- Keep whichever matching instance is worn.
assert(ctx.equipMany({back={{name='Missing A'},{name='Missing B'}}})==nil and #sent==2)
reset(); ctx=context()
assert(ctx.equip('back',{'Better Mantle','Fallback Mantle'})==true and sent[1].index==2)
assert(ctx.equip('back',{'Better Mantle','Fallback Mantle'})==true and #sent==1)
assert(ctx.checkEquipMany({back={{name='Better Mantle'},{name='Fallback Mantle'}}})==nil)
-- An owned candidate with incompatible slots doesn't block a later valid one.
reset(); ctx=context()
items.wardrobe[6]={id=4,slot=6,count=1,status=0}
assert(ctx.equipMany({back={{name='Better Ring'},{name='Fallback Mantle'}}})==1 and sent[1].index==2)
-- Resolve paired slots deterministically and never assign one copy twice.
reset(); ctx=context()
items.wardrobe[6]={id=4,slot=6,count=1,status=0}
items.wardrobe[7]={id=5,slot=7,count=1,status=0}
local rings={ring1={{name='Better Ring'},{name='Fallback Ring'}},ring2={{name='Better Ring'},{name='Fallback Ring'}}}
assert(ctx.equipMany(rings)==2 and sent[1].index==6 and sent[2].index==7)
assert(ctx.equipMany(rings)==nil and #sent==2)
ack(13,6); ack(14,7)
items.wardrobe[8]={id=4,slot=8,count=1,status=0}
assert(ctx.equipMany(rings)==1 and sent[3].slot==14 and sent[3].index==8)
ack(14,8)
assert(ctx.equipMany(rings)==nil and #sent==3)
-- Required augments choose the right physical copy; unspecified augments retain it.
reset(); ctx=context()
items.wardrobe[10]={id=6,slot=10,count=1,status=0,augments={'STR+10'}}
items.wardrobe[11]={id=6,slot=11,count=1,status=0,augments={'STR+20'}}
ack(13,11)
assert(ctx.equipMany({ring1={{name='Augmented Ring',augments={'STR+20'}},{name='Fallback Ring'}}})==nil)
assert(ctx.equipMany({ring1={name='Augmented Ring'}})==nil)
assert(ctx.equipMany({ring1={{name='Augmented Ring',augments={'STR+10'}},{name='Fallback Ring'}}})==1)
assert(sent[1].index==10)
assert(ctx.equipMany({ring1={{name='Augmented Ring',augments={'STR+10'}}}})==nil)
-- Push saves exact identity; pop restores it without candidate re-selection.
reset(); ctx=context()
assert(ctx.equipPush(set)==1); ack(15,2)
items.wardrobe[1]={id=1,slot=1,count=1,status=0}
assert(ctx.equipPop()>0 and sent[2].index==3) -- Restore Original, not the newly available Better.
manager:destroy(); inventory.equipment_manager=nil
print('PASS: ordered candidates, fallback/upgrade, duplicate stability, pending state, paired-slot exclusions, augments and exact push/pop')
