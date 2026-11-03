local file=assert(io.open('lib/action-context.lua')); local source=file:read('*a'); file:close()
local body=assert(source:match('(context.findKeyItem = function.-)\n    %-%-%-%-'))
local owned={123}
local resource={id=123,en='Test key item'}
local context={}
local environment=setmetatable({context=context,findKeyItem=function(query)
    if query==123 or query=='Test key item' then return resource end
end,windower={ffxi={get_key_items=function() return owned end}}},{__index=_G})
local chunk=assert(loadstring(body)); setfenv(chunk,environment); chunk()
assert(context.findKeyItem('Test key item')==resource and context.key_item==resource)
assert(context.findKeyItem(123)==resource)
owned={}
assert(not context.findKeyItem(123) and not context.key_item)
owned=nil
assert(not context.findKeyItem(123))
owned={123}
assert(not context.findKeyItem('Unknown') and not context.key_item)
assert(context.findKeyItem(123)==resource)
print('PASS: context key item ownership by name/ID, acquired/consumed state, unknown resources and unavailable key items')
