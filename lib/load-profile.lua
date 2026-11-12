-- Optional synchronous load diagnostics; disabled paths do not read the clock.
local M={}
local active
local enabled=false
local parents={}
-- A marker survives addon reloads, so startup can be profiled before settings load.
local marker=windower and windower.addon_path and windower.addon_path..'.data/load-profile.enabled'
if marker then
    local ok,file=pcall(io.open,marker,'r')
    if ok and file then enabled=true;file:close() end
end
function M.setEnabled(value)
    enabled=value==true
    active=nil;parents={}
end
function M.isEnabled() return enabled end
function M.configure(value)
    assert(marker,'Profiling requires an addon path')
    if value then
        local directory=windower.addon_path..'.data/'
        if not windower.dir_exists(directory) then windower.create_dir(directory) end
        local file=assert(io.open(marker,'w'));file:write('enabled\n');file:close()
    else
        local file=io.open(marker,'r')
        if file then file:close();assert(os.remove(marker)) end
    end
    M.setEnabled(value)
end
function M.now() if active then return os.clock() end end
function M.start(name)
    if not active then return end
    local timers=active.timers[name]
    if not timers then timers={};active.timers[name]=timers end
    timers[#timers+1]=os.clock()
end
function M.stop(name)
    if not active then return end
    local timers=active.timers[name]
    if not timers or #timers==0 then return end
    local started=table.remove(timers)
    M.sample(name,started)
end
function M.checkpoint(name)
    if not active then return end
    local now=os.clock()
    M.sample(name,active.checkpoint or active.started)
    active.checkpoint=now
end
function M.report(message)
    if not enabled then return end
    print(message)
    -- Profiling must never make a successful load fail.
    pcall(function()
        if not windower or not windower.addon_path then return end
        local player=windower.ffxi.get_player()
        local directory=windower.addon_path..'.data/'
        if not windower.dir_exists(directory) then windower.create_dir(directory) end
        local name=(player and player.name or 'Unknown'):gsub('[^%w_-]','_')
        local file=io.open(directory..'load-profile-'..name..'.log','a')
        if file then file:write(os.date('[%Y-%m-%d %H:%M:%S] ')..message..'\n');file:close() end
    end)
end
function M.begin(label)
    if not enabled then return end
    if active then parents[#parents+1]=active end
    active={label=label,started=os.clock(),stages={},timers={},reads=0,parses=0,readTime=0,parseTime=0,files={},metrics={}}
end
function M.sample(name,started)
    if not active or not started then return end
    local metric=active.metrics[name] or {count=0,time=0}
    active.metrics[name]=metric
    metric.count=metric.count+1;metric.time=metric.time+os.clock()-started
end
function M.measure(name,fn,...)
    if not active then return fn(...) end
    local started=os.clock()
    local function pack(...)return {n=select('#',...),...}end
    local result=pack(fn(...))
    M.sample(name,started)
    return unpack(result,1,result.n)
end
function M.stage(name,started)
    if active and started then active.stages[#active.stages+1]=string.format('%s=%.1fms',name,(os.clock()-started)*1000) end
end
function M.read(file,path)
    if not active then return file:read() end
    local started=os.clock()
    local value=file:read()
    if active then
        active.reads=active.reads+1;active.readTime=active.readTime+os.clock()-started
        if path then active.files[path]=true end
    end
    return value
end
function M.parse(parse,value)
    if not active then return parse(value) end
    local started=os.clock()
    local result=parse(value)
    if active then active.parses=active.parses+1;active.parseTime=active.parseTime+os.clock()-started end
    return result
end
function M.eventRead(started,path)
    if active and started then
        active.reads=active.reads+1;active.readTime=active.readTime+os.clock()-started;active.files[path]=true
    end
end
function M.finish(report)
    local profile=active;active=table.remove(parents)
    if not profile then return end
    report=report or M.report
    local unique=0;for _ in pairs(profile.files)do unique=unique+1 end
    report(string.format('[load profile] %s total=%.1fms | %s | reads=%d (%d unique, %.1fms), parses=%d (%.1fms)',
        profile.label,(os.clock()-profile.started)*1000,table.concat(profile.stages,', '),
        profile.reads,unique,profile.readTime*1000,profile.parses,profile.parseTime*1000))
    local names={};for name in pairs(profile.metrics)do names[#names+1]=name end
    table.sort(names)
    local details={}
    for _,name in ipairs(names)do
        local metric=profile.metrics[name]
        details[#details+1]=string.format('%s=%.1fms/%d calls',name,metric.time*1000,metric.count)
    end
    if #details>0 then report('[load profile] '..profile.label..' detail (inclusive/overlapping): '..table.concat(details,', ')) end
end
return M
