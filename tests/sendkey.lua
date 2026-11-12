local f=assert(io.open('lib/commands.lua'));local source=f:read('*a');f:close()
local body=assert(source:match("(handlers%['sendkey'%] = function%(args%).-)handlers%['sk'%] = handlers%['sendkey'%]"))
body=body:gsub("('[^'\r\n]*'):format",'(%1):format')
local sent,sleeps,messages={},{},{}
local env={handlers={},table=table,ipairs=ipairs,tonumber=tonumber,math=math,
 text_yellow=function(value)return value end,
 writeMessage=function(value)messages[#messages+1]=value end,
 coroutine={sleep=function(value)sleeps[#sleeps+1]=value end},
 windower={send_command=function(value)sent[#sent+1]=value end}}
local fn=assert(loadstring(body));setfenv(fn,env);fn()
local function run(args)
 sent={};sleeps={};messages={};env.handlers.sendkey(args)
 local keys={}
 for _,command in ipairs(sent)do keys[#keys+1]=assert(command:match('^setkey (.-) down;')) end
 return table.concat(keys,',')
end
assert(run({'3x','down','enter'})=='down,down,down,enter')
assert(sleeps[1]==0.5 and #sleeps==5)
assert(run({'3','enter'})=='3,enter')
assert(run({'2x','3','enter'})=='3,3,enter')
assert(run({'down','2X','up','enter'})=='down,up,up,enter')
assert(run({'down','down','down','enter'})=='down,down,down,enter')
assert(run({'x','enter'})=='x,enter')
for _,args in ipairs({{'down','3x'},{'0x','down'},{'2x','3x','down'}})do
 assert(run(args)=='' and #messages==1 and #sleeps==0)
end
assert(run({})=='' and #sent==0)
print('PASS: explicit key multipliers, literal numeric keys, mixed sequences, preserved timing and validation before sending')
