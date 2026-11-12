local Loader=require('./lib/variable-loader')
local function rank(source)return ({child=0,parent=1,stock=2})[source] end
local function merged(first,second)
 local vars={};local loader=Loader.new(nil,rank)
 loader.merge(vars,first[2],first[1]);loader.merge(vars,second[2],second[1]);return vars
end
local parent={'parent',{frontline_engagement={distance=12,angle='backside'},
 values={1,2},cleared=5,object={a=1},['!strong']=1,weak=1}}
local child={'child',{frontline_engagement={distance=17},values={3},cleared='$object.null',
 object='$object.empty',strong=2,['^weak']=2}}
for _,pair in ipairs({{parent,child},{child,parent}})do
 local vars=merged(pair[1],pair[2])
 assert(vars.frontline_engagement.distance==17 and vars.frontline_engagement.angle=='backside')
 assert(#vars.values==1 and vars.values[1]==3 and vars.cleared==nil and next(vars.object)==nil)
 assert(vars.strong==1 and vars.weak==1) -- Explicit priority still wins first.
end
for _,prefix in ipairs({'','!','^'})do
 for _,pair in ipairs({{{'parent',{[prefix..'x']=1}},{'child',{[prefix..'x']=2}}},
                      {{'child',{[prefix..'x']=2}},{'parent',{[prefix..'x']=1}}}})do
  assert(merged(pair[1],pair[2]).x==2)
 end
end
-- Lower-precedence stock imported by a child must not override namespace values.
assert(merged({'parent',{x=1}},{'stock',{x=2}}).x==1)
assert(merged({'child',{x=1}},{'child',{x=2}}).x==1) -- Within-layer order is unchanged.
for _,pair in ipairs({
 {{'parent',{list={1,2},['array.append(list)']={4}}},{'child',{['array.remove(list)']={2,4},['array.append(list)']={3}}}},
 {{'child',{['array.remove(list)']={2,4},['array.append(list)']={3}}},{'parent',{list={1,2},['array.append(list)']={4}}}}
})do
 local vars=merged(pair[1],pair[2]);assert(#vars.list==2 and vars.list[1]==1 and vars.list[2]==3)
end
for _,pair in ipairs({
 {{'parent',{['array.append(list)']={1}}},{'child',{list='$array.empty'}}},
 {{'child',{list='$array.empty'}},{'parent',{['array.append(list)']={1}}}}
})do assert(#merged(pair[1],pair[2]).list==0)end
-- Use actual Geas setup data, discovered after an ancestor WHM common file.
local json=require('./lib/jsonlua')
local function read(path)local f=assert(io.open(path));local d=json.parse(f:read('*a'));f:close();return d.vars end
local actual=merged({'parent',read('settings/_namespaces/_boss/actions/lib/common/whm.json')},
 {'child',read('settings/_namespaces/_geas/actions/lib/setup/use-spacing.json')})
assert(actual.frontline_engagement.distance==17 and actual.frontline_engagement.radius_multiplier==0)
print('PASS: namespace ties in both import orders, nested fields, explicit priorities, arrays/overlays/clears and real Geas spacing')
