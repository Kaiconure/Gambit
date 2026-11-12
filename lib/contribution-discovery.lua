-- Read contribution metadata before any slots are expanded. This pass never
-- executes actions or merges variables/macros; ordinary imports still do that.
local copy=require('./lib/variable-values').copy
local scopes=require('./lib/variable-scopes')
local conditions=require('./lib/action-preconditions')
local M={}
function M.new(container,player,read)
    local function contains(list,value)
        for _,item in ipairs(list or {}) do if item==value then return true end end
        return false
    end
    local function enabled(action)
        if action.disabled then return false end
        local filter=action.filter or {}
        local main=type(filter.main_jobs)=='table' and #filter.main_jobs>0
        local sub=type(filter.sub_jobs)=='table' and #filter.sub_jobs>0
        if (main or sub) and not ((main and contains(filter.main_jobs,player.main_job))
            or (sub and contains(filter.sub_jobs,player.sub_job))) then return false end
        if filter.names then
            local names=type(filter.names)=='table' and filter.names or {filter.names}
            if not contains(names,player.name) then return false end
        end
        return true
    end
    local scan
    scan=function(actions,parent,source,stack,depth,area)
        assert(depth<=10,'Maximum contribution discovery import depth exceeded: '..tostring(source))
        for index,raw in ipairs(actions or {}) do
            local action=type(raw)=='string' and {import=raw} or copy(raw)
            assert(type(action)=='table','Contribution imports must be action objects')
            if enabled(action) then
                conditions.inherit(parent,action)
                scopes.inherit(parent,action)
                scopes.prepare(container,action)
                action._contributionPath=copy(parent._contributionPath)
                if action.slot or action.slots then
                    container._slots.registerHook(action,source,(area or 'contribution')..':'..index..':'..table.concat(action._contributionPath or {},'/'))
                end
                for _,key in ipairs({'import','imports'}) do
                    local refs=action[key]
                    if type(refs)=='string' then refs={refs} end
                    for _,reference in ipairs(refs or {}) do
                        if type(reference)=='string' and reference:sub(1,2)~='--' then
                            local doc,path=read(reference,action)
                            if doc then
                                assert(not stack[path],'Recursive contribution import: '..path)
                                stack[path]=true
                                container._slots.collect(doc,path,action)
                                for _,area in ipairs({'actions','imports','loading','functions'}) do
                                    scan(doc[area],action,path,stack,depth+1,area)
                                end
                                stack[path]=nil
                            end
                        end
                    end
                end
            end
        end
    end
    return function(actions,parent,source)scan(actions,parent,source,{},0)end
end
return M
