local copy=require('./lib/variable-values').copy
local References={}
function References.resolve(value,lookup,active,depth)
    if type(value)~='table' then return value end
    active=active or {}; depth=depth or 0
    assert(depth<32,'Equipment variable reference nesting exceeds 32 levels')
    if value.var~=nil then
        assert(type(value.var)=='string' and value.var:match('%S'),'Equipment var must be a nonempty variable path')
        for key in pairs(value) do assert(key=='var','Equipment var references cannot include other fields') end
        assert(not active[value],'Circular equipment variable reference: '..value.var)
        active[value]=true
        local result=References.resolve(lookup(value.var),lookup,active,depth+1)
        active[value]=nil
        assert(result==nil or type(result)=='string' or type(result)=='table',
            'Equipment variable must resolve to an item string, object, or candidate array')
        return copy(result)
    end
    if #value>0 then
        local result={}
        for _,candidate in ipairs(value) do
            local resolved=References.resolve(candidate,lookup,active,depth+1)
            if resolved~=nil then
                if type(resolved)=='table' and #resolved>0 then
                    for _,item in ipairs(resolved) do result[#result+1]=item end
                else result[#result+1]=resolved end
            end
        end
        return result
    end
    return value
end
return References
