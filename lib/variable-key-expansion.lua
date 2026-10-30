-- Expand explicit csv(...) keys before priority-aware variable merging.
local function expand(value,inherited,label)
    if type(value)~='table' then return value end
    local result,generated,explicit={},{},{}
    local function keyInfo(raw)
        if type(raw)~='string' then return raw,inherited,'' end
        local prefix=raw:sub(1,1)
        if prefix=='!' then return raw:sub(2),1,prefix end
        if prefix=='^' then return raw:sub(2),-1,prefix end
        return raw,inherited,''
    end
    local function identity(name,priority) return tostring(priority)..':'..tostring(name) end
    for raw in pairs(value) do
        local name,priority=keyInfo(raw)
        if type(name)~='string' or not name:match('^csv%(') then
            explicit[identity(name,priority)]=true
        end
    end
    for raw,child in pairs(value) do
        local name,priority,prefix=keyInfo(raw)
        if type(name)=='string' and name:match('^csv%(') then
            local contents=name:match('^csv%((.*)%)$')
            assert(contents,label..': malformed CSV variable key '..name)
            for item in (contents..','):gmatch('(.-),') do
                item=item:match('^%s*(.-)%s*$')
                assert(item~='',label..': empty name in '..name)
                local id=identity(item,priority)
                assert(not generated[id],label..': overlapping CSV variable '..item)
                generated[id]=true
                if not explicit[id] then
                    result[prefix..item]=expand(child,priority,label..'.'..item)
                end
            end
        else
            result[raw]=expand(child,priority,label..'.'..tostring(name))
        end
    end
    return result
end
return expand
