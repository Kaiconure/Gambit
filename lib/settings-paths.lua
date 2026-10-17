-- Session state: this module survives settings reloads, but not addon reloads.
local paths = {}
local namespace = nil
local loadedNamespace = nil
local loadedPrecedence = {}

local SETTINGS_ROOT = './settings'
local function directoryExists(path)
    return windower and windower.dir_exists and
        windower.dir_exists((windower.addon_path or '') .. path:gsub('^%./', '')) or false
end

function paths.namespaceRoot()
    if directoryExists('./settings/_ns') then return './settings/_ns' end
    if directoryExists('./settings/.ns') then return './settings/.ns' end
    return './settings/_ns'
end

function paths.namespacePath(name)
    local valid, message = paths.validateNamespace(name)
    assert(valid, message)
    local root = paths.namespaceRoot()
    for segment in (name or ''):gmatch('[^/]+') do
        local exact = root .. '/' .. segment
        if not directoryExists(exact) and segment:sub(1,1) ~= '_' and directoryExists(root .. '/_' .. segment) then
            exact = root .. '/_' .. segment
        end
        root = exact
    end
    return root
end

function paths.namespaceExists(name)
    return directoryExists(paths.namespacePath(name))
end

function paths.getNamespace()
    return namespace
end

function paths.validateNamespace(name)
    if name ~= nil and (
        type(name) ~= 'string' or
        not name:match('^[%w_/-]+$') or
        name:sub(1, 1) == '/' or
        name:sub(-1) == '/' or
        name:find('//', 1, true)
    ) then
        return false, 'Namespace names must be slash-separated folder names containing only letters, numbers, underscores, and hyphens.'
    end
    for segment in (name or ''):gmatch('[^/]+') do
        local normalized = segment:lower():gsub('^_+', '')
        if normalized == 'actions' or normalized == 'players' then
            return false, 'Namespace folder name "' .. segment .. '" is reserved for namespace contents.'
        end
        if normalized == 'con' or normalized == 'nul' or normalized == 'aux' or normalized == 'prn'
            or normalized:match('^com[1-9]$') or normalized:match('^lpt[1-9]$') then
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
        if parent then assert(exists(current), 'Inherited namespace does not exist: ' .. current) end
        visiting[identity] = true
        local config = readConfig(current)
        if config == nil then config = {} end
        assert(type(config) == 'table', 'Invalid .nsconfig for ' .. current .. ': expected an object')
        assert(config.inheritable == nil or type(config.inheritable) == 'boolean', 'inheritable must be boolean in ' .. current)
        if parent and config.inheritable == false then
            error('Namespace ' .. text_namespace(current, Colors.red) .. ' explicitly disables inheritance (inheritable: false)', 0)
        end
        result[#result+1] = current
        if config.inherits_from ~= nil then
            assert(type(config.inherits_from) == 'string', 'inherits_from must be a single namespace string in ' .. current)
            visit(config.inherits_from, true)
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
    if parent ~= nil then
        local ok, err = pcall(function()
            local validParent, parentMessage = paths.validateNamespace(parent)
            assert(validParent, parentMessage)
            paths.resolveInheritance(name, function(current)
                local file = files.new(paths.namespacePath(current) .. '/.nsconfig')
                local config
                if file:exists() then
                    config = json.parse(file:read())
                    assert(type(config) == 'table', 'Invalid .nsconfig for ' .. current)
                    if current == name then
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
            initialConfig = json.stringify({inherits_from = parent}) .. '\n'
        end)
        if not ok then return false, tostring(err) end
    end
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
    local root = loadedNamespace and (paths.namespacePath(loadedNamespace) .. '/players') or './settings'
    return root .. '/' .. playerName .. '/' .. relative
end

-- Namespace character/common paths precede base character/common paths.
-- An explicit scope limits lookup to character or common files in both roots.
function paths.candidates(playerName, relative, scope)
    local roots = {}
    for _, name in ipairs(loadedPrecedence) do roots[#roots + 1] = paths.namespacePath(name) end
    roots[#roots + 1] = SETTINGS_ROOT
    local result = {}
    for _, root in ipairs(roots) do
        if scope ~= 'common' then
            local characterRoot = root == SETTINGS_ROOT and root or (root .. '/players')
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
        libraries[#libraries + 1] = root .. '/players/' .. playerName .. '/actions/lib'
    end
    local result = {}
    for _, library in ipairs(libraries) do
        local relatives = {'common/common'}
        for _, group in ipairs(groups or {}) do
            relatives[#relatives + 1] = 'common/(' .. group .. ')'
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
