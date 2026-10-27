local module = {}
function module.new(present, leader)
    local state = {present=present, leader=leader, warned=false}
    function state.update(current, now)
        if current == nil then state.since=nil; return false end
        if not state.present or state.warned or current == state.leader then
            state.since=nil
            return false
        end
        -- Require a stable observation, not a transient party update.
        if state.pending ~= current or not state.since then
            state.pending=current; state.since=now
        end
        if now - state.since < 5 then return false end
        state.warned=true
        return true
    end
    return state
end
return module
