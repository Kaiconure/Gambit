-- Compile configuration once; queries touch only matching actor/trigger buckets.
local aliases=require('./lib/resource-name-aliases')
local copy=require('./lib/variable-values').copy
local M={}
local function list(value)
    if value==nil then return {} end
    return type(value)=='table' and value or {value}
end
local function triggerKey(value)
    assert(type(value)=='string' or type(value)=='number','Reaction names must be strings or IDs')
    if value=='*' then return false end
    local id=tonumber(value)
    return id and ('id:'..id) or ('name:'..aliases.key(value))
end
function M.flatten(rules)
    local result,active={},{}
    local function expand(group)
        assert(type(group)=='table','Face-away rules and groups must be arrays')
        assert(not active[group],'Circular face-away rule group')
        active[group]=true
        local count=0
        for key in pairs(group) do
            assert(type(key)=='number' and key>=1 and key%1==0 and key<=#group,
                'Face-away groups must be dense arrays without settings')
            count=count+1
        end
        assert(count==#group,'Face-away groups must be dense arrays')
        for _,entry in ipairs(group) do
            assert(type(entry)=='table','Face-away entries must be objects or groups')
            if entry[1]~=nil or next(entry)==nil then expand(entry)
            else
                for key in pairs(entry) do assert(type(key)=='string','Invalid face-away rule or sparse group') end
                result[#result+1]=entry
            end
        end
        active[group]=nil
    end
    expand(rules or {})
    return result
end
function M.compile(rules,stock)
    assert(rules==nil or type(rules)=='table','Face-away rules must be an array')
    assert(stock==nil or type(stock)=='table','Stock face-away rules must be an array')
    local definitions,overrides={},{}
    for _,rule in ipairs(M.flatten(rules)) do
        assert(type(rule)=='table','Face-away entries must be objects')
        if rule.key then overrides[rule.key]=true end
        definitions[#definitions+1]={rule=rule}
    end
    for _,rule in ipairs(M.flatten(stock)) do
        if not overrides[rule.key] then definitions[#definitions+1]={rule=rule,stock=true} end
    end
    local index={}
    for order,definition in ipairs(definitions) do
        local rule=definition.rule
        assert(type(rule)=='table','Face-away entries must be objects')
        assert(rule.disabled==nil or type(rule.disabled)=='boolean','Reaction disabled must be boolean')
        assert(rule.key==nil or type(rule.key)=='string','Reaction key must be a string')
        if not rule.disabled then
            local actors=rule.actor==nil and {false} or list(rule.actor)
            for _,actor in ipairs(actors) do assert(actor==false or type(actor)=='string','Reaction actors must be names') end
            local options=copy(rule.options or {})
            options.key=rule.key or options.key
            require('./lib/reaction-options').timeout(options.timeout)
            require('./lib/reaction-options').angle(options)
            if options.distance~=nil then
                assert(type(options.distance)=='number' and options.distance>=0 and options.distance<math.huge,
                    'Reaction distance must be a finite nonnegative center distance')
            end
            local bracket=rule.start~=nil or rule.release~=nil
            if bracket then
                assert(type(rule.start)=='table' and type(rule.release)=='table','Bracketed reactions require start and release objects')
                options.key=rule.key or options.key or ('configured-face-away:'..order)
                options.bracket=true
            end
            local function add(kind,phase,names,operation)
                assert(kind=='enemy_spell' or kind=='enemy_ability','Invalid reaction kind')
                assert(phase=='pre' or phase=='post','Reaction trigger phase must be pre or post')
                index[kind]=index[kind] or {};local phases=index[kind]
                phases[phase]=phases[phase] or {};local byActor=phases[phase]
                local entry={order=order,operation=operation,options=options,stock=definition.stock,specific=rule.actor~=nil}
                for _,actor in ipairs(actors) do
                    byActor[actor]=byActor[actor] or {};local triggers=byActor[actor]
                    for _,name in ipairs(list(names)) do
                        local key=triggerKey(name)
                        triggers[key]=triggers[key] or {}
                        triggers[key][#triggers[key]+1]=entry
                    end
                end
            end
            if bracket then
                for _,operation in ipairs({'start','release'}) do
                    local trigger=rule[operation]
                    local phase=trigger.phase or 'post'
                    assert(phase=='pre' or phase=='post','Reaction trigger phase must be pre or post')
                    add('enemy_ability',phase,trigger.abilities,operation)
                    add('enemy_spell',phase,trigger.spells,operation)
                end
            else
                for _,kind in ipairs(rule.kind and {rule.kind} or {'enemy_ability','enemy_spell'}) do
                    add(kind,'pre',rule.names,'start')
                end
            end
            end
    end
    -- A function is an immutable handle: event-variable snapshots share it
    -- without copying the source array or the compiled index per notification.
    return function(event)
        local phases=index[event.kind]
        local byActor=phases and phases[event.phase]
        if not byActor or not event.actor or (event.phase=='post' and not event.completed) then return {} end
        local selected={}
        local function collect(actor)
            local triggers=byActor[actor]
            if not triggers then return end
            local function bucket(key)
                for _,entry in ipairs(triggers[key] or {}) do
                    local previous=selected[entry.order]
                    if not previous or entry.operation=='release' then selected[entry.order]=entry end
                end
            end
            bucket(false)
            if event.id then bucket('id:'..event.id) end
            if event.name then bucket('name:'..aliases.key(event.name)) end
        end
        collect(false)
        if event.actor.name then collect(event.actor.name) end
        local result={}
        local customStart,specificStock=false,false
        for _,entry in pairs(selected) do
            if entry.operation=='start' then
                if not entry.stock then customStart=true
                elseif entry.specific then specificStock=true end
            end
        end
        for _,entry in pairs(selected) do
            if not entry.stock or entry.operation=='release'
                or (not customStart and (not specificStock or entry.specific)) then
                result[#result+1]=copy(entry)
            end
        end
        table.sort(result,function(a,b)return a.order<b.order end)
        return result
    end
end
return M
