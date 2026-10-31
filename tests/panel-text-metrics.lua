local Metrics=require('./lib/ux/text-metrics')
local Buffer=require('./lib/ux/log-buffer')
local regular={font='Segoe UI',fontSize=12,bold=false}
local bold={font='Segoe UI',fontSize=12,bold=true}
local mono={font='Consolas',fontSize=12,bold=false}
assert(Metrics.width(regular,'iiii')<Metrics.width(regular,'WWWW'))
assert(Metrics.width(bold,'Objectives')>Metrics.width(regular,'Objectives'))
assert(Metrics.width(mono,'iiii')==Metrics.width(mono,'WWWW'))
local text='Interact with Diaphanous Bitzer #B after walking on foot (Sheet B)'
local width=Metrics.width(regular,text)
assert(width>400 and width<550) -- Previously estimated at 634px before padding.
local cache=regular.measured
assert(Metrics.width(regular,text)==width and regular.measured==cache)
regular.fontSize=24
assert(Metrics.width(regular,text)==width*2 and regular.measured~=cache)
regular.fontSize=12
local colored='\\cs(100,235,130)Wide WWW\\cr'
assert(Metrics.width(regular,colored)==Metrics.width(regular,'Wide WWW'))
assert(Metrics.width(regular,'ii\nWW')==Metrics.width(regular,'WW'))
local clip=Metrics.clip(regular,colored,Metrics.width(regular,'Wide ')+0.01)
assert(Buffer.uncolored(clip)=='Wide ' and clip:sub(-3)=='\\cr')
assert(Metrics.clip(regular,'→',1)=='')
assert(Metrics.clip(regular,'→',16)=='→')
print('PASS: proportional/bold/monospace metrics, bounded cache, scaling, color markup and pixel clipping')
