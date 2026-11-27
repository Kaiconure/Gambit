local file=assert(io.open('lib/commands.lua'))
local source=file:read('*a'); file:close()
local handler=assert(source:match("(handlers%['reload'%] = function.-)\nhandlers%['r'%] = handlers%['reload'%]"))
handler=handler:gsub("('[^'\r\n]*'):format",'(%1):format')
local calls,errors={},{}
local activeNamespace='xp/speed'
local function indexOf(values,needle)
    for index,value in ipairs(values) do
        if type(value)=='string' and value:lower()==needle:lower() then return index end
    end
end
local env=setmetatable({handlers={},arrayIndexOfStrI=indexOf,settingsPaths={
    getLoadedNamespace=function() return activeNamespace end,
    validateNamespace=function(name) return name=='example', 'invalid namespace' end,
},settings={actionInfo={name='current'}},
    reloadSettings=function(actions,bypass,namespace,verbose)
        calls[#calls+1]={actions=actions,bypass=bypass,namespace=namespace,
            namespaceIsFalse=namespace==false,verbose=verbose}
        activeNamespace=namespace or nil
    end,
    writeError=function(message) errors[#errors+1]=message end,
    writeMessage=function() end,text_action=tostring,
},{__index=_G})
local chunk=assert(loadstring(handler));setfenv(chunk,env);chunk()
local run=env.handlers.reload

run({})
assert(calls[#calls].namespace=='xp/speed' and calls[#calls].actions==nil)
run({'-ns','example'})
run({})
assert(calls[#calls].namespace=='example' and calls[#calls].actions==nil)
run({'-r'})
assert(calls[#calls].namespace=='example' and calls[#calls].actions=='current')
run({'-global'})
run({})
assert(calls[#calls].namespaceIsFalse)

run({'-a','gambit:skillups/ranged','-ns','global'})
assert(calls[#calls].actions=='gambit:skillups/ranged' and calls[#calls].namespaceIsFalse)
run({'-a','gambit:skillups/ranged','-ns','gambit'})
assert(calls[#calls].namespaceIsFalse)
run({'-a','gambit:skillups/ranged','-global'})
assert(calls[#calls].namespaceIsFalse)
run({'-a','gambit:skillups/ranged','-gambit'})
assert(calls[#calls].namespaceIsFalse)
run({'-a','local','-ns','example'})
assert(calls[#calls].namespace=='example')
local count=#calls
run({'-global','-ns','example'})
run({'-global','-gambit'})
run({'-global','-so'})
assert(#calls==count and #errors==3)
print('PASS: reload global/gambit namespace aliases and shorthand flags')
