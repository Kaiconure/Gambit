local profiling=require('./lib/load-profile')
local M={}
local generated
local function data()
    if not generated then
        profiling.start('generated item index load')
        local ok,value=pcall(require,'./meta/generated-item-name-index')
        generated=ok and type(value)=='table' and value or {}
        profiling.stop('generated item index load')
    end
    return generated
end
function M.lookup(items,name,mode,matches)
    if mode~='English' then return nil end
    local key=name:match('^"(.*)"$') or name
    local id=data()[key]
    if type(id)~='number' then return nil end
    local item=items[id]
    -- The shipped index is a hint; live metadata is always authoritative.
    if item and matches(item,name) then return item end
end
function M.build(items)
    local names={}
    for id,item in pairs(items)do
        for _,field in ipairs({'en','enl'})do
            local name=item[field]
            if type(name)=='string' and name~='' then
                name=name:lower()
                if names[name]==nil then names[name]=id
                elseif names[name]~=id then names[name]=false end
            end
        end
    end
    -- Ambiguous names fall back to the existing first-match resource search.
    return names
end
function M.write(items,path)
    local names=M.build(items)
    local keys={}
    for name,id in pairs(names)do if id then keys[#keys+1]=name end end
    table.sort(keys)
    local lines={'-- Generated item name-to-ID hints. Regenerate with //gbt regen-item-index.','return {'}
    for _,name in ipairs(keys)do lines[#lines+1]=string.format(' [%q]=%d,',name,names[name])end
    lines[#lines+1]='}\n'
    local file=assert(io.open(path,'w'))
    local ok,result,err=pcall(file.write,file,table.concat(lines,'\n'))
    local closed,closeError=file:close()
    if not ok then error(result) end
    assert(result,err);assert(closed,closeError)
    M.reload()
    return #keys
end
function M.reload()
    generated=nil
    package.loaded['./meta/generated-item-name-index']=nil
end
return M
