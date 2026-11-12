local values = require('./lib/variable-values')
local preconditions = require('./lib/action-preconditions')
local scopes = require('./lib/variable-scopes')
local slots = {}
local contributionEntries = require('./lib/contribution-entries')
local priorityAliases = {highest=-1000, high=-100, normal=0, low=100, lowest=1000}
local function actionPriority(value)
    if value == nil then return 0 end
    if type(value) == 'string' then value = priorityAliases[value:lower()] end
    assert(type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge,
        'Contribution priority must be a finite number or highest/high/normal/low/lowest')
    return value
end
local settingsPaths = require('./lib/settings-paths')

-- Add native hooks once, after imports expand. Explicit placements take precedence
-- so existing files do not execute the same contributions twice.
function slots.addAutomatic(container, types)
    for _, kind in ipairs(types) do
        if kind ~= 'imports' and kind ~= 'functions' then
            local actions = container[kind]
            local present = {}
            for _, action in ipairs(actions) do
                for _, entry in ipairs(slots.names(action)) do
                    if type(entry) == 'table' then
                        for _, name in ipairs(entry) do present[name] = true end
                    else present[entry] = true end
                end
            end
            local setup, priority, fallback = kind .. '-setup', kind .. '-priority', kind .. '-fallback'
            if not present[priority] then table.insert(actions, 1, {slot=priority}) end
            if not present[setup] then table.insert(actions, 1, {slot=setup}) end
            if not present[fallback] then actions[#actions+1] = {slot=fallback} end
        end
    end
end

-- Lower values have higher precedence. Namespace proximity precedes file specificity.
function slots.priority(source, namespaces, playerName, mainJob)
    source = source:gsub('\\', '/'):gsub('^%./', ''):lower()
    local layer, relative = #namespaces * 2 + 2, source
    for index, namespace in ipairs(namespaces) do
        local prefix = settingsPaths.namespacePath(namespace):gsub('^%./', ''):lower() .. '/'
        local personal = settingsPaths.namespacePlayerRoot(namespace):gsub('^%./', ''):lower()
            .. '/' .. playerName:lower() .. '/'
        if source:sub(1, #personal) == personal then
            layer, relative = (index-1)*2, source:sub(#personal+1)
            break
        elseif source:sub(1, #prefix) == prefix then
            layer, relative = (index-1)*2+1, source:sub(#prefix+1)
            break
        end
    end
    if layer == #namespaces * 2 + 2 then
        local personal = 'settings/' .. playerName:lower() .. '/'
        if source:sub(1, #personal) == personal then
            layer, relative = #namespaces*2, source:sub(#personal+1)
        elseif source:sub(1,9) == 'settings/' then
            layer, relative = #namespaces*2+1, source:sub(10)
        end
    end
    local specificity = 0 -- Entry points and explicit libraries precede common defaults.
    local name = relative:match('/common/([^/]+)%.json$')
    if name then
        if name == mainJob:lower() then specificity = 1
        elseif name:match('^%(.+%)$') then specificity = 2
        else specificity = 3 end
    elseif relative:match('/common%.json$') then specificity = 3 end
    return layer*10 + specificity
end

local function validateArray(value)
    assert(type(value) == 'table', 'slot/slots must be a string or array')
    for index in pairs(value) do
        assert(type(index) == 'number' and index >= 1 and index <= #value and index % 1 == 0,
            'Slot lists must be arrays')
    end
end

local function validateName(name)
    assert(type(name) == 'string' and name:match('%S'), 'Slot names must be nonempty strings')
end

function slots.names(action)
    if action.actions~=nil and (action.slot~=nil or action.slots~=nil) then
        assert(type(action.slot)=='string' and action.slots==nil,'Inline contributions require one string slot')
        local name=action.slot:gsub('^[!^]',''):match('^%s*(.-)%s*$')
        validateName(name)
        assert(not name:match('^[!^]') and not name:find(',',1,true),'Inline contributions require one slot name')
        return {name}
    end
    local result = {}
    for _, key in ipairs({'slot', 'slots'}) do
        local names = action[key]
        if names ~= nil then
            if type(names) == 'string' then names = {names} end
            validateArray(names)
            for _, name in ipairs(names) do
                if type(name) == 'table' then
                    validateArray(name)
                    for _, alternative in ipairs(name) do validateName(alternative) end
                else
                    validateName(name)
                end
                result[#result+1] = name
            end
        end
    end
    return result
end

function slots.new(container, priority, warn, matchesRequired, defaultSource)
    local groups, seen, used = {}, {}, {}
    local serial = 0
    local discovering,discoveredSources=false,{}
    local dependencies={}
    local discoveryHooks
    local function reaches(from,target,visited)
        if from==target then return true end
        if visited[from] then return false end
        visited[from]=true
        for nextSlot in pairs(dependencies[from] or {}) do
            if reaches(nextSlot,target,visited) then return true end
        end
        return false
    end
    local result = {}
    function result.collect(document, source, parent, occurrence)
        if document.contributions == nil then return end
        if parent and parent._slotContribution and not discovering then
            assert(discoveredSources[source], 'Contribution definitions were not discovered before expansion: '..source)
            return
        end
        if discovering then discoveredSources[source]=true end
        local entries,ordered = contributionEntries.read(document.contributions, matchesRequired)
        local path=parent and parent._contributionPath
        local origin=path and path[#path]
        if origin then
            for _,entry in ipairs(entries) do
                local names=entry.slot
                validateName(names)
                for name in (names..','):gmatch('(.-),') do
                    name=name:match('^%s*(.-)%s*$'):gsub('^[!^]',''):match('^%s*(.-)%s*$')
                    assert(not reaches(name,origin,{}),'Recursive contribution dependency: '..origin..' -> '..name..' ('..source..')')
                    dependencies[origin]=dependencies[origin] or {}
                    dependencies[origin][name]=true
                end
            end
        end
        local key = source .. ':' .. tostring(parent and parent._variableScope or 0)..':'..tostring(occurrence or '')
        if seen[key] then return end
        seen[key] = true
        local declared = {}
        for _,entry in ipairs(entries) do
            if ordered then declared={} end -- Repeated entries are intentional.
            local names,actions=entry.slot,entry.actions
            local optional=entry.optional==true
            local requiredAliases
            -- A filtered contribution is required for its selected audience by
            -- default. An explicit required_for replaces that warning audience;
            -- contribution filtering already limits it to the intersection.
            local requiredFor=entry.required_for or entry['for']
            if requiredFor~=nil then
                requiredAliases={}
                optional=not (matchesRequired and matchesRequired(requiredFor))
            end
            assert(type(actions) == 'table', 'Slot contributions must be arrays')
            for _, action in ipairs(actions) do
                assert(type(action) == 'table', 'Slot actions must be objects')
                actionPriority(action.priority)
            end
            for index in pairs(actions) do
                assert(type(index) == 'number' and index >= 1 and index <= #actions and index % 1 == 0,
                    'Slot contributions must be arrays')
            end
            for part in (names .. ','):gmatch('(.-),') do
            local name = part:match('^%s*(.-)%s*$')
            local replace = name:sub(1,1) == '!'
            local fallback = name:sub(1,1) == '^'
            if replace or fallback then name = name:sub(2):match('^%s*(.-)%s*$') end
            validateName(name)
            for _,ancestor in ipairs(parent and parent._contributionPath or {}) do
                assert(ancestor~=name,'Recursive contribution chain: '..table.concat(parent._contributionPath,' -> ')..' -> '..name..' ('..source..')')
            end
            assert(not name:match('^[!^]'), 'Only one ! or ^ prefix is allowed on a contribution name')
            assert(not declared[name], 'Duplicate contribution name: ' .. name)
            declared[name] = true
            if requiredAliases then requiredAliases[#requiredAliases+1] = name end
            groups[name] = groups[name] or {}
            groups[name][#groups[name]+1] = {
                actions=values.copy(actions), parent=values.copy(parent or {}),
                source=source, priority=priority(source), order=#groups[name]+1, replace=replace, fallback=fallback, optional=optional,
                requiredAliases=requiredAliases, ordered=ordered,
            }
            end
        end
    end
    local function collectInline(types)
        for _,kind in ipairs(types) do
            for index,placeholder in ipairs(container[kind] or {}) do
                if not placeholder._slotContribution and placeholder.actions~=nil and (placeholder.slot~=nil or placeholder.slots~=nil) then
                    slots.names(placeholder)
                    local source=placeholder._slotSource or defaultSource or placeholder.importedFrom or '(inline slot)'
                    local identity=placeholder.id or placeholder.source or (kind..':'..index)
                    local occurrence='inline-'..identity..':'..tostring(placeholder._variableScope or 0)
                    result.collect({contributions={[placeholder.slot]=placeholder.actions}},source,nil,occurrence)
                end
            end
        end
    end
    local function selected(group)
        local result={}
        for _,value in ipairs(group) do result[#result+1]=value end
        table.sort(result,function(a,b)
            if a.priority~=b.priority then return a.priority<b.priority end
            return a.order<b.order
        end)
        local explicit=false
        for _,value in ipairs(result) do if not value.fallback then explicit=true;break end end
        local filtered={}
        local cutoff
        for _,value in ipairs(result) do
            if cutoff and not (value.ordered and value.source==cutoff.source and value.priority==cutoff.priority) then break end
            local sameFallback=not explicit and filtered[1] and value.ordered
                and value.source==filtered[1].source and value.priority==filtered[1].priority
            if (explicit and not value.fallback) or (not explicit and (#filtered==0 or sameFallback)) then
                filtered[#filtered+1]=value
                if value.replace then
                    if value.ordered then cutoff=value else break end
                end
            end
        end
        return filtered
    end
    -- Discovery walks only selected contribution branches. Register their hooks
    -- before expansion so nested providers can still populate earlier slots.
    function result.registerHook(action, source, occurrence)
        assert(discoveryHooks, 'Nested hooks must be discovered before expansion')
        assert(not action.import and not action.imports and not action.when and not action.commands,
            'A slot must be a standalone placeholder')
        local origin=action._contributionPath and action._contributionPath[#action._contributionPath]
        for _,entry in ipairs(slots.names(action)) do
            local names=type(entry)=='table' and entry or {entry}
            for _,name in ipairs(names) do
                if origin then
                    assert(not reaches(name,origin,{}),'Recursive contribution dependency: '..origin..' -> '..name..' ('..source..')')
                    dependencies[origin]=dependencies[origin] or {}
                    dependencies[origin][name]=true
                end
            end
            discoveryHooks[#discoveryHooks+1]={names=names,action=action}
        end
        if action.actions~=nil then
            -- The hook itself supplies conditions/scopes at each occurrence.
            result.collect({contributions={[action.slot]=action.actions}},source,
                {_contributionPath=action._contributionPath},'nested-inline-'..occurrence)
        end
    end
    function result.discover(types,visit)
        collectInline(types)
        local hooks={}
        discoveryHooks=hooks
        for _,kind in ipairs(types) do
            for _,action in ipairs(container[kind] or {}) do
                for _,entry in ipairs(slots.names(action)) do
                    hooks[#hooks+1]={names=type(entry)=='table' and entry or {entry},action=action}
                end
            end
        end
        local visited={}
        discovering=true
        for round=1,11 do
            local pending={}
            for _,hook in ipairs(hooks) do
                for _,name in ipairs(hook.names) do
                    if groups[name]~=nil then
                        for _,group in ipairs(selected(groups[name])) do
                            visited[group]=visited[group] or {}
                            local scope=hook.action._variableScope or 0
                            if not visited[group][scope] then
                                visited[group][scope]=true
                                pending[#pending+1]={name=name,group=group,placeholder=hook.action,scope=scope}
                            end
                        end
                        break
                    end
                end
            end
            if #pending==0 then discovering=false;return end
            assert(round<=10,'Maximum contribution discovery depth exceeded')
            table.sort(pending,function(a,b)
                if a.name~=b.name then return a.name<b.name end
                if a.group.order~=b.group.order then return a.group.order<b.group.order end
                return a.scope<b.scope
            end)
            for _,item in ipairs(pending) do
                local parent=values.copy(item.group.parent)
                local function cloneScope(id)
                    if not id then return item.placeholder._variableScope end
                    local definition=container._variableScopes[id]
                    local proxy={with_vars=values.copy(definition.overrides),_variableScope=cloneScope(definition.parent)}
                    scopes.prepare(container,proxy)
                    return proxy._variableScope
                end
                parent._variableScope=cloneScope(parent._variableScope)
                local inherited=preconditions.collect(item.placeholder)
                for _,condition in ipairs(preconditions.collect(parent)) do inherited[#inherited+1]=condition end
                parent.precondition=nil
                parent._inheritedPreconditions=inherited
                parent._contributionPath=values.copy(parent._contributionPath or {})
                parent._contributionPath[#parent._contributionPath+1]=item.name
                visit(item.group.actions,parent,item.group.source)
            end
        end
    end
    function result.expand(types, deferWarnings)
        collectInline(types)
        -- Keep discoverable hooks after placeholder expansion, including empty
        -- hooks and unselected fallback alternatives.
        container._availableSlots = container._availableSlots or {}
        for _, kind in ipairs(types) do
            local position = 0
            for _, action in ipairs(container[kind] or {}) do
                for _, entry in ipairs(slots.names(action)) do
                    local names = type(entry) == 'table' and entry or {entry}
                    for _, name in ipairs(names) do
                        local sections = container._availableSlots[name] or {}
                        container._availableSlots[name] = sections
                        position = position + 1
                        -- List repeated hooks at their first occurrence. Fallback
                        -- alternatives retain their declared preference order.
                        sections[kind] = sections[kind] or position
                    end
                end
            end
        end
        for name, group in pairs(groups) do groups[name]=selected(group) end
        for _, kind in ipairs(types) do
            local output = {}
            for _, placeholder in ipairs(container[kind]) do
                if placeholder.slot == nil and placeholder.slots == nil then
                    output[#output+1] = placeholder
                else
                    for _, entry in ipairs(slots.names(placeholder)) do
                    local name
                    local alternatives = type(entry) == 'table' and entry or {entry}
                    for _, alternative in ipairs(alternatives) do
                        -- Unselected fallbacks are intentional, not unmatched slots.
                        used[alternative] = true
                        if not name and groups[alternative] ~= nil then name = alternative end
                    end
                    local contributed = {}
                    for _, group in ipairs((name and groups[name]) or {}) do
                        -- Each occurrence owns a copy of the contribution's scope chain.
                        local parent = values.copy(group.parent)
                        local function cloneScope(id)
                            if not id then return placeholder._variableScope end
                            local definition = container._variableScopes[id]
                            local ancestor = cloneScope(definition.parent)
                            local proxy = {with_vars=values.copy(definition.overrides), _variableScope=ancestor}
                            scopes.prepare(container, proxy)
                            return proxy._variableScope
                        end
                        parent._variableScope = cloneScope(parent._variableScope)
                        local inherited = preconditions.collect(placeholder)
                        for _, condition in ipairs(preconditions.collect(parent)) do
                            inherited[#inherited+1] = condition
                        end
                        for _, definition in ipairs(group.actions) do
                            assert(type(definition) == 'table', 'Slot actions must be objects')
                            local action = values.copy(definition)
                            serial = serial + 1
                            action._inheritedPreconditions = values.copy(inherited)
                            action._variableScope = parent._variableScope
                            action.on_load = placeholder.on_load or action.on_load
                            action.as_function = placeholder.as_function or action.as_function
                            action.importedFrom = group.source
                            action._slotContribution = serial
                            contributed[#contributed+1] = {action=action,
                                priority=actionPriority(action.priority), order=#contributed+1}
                        end
                    end
                    table.sort(contributed, function(a,b)
                        if a.priority ~= b.priority then return a.priority < b.priority end
                        return a.order < b.order
                    end)
                    for _, item in ipairs(contributed) do
                        item.action.priority = nil
                        output[#output+1] = item.action
                    end
                    end
                end
            end
            container[kind] = output
        end
        if not deferWarnings then result.finish() end
    end
    function result.finish()
        local names = {}
        for name, group in pairs(groups) do
            if not used[name] then
                for _, contribution in ipairs(group) do
                    local satisfied = false
                    for _, alias in ipairs(contribution.requiredAliases or {}) do
                        if used[alias] then satisfied = true; break end
                    end
                    if not contribution.optional and not satisfied then names[#names+1]=name; break end
                end
            end
        end
        table.sort(names)
        for _, name in ipairs(names) do warn('No action slot found for contributions: ' .. name) end
    end
    return result
end

return slots
