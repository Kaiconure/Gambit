-- Compile the entire context: isolated helper tests cannot catch upvalue limits.
local f=assert(io.open('lib/action-context.lua'))
local source=f:read('*a');f:close()
-- Windower allows method calls directly on string literals; stock Lua does not.
source=source:gsub("('[^'\r\n]*'):format", '(%1):format')
assert(loadstring(source, '@lib/action-context.lua'))
print('PASS: complete action context compiles within Lua limits')
