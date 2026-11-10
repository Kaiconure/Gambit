-- Match the JSON round-trip used for compilation without serializing text.
-- Duplicate shared references per occurrence: compiled actions must not share
-- mutable scheduler fields merely because their source tables were shared.
local function snapshot(value,active)
    local kind=type(value)
    if kind=='number' then
        assert(value==value and math.abs(value)<math.huge,'Non-finite number in settings snapshot')
        return value
    end
    if kind=='string' or kind=='boolean' or kind=='nil' then return value end
    if kind~='table' then return nil end -- jsonlua emits null for unsupported values.
    active=active or {}
    assert(not active[value],'Circular table in settings snapshot')
    active[value]=true
    local count=0
    local array=true
    for _ in pairs(value) do
        count=count+1
        if value[count]==nil then array=false end
    end
    array=array and count>0
    local result={}
    if array then
        for index=1,count do result[index]=snapshot(value[index],active) end
    else
        for key,child in pairs(value)do
            assert(type(key)=='string' or type(key)=='number','Invalid settings snapshot key')
            result[type(key)=='number' and tostring(key) or key]=snapshot(child,active)
        end
    end
    active[value]=nil
    return result
end
return snapshot
