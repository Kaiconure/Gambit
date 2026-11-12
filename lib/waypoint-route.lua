local M={}
local function finite(value)
    return type(value)=='number' and value==value and math.abs(value)<math.huge
end
local function nonnegative(value,label,default)
    if value==nil then return default end
    assert(finite(value) and value>=0,label..' must be a finite nonnegative number')
    return value
end
local function dense(value,label)
    assert(type(value)=='table',label..' must be an array')
    for key in pairs(value) do
        assert(type(key)=='number' and key>=1 and key%1==0 and key<=#value,label..' must be a dense array')
    end
end
function M.new(config,position,now)
    assert(type(config)=='table','Waypoint route configuration must be an object')
    dense(config.points,'Waypoint route points')
    assert(#config.points>0,'Waypoint route requires at least one point')
    local mode=config.mode or 'bounce'
    assert(mode=='bounce' or mode=='cycle','Waypoint route mode must be bounce or cycle')
    local route=setmetatable({config=config,mode=mode,points={},step=1,
        cornerRadius=nonnegative(config.corner_radius,'Waypoint route corner_radius',0),
        tolerance=config.tolerance~=nil and nonnegative(config.tolerance,'Waypoint route tolerance') or nil,
        turnPause=nonnegative(config.turn_pause,'Waypoint route turn_pause',0.35)},{__index=M})
    for index,point in ipairs(config.points) do
        assert(type(point)=='table' and finite(point.x) and finite(point.y),
            'Waypoint route point '..index..' requires finite x and y coordinates')
        route.points[index]={x=point.x,y=point.y,
            corner_radius=point.corner_radius~=nil and nonnegative(point.corner_radius,'Waypoint corner_radius') or nil,
            tolerance=point.tolerance~=nil and nonnegative(point.tolerance,'Waypoint tolerance') or nil,
            pause=point.pause~=nil and nonnegative(point.pause,'Waypoint pause') or nil,
            duration=point.duration~=nil and nonnegative(point.duration,'Waypoint duration') or nil}
    end
    route.index=1
    if position and finite(position.x) and finite(position.y) then
        local nearestDistance
        for index,point in ipairs(route.points) do
            local distance=(position.x-point.x)^2+(position.y-point.y)^2
            if not nearestDistance or distance<nearestDistance then
                route.index,nearestDistance=index,distance
            end
        end
    end
    route.started=now or 0
    return route
end
function M:point() return self.points[self.index] end
function M:threshold(defaultTolerance)
    local point=self:point()
    local tolerance=point.tolerance or self.tolerance or defaultTolerance or 0.33
    return math.max(tolerance,point.corner_radius or self.cornerRadius)
end
function M:timedOut(now)
    local duration=self:point().duration
    return duration and now-self.started>=duration or false
end
function M:advance(now)
    if #self.points<2 then return end
    local leaving=self:point()
    local reversed=false
    if self.mode=='cycle' then
        self.index=self.index%#self.points+1
    elseif self.index>=#self.points and self.step==1 then
        self.step=-1;self.index=#self.points-1;reversed=true
    elseif self.index<=1 and self.step==-1 then
        self.step=1;self.index=2;reversed=true
    else
        self.index=self.index+self.step
    end
    self.started=now or self.started
    local explicitPause=leaving.pause or 0
    return {point=self:point(),reversed=reversed,stop=reversed or explicitPause>0,
        pause=explicitPause>0 and explicitPause or (reversed and self.turnPause or 0)}
end
return M
