local json=require('./lib/jsonlua')
local Export={}
local slots={'main','sub','range','ammo','head','body','hands','legs','feet','neck','waist','ear1','ear2','ring1','ring2','back'}
local slotOrder={}
for index,slot in ipairs(slots) do slotOrder[slot]=index end
local function pretty(value,depth,inline)
    if type(value)~='table' then return json.stringify(value) end
    local array=#value>0
    local keys={}
    if array then for i=1,#value do keys[#keys+1]=i end
    else for key in pairs(value) do keys[#keys+1]=key end
        table.sort(keys,function(a,b)
            if slotOrder[a] and slotOrder[b] then return slotOrder[a]<slotOrder[b] end
            if a=='name' then return b~='name' elseif b=='name' then return false end
            return a<b
        end)
    end
    if #keys==0 then return array and '[]' or '{}' end
    if inline then
        local parts={}
        for _,key in ipairs(keys) do
            parts[#parts+1]=(array and '' or json.stringify(key)..': ')..pretty(value[key],depth,true)
        end
        return (array and '[ ' or '{ ')..table.concat(parts,', ')..(array and ' ]' or ' }')
    end
    local lines={array and '[' or '{'}
    for index,key in ipairs(keys) do
        lines[#lines+1]=string.rep('  ',depth+1)..(array and '' or json.stringify(key)..': ')..
            pretty(value[key],depth+1,slotOrder[key]~=nil)..(index<#keys and ',' or '')
    end
    lines[#lines+1]=string.rep('  ',depth)..(array and ']' or '}')
    return table.concat(lines,'\n')
end
function Export.render(inventory,items)
    assert(items and items.equipment,'Equipment state is unavailable')
    local gear={}
    local fields={ear1='left_ear',ear2='right_ear',ring1='left_ring',ring2='right_ring'}
    for _,slot in ipairs(slots) do
        local field=fields[slot] or slot
        local index=items.equipment[field]
        assert(type(index)=='number','Equipment slot is unavailable: '..slot)
        if index>0 then
            local item=inventory.find_equipment_in_slot(slot,items,true)
            assert(item and item.name,'Equipped item is unavailable: '..slot)
            local piece={name=item.name}
            if item.augments and #item.augments>0 then
                piece.augments={}
                for i,augment in ipairs(item.augments) do piece.augments[i]=augment end
            end
            gear[slot]=piece
        end
    end
    assert(next(gear),'No equipped items were found')
    return pretty({vars={gear={['csv(battle, idle)']=gear}}},0)..'\n'
end
return Export
