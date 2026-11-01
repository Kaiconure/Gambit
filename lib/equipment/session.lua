-- A context-local phase plan. Item resolution stays in the shared inventory API.
local copy=require('./lib/variable-values').copy
local Session={}
Session.__index=Session
local order={0,2,4,9,5,6,15,10,7,8,11,12,13,14,1,3}
function Session.new(manager,inventory)
    local self=setmetatable({manager=manager,planned={},closed=false},Session)
    self.inventory=inventory.bind_equipment(self)
    self.locks=manager.locks and copy(manager.locks.slots)
    return self
end
function Session:snapshot(items,confirmed)
    local result=self.manager:snapshot(items,confirmed)
    if not confirmed then
        for slot,op in pairs(self.planned) do
            local field=self.manager:slotField(slot)
            result.equipment[field]=op.item.localId
            result.equipment[field..'_bag']=op.item.bagId
        end
    end
    return result
end
function Session:submit(operations)
    assert(not self.closed,'Equipment phase session is closed')
    if self.locks then operations=self.manager.locks:filter(operations,self.locks) end
    for _,op in ipairs(operations) do self.planned[op.slot]=copy(op) end
    return #operations
end
function Session:commit()
    assert(not self.closed,'Equipment phase session is closed')
    local operations={}
    for _,slot in ipairs(order) do
        if self.planned[slot] then operations[#operations+1]=self.planned[slot] end
    end
    self.closed=true
    return self.manager:submit(operations)
end
function Session:discard()
    self.closed=true
    self.planned={}
end
return Session
