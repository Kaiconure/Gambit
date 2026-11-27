-- Publish authoritative self casting state before lifecycle handlers run.
local SelfSpell={}
local function clear(state,globals,interrupted)
    if globals.isSpellCasting then state:setSpellCompleted(interrupted) end
    globals.isSpellCasting=false
    globals.currentSpell=nil
    globals.spellTarget=nil
    globals.spellCastDeadline=nil
end

function SelfSpell.expire(state,globals,now)
    if not globals.isSpellCasting or not globals.spellCastDeadline or now<globals.spellCastDeadline then
        return false
    end
    clear(state,globals,true)
    if globals.last_spell and globals.last_spell.status=='casting' then
        globals.last_spell.status='timed_out'
        globals.last_spell.time=now
    end
    return true
end

function SelfSpell.apply(observation,state,globals,clock)
    local now=(clock or os.clock)()
    observation.was_casting=globals.isSpellCasting
    observation.previous_spell=globals.currentSpell
    observation.previous_target=globals.spellTarget
    local spell=observation.resource
    if observation.phase=='mid' then
        globals.isSpellCasting=true
        globals.currentSpell=spell
        globals.spellTarget=observation.target
        local castTime=spell and tonumber(spell.cast_time)
        globals.spellCastDeadline=now+math.max(0,castTime or 10)+3
        if spell then state:setSpellStart(spell,observation.target_id) end
    else
        clear(state,globals,observation.outcome=='interrupted')
    end
    if observation.outcome=='interrupted' then
        if globals.last_spell and globals.last_spell.status=='casting' then
            globals.last_spell.status='interrupted'; globals.last_spell.time=now
        end
    elseif spell then
        local target=observation.target
        globals.last_spell={id=spell.id,name=spell.en or spell.name,element=spell.element,time=now,
            status=observation.phase=='mid' and 'casting' or 'completed',
            target=observation.target_id and {id=observation.target_id,
                name=target and target.name,index=target and target.index} or nil}
    end
end
return SelfSpell
