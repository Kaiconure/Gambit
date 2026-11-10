local M={}
function M.angle(options)
    if options.angle==nil then return nil end
    return require('./lib/alignment').parse(options.angle)
end
-- nil represents no deadline; never store infinity in state/JSON snapshots.
function M.timeout(value)
    if value==nil or value==math.huge then return nil end
    if type(value)=='string' then
        local name=value:match('^%s*(.-)%s*$'):lower()
        if name=='inf' or name=='infinity' then return nil end
    end
    assert(type(value)=='number' and value>=0 and value<math.huge,
        'Reaction timeout must be a nonnegative number, null, inf or infinity')
    return value
end
return M
