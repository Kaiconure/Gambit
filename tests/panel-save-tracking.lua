local Status=require('./lib/ux/status-panel')
local Config=require('./lib/ux/status-config')
local saved={}
local function primitive()
    return setmetatable({}, {__index=function() return function() end end})
end
local panel=Status.new({texts={new=primitive},images={new=primitive},
    windower={register_event=function() return 1 end,unregister_event=function() end},
    loggedIn=function() return true end,enabled=function() return false end,
    subscribe=function() return function() end end,toggle=function() end,
    context=function() return {gambit={strategy='leader'}} end,
    save=function(options) saved[#saved+1]=options end},
    {visible=false,width=900,height=500,x=800,y=700,theme='solid',show_log=true,
        anchor={vertical='bottom',horizontal='right'},tracking={current='custom',sets={custom={}}}})
panel:setTracking('default')
panel:saveTracking('mine')
assert(panel.options.tracking.current=='mine' and panel.trackingOverride==nil)
assert(saved[#saved].tracking.sets.mine and saved[#saved].tracking.sets.default==nil)
assert(panel.options.tracking.sets.mine~=panel.options.tracking.sets.default)
local original=panel.options.tracking.sets.default[1].name
panel.options.tracking.sets.mine[1].name='Changed'
assert(panel.options.tracking.sets.default[1].name==original)
panel:setTemporaryTracking({{name='Temporary',expression="'live'"}})
local count=#saved
local ok,err=pcall(panel.saveTracking,panel,'mine')
assert(not ok and tostring(err):find('-force',1,true))
assert(#saved==count and panel.trackingOverride and panel.options.tracking.sets.mine[1].name=='Changed')
panel:saveTracking('mine',true)
assert(#panel.options.tracking.sets.mine==1 and panel.options.tracking.sets.mine[1].expression=="'live'")
assert(panel.trackingOverride==nil and saved[#saved].tracking.current=='mine')
local loaded=Config.normalize(saved[#saved])
assert(loaded.tracking.sets.mine[1].name=='Temporary')
local before=#saved
assert(not pcall(panel.saveTracking,panel,'default'))
assert(not pcall(panel.saveTracking,panel,''))
assert(#saved==before and panel.options.tracking.current=='mine')
panel:setTemporaryTracking({{references='compact'}})
panel:saveTracking('expanded')
assert(#panel.options.tracking.sets.expanded>0 and not panel.options.tracking.sets.expanded[1].references)
panel:destroy()
print('PASS: save tracking snapshots, temporary rows, overwrite, stock protection, expansion and persistence')