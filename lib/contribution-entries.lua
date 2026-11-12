-- Normalize declarations before discovery/compilation so filtered entries have
-- no imports, variables, warnings, replacement effects, or dependency edges.
local M={}
local function array(value,label)
    assert(type(value)=='table',label..' must be an array')
    for index in pairs(value) do
        assert(type(index)=='number' and index>=1 and index%1==0 and index<=#value,label..' must be a dense array')
    end
end
local function selectors(value,label)
    array(value,label)
    for _,name in ipairs(value) do assert(type(name)=='string' and name:match('%S'),label..' must contain selectors') end
end
function M.read(definitions,matches,warn)
    if definitions==nil then return {} end
    assert(type(definitions)=='table','contributions must be an array or legacy object')
    local ordered=definitions[1]~=nil
    local entries={}
    if ordered then
        array(definitions,'contributions')
        for _,entry in ipairs(definitions) do entries[#entries+1]=entry end
    else
        -- Retain compatibility for external configurations; migrated files use
        -- ordered entries with explicit actions arrays.
        for name,value in pairs(definitions) do
            assert(type(name)=='string','contributions must be a dense array')
            local entry={slot=name}
            if type(value)=='table' and (value.actions~=nil or value.optional~=nil or value.required_for~=nil or value['for']~=nil) then
                for key,child in pairs(value) do
                    assert(key~='slot','Legacy contributions use the object key as their slot')
                    entry[key]=child
                end
            else entry.actions=value end
            entries[#entries+1]=entry
        end
    end
    local result={}
    for _,entry in ipairs(entries) do
        assert(type(entry)=='table','Contribution entries must be objects')
        for key in pairs(entry) do
            local known=key=='slot' or key=='actions' or key=='for' or key=='optional' or key=='required_for'
            local documentation=key=='comment' or key=='note' or key == 'comments' or key == 'notes'
            if not known and not documentation and warn then warn('Unknown contribution field: '..tostring(key)) end
        end
        assert(type(entry.slot)=='string' and entry.slot:match('%S'),'Contribution slot must be a nonempty string')
        array(entry.actions,'Contribution actions')
        assert(entry.optional==nil or type(entry.optional)=='boolean','Contribution optional must be boolean')
        if entry.required_for~=nil then selectors(entry.required_for,'Contribution required_for') end
        if entry['for']~=nil then selectors(entry['for'],'Contribution for') end
        if entry['for']==nil or (matches and matches(entry['for'])) then
            result[#result+1]={slot=entry.slot,actions=entry.actions,['for']=entry['for'],
                optional=entry.optional,required_for=entry.required_for}
        end
    end
    return result,ordered
end
return M
