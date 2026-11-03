local file=assert(io.open('lib/commands.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match("(handlers%['function'%] = function.-)\nhandlers%['func'%]"))
body=body:gsub("('[^'\r\n]*'):format",'(%1):format')
local output={}
local env=setmetatable({handlers={},actionStateManager={functions={
    ['abyssea/checklists/orthrus']={description='Orthrus'},['abyssea/red/use']={},['other']={},['a.b/test']={}}},
    getArgValue=function(args,flag) for i,v in ipairs(args) do if v==flag then return args[i+1] end end end,
    arrayIndexOfStrI=function(args,flag) for i,v in ipairs(args) do if v:lower()==flag then return i end end end,
    writeMessage=function(message) output[#output+1]=message end,
    text_green=tostring,text_gray=tostring,pluralize=function(n) return tostring(n) end}, {__index=_G})
local chunk=assert(loadstring(body)); setfenv(chunk,env); chunk()
local function run(args) output={}; env.handlers['function'](args); return table.concat(output,'\n') end
assert(run({'-list'}):find('You have 4 configured!',1,true))
local filtered=run({'-n','ABYSSEA/','-list'})
assert(filtered:find('Orthrus',1,true) and filtered:find('Found 2 matching',1,true) and not filtered:find('\nother\n',1,true))
assert(run({'-list','-prefix','a.b/'}):find('Found 1 matching',1,true))
assert(run({'-prefix','missing'}):find('Found 0 matching',1,true))
assert(run({'-n','-list'}):find('You have 4 configured!',1,true))
assert(run({'-n','-f','abyssea'}):find('Found 2 matching',1,true))
assert(run({'-n','-filter','ABYSSEA'}):find('Found 2 matching',1,true))
print('PASS: function listing prefix filters, shortcut arguments, case folding, literal matching, no matches and unfiltered listing')
