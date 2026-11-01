local factory=require('./lib/execution-factory')
local copy=require('./lib/variable-values').copy
local Locks={}
Locks.__index=Locks
local compiled=setmetatable({},{__mode='k'})
local byCode,codeOrder={},{}
local emptyEnvironment={}
local function same(a,b)
    return a and b and a.localId==b.localId and (a.localId==0 or a.bagId==b.bagId)
        and (a.id==nil or b.id==nil or a.id==b.id)
end
local function conditions(value)
    assert(type(value)=='table','Equipment lock_when must be an array of expressions')
    local cached=compiled[value]
    if cached then return cached end
    local result={}
    for i,code in pairs(value) do
        assert(type(i)=='number' and i>=1 and i<=#value and i%1==0 and type(code)=='string',
            'Equipment lock_when must be an array of expressions')
    end
    for _,code in ipairs(value) do
        if not byCode[code] then
            byCode[code]=factory.get(code); codeOrder[#codeOrder+1]=code
            if #codeOrder>128 then byCode[table.remove(codeOrder,1)]=nil end
        end
        result[#result+1]=byCode[code]
    end
    compiled[value]=result
    return result
end
function Locks.new(deps) return setmetatable({deps=deps,slots={}},Locks) end
function Locks:clear() self.slots={} end
function Locks:active(slot,slots)
    slots=slots or self.slots
    local lock=slots[slot]
    if not lock then return end
    local ok,context=pcall(self.deps.context,'equipment lock')
    if not ok or not context then return lock end -- Do not unlock during unavailable context.
    for _,fn in ipairs(lock.conditions) do
        setfenv(fn,context)
        local success,value=pcall(fn)
        setfenv(fn,emptyEnvironment)
        if not success then
            if not lock.reported then self.deps.report('Equipment lock: '..tostring(value)); lock.reported=true end
            return lock
        end
        if not value then slots[slot]=nil; return end
    end
    return lock
end
function Locks:filter(ops,slots)
    slots=slots or self.slots
    local accepted={}
    -- Compile all supplied conditions before making any runtime state changes.
    local prepared={}
    for i,op in ipairs(ops) do if op.lock_when~=nil then prepared[i]=conditions(op.lock_when) end end
    for i,op in ipairs(ops) do
        local lock=self:active(op.slot,slots)
        if not lock or same(lock.item,op.item) then
            accepted[#accepted+1]=op
            if prepared[i] and #prepared[i]>0 then
                slots[op.slot]={item=copy(op.item),conditions=prepared[i],pending=true}
                self:active(op.slot,slots)
            end
        end
    end
    return accepted
end
function Locks:allows(slot,item)
    local lock=self:active(slot)
    return not lock or same(lock.item,item)
end
function Locks:observe(slot,item)
    local lock=self.slots[slot]
    if not lock then return end
    if same(lock.item,item) then lock.pending=false
    elseif not lock.pending then self.slots[slot]=nil end
end
function Locks:failed(slot,item)
    local lock=self.slots[slot]
    if lock and lock.pending and same(lock.item,item) then self.slots[slot]=nil end
end
return Locks
