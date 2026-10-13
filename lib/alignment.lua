-- Angles are degrees relative to the target's facing. Positive is left:
-- Windower vectors use (cos(a), -sin(a)), with X east and Y south.
local alignment = {}
local named = {
    frontside={{0, 30}},
    backside={{180, 30}},
    left={{90, 30}},
    right={{-90, 30}},
    side={
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
    if preferred and alignment.contains(spec,preferred) then add(preferred) else
        local arc=spec.arcs[math.random(#spec.arcs)]
        add(arc[1]+(math.random()*2-1)*arc[2])
    end
    -- Include both extremes of every allowed arc (including the opposite side).
    for _,arc in ipairs(spec.arcs) do add(arc[1]-arc[2]);add(arc[1]+arc[2]) end
    return result
end

return alignment
