local selectors=require('./lib/target-selectors')
local Paths=require('./lib/settings-paths')
local Config=require('./lib/events/config')
local Entry=require('./lib/action-entry-points')
for _,case in ipairs({{'WHM','healers','mages'},{'BLM','nukers','mages'},
    {'PLD','tanks','melee'},{'GEO','~melee','~healers'}}) do
    local job,narrow,broad=unpack(case)
    local groups=selectors.entryPointGroups(job)
    local first='root/('..narrow..').json'
    local second='root/('..broad..').json'
    local actual=Entry.find({'root'},job,nil,groups,function(path) return path==first or path==second end)
    assert(actual==first,job)
    local paths=Paths.eventFiles('Tester',job,groups)
    local base='./settings/events/'
    local rule=base..'('..narrow..').json'
    local fallback=base..'('..broad..').json'
    local selected=Config.load(paths,function(path)
        if path==rule or path==fallback then return {} end
        if path==rule:gsub('%.json$','.vars.json') then return {vars={winner=narrow}} end
        if path==fallback:gsub('%.json$','.vars.json') then return {vars={winner=broad}} end
    end)
    assert(selected.path==rule and selected.vars.winner==narrow,job)
end
-- Aliases have identical membership and retain alphabetical tie-breaking.
local ordered=selectors.orderEntryPointGroups({'mages','mage','healers','healer'})
assert(table.concat(ordered,',')=='healer,healers,mage,mages')
for _,job in ipairs({'WHM','BLM','PLD','RDM'}) do
    local groups=selectors.entryPointGroups(job,true)
    local alpha={}
    local leaderIndex
    for index,name in ipairs(groups) do
        if name:sub(1,1)~='~' then alpha[#alpha+1]=name end
        if name=='leader' then leaderIndex=index end
    end
    table.sort(alpha)
    assert(alpha[leaderIndex]=='leader')
end
print('PASS: narrow group and inverse-complement selection, event variable precedence, alias ties and stable leader slot')
