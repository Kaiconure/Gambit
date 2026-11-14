-- In-memory state that survives action, event, and namespace reloads. The
-- module itself is discarded when Gambit is unloaded, so this is deliberately
-- not persistent configuration.
local values=require('./lib/variable-values')

local state={}
local session={}

local function set(path,value)
    local levels=values.path(path)
    if #levels==0 then return nil end
    local target=session
    for index=1,#levels-1 do
        local key=levels[index]
        local child=target[key]
        if child==nil then
            child={}; target[key]=child
        elseif type(child)~='table' then
            return nil
        end
        target=child
    end
    target[levels[#levels]]=value
    return value
end

function state.values() return session end
function state.get(path) return values.get(session,path) end
function state.set(path,value) return set(path,value) end
function state.reset(path)
    if path==nil or path=='' then
        for key in pairs(session) do session[key]=nil end
        return
    end
    return set(path,nil)
end

return state
