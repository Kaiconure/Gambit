local messages={}
writeMessage=function(value) messages[#messages+1]=value end
Colors={gray=1}
for _, name in ipairs({'text_green','text_red','text_yellow','text_number','text_gray','text_blue'}) do
    _G[name]=tostring
end
local output=require('./lib/value-output')
for _, value in ipairs({false,true,42,'hello',function() end}) do
    messages={}
    output.write('result',value,'Eval')
    assert(#messages==2 and messages[1]=='Eval '..type(value)..' value:')
end
messages={};output.write('missing',nil)
assert(messages[2]=='  missing: nil')
messages={};output.write('items',{'hello',false,7})
assert(#messages==5 and messages[3]=='    1: "hello"' and messages[4]=='    2: false')
messages={};output.write('map',{key='value'})
assert(messages[3]=='    key: "value"')
messages={};output.write('empty',{})
assert(#messages==2)
local cyclic={};cyclic.self=cyclic
messages={};output.write('cyclic',cyclic)
assert(#messages==3)
print('PASS: shared typed output, scalars, nil, arrays, maps, empty/cyclic tables, functions')
