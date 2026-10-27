local info=require('./lib/job-info')
assert(info.name('sTERIS')=='Steris')
for _, name in ipairs({'ab','Bad-name','Name123','abcdefghijklmnop'}) do assert(not info.name(name)) end
for _, spec in ipairs({'WHM','whm/rdm','WHM75','WHM75/BLM37','WHM/RDM49','WHM99/RDM'}) do
    local record=assert(info.parse(spec))
    assert(record.main_job=='WHM')
end
assert(info.parse('WHM/RDM').sub_job_level==1)
assert(info.parse('WHM').main_job_level==1)
for _, spec in ipairs({'WHM0','WHM100','XXX','WHM/XXX','WHM75junk','WHM/','WHM1.5'}) do assert(not info.parse(spec)) end
local records={}
assert(info.apply(records,'sTERIS',info.parse('WHM75/BLM37')))
assert(info.apply(records,'Steris',info.parse('RDM')))
assert(records.Steris.main_job_level==1 and records.Steris.sub_job==nil)
assert(info.apply(records,'Steris',assert(info.record('WAR',99,'SAM',59))))
assert(records.Steris.main_job=='WAR' and records.Steris.sub_job_level==59)
assert(info.record('WHM',99,'n/a',0).sub_job==nil)
assert(info.message('Steris',info.parse('WHM'))=='job -n Steris -main WHM -main-l 1')
print('PASS: job specs, names, default levels, whole-record replacement and live updates')
