local Waypoint=require('./lib/ux/waypoint')
local Config=require('./lib/ux/status-config')
local Status=require('./lib/ux/status-panel')

for _,color in ipairs({'green','yellow','red','gray'}) do
    for _,frame in ipairs({0,8,16,24,31}) do
        local file=assert(io.open(('content/ui/general/direction/%s/%02d.png'):format(color,frame),'rb'))
        file:close()
    end
end

local config={zone=77,x=10,y=0,near=10,mid=30,show_distance=true,distance_format='%.1f yalms',size=32}
local context={zone_id=77,me={x=0,y=0,heading=0}}
local state=assert(Waypoint.resolve(config,context))
assert(state.frame==0 and state.color=='green' and state.label=='10.0 yalms')
config.x,config.y=0,-20
state=assert(Waypoint.resolve(config,context))
assert(state.frame==8 and state.color=='yellow')
context.me.heading=math.pi/2
assert(Waypoint.resolve(config,context).frame==0)
config.x,config.y=50,0; context.me.heading=0
assert(Waypoint.resolve(config,context).color=='red')
config.far=40; assert(Waypoint.resolve(config,context).color=='red') -- Fixed points remain visible beyond far.
config.far=nil; context.zone_id=78; assert(Waypoint.resolve(config,context)==nil)

context.zone_id=77; context.me.heading=0
local nameLookups=0
local tracked={zone=77,name='Tracked mob',mob_id=42,mob_name='Fallback',near=5,mid=30,
    show_distance=true,distance_format='%.1f yalms'}
context.mobById=function(id) assert(id==42); return {mob={x=0,y=-20}} end
context.findByName=function() nameLookups=nameLookups+1; return {mob={x=-20,y=0}} end
state=assert(Waypoint.resolve(tracked,context))
assert(state.frame==8 and state.color=='yellow' and nameLookups==0)
tracked.far=10; assert(Waypoint.resolve(tracked,context).color=='yellow')
tracked.far=nil
context.mobById=function() return {mob={x=50,y=0,valid_target=false}} end
context.ipcPositionById=function(id)
    assert(id==42)
    return {id=id,zone=77,x=-20,y=0}
end
state=assert(Waypoint.resolve(tracked,context,{x=0,y=-20,id=42}))
assert(state.frame==16 and state.color=='yellow' and state.current==true)
context.ipcPositionById=nil
state=assert(Waypoint.resolve(tracked,context,{x=0,y=-20}))
assert(state.frame==8 and state.color=='gray' and state.current==false)
context.mobById=function() error('not available') end
state=assert(Waypoint.resolve(tracked,context))
assert(state.frame==16 and nameLookups==1)
context.findByName=function() return nil end
assert(Waypoint.resolve(tracked,context)==nil)
state=assert(Waypoint.resolve(tracked,context,{x=0,y=-20}))
assert(state.frame==8 and state.color=='gray' and state.current==false)
tracked.x,tracked.y=10,0
state=assert(Waypoint.resolve(tracked,context))
assert(state.frame==0 and state.color=='gray') -- Fixed coordinates are a final fallback.

local named={zone=77,mob_name='Runner',near=5,mid=30,show_distance=false}
context.findByName=function() return {mob={id=84,x=20,y=0,valid_target=true}} end
state=assert(Waypoint.resolve(named,context))
assert(state.id==84 and state.current==true)
context.findByName=function() return nil end
context.ipcPositionById=function(id) return {id=id,zone=77,x=0,y=-20} end
state=assert(Waypoint.resolve(named,context,state))
assert(state.id==84 and state.frame==8 and state.current==true)
context.ipcPositionById=nil

local definition={name='Waypoint',zone=77,x=10,y=0,near=10,mid=15,show_distance=true}
local normalized=Config.normalize({waypoint=definition})
assert(normalized.waypoint.distance_format=='%.1f yalms')
local function invalid(waypoint)
    assert(not pcall(Config.normalize,{waypoint=waypoint}))
