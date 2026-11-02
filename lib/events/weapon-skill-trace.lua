-- Opt-in bounded capture; disabled calls do not inspect equipment or packets.
local copy=require('./lib/variable-values').copy
local Trace={}
local capture
function Trace.active() return capture and not capture.full end
function Trace.start(clock)
    capture={clock=clock or os.clock,started=(clock or os.clock)(),rows={}}
end
function Trace.record(kind,data)
    if not Trace.active() then return end
    if #capture.rows>=2048 then capture.full=true; return end
    local row=copy(data or {})
    row.step=#capture.rows+1; row.time=capture.clock()-capture.started; row.kind=kind
    capture.rows[#capture.rows+1]=row
end
function Trace.stop()
    if not capture then return end
    local result={duration=capture.clock()-capture.started,truncated=not not capture.full,entries=capture.rows}
    capture=nil
    return result
end
return Trace
