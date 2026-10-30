local Loader=require('./lib/variable-loader')
local function load(value,priority)
    local result={}
    Loader.new().merge(result,value,'test',priority)
    return result
end
local input={gear={['csv( Savage Blade , Shining Blade )']={ring1={name='Ring'}}}}
local result=load(input)
assert(result.gear['Savage Blade'].ring1.name=='Ring')
assert(result.gear['Shining Blade'].ring1.name=='Ring')
result.gear['Savage Blade'].ring1.name='Changed'
assert(result.gear['Shining Blade'].ring1.name=='Ring')
assert(input.gear['csv( Savage Blade , Shining Blade )'].ring1.name=='Ring')
result=load({['csv(A,B)']={x=1},A={x=2}})
assert(result.A.x==2 and result.B.x==1)
result=load({['!csv(A,B)']=1,A=2})
assert(result.A==1 and result.B==1)
result=load({['^csv(A,B)']=1,A=2})
assert(result.A==2 and result.B==1)
result=load({['!parent']={['csv(A,B)']=1,['!A']=2}})
assert(result.parent.A==2 and result.parent.B==1)
local state,vars=Loader.new(),{}
state.merge(vars,{['csv(A,B)']={x=2}},'specific')
state.merge(vars,{['^csv(A,B,C)']={x=1}},'fallback')
assert(vars.A.x==2 and vars.B.x==2 and vars.C.x==1)
result=load({['csv(A,B)']={{['csv(x,y)']=3}}})
assert(result.A[1].x==3 and result.B[1].y==3)
for _,value in ipairs({
    {['csv()']=1},{['csv(A,)']=1},{['csv(,A)']=1},{['csv(A,,B)']=1},
    {['csv(A']=1},{['csv(A,A)']=1},{['csv(A,B)']=1,['csv(B,C)']=2},
}) do
    local ok,err=pcall(load,value)
    assert(not ok and tostring(err):find('test',1,true))
end
print('PASS: recursive CSV keys, independent copies, explicit siblings, priorities, arrays and deterministic validation')
