-- Publish self result history before post handlers. Effect/buff processing is separate.
local SelfAction={}
function SelfAction.apply(observation,state,globals,clock)
    local resource=observation.resource
    if not resource then return end
    if observation.kind=='job_ability' then
        local target=observation.target
        globals.last_ability={id=resource.id,name=resource.en or resource.name,element=resource.element,
            time=(clock or os.clock)(),target=observation.target_id and {
                id=observation.target_id,name=target and target.name,index=target and target.index} or nil}
    elseif observation.kind=='weapon_skill' and observation.actor and observation.target then
        local damage=observation.detail and observation.detail.param
        local chainable=(resource.skillchain_a or '')~='' or (resource.skillchain_b or '')~=''
            or (resource.skillchain_c or '')~=''
        if chainable and type(damage)=='number' and damage>0 then
            state:setPartyWeaponSkill(observation.actor,resource,observation.target)
            observation.weapon_skill_published=true
        end
    end
end
return SelfAction
