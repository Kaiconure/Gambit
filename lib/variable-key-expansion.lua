-- Expand explicit csv(...) keys before priority-aware variable merging.
local function keyInfo(raw,inherited)
    if type(raw)~='string' then return raw,inherited,'' end
    local prefix=raw:sub(1,1)
    if prefix=='!' then return raw:sub(2),1,prefix end
    if prefix=='^' then return raw:sub(2),-1,prefix end
    return raw,inherited,''
end
local function identity(name,priority) return tostring(priority)..':'..tostring(name) end
-- Objects combine recursively; explicit scalars/arrays replace generated ones.
-- Keep differently prioritized keys separate for the normal variable loader.
local function overlay(base,specific,priority)
    if type(base)~='table' or type(specific)~='table' or base[1]~=nil or specific[1]~=nil then
        return specific
    end
    local keys={}
    for raw in pairs(base) do
        local name,childPriority=keyInfo(raw,priority)
        keys[identity(name,childPriority)]=raw
    end
    for raw,child in pairs(specific) do
        local name,childPriority=keyInfo(raw,priority)
        local previous=keys[identity(name,childPriority)]
        if previous~=nil then
            child=overlay(base[previous],child,childPriority)
            base[previous]=nil
        end
        base[raw]=child
    end
    return base
end
local function expand(value,inherited,label)
    if type(value)~='table' then return value end
    local result,generated={},{}
    -- Expand shared definitions first, independently of JSON/pairs ordering.
    for raw,child in pairs(value) do
        local name,priority,prefix=keyInfo(raw,inherited)
        if type(name)=='string' and name:match('^csv%(') then
            local contents=name:match('^csv%((.*)%)$')
            assert(contents,label..': malformed CSV variable key '..name)
            for item in (contents..','):gmatch('(.-),') do
                item=item:match('^%s*(.-)%s*$')
                assert(item~='',label..': empty name in '..name)
                local id=identity(item,priority)
                assert(not generated[id],label..': overlapping CSV variable '..item)
                generated[id]=prefix..item
                result[prefix..item]=expand(child,priority,label..'.'..item)
            end
        end
    end
    for raw,child in pairs(value) do
        local name,priority=keyInfo(raw,inherited)
        if type(name)~='string' or not name:match('^csv%(') then
            local specific=expand(child,priority,label..'.'..tostring(name))
            local shared=generated[identity(name,priority)]
            if shared then
                specific=overlay(result[shared],specific,priority)
                result[shared]=nil
            end
            result[raw]=specific
        end
    end
    return result
end
return expand
