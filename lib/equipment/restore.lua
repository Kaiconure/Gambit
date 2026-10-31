-- Restore only an unconsumed lifecycle baseline, never an intermediate push.
return function(stack, inventory)
    for _,entry in ipairs(stack) do
        if entry.event_baseline then
            assert(type(entry.removed)=='table','Invalid equipment baseline')
            local count=inventory.restore_equipment(entry.removed)
            for index=#stack,1,-1 do stack[index]=nil end
            return count>0 and count or nil
        end
    end
end
