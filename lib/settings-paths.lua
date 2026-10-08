-- Session state: this module survives settings reloads, but not addon reloads.
local paths = {}
local namespace = nil
local loadedNamespace = nil

local SETTINGS_ROOT = './settings'
local NS_ROOT       = SETTINGS_ROOT .. '/.ns/'

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

function paths.setLoadedNamespace(name)
    loadedNamespace = name
end

function paths.ensureNamespaceFolders(playerName, name)
    name = name or namespace
    if not name then return true end
    if type(playerName) ~= 'string' or playerName == '' then
        return false, 'A logged-in character is required to initialize a namespace.'
    end

    local root = NS_ROOT .. name .. '/'
    for _, folder in ipairs({'actions', 'actions/lib', playerName}) do
        -- create_path creates missing parents and leaves existing folders intact.
        local created, err = files.create_path(root .. folder)
        if not created then
            return false, 'Unable to create namespace folder ' .. root .. folder .. ': ' .. tostring(err)
        end
    end
    return true
end

function paths.writePath(playerName, relative)
    local root = loadedNamespace and (NS_ROOT .. loadedNamespace) or './settings'
    return root .. '/' .. playerName .. '/' .. relative
end

-- Namespace character/common paths precede base character/common paths.
-- An explicit scope limits lookup to character or common files in both roots.
function paths.candidates(playerName, relative, scope)
    local roots = {}
    if loadedNamespace then roots[#roots + 1] = NS_ROOT .. loadedNamespace end
    roots[#roots + 1] = SETTINGS_ROOT
    local result = {}
    for _, root in ipairs(roots) do
        if scope ~= 'common' then result[#result + 1] = root .. '/' .. playerName .. '/' .. relative end
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
function paths.commonFiles(playerName, mainJob)
    local libraries = {
        './actions/lib',
        SETTINGS_ROOT .. '/actions/lib',
        SETTINGS_ROOT .. '/' .. playerName .. '/actions/lib',
    }
    if loadedNamespace then
        local root = NS_ROOT .. loadedNamespace
        libraries[#libraries + 1] = root .. '/actions/lib'
        libraries[#libraries + 1] = root .. '/' .. playerName .. '/actions/lib'
    end
    local result = {}
    for _, library in ipairs(libraries) do
        for _, relative in ipairs({'common/common', 'common/' .. mainJob, 'common'}) do
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
