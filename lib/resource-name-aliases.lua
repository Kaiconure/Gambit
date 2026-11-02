local pairsByName={}
local canonicalByName={}
for _,pair in ipairs(require('./meta/resource-name-aliases')) do
    pairsByName[pair[1]:lower()]=pair
    pairsByName[pair[2]:lower()]=pair
    canonicalByName[pair[1]:lower()]=pair[1]:lower()
    canonicalByName[pair[2]:lower()]=pair[1]:lower()
end
local Aliases={}
function Aliases.key(name)
    if type(name)~='string' then return end
    local lower=name:lower()
    return canonicalByName[lower] or lower
end
local function query(value,column)
    local name=type(value)=='table' and not value.id and value.name or value
    local pair=type(name)=='string' and pairsByName[name:lower()]
    return pair and pair[column] or value
end
function Aliases.spell(value) return query(value,2) end
function Aliases.monster(value) return query(value,1) end
function Aliases.matchesAny(resource,filters)
    if not resource then return false end
    if filters[1]==nil then return true end
    local canonical=Aliases.key(resource.en or resource.name)
    for _,value in ipairs(filters) do
        if value=='*' then return true end
        local numeric=(type(value)=='number' or type(value)=='string') and tonumber(value)
        if numeric then
            if numeric==resource.id then return true end
        elseif type(value)=='string' and canonical and Aliases.key(value)==canonical then return true end
    end
    return false
end
function Aliases.keys(value)
    assert(type(value)=='table','resourceAliasKeys expects a table')
    local result,seen={},{}
    for name,child in pairs(value) do
        local pair=type(name)=='string' and pairsByName[name:lower()]
        if pair then
            local canonical=pair[1]
            assert(seen[canonical]==nil or seen[canonical]==child,
                'Conflicting resource name aliases: '..canonical)
            seen[canonical]=child
            result[pair[1]]=child; result[pair[2]]=child
        end
        result[name]=child
    end
    return result
end
return Aliases
