-- Event placement and validation around the shared contribution-selection engine.
local actionSlots=require('./lib/action-slots')
local copy=require('./lib/variable-values').copy
local slots={}
function slots.new(rules,layouts,paths,warn,matchesRequired,compile)
    local container,types,reserved={},{},{}
    for _,layout in ipairs(layouts) do
        local key=layout.section..'.'..layout.phase
        types[#types+1]=key
        container[key]=rules[layout.section][layout.phase]
        reserved[key..'.before']=true; reserved[key..'.after']=true
    end
    local directories,rank={},{}
    for _,path in ipairs(paths) do
        local directory=path:match('^(.*)/[^/]+$')
        if directory and not rank[directory] then
            directories[#directories+1]=directory
            rank[directory]=#directories
        end
    end
    local function priority(source)
        local rulePath=source:gsub('%.vars%.json$','.json')
        for index,directory in ipairs(directories) do
            if rulePath:sub(1,#directory+1)==directory..'/' then
                local specificity=0
                for position,path in ipairs(paths) do
                    if path==rulePath then specificity=position; break end
                end
                return index*(#paths+1)+specificity
            end
        end
        return (#directories+1)*(#paths+1)
    end
    local engine=actionSlots.new(container,priority,function(message)
        if warn then warn(message:gsub('No action slot','No event slot')) end
    end,matchesRequired)
    local result={}
    function result.collect(document,path)
        if document.contributions==nil then return end
        assert(type(document.contributions)=='table',path..': contributions must be an object')
        local definitions={}
        for name,value in pairs(document.contributions) do
            local wrapped=type(value)=='table' and (value.actions~=nil or value.optional~=nil or value.required_for~=nil)
            local actions=wrapped and value.actions or value
            assert(type(actions)=='table',path..': contributions require an actions array')
            for index in pairs(actions) do
                assert(type(index)=='number' and index>=1 and index%1==0 and index<=#actions,
                    path..': contribution actions must be a dense array')
            end
            local compiled={}
            for index,rule in ipairs(actions) do
                local item=compile(rule,path..':contributions['..tostring(name)..']['..index..']',true)
                if item then compiled[#compiled+1]=item end
            end
            if wrapped then
                local definition=copy(value)
                definition.actions=compiled
                definitions[name]=definition
            else definitions[name]=compiled end
        end
        local ok,err=pcall(engine.collect,{contributions=definitions},path)
        assert(ok,path..': '..tostring(err))
    end
    function result.expand()
        local explicit={}
        for _,key in ipairs(types) do
            for _,item in ipairs(container[key]) do
                for _,entry in ipairs(actionSlots.names(item)) do
                    for _,name in ipairs(type(entry)=='table' and entry or {entry}) do
                        assert(not reserved[name],'Built-in event slot cannot be redeclared: '..name)
                        assert(not explicit[name],'Duplicate event slot: '..name)
                        explicit[name]=true
                    end
                end
            end
            table.insert(container[key],1,{slot=key..'.before'})
            container[key][#container[key]+1]={slot=key..'.after'}
        end
        engine.expand(types)
        for _,layout in ipairs(layouts) do
            local list={}
            for _,rule in ipairs(container[layout.section..'.'..layout.phase]) do
                if rule.id then
                    for index=#list,1,-1 do if list[index].id==rule.id then table.remove(list,index) end end
                end
                if not rule.disabled then
                    list[#list+1]={id=rule.id,source=rule.source,stop=rule.stop,
                        conditions=rule.conditions,commands=rule.commands}
                end
            end
            rules[layout.section][layout.phase]=list
        end
        return container._availableSlots
    end
    return result
end
return slots