end
invalid({name='Bad',zone=77,x=0}); invalid({name='Bad',zone=77,x=0,y=0,near=10,mid=5})
invalid({name='Bad',zone=77,x=0,y=0,near=5,mid=10,far=9})
assert(Config.normalizeWaypoint({name='Mob',zone=77,mob_name='???'}).mob_name=='???')
assert(Config.normalizeWaypoint({name='Mob',zone=77,mob_id=123}).mob_id==123)
invalid({name='Bad',zone=77,mob_id=-1}); invalid({name='Bad',zone=77,mob_name=''})

local function primitive()
    return setmetatable({}, {__index=function(_,key)
        return function(self,value,...)
            if key=='path' then self.texture=value end
            if key=='visible' then self.shown=value end
            if key=='text' then self.value=value end
            if key=='destroy' then self.destroyed=true end
        end
    end})
end
context.zone_id=77; context.me={x=0,y=0,heading=0}
local panel=Status.new({texts={new=primitive},images={new=primitive},
    windower={register_event=function() return 1 end,unregister_event=function() end},
    loggedIn=function() return true end,enabled=function() return true end,
    subscribe=function() return function() end end,toggle=function() end,
    context=function() return context end}, {waypoint=definition})
panel:update()
local waypoint=panel.waypoint
assert(#panel.entries==4 and waypoint.icon.image.texture:find('direction/green/00.png',1,true))
assert(waypoint.distance.text.value=='10.0 yalms' and waypoint.name.text.value=='Waypoint'
    and waypoint.icon.image.shown==true and waypoint.icon.x<0)
assert(waypoint.background.parts.center.shown==true and waypoint.sideWidth>waypoint.config.size)
context.me.heading=math.pi
panel.nextUpdate=0; panel:update()
assert(waypoint.icon.image.texture:find('direction/green/16.png',1,true))
waypoint.config.mob_id=42
context.mobById=function() return nil end
panel.nextUpdate=0; panel:update()
assert(waypoint.icon.image.texture:find('direction/gray/16.png',1,true))
waypoint.config.mob_id=nil
panel:setAnchor('top','left'); panel.nextUpdate=0; panel:update()
assert(waypoint.icon.x>panel.panel.width)
local attachedX=waypoint.icon.x
panel:setSize(600,nil); panel.nextUpdate=0; panel:update()
waypoint=panel.waypoint
assert(waypoint.icon.x>attachedX and waypoint.icon.x>panel.panel.width)
context.mobById=function() return {mob={x=25,y=0,valid_target=true}} end
panel:setWaypoint({name='Persistent',zone=77,mob_id=99,near=10,mid=30})
assert(panel.waypoint.lastKnown.x==25 and panel.waypoint.lastKnown.y==0)
context.mobById=function() return {mob={x=50,y=0,valid_target=false}} end
panel:configure(panel.options)
panel.nextUpdate=0; panel:update()
waypoint=panel.waypoint
assert(waypoint.config.name=='Persistent' and waypoint.lastKnown.x==25
    and waypoint.state.color=='gray')
context.zone_id=78
panel.nextUpdate=0; panel:update()
assert(waypoint.icon.image.shown==false and waypoint.name.text.value==''
    and waypoint.background.parts.center.shown==false)
context.zone_id=77
panel:setWaypoint({name='Temporary',zone=77,x=50,y=0,near=10,mid=30,show_distance=false})
assert(panel.waypoint.config.name=='Temporary' and panel.waypointOverride.name=='Temporary')
panel:setWaypoint(nil)
assert(panel.waypoint.config.name=='Waypoint' and panel.waypointOverride==nil)
local contextFile=assert(io.open('lib/action-context.lua'))
local contextSource=contextFile:read('*a'); contextFile:close()
assert(contextSource:find('context.setPanelWaypoint = function(waypoint)',1,true))
assert(contextSource:find('context.ipcPositionById = function(id)',1,true))
local addonFile=assert(io.open('Gambit.lua'))
local addonSource=addonFile:read('*a'); addonFile:close()
assert(addonSource:find('status_panel:configure(loadPanelSettings(),false)',1,true))
assert(addonSource:find('local POSITION_HEARTBEAT = 5',1,true))
panel:destroy()

print('PASS: waypoint panel validation, range colors, relative bearing, distance and zone visibility')
