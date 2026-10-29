-- Own equipment state/listeners for normal actions and event handlers alike.
local Queue=require('./lib/equipment/queue')
local Service={}
Service.__index=Service
local fields={'main','sub','range','ammo','head','body','hands','legs','feet','neck','waist',
    'left_ear','right_ear','left_ring','right_ring','back'}
function Service.new(deps)
    local self=setmetatable({deps=deps,listeners={}},Service)
    local function identity(slot,bag,index,items)
        if index==0 then return {localId=0,bagId=0,id=0} end
        local item=items and deps.inventory.get_item_from_bag(items,bag,index)
        -- Packet location remains authoritative even if inventory metadata has
        -- not arrived yet. Inventory supplies identity, not the equipped slot.
        return {localId=index,bagId=bag,id=item and item.id}
    end
    self.queue=Queue.new({clock=deps.clock or os.clock,report=deps.report,
        read=function()
            local items=deps.windower.ffxi.get_items()
            local result={}
            if items and items.equipment then
                for slot=0,15 do
                    local name=fields[slot+1]
                    local index=items.equipment[name]
                    if type(index)=='number' then
                        result[slot]=identity(slot,items.equipment[name..'_bag'] or 0,index,items)
                    end
                end
            end
            return result
        end,
        valid=function(item)
            if item.localId==0 then return true end
            local items=deps.windower.ffxi.get_items()
            local resource=items and deps.inventory.get_item_from_bag(items,item.bagId,item.localId)
            return resource and resource.id==item.id
        end,
        send=function(slot,item)
            if deps.packets then
                deps.packets.inject(deps.packets.new('outgoing',0x050,{
                    ['Item Index']=item.localId,['Equip Slot']=slot,['Bag']=item.bagId}))
            else deps.windower.ffxi.set_equip(item.localId,slot,item.bagId) end
        end})
    local function listen(name,fn) self.listeners[#self.listeners+1]=deps.windower.register_event(name,fn) end
    listen('prerender',function() self.queue:tick() end)
    listen('incoming chunk',function(id,original,modified,injected)
        if injected then return end
        local data=original or modified
        if type(data)~='string' then return end
        if id==0x050 then
            local index,slot,bag=data:byte(5,7)
            local items=deps.windower.ffxi.get_items()
            if slot and slot<=15 then
                local item=identity(slot,bag,index,items)
                if item then self.queue:ack(slot,item) end
            end
        elseif id==0x117 and #data>=136 then
            local items=deps.windower.ffxi.get_items()
            for slot=0,15 do
                local index,reportedSlot,bag=data:byte(73+slot*4,75+slot*4)
                local item=identity(reportedSlot,bag,index,items)
                if item and reportedSlot<=15 then self.queue:ack(reportedSlot,item,true) end
            end
            self.queue:tick()
        end
    end)
    listen('logout',function() self.queue:clear() end)
    listen('login',function() self:resync() end)
    listen('zone change',function() self:resync() end)
    listen('job change',function() self:resync() end)
    return self
end
function Service:snapshot(items,confirmed)
    local result={}
    for key,value in pairs(items) do result[key]=value end
    result.equipment={}
    for slot,item in pairs(self.queue:view(confirmed)) do
        local field=fields[slot+1]
        result.equipment[field]=item.localId
        result.equipment[field..'_bag']=item.bagId
    end
    return result
end
function Service:slotField(slot) return fields[slot+1] end
function Service:resync() return self.queue:resync() end
function Service:session() return require('./lib/equipment/session').new(self,self.deps.inventory) end
function Service:submit(ops)
    local current=self.queue:view()
    local main,sub
    for _,op in ipairs(ops) do
        if op.slot==0 then main=op elseif op.slot==1 then sub=op end
    end
    local previous=current[0]
    local mainChanged=main and (not previous or (previous.id~=nil and main.item.id~=nil and previous.id~=main.item.id)
        or previous.localId~=main.item.localId or previous.bagId~=main.item.bagId)
    if mainChanged and sub and current[1] and current[1].localId~=0 then
        local ordered={{slot=1,item={localId=0,bagId=0,id=0}}}
        for _,op in ipairs(ops) do
            local item={slot=op.slot,item=op.item,after=op.after}
            if item.slot==0 then item.after=1 end
            ordered[#ordered+1]=item
        end
        ops=ordered
    end
    local count=self.queue:submit(ops)
    if count>0 and self.deps.verbose then
        self.deps.verbose('Queued equipment changes: '..(self.deps.formatCount and self.deps.formatCount(count) or count))
    end
    return count
end
function Service:barrier(fn) return self.queue:barrier(fn) end
function Service:destroy()
    for _,id in ipairs(self.listeners) do self.deps.windower.unregister_event(id) end
    self.queue:clear()
end
return Service
