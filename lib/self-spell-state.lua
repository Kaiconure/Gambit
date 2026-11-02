-- Publish authoritative self casting state before lifecycle handlers run.
local SelfSpell={}
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
        if spell then state:setSpellStart(spell,observation.target_id) end
    else
        if globals.isSpellCasting then state:setSpellCompleted(observation.outcome=='interrupted') end
        globals.isSpellCasting=false
        globals.currentSpell=nil
        globals.spellTarget=nil
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
