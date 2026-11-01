-- Ordered equipment batches and dispatch barriers, independent of Windower.
local copy=require('./lib/variable-values').copy
local Queue={}
Queue.__index=Queue
local function same(a,b)
    return a and b and a.localId==b.localId and (a.localId==0 or a.bagId==b.bagId)
        and (a.id==nil or b.id==nil or a.id==b.id)
end
function Queue.new(deps)
    local self=setmetatable({deps=deps,batches={},confirmed={},running=false},Queue)
    self:bootstrap()
    return self
end
function Queue:bootstrap()
    -- A deliberate baseline read, never called by queries or queue processing.
    self.confirmed=copy(self.deps.read() or {})
end
function Queue:resync()
    self:clear()
    self:bootstrap()
end
function Queue:view(confirmed)
    local result=copy(self.confirmed)
    if not confirmed then
        for _,batch in ipairs(self.batches) do
            for _,op in ipairs(batch.ops or {}) do
                if op.state~='failed' then result[op.slot]=copy(op.item) end
            end
        end
    end
    return result
end
function Queue:submit(ops)
    if self.clearing then return 0 end
    local current=self:view()
    local planned={}
    for _,op in ipairs(ops) do
        if not same(current[op.slot],op.item) then
            local entry={slot=op.slot,item=copy(op.item),after=op.after,state='queued',attempts=0}
            planned[#planned+1]=entry
            current[op.slot]=entry.item
        end
    end
    if #planned==0 then return 0 end
    self.batches[#self.batches+1]={ops=planned}
    self:tick()
    return #planned
end
function Queue:barrier(callback)
    if self.clearing then callback(false); return end
    self.batches[#self.batches+1]={callback=callback}
    self:tick()
end
function Queue:ack(slot,item,defer)
    self.confirmed[slot]=copy(item)
    if self.deps.observed then self.deps.observed(slot,item) end
    local batch=self.batches[1]
    if batch and batch.ops then
        for _,op in ipairs(batch.ops) do
            if op.slot==slot and op.state=='sent' and same(op.item,item) then op.state='acknowledged'; break end
        end
    end
    if not defer then self:tick() end
end
function Queue:tick()
    if self.running then return end
    self.running=true
    while self.batches[1] do
        local batch=self.batches[1]
        if batch.callback then
            table.remove(self.batches,1)
            local success=not self.failed
            self.failed=nil
            local ok,err=pcall(batch.callback,success)
            if not ok then self.deps.report('Equipment barrier: '..tostring(err)) end
        else
            local complete,failed=true,false
            for _,op in ipairs(batch.ops) do
                if op.state~='acknowledged' then
                    complete=false
                    local ready=true
                    for _,earlier in ipairs(batch.ops) do
                        if earlier==op then break end
                        if (op.after==earlier.slot or op.slot==earlier.slot) and earlier.state~='acknowledged' then ready=false end
                    end
                    local now=self.deps.clock()
                    if ready and (op.state=='queued' or now-op.sent_at>=0.75) then
                        if self.deps.allows and not self.deps.allows(op.slot,op.item) then
                            -- Discard blocked work; it must not run later when the lock expires.
                            op.state='acknowledged'
                        elseif op.attempts>=3 or not self.deps.valid(op.item) then
                            op.state='failed'; failed=true
                            self.deps.report('Equipment swap failed for slot '..op.slot)
                            break
                        else
                            op.attempts=op.attempts+1
                            op.state='sent'; op.sent_at=now
                            local ok,err=pcall(self.deps.send,op.slot,op.item)
                            if not ok then
                                op.state='failed'; failed=true
                                self.deps.report('Equipment submission: '..tostring(err)); break
                            end
                        end
                    end
                end
            end
            if complete or failed then
                table.remove(self.batches,1)
                if failed and self.deps.failed then
                    for _,op in ipairs(batch.ops) do
                        if op.state~='acknowledged' then self.deps.failed(op.slot,op.item) end
                    end
                end
                if failed then self.failed=true end
            else break end
        end
    end
    self.running=false
end
function Queue:clear()
    self.clearing=true
    local batches=self.batches
    self.batches={}; self.failed=nil; self.confirmed={}
    for _,batch in ipairs(batches) do
        if batch.callback then
            local ok,err=pcall(batch.callback,false)
            if not ok then self.deps.report(tostring(err)) end
        end
    end
    self.clearing=false
end
return Queue
