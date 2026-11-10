-- Angles are degrees relative to the target's facing. Positive is left:
-- Windower vectors use (cos(a), -sin(a)), with X east and Y south.
--
-- NOTE: For angle pairs, the values are:
--  [1] = Arc center
--  [2] = Allowed arc angle to either side of the center
--
-- So, {0, 15} means "at the front, or 15 degrees left or right of that"
--
local alignment = {}
local named = {
    frontside={{0, 30}},    -- Frontside/backside: Generally on the front or back side of the target
    backside={{180, 30}},
    fore={{0, 10}},         -- Fore/aft: Tighter spreads around the front and back
    aft={{180, 15}},
    left={{-90, 30}},       -- Left/right: Generally on the appropriate side of the target
    right={{90, 30}},
    lefter={{-90, 5}},      -- Lefter/righter: Left and right, but with tighter constraints
    righter={{90, 5}},
    sider={{-90,5},{90,5}},
    aside={{180, 100}},     -- Anywhere except near the mob's front
    side={                  -- Side: Either left or right is acceptable
        {90, 30},
        {-90, 30}
    }
}
local exactNames = {
    rear = 180,
    face = 0,
    front = 0,
    facing = 0,
}

local function finite(n) return n and n == n and math.abs(n) < math.huge end
local function delta(a,b) return (a-b+180)%360-180 end

function alignment.parse(value)
    if value == nil then return {free=true} end
    local number = tonumber(value)
    if finite(number) then return {exact=number} end
    if type(value)=='string' then
        local text=value:lower():gsub('%s','')
        if exactNames[text] ~= nil then return {exact=exactNames[text]} end
        if named[text] then return {arcs=named[text]} end
        local center, width=text:match('^([%+%-]?[%d%.]+)%+/%-([%d%.]+)$')
        if center then
            center,width=tonumber(center),tonumber(width)
            if finite(center) and finite(width) and width<=180 then
                return {arcs={{center,width}}}
            end
        end
        local first,last=text:match('^([%+%-]?[%d%.]+)%-([%+%-]?[%d%.]+)$')
        first,last=tonumber(first),tonumber(last)
        if finite(first) and finite(last) then
            local span=(last-first)%360
            if math.abs(last-first)>=360 then span=360 end
            return {arcs={{first+span/2,span/2}}}
        end
    end
    error('Invalid alignment angle: '..tostring(value))
end

function alignment.bearing(target, position)
    return -math.atan2(position.y-target.y,position.x-target.x)*180/math.pi
        - (target.heading or 0)*180/math.pi
end

function alignment.contains(spec, angle)
    if spec.free then return true end
    if spec.exact then return math.abs(delta(angle,spec.exact))<0.000001 end
    for _,arc in ipairs(spec.arcs) do
        if math.abs(delta(angle,arc[1]))<=arc[2]+0.000001 then return true end
    end
    return false
end

function alignment.candidates(spec, bearing, preferred)
    if spec.exact then return {spec.exact} end
    if spec.free then return {bearing,bearing+45,bearing-45} end
    local result={}
    local function add(angle)
        for _,old in ipairs(result) do if math.abs(delta(old,angle))<0.001 then return end end
        result[#result+1]=angle
    end
    if alignment.contains(spec,bearing) then add(bearing)
    elseif preferred and alignment.contains(spec,preferred) then add(preferred) else
        local arc=spec.arcs[math.random(#spec.arcs)]
        add(arc[1]+(math.random()*2-1)*arc[2])
    end
    -- Include both extremes of every allowed arc (including the opposite side).
    for _,arc in ipairs(spec.arcs) do add(arc[1]-arc[2]);add(arc[1]+arc[2]) end
    return result
end

-- Work with the union of all allowed arcs, excluding gaps and double-counted
-- overlap. Split wraparound arcs at zero before slicing their total length.
function alignment.intervals(spec)
    local intervals={}
    for _,arc in ipairs(spec.arcs or {}) do
        local width=arc[2]*2
        if width>=360 then return {{0,360}} end
        if width>0 then
            local first=(arc[1]-arc[2])%360
            local last=first+width
            intervals[#intervals+1]={first,math.min(last,360)}
            if last>360 then intervals[#intervals+1]={0,last-360} end
        end
    end
    table.sort(intervals,function(a,b)return a[1]<b[1]end)
    local result={}
    for _,range in ipairs(intervals) do
        local previous=result[#result]
        if previous and range[1]<=previous[2] then previous[2]=math.max(previous[2],range[2])
        else result[#result+1]={range[1],range[2]} end
    end
    return result
end

function alignment.slice(spec,index,count)
    if spec.exact or spec.free or count<=1 then return spec end
    local ranges=alignment.intervals(spec)
    local total=0
    for _,range in ipairs(ranges) do total=total+range[2]-range[1] end
    if total==0 then return spec end
    local first,last=(index-1)*total/count,index*total/count
    local offset,result=0,{arcs={}}
    for _,range in ipairs(ranges) do
        local length=range[2]-range[1]
        local start,finish=math.max(first,offset),math.min(last,offset+length)
        if finish>start then
            local a,b=range[1]+start-offset,range[1]+finish-offset
            result.arcs[#result.arcs+1]={(a+b)/2,(b-a)/2}
        end
        offset=offset+length
    end
    return result
end

function alignment.closest(spec,bearing)
    if spec.exact then return spec.exact end
    if spec.free or alignment.contains(spec,bearing) then return bearing end
    local best,gap
    for _,arc in ipairs(spec.arcs or {}) do
        for _,angle in ipairs({arc[1]-arc[2],arc[1]+arc[2]}) do
            local distance=math.abs(delta(angle,bearing))
            if not gap or distance<gap then best,gap=angle,distance end
        end
    end
    return best or bearing
end

function alignment.distributedCandidates(spec,preferred,bearing,count)
    local candidates={}
    local function add(angle)
        for _,old in ipairs(candidates) do if math.abs(delta(old,angle))<0.001 then return end end
        candidates[#candidates+1]=angle
    end
    local first=alignment.closest(preferred,bearing)
    add(first)
    -- Accept the current valid region after trying the assigned region; then
    -- explore every actual arc and other fractional slices, never named cases.
    add(alignment.closest(spec,bearing))
    -- If a whole arc is blocked, try a different arc before spending the
    -- movement budget on more points in that same obstructed region.
    for _,arc in ipairs(spec.arcs or {}) do
        if not alignment.contains({arcs={arc}},first) then add(arc[1]) end
    end
    for _,arc in ipairs(spec.arcs or {}) do add(arc[1]) end
    for i=1,count do
        for _,arc in ipairs(alignment.slice(spec,i,count).arcs or {}) do add(arc[1]) end
    end
    for _,arc in ipairs(spec.arcs or {}) do add(arc[1]-arc[2]);add(arc[1]+arc[2]) end
    return candidates
end

return alignment
