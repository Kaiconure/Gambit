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
result=load({gear={['csv(battle,idle)']={ring1={name='Yacuruna Ring'},
    ring2={name='Yacuruna Ring'},back={name='Repulse Mantle'}},idle={ring2={name='Schneddick Ring'}}}})
assert(result.gear.idle.ring1.name=='Yacuruna Ring' and result.gear.idle.back.name=='Repulse Mantle')
assert(result.gear.idle.ring2.name=='Schneddick Ring' and result.gear.battle.ring2.name=='Yacuruna Ring')
result=load({['csv(A,B)']={piece={name='Ring',meta={stop=true}},list={1,2}},
    A={piece={name='Other'},list={3}}})
assert(result.A.piece.name=='Other' and result.A.piece.meta.stop)
assert(#result.A.list==1 and result.A.list[1]==3 and #result.B.list==2)
result=load({['csv(A,B)']={x=1,y=2},A={}})
assert(result.A.x==1 and result.A.y==2) -- Empty objects add no overrides.
result=load({['csv(A,B)']={x=1,y=2},A='$object.null'})
assert(result.A==nil and result.B.y==2)
result=load({['csv(A,B)']={['!x']=1,['^y']=2,z=3},A={x=4,y=5,z=6}})
assert(result.A.x==1 and result.A.y==5 and result.A.z==6)
result=load({['!parent']={['csv(A,B)']={x=1,y=2},['!A']={x=3}}})
assert(result.parent.A.x==3 and result.parent.A.y==2 and result.parent.B.x==1)
local merged,mergeState={},Loader.new()
mergeState.merge(merged,{['csv(A,B)']={x=1,y=2},A={x=3}},'character')
mergeState.merge(merged,{A={x=4,y=5,z=6}},'other import')
assert(merged.A.x==3 and merged.A.y==2 and merged.A.z==6) -- Ordinary cross-file precedence is unchanged.
mergeState.merge(merged,{A={['!y']=7}},'priority override')
assert(merged.A.y==7)
result=load({['csv(A,B)']={x=1},A='$object.empty'})
assert(next(result.A)==nil and result.B.x==1)
result=load({['csv(A,B)']={nested={x=1,y=2}},A={nested={x=3}}})
result.A.nested.y=9
assert(result.B.nested.y==2) -- Generated siblings retain independent copies after overlay.
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
