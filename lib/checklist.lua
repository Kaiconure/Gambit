local Checklist={}
local function path(checklistId,itemId)
    assert(checklistId~=nil and itemId~=nil,'Checklist and item ids are required')
    for _,id in ipairs({checklistId,itemId}) do
        assert(type(id)=='string' and id:match('^[%a_][%w_-]*$'),
            'Checklist ids must start with a letter or underscore and contain only letters, digits, underscores or hyphens')
    end
    return 'panel.'..checklistId..'.'..itemId
end
function Checklist.attach(context,get,set)
    context.checklistGet=function(checklistId,itemId)
        return not not get(path(checklistId,itemId))
    end
    context.checklistSet=function(checklistId,itemId,checked)
        local key=path(checklistId,itemId)
        local value=not not checked
        set(key,value)
        return value
    end
end
return Checklist
