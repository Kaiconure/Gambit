local profiling=require('./lib/load-profile')
-- Session state: this module survives settings reloads, but not addon reloads.
local paths = {}
local targetSelectors=require('./lib/target-selectors')
local namespace = nil
local loadedNamespace = nil
local loadedPrecedence = {}
local directoryCache

-- Nested loads share the active snapshot; even failed loads restore the prior
-- scope. No cached result survives the outermost load.
function paths.withDirectoryCache(fn)
    local previous=directoryCache
    directoryCache=previous or {}
    local function pack(...)return {n=select('#',...),...}end
    local result=pack(pcall(fn))
    directoryCache=previous
    if not result[1] then error(result[2],0) end
    return unpack(result,2,result.n)
end

local SETTINGS_ROOT = './settings'
local GAMBIT_PREFIX = 'gambit:'
function paths.gambitReference(value)
    if type(value)~='string' or value:sub(1,#GAMBIT_PREFIX):lower()~=GAMBIT_PREFIX then return nil,value end
    return true,value:sub(#GAMBIT_PREFIX+1)
end
function paths.isGambitReference(value) return paths.gambitReference(value)==true end
local function directoryExists(path)
    local started=profiling.now()
    local resolved=(windower and windower.addon_path or '')..path:gsub('^%./',''):gsub('\\','/')
    local key=resolved:lower()
    if directoryCache and directoryCache[key]~=nil then
        profiling.sample('directory cache hits',started)
        return directoryCache[key]
    end
    local result=windower and windower.dir_exists and
        windower.dir_exists(resolved) or false
    if directoryCache then directoryCache[key]=result end
    profiling.sample('directory probes',started)
    return result
end

local function organizationalRoot(parent, name)
    local preferred = parent .. '/_' .. name
    local plain = parent .. '/' .. name
    if directoryExists(preferred) then return preferred end
    if directoryExists(plain) then return plain end
    return preferred
end

function paths.namespaceRoot()
    return organizationalRoot('./settings', 'namespaces')
end

function paths.bundledNamespaceRoot()
    return organizationalRoot('.', 'namespaces')
end

function paths.namespaceSettingsRoot()
    return organizationalRoot('./settings', 'namespace-settings')
end

local function resolvePath(root, name)
    local valid, message = paths.validateNamespace(name)
    assert(valid, message)
    for segment in (name or ''):gmatch('[^/]+') do
        local exact = root .. '/' .. segment
        if not directoryExists(exact) and segment:sub(1,1) ~= '_' and directoryExists(root .. '/_' .. segment) then
            exact = root .. '/_' .. segment
        end
        root = exact
    end
    return root
end

function paths.namespacePath(name)
    local stock
    stock,name=paths.gambitReference(name)
    if stock then return resolvePath(paths.bundledNamespaceRoot(),name) end
    local user = resolvePath(paths.namespaceRoot(), name)
    if directoryExists(user) then return user end
    local shipped = resolvePath(paths.bundledNamespaceRoot(), name)
    if directoryExists(shipped) then return shipped end
    return user
end

function paths.namespacePlayerRoot(name)
    -- Use the resolved spelling so underscore aliases share personal settings.
    local resolved = paths.namespacePath(name)
    local relative = resolved:match('^%./settings/_?namespaces/(.*)$')
        or resolved:match('^%./_?namespaces/(.*)$')
    return paths.namespaceSettingsRoot() .. '/' .. relative .. '/players'
end

function paths.namespaceExists(name)
    return directoryExists(paths.namespacePath(name))
end

-- Namespace content directories delimit the owning namespace, including
-- inherited or underscore-aliased namespaces. Display paths omit leading ./.
function paths.namespaceRelativeFile(fileName)
    if not fileName then return end
    local normalized=fileName:gsub('\\','/')
    local relative=normalized:gsub('^%./','')
    if relative:match('^settings/_?namespace%-settings/') then
        return relative:match('/(players/.*)$') or relative
    end
    if relative:match('^settings/_?namespaces/') or relative:match('^_?namespaces/') then
        return relative:match('/(actions/.*)$')
            or relative:match('/(events/.*)$') or relative
    end
    return relative
end

function paths.fileNamespace(fileName)
    if not fileName then return end
    local relative=fileName:gsub('\\','/'):gsub('^%./','')
    return relative:match('^settings/_?namespace%-settings/(.-)/players/')
        or relative:match('^_?namespaces/(.-)/events/')
        or relative:match('^_?namespaces/(.-)/actions/')
        or relative:match('^settings/_?namespaces/(.-)/events/')
        or relative:match('^settings/_?namespaces/(.-)/actions/')
end

function paths.isNamespaceInitialized(name)
    return paths.namespaceExists(name) and files.new(paths.namespacePath(name) .. '/.nsconfig'):exists()
end

function paths.namespaceInitializationError(name)
    return 'Namespace ' .. name .. ' is missing its folder or .nsconfig. Use gbt ns -set ' .. name .. ' -force to initialize it.'
end

-- A .nsconfig marks a listable namespace; unmarked organizational folders
-- are still traversed. Never descend into reserved namespace content folders.
function paths.listNamespaces()
    local result, abstract, bundled = {}, {}, {}
    local seen = {}
    local function visit(directory, parent, sourceRoot)
        local absolute = (windower.addon_path or '') .. directory:gsub('^%./', '') .. '/'
        for _, segment in ipairs(windower.get_dir(absolute) or {}) do
            local physical = directory .. '/' .. segment
            local name = parent and (parent .. '/' .. segment) or segment
            if paths.validateNamespace(name) and directoryExists(physical) then
                if segment:sub(1,1) == '_' then
                    local short = segment:sub(2)
                    local alias = parent and (parent .. '/' .. short) or short
                    if short ~= '' and paths.validateNamespace(alias)
                        and resolvePath(sourceRoot, alias):lower() == physical:lower() then name = alias end
                end
                local configFile = files.new(physical .. '/.nsconfig')
                if configFile:exists() and not seen[name:lower()]
                    and paths.namespacePath(name):lower() == physical:lower() then
                    seen[name:lower()] = true
                    result[#result+1] = name
                    bundled[name] = physical:match('^%./_?namespaces/') ~= nil
                    local ok, config = pcall(function() return json.parse(configFile:read()) end)
                    abstract[name] = ok and type(config) == 'table' and config.abstract == true or false
                end
                visit(physical, name, sourceRoot)
            end
        end
    end
    for _, root in ipairs({paths.namespaceRoot(), paths.bundledNamespaceRoot()}) do
        if directoryExists(root) then visit(root, nil, root) end
    end
    table.sort(result, function(a,b)
        if a:lower() == b:lower() then return a < b end
        return a:lower() < b:lower()
    end)
    return result, abstract, bundled
end

function paths.getNamespace()
    return namespace
end

function paths.validateNamespace(name)
    local stock
    stock,name=paths.gambitReference(name)
    if stock and (name=='' or name:lower():find('^gambit:')) then
        return false, 'gambit: requires a namespace name.'
    end
    if name ~= nil and (
        type(name) ~= 'string' or
        not name:match('^[%w_/%.-]+$') or
        name:sub(1, 1) == '/' or
        name:sub(-1) == '/' or
        name:find('//', 1, true)
    ) then
        return false, 'Namespace names must be slash-separated folder names containing only letters, numbers, underscores, hyphens, and dots.'
    end
    for segment in (name or ''):gmatch('[^/]+') do
        if segment:sub(1,1) == '.' or segment:sub(-1) == '.' then
            return false, 'Namespace folder name "' .. segment .. '" cannot start or end with a dot.'
        end
        local normalized = segment:lower():gsub('^_+', '')
        if normalized == 'actions' or normalized == 'players' or normalized == 'events' then
            return false, 'Namespace folder name "' .. segment .. '" is reserved for namespace contents.'
        end
        local device = normalized:match('^[^.]+') or normalized
        if device == 'con' or device == 'nul' or device == 'aux' or device == 'prn'
            or device:match('^com[1-9]$') or device:match('^lpt[1-9]$') then
            return false, 'Namespace folder name "' .. segment .. '" is a reserved Windows device name.'
        end
    end
    return true
end

function paths.setNamespace(name)
    local success, message = paths.validateNamespace(name)
    if not success then return false, message end
    namespace = name
    return true
end

function paths.getLoadedNamespace()
    return loadedNamespace
end

-- Highest priority first. Keep resolution separate from lookup so a future
-- multiple-parent linearizer can supply the same list without changing consumers.
function paths.resolveInheritance(name, readConfig, exists)
    local result, visiting = {}, {}
    local function visit(current, parent)
        local valid, message = paths.validateNamespace(current)
        assert(valid, message)
        local identity = paths.namespacePath(current):lower()
        assert(not visiting[identity], 'Namespace inheritance cycle at ' .. current)
        if parent then assert(exists(current), paths.namespaceInitializationError(current)) end
        visiting[identity] = true
        local config = readConfig(current)
        assert(config ~= nil, paths.namespaceInitializationError(current))
        assert(type(config) == 'table', 'Invalid .nsconfig for ' .. current .. ': expected an object')
        for _, field in ipairs({'description', '!description'}) do
            if config[field] ~= nil then
                local description = config[field]
                assert(type(description) == 'string' or type(description) == 'table',
                    field .. ' must be a string or array of strings in ' .. current)
                if type(description) == 'table' then
                    for key, line in pairs(description) do
                        assert(type(key) == 'number' and key >= 1 and key <= #description and key % 1 == 0
                            and type(line) == 'string', field .. ' must be a string or array of strings in ' .. current)
                    end
                end
            end
        end
        assert(config.inheritable == nil or type(config.inheritable) == 'boolean', 'inheritable must be boolean in ' .. current)
        assert(config.abstract == nil or type(config.abstract) == 'boolean', 'abstract must be boolean in ' .. current)
        if parent and config.inheritable == false then
            error('Namespace ' .. text_namespace(current, Colors.red) .. ' explicitly disables inheritance (inheritable: false)', 0)
        end
        result[#result+1] = current
        if config.inherits_from ~= nil then
            assert(type(config.inherits_from) == 'string', 'inherits_from must be a single namespace string in ' .. current)
            local stock=paths.gambitReference(current)
            local parent=config.inherits_from
            if stock and not paths.gambitReference(parent) then parent=GAMBIT_PREFIX..parent end
            visit(parent, true)
        end
        visiting[identity] = nil
    end
    if name then visit(name, false) end
    return result
end

function paths.getLoadedPrecedence()
    local copy = {}
    for i, name in ipairs(loadedPrecedence) do copy[i] = name end
    return copy
end

function paths.setLoadedNamespace(name, precedence)
    loadedNamespace = name
    loadedPrecedence = precedence or (name and {name} or {})
end

function paths.ensureNamespaceFolders(playerName, name, parent)
    name = name or namespace
    if not name then return true end
    if type(playerName) ~= 'string' or playerName == '' then
        return false, 'A logged-in character is required to initialize a namespace.'
    end

    local valid, message = paths.validateNamespace(name)
    if not valid then return false, message end
    local root = paths.namespacePath(name) .. '/'
    local initialConfig = '{}\n'
    do
        local ok, err = pcall(function()
            if parent ~= nil then
                local validParent, parentMessage = paths.validateNamespace(parent)
                assert(validParent, parentMessage)
            end
            paths.resolveInheritance(name, function(current)
                local file = files.new(paths.namespacePath(current) .. '/.nsconfig')
                local config
                if file:exists() then
                    config = json.parse(file:read())
                    assert(type(config) == 'table', 'Invalid .nsconfig for ' .. current)
                    if current == name and parent ~= nil then
                        if type(config.inherits_from) ~= 'string' or
                            paths.namespacePath(config.inherits_from):lower() ~= paths.namespacePath(parent):lower() then
                            error('Namespace ' .. text_namespace(name, Colors.error) .. ' already has a different or missing parent.', 0)
                        end
                    end
                elseif current == name then
                    config = {inherits_from = parent}
                end
                return config
            end, function(current)
                return paths.namespaceExists(current)
            end)
            if parent ~= nil then initialConfig = json.stringify({inherits_from = parent}) .. '\n' end
        end)
        if not ok then return false, tostring(err) end
    end
    -- Selecting a bundled namespace must never initialize files in its folder.
    if root:match('^%./_?namespaces/') then return true end
    -- Character folders are created by the file writer only when an override is saved.
    for _, folder in ipairs({'actions', 'actions/lib'}) do
        -- create_path creates missing parents and leaves existing folders intact.
        local created, err = files.create_path(root .. folder)
        if not created then
            return false, 'Unable to create namespace folder ' .. root .. folder .. ': ' .. tostring(err)
        end
    end
    local config = files.new(root .. '.nsconfig')
    if not config:exists() then
        local ok, result, err = pcall(function() return config:write(initialConfig) end)
        if not ok or not result then
            return false, 'Unable to create namespace configuration ' .. root .. '.nsconfig: ' .. tostring(ok and err or result)
        end
    end
    return true
end

function paths.writePath(playerName, relative)
    local root = loadedNamespace and paths.namespacePlayerRoot(loadedNamespace) or './settings'
    return root .. '/' .. playerName .. '/' .. relative
end

-- Closest scope/location wins; only the first existing event file is loaded.
function paths.eventFiles(playerName, mainJob, groups)
    local roots={}
    for _,name in ipairs(loadedPrecedence) do
        roots[#roots+1]={paths.namespacePath(name),
            not paths.isGambitReference(name) and paths.namespacePlayerRoot(name) or nil}
    end
    roots[#roots+1]={SETTINGS_ROOT, SETTINGS_ROOT}
    local positives,inverses={},{}
    for _,group in ipairs(targetSelectors.orderEntryPointGroups(groups)) do
        local list=group:sub(1,1)=='~' and inverses or positives
        list[#list+1]=group
    end
    local result={}
    local function addDirectory(directory)
        result[#result+1]=directory..'/'..mainJob:lower()..'.json'
        for _,group in ipairs(positives) do result[#result+1]=directory..'/('..group..').json' end
        for _,group in ipairs(inverses) do result[#result+1]=directory..'/('..group..').json' end
        result[#result+1]=directory..'/(all).json'
    end
    for _,entry in ipairs(roots) do
        local root, characterRoot=entry[1], entry[2]
        if characterRoot then addDirectory(characterRoot..'/'..playerName..'/events') end
        addDirectory(root..'/events')
    end
    addDirectory('./events') -- Shipped defaults never outrank user settings.
    return result
end

-- Namespace character/common paths precede base character/common paths.
-- An explicit scope limits lookup to character or common files in both roots.
-- Entry points resolve a complete selector search within each namespace.
-- Global character/shared directories are separate implicit fallback layers.
function paths.entryPointLayers(playerName,relative)
    local result={}
    for _,name in ipairs(loadedPrecedence) do
        local root=paths.namespacePath(name)
        if paths.isGambitReference(name) then result[#result+1]=root..'/'..relative
        else result[#result+1]={paths.namespacePlayerRoot(name)..'/'..playerName..'/'..relative,root..'/'..relative} end
    end
    result[#result+1]=SETTINGS_ROOT..'/'..playerName..'/'..relative
    result[#result+1]=SETTINGS_ROOT..'/'..relative
    return result
end

function paths.candidates(playerName, relative, scope)
    local roots = {}
    for _, name in ipairs(loadedPrecedence) do
        roots[#roots + 1] = {paths.namespacePath(name),
            not paths.isGambitReference(name) and paths.namespacePlayerRoot(name) or nil}
    end
    roots[#roots + 1] = {SETTINGS_ROOT, SETTINGS_ROOT}
    local result = {}
    for _, entry in ipairs(roots) do
        local root, characterRoot = entry[1], entry[2]
        if scope ~= 'common' and characterRoot then
            result[#result + 1] = characterRoot .. '/' .. playerName .. '/' .. relative
        end
        if scope ~= 'character' then result[#result + 1] = root .. '/' .. relative end
    end
    return result
end

function paths.firstExisting(candidates, exists)
    for _, path in ipairs(candidates) do
        if exists(path) then return path end
    end
end

-- Automatic common files are additive, listed from lowest to highest priority.
function paths.commonFiles(playerName, mainJob, groups)
    local libraries = {
        './actions/lib',
        SETTINGS_ROOT .. '/actions/lib',
        SETTINGS_ROOT .. '/' .. playerName .. '/actions/lib',
    }
    for i = #loadedPrecedence, 1, -1 do
        local root = paths.namespacePath(loadedPrecedence[i])
        libraries[#libraries + 1] = root .. '/actions/lib'
        if not paths.isGambitReference(loadedPrecedence[i]) then
            libraries[#libraries + 1] = paths.namespacePlayerRoot(loadedPrecedence[i]) .. '/' .. playerName .. '/actions/lib'
        end
    end
    local result = {}
    for _, library in ipairs(libraries) do
        local relatives = {'common/common'}
        -- Common imports run backward, so inverse defaults precede positives.
        for _, group in ipairs(groups or {}) do
            if group:sub(1,1) == '~' then relatives[#relatives + 1] = 'common/(' .. group .. ')' end
        end
        for _, group in ipairs(groups or {}) do
            if group:sub(1,1) ~= '~' then relatives[#relatives + 1] = 'common/(' .. group .. ')' end
        end
        relatives[#relatives + 1] = 'common/' .. mainJob
        relatives[#relatives + 1] = 'common'
        for _, relative in ipairs(relatives) do
            result[#result + 1] = library .. '/' .. relative .. '.json'
        end
    end
    return result
end

function paths.importCandidates(playerName, reference)
    local stock
    stock,reference=paths.gambitReference(reference)
    if stock then
        assert(type(reference)=='string' and reference~='' and not reference:find(':',1,true),
            'Invalid gambit action import')
        assert(reference:sub(1,1)~='/' and not reference:find('\\',1,true),
            'Invalid gambit action import '..reference)
        for part in (reference..'/'):gmatch('(.-)/') do
            assert(part~='' and part~='.' and part~='..','Invalid gambit action import '..reference)
        end
        return {'./actions/lib/'..reference:gsub('^/','')..'.json'}
    end
    local suffix = reference:match('^%$%(GlobalLib%)(.*)')
    if suffix then return { './actions/lib' .. suffix .. '.json' } end
    local scope
    suffix = reference:match('^%$%(PlayerLib%)(.*)')
    if suffix then
        scope = 'character'
    else
        suffix = reference:match('^%$%(SettingsLib%)(.*)')
        if suffix then scope = 'common' end
    end
    local relative = 'actions/lib/' .. (suffix or reference):gsub('^/', '') .. '.json'
    local result = paths.candidates(playerName, relative, scope)
    if not scope then result[#result + 1] = './' .. relative end
    return result
end

return paths
