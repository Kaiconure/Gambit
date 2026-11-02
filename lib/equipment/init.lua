-- Own equipment state/listeners for normal actions and event handlers alike.
local Queue=require('./lib/equipment/queue')
local Locks=require('./lib/equipment/locks')
local trace=require('./lib/events/weapon-skill-trace')
local Service={}
Service.__index=Service
local fields={'main','sub','range','ammo','head','body','hands','legs','feet','neck','waist',
    'left_ear','right_ear','left_ring','right_ring','back'}
function Service.new(deps)
    local self=setmetatable({deps=deps,listeners={}},Service)
    local ffxi=deps.windower.ffxi
    if ffxi.get_player and ffxi.get_mob_by_target then
        local player=ffxi.get_player()
        local mob=ffxi.get_mob_by_target('me')
        local info=ffxi.get_info and ffxi.get_info()
        local items=ffxi.get_items()
        if not player or not mob or mob.id~=player.id or not mob.valid_target
            or (info and info.logged_in==false) or not items or not items.equipment then
            self.zoneLoading=true; self.zoneArrived=true
        end
    end
    self.locks=Locks.new({context=deps.context or function() end,report=deps.report})
    local function identity(slot,bag,index,items)
        if index==0 then return {localId=0,bagId=0,id=0} end
        local item=items and deps.inventory.get_item_from_bag(items,bag,index)
        -- Packet location remains authoritative even if inventory metadata has
        -- not arrived yet. Inventory supplies identity, not the equipped slot.
        return {localId=index,bagId=bag,id=item and item.id}
    end
    self.queue=Queue.new({clock=deps.clock or os.clock,report=deps.report,
        ready=function() return not self.zoneLoading end,
        ackTimeout=function()
            local now=(deps.clock or os.clock)()
            return self.zoneAckGraceUntil and now<=self.zoneAckGraceUntil and 6 or 2.25
        end,
        readSlot=function(slot)
            local items=deps.windower.ffxi.get_items()
            local equipment=items and items.equipment
            local field=fields[slot+1]
            local index=equipment and equipment[field]
            if type(index)=='number' then
                return identity(slot,equipment[field..'_bag'] or 0,index,items)
            end
        end,
        allows=function(slot,item) return self.locks:allows(slot,item) end,
        observed=function(slot,item) self.locks:observe(slot,item) end,
        failed=function(slot,item) self.locks:failed(slot,item) end,
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
    listen('outgoing chunk',function(id,original,modified,injected,blocked)
        if not trace.active() or (id~=0x050 and id~=0x051) then return end
        local data=modified or original
        if type(data)~='string' or #data<7 then return end
        local entries={}
        if id==0x050 then
            entries[1]={index=data:byte(5),slot=data:byte(6),bag=data:byte(7)}
        else
            for index=1,math.min(data:byte(5),16) do
                local offset=9+(index-1)*4
                if #data>=offset+2 then entries[#entries+1]={index=data:byte(offset),slot=data:byte(offset+1),bag=data:byte(offset+2)} end
            end
        end
        trace.record('outgoing_equipment_observed',{packet=id,sequence=data:byte(3)+data:byte(4)*256,
            injected=not not injected,blocked_on_entry=not not blocked,items=entries})
    end)
    listen('prerender',function()
        if self.zoneLoading and self.zoneArrived then
            local ffxi=deps.windower.ffxi
            local player=ffxi.get_player and ffxi.get_player()
            local mob=ffxi.get_mob_by_target and ffxi.get_mob_by_target('me')
            local info=ffxi.get_info and ffxi.get_info()
            local items=ffxi.get_items()
            local usable=player and mob and mob.id==player.id and mob.valid_target
                and (not info or info.logged_in~=false) and items and items.equipment
            if usable then
                local now=(deps.clock or os.clock)()
                self.zoneReadySince=self.zoneReadySince or now
                -- A quiet interval avoids sending while the client is still
                -- transitioning. Do not require a full inventory retransmission.
                if now-self.zoneReadySince>=1 then
                    self.queue:bootstrap()
                    for slot,item in pairs(self.queue.confirmed) do self.locks:observe(slot,item) end
                    self.zoneLoading=false
                    self.zoneAckGraceUntil=now+10
                end
            else
                self.zoneReadySince=nil
            end
        end
        self.queue:tick()
    end)
    listen('incoming chunk',function(id,original,modified,injected)
        if injected then return end
        local data=original or modified
        if type(data)~='string' then return end
        if id==0x00B then
            self.zoneLoading=true; self.zoneArrived=false; self.zoneReadySince=nil
            self.locks:clear(); self.queue:clear()
        elseif id==0x050 then
            local index,slot,bag=data:byte(5,7)
            if trace.active() and slot then trace.record('incoming_equipment_packet',{packet=id,
                sequence=data:byte(3)+data:byte(4)*256,slot=slot,index=index,bag=bag}) end
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
    listen('logout',function()
        self.zoneLoading=true; self.zoneArrived=true; self.zoneReadySince=nil
        self.locks:clear(); self.queue:clear()
    end)
    listen('login',function()
        self.zoneLoading=true; self.zoneArrived=true; self.zoneReadySince=nil
        self:resync()
    end)
    listen('zone change',function()
        if not self.zoneLoading then self.locks:clear(); self.queue:clear() end
        self.zoneLoading=true
        self.zoneArrived=true; self.zoneReadySince=nil
    end)
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
function Service:isReady() return not self.zoneLoading and not self.queue.clearing end
function Service:resync() self.locks:clear(); return self.queue:resync() end
function Service:clearLocks() self.locks:clear() end
function Service:session() return require('./lib/equipment/session').new(self,self.deps.inventory) end
function Service:submit(ops)
    if self.queue.clearing then return 0 end
    ops=self.locks:filter(ops)
    for slot,item in pairs(self.queue:view(true)) do self.locks:observe(slot,item) end
    local current=self.queue:view()
    local main,sub
    for _,op in ipairs(ops) do
        if op.slot==0 then main=op elseif op.slot==1 then sub=op end
    end
    local previous=current[0]
    local mainChanged=main and (not previous or (previous.id~=nil and main.item.id~=nil and previous.id~=main.item.id)
        or previous.localId~=main.item.localId or previous.bagId~=main.item.bagId)
    -- Main-hand changes can implicitly remove the offhand. Preserve an owned
    -- offhand rather than trying to work around its lock by unequipping first.
    if mainChanged and current[1] and current[1].localId~=0 and self.locks:active(1) then
        local filtered={}
        for _,op in ipairs(ops) do if op.slot~=0 then filtered[#filtered+1]=op end end
        self.locks:failed(0,main.item)
        ops=filtered; mainChanged=false
    end
    if mainChanged and sub and current[1] and current[1].localId~=0 then
        local ordered={{slot=1,item={localId=0,bagId=0,id=0}}}
        for _,op in ipairs(ops) do
            local item={slot=op.slot,item=op.item,after=op.after}
            if item.slot==0 then item.after=1 end
            ordered[#ordered+1]=item
        end
        ops=self.locks:filter(ordered)
    end
    local count=self.queue:submit(ops)
    if count>0 and self.deps.debug and (not self.deps.debugEnabled or self.deps.debugEnabled()) then
        self.deps.debug('Queued equipment changes: '..(self.deps.formatCount and self.deps.formatCount(count) or count))
    end
    return count
end
function Service:barrier(fn) return self.queue:barrier(fn) end
function Service:destroy()
    for _,id in ipairs(self.listeners) do self.deps.windower.unregister_event(id) end
    self.queue:clear()
    self.locks:clear()
end
return Service
