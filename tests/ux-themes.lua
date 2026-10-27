local Theme=require('./lib/ux/theme')
assert(Theme.backgrounds.ff7.border==10 and Theme.backgrounds.ff8.border==5)
local checked={}
local definitions={solid={color={1,2,3}},custom={folder='content/ui/custom/',border=8,opacity=190}}
local registry=Theme.validate(definitions,function(path) checked[#checked+1]=path; return true end)
assert(registry.custom.border==8 and #checked==9)
assert(registry.solid.opacity==255 and definitions.solid.opacity==nil)
assert(not pcall(Theme.validate,definitions,function() return false end))
local minimal=Theme.validate(definitions,function(path) return path:match('/center.png$')~=nil end)
assert(minimal.custom.pieces.center and not minimal.custom.pieces.left)
for _,bad in ipairs({{folder='../escape/',border=4},{folder='/absolute/',border=4},
    {folder='content/ui/ff7/',border=0},{color={256,0,0}},{color={0,0,0},opacity=-1}}) do
    assert(not pcall(Theme.validate,{solid={color={0,0,0}},bad=bad}))
end
print('PASS: JSON theme registry, arbitrary skins, defaults, asset checks and validation')
