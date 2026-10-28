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
panel:setTemporaryTracking({{name='Temporary',value='Value'}})
panel.buffer:add('Retained log')
panel:reset()
local function equal(a,b)
    if type(a)~='table' then return a==b end
    if type(b)~='table' then return false end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
assert(equal(panel.options,Config.normalize(Config.defaults)))
assert(#saved==1 and equal(saved[1],panel.options))
assert(panel.trackingOverride==nil and panel.options.tracking.sets.custom==nil)
assert(panel.options.tracking~=Config.defaults.tracking)
assert(panel.buffer.lines[1]=='Retained log')
panel:destroy()
print('PASS: reset restores and saves all defaults, clears overrides and custom sets, preserves log history')
