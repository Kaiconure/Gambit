local paths = dofile('lib/settings-paths.lua')
json = dofile('lib/jsonlua.lua')
Colors = {error=1}
text_namespace = function(value) return value end
local disk, directories = {}, {base=true}
local writes, creates = 0, 0
local function config(name) return './settings/.ns/' .. name .. '/.nsconfig' end
disk[config('base')] = '{}'
files = {
    create_path=function() creates=creates+1; return true end,
    new=function(path) return {
        exists=function() return disk[path]~=nil end,
        read=function() return disk[path] end,
        write=function(_,value) writes=writes+1; disk[path]=value; return true end,
    } end,
}
windower={addon_path='',dir_exists=function(path)
    return path=='settings/.ns' or directories[path:gsub('^settings/%.ns/','')] == true
end}
assert(paths.ensureNamespaceFolders('Player','child','base'))
assert(json.parse(disk[config('child')]).inherits_from=='base')
assert(json.parse(disk[config('child')]).inheritable==nil)
assert(paths.ensureNamespaceFolders('Player','child','base'))
assert(writes==1)
local function rejected(name,parent)
    local beforeWrites,beforeCreates=writes,creates
    assert(not paths.ensureNamespaceFolders('Player',name,parent))
    assert(writes==beforeWrites and creates==beforeCreates)
end
disk[config('empty')]='{}'
rejected('empty','base')
local ok, message = paths.ensureNamespaceFolders('Player','empty','base')
assert(not ok and message == 'Namespace empty already has a different or missing parent.')
rejected('child','other')
rejected('new','missing')
rejected('new','actions')
rejected('self','self')
directories.closed=true; disk[config('closed')]='{"inheritable":false}'
rejected('new','closed')
directories.unconfigured=true
assert(paths.ensureNamespaceFolders('Player','from-unconfigured','unconfigured'))
disk[config('base')]='{"inheritable":true,"inherits_from":"new"}'
rejected('new','base')
disk[config('base')]='not json'
rejected('new','base')
assert(paths.ensureNamespaceFolders('Player','plain'))
assert(disk[config('plain')]=='{}\n')
print('PASS: parent initialization, existing config preservation, invalid parents/chains before writes, and plain creation')
