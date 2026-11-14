local Config=require('./lib/events/config')
local Runtime=require('./lib/events/runtime')

local captured={}
local config=Config.load({'text-test'},function()
    return {texts={received={{
        when={"event.text:find('Objective:', 1, true)"},
        commands={"setActionVar('objective', event.text)","setActionVar('mode', event.mode)"},
    }}}}
end)
assert(config.available_slots['texts.received.before'] and config.available_slots['texts.received.after'])
assert(not pcall(Config.load,{'bad'},function()
    return {texts={use_equipment_snapshot=true,received={}}}
end))

local runtime=Runtime.new(config,{clock=os.clock,report=function(message) error(message) end,
    context=function(_,state)
        return {vars=state.vars,setActionVar=function(name,value) captured[name]=value; return value end}
    end})
runtime:observe({kind='text',text='Unrelated message',original='Unrelated message',mode=1},'received')
assert(captured.objective==nil)
runtime:observe({kind='text',text='Objective: Eliminate all enemies.',
    original='Objective: Eliminate all enemies.',modified='Objective: Eliminate all enemies.',mode=148},'received')
assert(captured.objective=='Objective: Eliminate all enemies.' and captured.mode==148)

-- Incoming text continues during zoning, when player-backed temporary contexts
-- are deliberately unavailable. Skipping that observation must remain quiet.
local reports={}
local contextAvailable=false
local deferred={}
local unavailable=Runtime.new(config,{clock=os.clock,
    report=function(message) reports[#reports+1]=message end,
    context=function(_,state)
        if not contextAvailable then return nil end
        return {vars=state.vars,setActionVar=function(name,value) deferred[name]=value end}
    end})
unavailable:observe({kind='text',text='Objective: Eliminate all enemies.',mode=148},'received')
assert(#reports==0 and deferred.objective==nil and #unavailable.deferredObservations==1)
contextAvailable=true
unavailable:tick()
assert(deferred.objective=='Objective: Eliminate all enemies.' and #unavailable.deferredObservations==0)

-- Actual context-construction failures remain visible.
local broken=Runtime.new(config,{clock=os.clock,
    report=function(message) reports[#reports+1]=message end,
    context=function() error('context failure') end})
broken:observe({kind='text',text='Objective: Eliminate all enemies.',mode=148},'received')
assert(#reports==1 and reports[1]:find('context failure',1,true))
print('PASS: incoming text event schema, slots, filtering and global-state commands')
