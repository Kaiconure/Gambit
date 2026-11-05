local entryPoints = {}

-- Search selectors within a single layer. Namespace layers contain character
-- and shared directories; important selectors retain their local override cap.
local function findLayer(locations, job, subJob, groups, exists)
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
    for _, group in ipairs(groups) do
        for i = 1, #locations do
            local name = '(' .. group .. ')'
            if group:sub(1,1) ~= '~' and exists(path(i, name)) then return path(i, name), name end
        end
    end
    for _, group in ipairs(groups) do
        for i = 1, #locations do
            local name = '(' .. group .. ')'
            if group:sub(1,1) == '~' and exists(path(i, name)) then return path(i, name), name end
        end
    end
    for i = 1, #locations do
        if exists(path(i, '(all)')) then return path(i, '(all)'), '(all)' end
    end
end

-- Closest layer wins before selector specificity is considered elsewhere.
-- Strings represent standalone fallback layers; arrays group a namespace's
-- character/shared directories into one selector search.
function entryPoints.find(layers,job,subJob,groups,exists)
    for _,layer in ipairs(layers) do
        local path,name=findLayer(type(layer)=='table' and layer or {layer},job,subJob,groups,exists)
        if path then return path,name end
    end
end

return entryPoints
