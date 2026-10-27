local entryPoints = {}

-- Locations are ordered most-specific first. Important selectors cap how far
-- exact job lookups may inherit; ordinary selectors remain global fallbacks.
function entryPoints.find(locations, job, subJob, groups, exists)
    local limit, override = #locations, nil
    local function path(i, name) return locations[i] .. '/' .. name .. '.json' end
    for i = 1, #locations do
        for _, group in ipairs(groups) do
            local name = '(!' .. group .. ')'
            if group:sub(1,1) ~= '~' and exists(path(i, name)) then override = {path(i, name), name}; break end
        end
        if not override and exists(path(i, '(!all)')) then
            override = {path(i, '(!all)'), '(!all)'}
        end
        if override then limit = i; break end
    end
    local exact = {}
    if subJob then exact[#exact + 1] = job:lower() .. '-' .. subJob:lower() end
    exact[#exact + 1] = job:lower()
    for _, name in ipairs(exact) do
        for i = 1, limit do
            if exists(path(i, name)) then return path(i, name), name end
        end
    end
    if override then return unpack(override) end
    for i = 1, #locations do
        for _, group in ipairs(groups) do
            local name = '(' .. group .. ')'
            if group:sub(1,1) ~= '~' and exists(path(i, name)) then return path(i, name), name end
        end
    end
    for i = 1, #locations do
        for _, group in ipairs(groups) do
            local name = '(' .. group .. ')'
            if group:sub(1,1) == '~' and exists(path(i, name)) then return path(i, name), name end
        end
    end
    for i = 1, #locations do
        if exists(path(i, '(all)')) then return path(i, '(all)'), '(all)' end
    end
end

return entryPoints
