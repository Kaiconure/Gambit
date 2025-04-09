__version = '0.95.5-beta26'
__name = 'Gambit'
__shortName = 'gbt'
__author = '@Kaiconure'
__commands = { 'gbt', 'gambit' }

_addon.version = __version
_addon.name = __name
_addon.shortName = __shortName
_addon.author = __author
_addon.commands = __commands

require('sets')
require('vectors')

extdata = require('extdata')
resources = require('resources')
packets = require('packets')
config = require('config')
files = require('files')

require('actions')

json = require('./lib/jsonlua')
directionality = require('./lib/directionality')

meta = meta or {}
meta.erase = require('./meta/erase') or {}
meta.dispel = require('./meta/dispel') or {}
meta.monster_abilities = require('./meta/monster_abilities') or {}
meta.trusts = require('./meta/trusts')
meta.jobs_with_mp = require('./meta/jobs_with_mp')
meta.buffs = require('./meta/buffs')
meta.immanence = require('./meta/immanence')

require('./lib/logging')
require('./lib/helpers')
require('./lib/settings')
require('./lib/resx')
require('./lib/eventing')
require('./lib/commands')
require('./lib/target-processing')

inventory = require('./lib/inventory')
smartMove = require('./lib/smart-move')

actionStateManager = require('./lib/action-state-manager')
require('./lib/action-processing')

ActionContext = require('./lib/action-context')

globals = {
    enabled         = false,
    isSpellCasting  = false,
    target          = nil,
    currentZone = nil,
    selfName = __name,
    selfShortName = __shortName,
    selfCommand = __commands[1],
    language = 'en',
    actionsEnabled = true,
    autoFollowIndex = nil,
    spells = {}
}

globals.spells.trust = resources.spells:type('Trust')

--------------------------------------------------------------------------------------
-- Make a command that can be run against this addon with an optional wait afterward
function makeSelfCommand(command, wait)
    local command = string.format('%s %s;',
        globals.selfCommand,
        command)
    
    if type(wait) == 'number' and wait > 0 then
        command = command .. string.format('wait %d;', wait)
    end

    return command
end

--------------------------------------------------------------------------------------
-- Run a command against this addon
function sendSelfCommand(command, wait)
    windower.send_command(makeSelfCommand(command, wait))
end

function reloadSettings(actionsName, bypassActions)
    bypassActions = bypassActions and settings.actions ~= nil

    settings = loadSettings(actionsName, bypassActions)
    logging_settings.verbosity = settings.verbosity

    -- We will not recompile actions or reset the current mob if this is a settings-only reload
    if not bypassActions then
        recompileActions()
        resetCurrentMob(nil, true)
    end

    writeMessage(text_green('Settings have been reloaded!', Colors.default))
end

-- Player status change
windower.register_event('status change', function(new_id, previous_id)
    
    if
        --new_id == STATUS_IDLE
        new_id ~= STATUS_ENGAGED
    then
        resetCurrentMob(nil, true)

        -- We'll unfollow once battle has ended to avoid the possibility of running
        -- off into space if autofollow was enabled
        windower.ffxi.follow(-1)
    -- elseif 
    --     new_id == 2 or  -- Dead
    --     new_id == 3 or  -- Dead while engaged
    --     new_id == 5 or  -- On a chocobo
    --     new_id == 85    -- On a mount that is not a chocobo
    -- then
    --     resetCurrentMob(nil, true)
    end
end)

---------------------------------------------------------------------
-- Zoned
windower.register_event('zone change', function(zone_id)
    -- Store the new zone
    globals.currentZone = zone_id > 0 and resources.zones[zone_id] or nil

    -- Clear tracking info
    actionStateManager:clearOthersSpells()

    local player = windower.ffxi and windower.ffxi.get_player()
    if
        player == nil or
        player.status == nil or
        not (player.status == 85 or player.status == 5)
    then
        -- Disable all the things unless we're mounted
        sendSelfCommand('disable -quiet')
    end
    resetCurrentMob(nil, true)
end)

---------------------------------------------------------------------
-- Addon loaded
windower.register_event('load', function()

    writeMessage('')
    writeMessage(string.format(' ===== Welcome to %s v%s! ===== ', globals.selfName, __version), Colors.green)
    writeMessage('    Use Shift+Alt+G to toggle automation.', Colors.blue)
    writeMessage('')

    sendSelfCommand('disable')

    smartMove:setLogger(writeDebug, writeTrace)

    local bind_toggle = 'bind !~g ' .. makeSelfCommand('toggle')
    local bind_follow = 'bind %^f ' .. makeSelfCommand('follow -toggle')

    -- writeMessage('bind_toggle: ' .. text_green(bind_toggle))
    -- writeMessage('bind_follow: ' .. text_green(bind_follow))

    windower.send_command(bind_toggle)  -- Use Shift+Alt+G to toggle automation
    windower.send_command(bind_follow)  -- Use Ctrl+F to toggle follow automation

    -- Store the current zone
    local info = windower.ffxi.get_info()
    globals.currentZone = info and info.zone > 0 and resources.zones[info.zone] or nil
    globals.language = info.language

    -- Store self info
    local me = windower.ffxi.get_mob_by_target('me')
    if me then
        globals.me_id = me.id
        globals.me_name = me.name
    end
    
    -- Reload all settings
    resetCurrentMob(nil, true)
    reloadSettings()
    
    -- Kick off background threads
    coroutine.schedule(cr_actionProcessor, 0)
end)

---------------------------------------------------------------------
-- Login
windower.register_event('login', function ()
    -- Store the current zone
    local info = windower.ffxi.get_info()
    globals.currentZone = info and info.zone > 0 and resources.zones[info.zone] or nil
    globals.language = info.language

    -- Store self info
    local me = windower.ffxi.get_mob_by_target('me')
    if me then
        globals.me_id = me.id
        globals.me_name = me.name
    end
    
    -- Reload all settings
    resetCurrentMob(nil, true)
    reloadSettings()
end)

---------------------------------------------------------------------
-- Addon unloaded
windower.register_event('unload', function()
    resetCurrentMob(nil, true)
    windower.send_command('unbind !~G;')    -- Unbind the automation toggle key
end)


local CATEGORY_SPELL_START          = 8     -- action.category=8, action.param = 24931
local CATEGORY_SPELL_INTERRUPT      = 8     -- action.category=8, action.param = 28787
local CATEGORY_SPELL_END            = 4

local CATEGORY_RANGED_START         = 12     -- action.category=12, action.param = 24931
local CATEGORY_RANGED_INTERRUPT     = 12     -- action.category=12, action.param = 24931
local CATEGORY_RANGED_END           = 2

local PARAM_STARTED                 = 24931 -- Normal start
local PARAM_INTERRUPTED             = 28787 -- Interrupted before completion

---------------------------------------------------------------------
-- Handle actions
windower.register_event('action', function(action)
    if
        action == nil or
        action.actor_id == nil or
        action.param == nil
    then
        return
    end

    local player        = windower.ffxi.get_player()
    local playerId      = player.id
    local actorId       = action.actor_id
    local isSelf        = actorId == playerId
    local actor         = windower.ffxi.get_mob_by_id(actorId)
    local isActorValid  = actor 
        and actor.valid_target 
        and actor.hpp 
        and actor.hpp > 0
    local isActorEnemy  = isActorValid and actor.spawn_type == SPAWN_TYPE_MOB

    if isActorValid then
        local isSpellStart              = action.category == CATEGORY_SPELL_START and action.param == PARAM_STARTED
        local isSpellInterrupted        = action.category == CATEGORY_SPELL_INTERRUPT and action.param == PARAM_INTERRUPTED
        local isSpellSuccessful         = action.category == CATEGORY_SPELL_END
        local isSpellCastingComplete    = isSpellInterrupted or isSpellSuccessful

        local isRangedStart         = action.category == CATEGORY_RANGED_START and action.param == PARAM_STARTED
        local isRangedInterrupted   = action.category == CATEGORY_RANGED_INTERRUPT and action.param == PARAM_INTERRUPTED
        local isRangedSuccessful    = action.category == CATEGORY_RANGED_END
        local isRangedComplete      = isRangedInterrupted or isRangedSuccessful

        if isSelf then
            if isSpellStart then
                if isSelf then     
                    globals.isSpellCasting = true
                    globals.currentSpell = nil
                    globals.spellTarget = nil
                end

                local actionTarget = action.targets and action.targets[1]

                if actionTarget then
                    local targetId = actionTarget.id
                    if targetId then
                        globals.spellTarget = windower.ffxi.get_mob_by_id(targetId)
                    end

                    local spellId = actionTarget.actions and actionTarget.actions[1] and actionTarget.actions[1].param
                    local spell = spellId and resources.spells[spellId]

                    globals.currentSpell = spell
                end

                if globals.currentSpell then
                    actionStateManager:setSpellStart(globals.currentSpell)

                    local message = 'Casting %s':format(text_spell(globals.currentSpell.name, Colors.verbose))
                    if globals.spellTarget then
                        message = '%s %s %s':format(message, CHAR_RIGHT_ARROW, text_target(globals.spellTarget.name, Colors.verbose))
                    end
                    writeVerbose(message)
                else
                    writeVerbose('Casting has started')
                end

            elseif globals.isSpellCasting and isSpellCastingComplete then
                actionStateManager:setSpellCompleted(isSpellInterrupted)

                if not isSpellSuccessful then
                    writeVerbose('  %s has %s!':format(
                        globals.currentSpell and (text_spell(globals.currentSpell.name, Colors.verbose)) or 'Casting',
                        text_red('been interrupted')
                    ))
                else
                    if globals.spellTarget and globals.currentSpell then
                        local first_action = action.targets and
                            action.targets[1] and
                            action.targets[1].actions and
                            action.targets[1].actions[1]
                        local damage = first_action and first_action.param
                        local message_id = first_action and first_action.message
                        local message = message_id and resources.action_messages[message_id] and resources.action_messages[message_id].en
                        local fields = fieldsearch(message)

                        local damage_text = nil
                        if damage then                            
                            if fields.status then
                                local status = resources.buffs[damage]
                                if status then
                                    damage_text = '(' .. text_buff(status.name) .. ')'
                                end
                            elseif string.find(message or '', 'resists the spell') then
                                damage_text = ''
                            else
                                if damage > 0 then
                                    damage_text = 'for %s%s':format(
                                        text_number(compress_number(damage), Colors.verbose),
                                        string.find(message or '', 'Magic Burst!') and text_green(' Magic Burst!') or ''
                                    )
                                end
                            end
                        end

                        --writeJsonToFile('data/spells/%d_%s_on_%s.json':format(os.clock(), globals.currentSpell.name, globals.spellTarget.name), action)

                        writeVerbose('  Completed! %s %s %s %s':format(
                                text_spell(globals.currentSpell.name, Colors.verbose),
                                CHAR_RIGHT_ARROW,
                                text_target(globals.spellTarget.name, Colors.verbose),
                                damage_text or ''
                            ))
                    end
                end
                
                globals.isSpellCasting = false
                globals.currentSpell = nil
                globals.spellTarget = nil
            end
        else
            if isSpellStart then
                local actionTarget = action.targets and action.targets[1]
                local target = nil
                local spell = nil

                if actionTarget then
                    local targetId = actionTarget.id
                    if targetId then
                        target = windower.ffxi.get_mob_by_id(targetId)
                    end

                    local spellId = actionTarget.actions and actionTarget.actions[1] and actionTarget.actions[1].param
                    spell = spellId and resources.spells[spellId]
                end

                if spell and target then
                    -- writeMessage('%s casting spell %s':format(
                    --     text_mob(actor.name),
                    --     text_spell(spell.name)
                    -- ))
                    actionStateManager:setOthersSpellStart(spell, actor, target)
                end
            elseif isSpellCastingComplete then
                -- writeMessage('%s\'s casting %s!':format(
                --     text_mob(actor.name),
                --     isSpellInterrupted and text_red('interrupted') or text_green('completed')
                -- ))
                actionStateManager:setOthersSpellCompleted(actor, isSpellInterrupted)
            end
        end

        -- NOTE: For now, ranged tracking is only for self
        if isSelf then
            if isRangedStart then
                actionStateManager:markRangedAttackStart()
            elseif isRangedComplete then
                actionStateManager:markRangedAttackCompleted(isRangedSuccessful)
            end
        end
    end
end)

---------------------------------------------------------------------
-- Job change
windower.register_event('job change', function()
    actionStateManager:setMeritPointInfo(0, 0, 0)
    actionStateManager:setCapacityPointInfo(0, 0)

    reloadSettings()
end)

---------------------------------------------------------------------
-- Addon command
windower.register_event('addon command', function (command, ...)
    local args = {...}
    
    for i, arg in ipairs(args) do
        if type(arg) == 'table' then
            local message = string.format(
                'Command [%s] called with argument %d as a table value. Value=%s',
                command,
                i,
                json.stringify(arg))
            writeMessage(message)
            print(message)
        end
    end

    commands.process(command, args)
end)

-- Call from the incoming chunk event, with the data from event 0x076 (party buff update message)
local function parse_party_buffs(data)
    local members = {}

    for  k = 0, 4 do
        local memberId = data:unpack('I', k*48+5)
        
        if memberId ~= 0 then
            members[memberId] =  { }
            for i = 1, 32 do
                local buffId = data:byte(k*48+5+16+i-1) + 256*( math.floor( data:byte(k*48+5+8+ math.floor((i-1)/4)) / 4^((i-1)%4) )%4) -- Credit: Byrth, GearSwap

                if resources.buffs[buffId] and not members[memberId][buffId] then
                    local count = #members[memberId]
                    members[memberId][count + 1] = buffId
                end
            end
        end
    end

    -- Sample response format:
    -- {
    --   "689675": [ 249, 255, 253, 40 ],
    --   "688767": [ 255 ]
    -- }

    return members
end

-- 
-- Removes tracking data of (beneficial) buffs from the specified mob.
-- NOTE: Does not actually remove buffs, just the tracking data for them.
local function removeTrackedBuffs(mob)
    local is_enemy = (mob.spawn_type == SPAWN_TYPE_MOB) and true or false
    local count = 0
    local total = 0

    local info = actionStateManager:getBuffInfoForMob(mob.id)
    for i, details in pairs(info.details) do
        if details.actor then
            local is_actor_enemy = (details.actor.spawn_type == SPAWN_TYPE_MOB) and true or false

            -- Beneficial buffs are those with statuses applied by actors of like type. A bit naive,
            -- but it's easy and will work for the majority of cases. 
            -- TODO: Investigate pets here.
            if is_actor_enemy == is_enemy then
                actionStateManager:setMobBuff(mob, details.buffId, false)
                count = count + 1
            end
        end

        total = total + 1
    end

    if count > 0 then
        writeComment('Buffs already removed. Untracking %s of %s buffs from %s!':format(
            text_number(count, Colors.comment),
            text_number(total, Colors.comment),
            text_mob(mob.name, Colors.comment)
        ))
    end
end

-- 
-- Removes tracking data of (detremental) debuffs from the specified mob.
-- NOTE: Does not actually remove debuffs, just the tracking data for them.
local function removeTrackedDebuffs(mob)
    local is_enemy = (mob.spawn_type == SPAWN_TYPE_MOB) and true or false
    local count = 0
    local total = 0

    local info = actionStateManager:getBuffInfoForMob(mob.id)
    for i, details in pairs(info.details) do
        if details.actor then
            local is_actor_enemy = (details.actor.spawn_type == SPAWN_TYPE_MOB) and true or false

            -- Detremental debuffs are those with statuses applied by actors of like type. A bit naive,
            -- but it's easy and will work for the majority of cases. 
            -- TODO: Investigate pets here.
            if is_actor_enemy ~= is_enemy then
                actionStateManager:setMobBuff(mob, details.buffId, false)
                count = count + 1
            end

            total = total + 1
        end
    end

    if total > 0 then
        writeComment('Untracking %s / %s debuffs from %s!':format(
            text_number(count, Colors.comment),
            text_number(total, Colors.comment),
            text_mob(mob.name, Colors.comment)
        ))
    end
end

local function reaction_statusRemoval(action, actor, target, reaction, param)
    -- Successful:  Reaction = 0, Param = <buff-id>
    -- No effect:   Reaction = 0, Param = 0
    -- Resisted:    Reaction = 1, Param = 0
    if reaction == 0 then
        if param == 0 then
            -- R0, P0: No effect to remove; clear buff info

            local is_actor_enemy = (actor.spawn_type == SPAWN_TYPE_MOB) and true or false
            local is_enemy = (target.spawn_type == SPAWN_TYPE_MOB) and true or false

            if is_enemy ~= is_actor_enemy then
                -- When the actor is of a different category than the target, this is a buff removal (e.g. Dispel)
                removeTrackedBuffs(target)
            else
                -- When the actor is of the same category as the target, this is a debuff removal(e.g. Erase)
                removeTrackedDebuffs(target)
            end
        else
            -- R0, P<buffId>: Successful removal of <param> buff
            
            local buff = resources.buffs[param or 0]
            if buff then                
                actionStateManager:setMobBuff(target, buff.id, false)

                writeVerbose('%s\'s %s (%s) effect was removed by %s':format(
                    text_mob(target.name, Colors.verbose),
                    text_spell(buff.name, Colors.verbose),
                    text_number(buff.id, Colors.verbose),
                    text_mob(actor and actor.name or '???', Colors.verbose)
                ))
            end
        end
    else
        -- R1, P0: Resisted. No-op, as the buff is still present.

        writeVerbose('%s resisted %s\'s %s!':format(
            text_mob(target.name, Colors.verbose),
            text_mob(actor and actor.name or '???', Colors.verbose),
            text_spell(action.name, Colors.verbose)
        ))
    end
end

local function reaction_statusAddition(action, actor, target, reaction, param, buffId, rawPacket)
    -- Successful:  Reaction = 0, Param = <buff-id>
    -- No effect:   Reaction = 1, Param = 0
    -- Resisted:    Reaction = 1, Param = <buff-id>

    local buff = buffId and resources.buffs[buffId]

    if reaction == 1 then
        if param == 0 then
            -- R1, P0: No effect, already present or unsettable due to conflicting buff.

            -- We'll create a new "pseudo-tracking" entry for this buff. It'll be a short-lived timer,
            -- applied by the actor of this event. It will have the byMe flag as false to ensure that
            -- it doesn't stick around past the timer expiry.
            if buff then
                local buffs = actionStateManager:getRawBuffsForMob(target.id)
                if not arrayIndexOf(buffs, buff.id) then
                    actionStateManager:setMobBuff(
                        target,
                        buff.id,
                        true,
                        math.min(60, action.duration or 60),
                        false,
                        actor
                    )

                    writeVerbose('%s\'s %s on %s had %s!':format(
                        text_mob(actor.name, Colors.verbose),
                        text_spell(action.name, Colors.verbose),
                        text_mob(target.name, Colors.verbose),
                        text_red('no effect', Colors.verbose)
                    ))
                end
            end

        else
            -- NOTE: For landed monster ability (Sticky Thread):
            --  - Reaction: 24+
            --  - Param: 13 (slow)

            -- R1, P0: Buff resisted. Remove it if present.
            if buff then
                actionStateManager:setMobBuff(target, buff.id, false)

                writeVerbose('%s %s %s\'s %s!':format(
                    text_mob(target.name, Colors.verbose),
                    text_red('resisted', Colors.verbose),
                    text_mob(actor.name, Colors.verbose),
                    text_spell(action.name, Colors.verbose)
                ))
            end
        end
    elseif param > 0 then
        -- R0, P<buff-id>: Buff applied successfully, add or update it.

        local me = windower.ffxi.get_mob_by_target('me')
        actionStateManager:setMobBuff(
            target,
            buff.id,
            true,
            action.duration or 60,
            actor.id == me.id,
            actor
        )

        -- writeJsonToFile('data/add-status/%d_%s_%s_on_%s.json':format(
        --     os.clock(),
        --     actor.name,
        --     buff.name,
        --     target.name
        -- ), rawPacket)

        writeComment('%s %s %s from %s\'s %s!':format(
            text_mob(target.name, Colors.comment),
            text_green('received', Colors.comment),
            text_spell(buff.name, Colors.comment),
            text_mob(actor.name, Colors.comment),
            text_spell(action.name, Colors.comment)
        ))
    end
end

---------------------------------------------------------------------
-- Finds the number associated with the specified target id
-- in a packet (Target 1 ID: 654321)
local function findPacketTargetNumber(packet, targetId)
    for i = 1, 32 do
        local targetKey = 'Target %d ID':format(i)
        if packet[targetKey] == nil then return end
        if packet[targetKey] == targetId then return i end
    end
end

local _handle_partyBuffsChunk = function (id, data)
    local partyBuffs = parse_party_buffs(data)
    actionStateManager:setMemberBuffs(partyBuffs)
end

local _handle_actionChunk = function(id, data)
    local packet = packets.parse('incoming', data)

    local count = tonumber(packet['Target Count']) or 0
    if count < 1 then return end

    local me = windower.ffxi.get_mob_by_target('me')

    -- Note: For now, we can only reliably track buffs on trusts if they were set by ourselves. This is
    -- because trusts don't send us messages when they lose effects we weren't responsible for.
    local actorId = tonumber(packet['Actor']) or 0
    --if actorId <= 0 or actorId ~= me.id then return end
    if actorId <= 0 then return end

    local actionId = tonumber(packet['Param']) or 0
    if actionId <= 0 then return end

    local category = tonumber(packet['Category']) or 0

    local actor = windower.ffxi.get_mob_by_id(actorId)
    local action = nil
    local actionStatus = nil
    local statusReaction = nil
    local buffId = nil
    local duration = nil
    local isRemoval = false
    local isDispel = false
    local isErase = false

    -- Certain buffs can be automatically removed if we see activity from the actor
    if actor and (actor.spawn_type == SPAWN_TYPE_MOB or actor.spawn_type == SPAWN_TYPE_TRUST) then
        actionStateManager:clearMobBuff(actor, BUFF_SLEEP1)
        actionStateManager:clearMobBuff(actor, BUFF_TERROR)
        actionStateManager:clearMobBuff(actor, BUFF_PETRIFIED)
    end

    if
        category == 4   -- Category 4 means this was a spell        
    then
        action = resources.spells[actionId]
        buffId = tonumber(action.status) or 0
        
        if action then
            isDispel    = arrayIndexOf(meta.dispel.spells, action.id)
            isErase     = arrayIndexOf(meta.erase.spells, action.id)

            -- Try to identify whether this is a weapon skill-like spell
            if
                actor and
                actor.id and
                actor.in_party
            then
                local context = actionStateManager:getContext()
                if
                    context and
                    context.party1_by_id and
                    context.party1_by_id[actor.id]
                then
                    local member = context.party1_by_id[actor.id]
                    if
                        member and
                        type(member.hasBuff) == 'function'
                    then
                        local chain_ability = nil
                        local ws_action = action
                        if
                            member.hasBuff(470) and
                            action.type == 'BlackMagic'
                        then
                            local category = meta.immanence:category_of(action.name)
                            if category then
                                local base_spell = findSpell(category)
                                if base_spell then
                                    ws_action = base_spell
                                end

                                chain_ability = resources.job_abilities[317] -- Immanence (SCH)
                            end
                        elseif member.hasBuff(164) and action.type == 'BlueMagic' and action.element then
                            chain_ability = resources.job_abilities[94] -- Chain Affinity (BLU)
                        end

                        if chain_ability then
                            local targetId = tonumber(packet['Target 1 ID':format(i)]) or 0
                            local target = windower.ffxi.get_mob_by_id(targetId)

                            if 
                                target and
                                target.valid_target and
                                target.spawn_type == SPAWN_TYPE_MOB
                            then
                                -- These are spells that act as skillchain openers
                                setPartyWeaponSkill(actor, ws_action, target)

                                writeVerbose('%s: %s %s %s':format(
                                    text_player(actor.name, Colors.verbose),
                                    text_weapon_skill('%s: %s':format(chain_ability.name, ws_action.name), Colors.verbose),
                                    CHAR_RIGHT_ARROW,
                                    text_mob(target.name)
                                ))
                            end
                        end
                    end
                end
            end
        end
    elseif
        category == 14  -- Unblinkable job abilities
    then
        action = resources.job_abilities[actionId]
        buffId = tonumber(action.status) or 0

        if action then
            isDispel    = arrayIndexOf(meta.dispel.job_abilities, action.id)
            isErase     = arrayIndexOf(meta.erase.job_abilities, action.id)
        end
    elseif
        category == 5   -- Category 4 means item
    then
        action = resources.items[actionId]
        statusReaction = 8
    elseif
        category == 11  -- Category 11 means monster weapon skill
    then
        action = resources.monster_abilities[actionId]
        if action then
            -- writeDebug('Mosnter ability %s (%s) detected!':format(
            --     text_spell(action.name, Colors.debug),
            --     text_number(action.id, Colors.debug)
            -- ))

            -- Monster abilities generally don't list their status effect, unfortunately
            if action.status then
                buffId = tonumber(action.status)
            end

            -- First, try to find this ability in the additional tracked metadata table for monster abilities
            if not buffId then
                local ma_meta = meta.monster_abilities[action.id]
                if ma_meta then
                    buffId = ma_meta.statuses and ma_meta.statuses[1]
                    -- writeDebug('Found monster ability meta for %s, which applies buff %s':format(
                    --     text_spell(action.name, Colors.debug),
                    --     text_number(buffId or -1, Colors.debug)
                    -- ))
                end
            end

            -- If we didn't get a buff id at this point, we can see if this ability has an 
            -- associated BLU spell. We'll borrow the status data from that if present.
            if not buffId then
                local spell = findSpell(action.name)
                if spell then
                    buffId = tonumber(spell.status)
                    if buffId then 
                        action = spell
                    end
                end
            end
        end
    end

    isRemoval = isDispel or isErase
    
    local firstTarget = nil
    local targetCount = 0

    if action then
        for i = 1, count do
            local targetId = tonumber(packet['Target %d ID':format(i)]) or 0
            local target = windower.ffxi.get_mob_by_id(targetId)

            -- We only track this event for trusts in our party. Actual player
            -- buffs are tracked in a better way via event 0x076.
            if
                target and
                target.valid_target
            then
                -- Store the first target
                firstTarget = firstTarget or target
                targetCount = targetCount + 1

                if
                    (target.spawn_type == SPAWN_TYPE_TRUST or target.spawn_type == SPAWN_TYPE_MOB)
                then
                    local message = tonumber(packet['Target %d Action 1 Message':format(i)]) or 0
                    local reaction = tonumber(packet['Target %d Action 1 Reaction':format(i)]) or 0
                    local param = tonumber(packet['Target %d Action 1 Param':format(i)]) or 0

                    -- Handle removal operations; dispel, erase, -na spells, etc
                    if isRemoval then

                        if isDispel or isErase then
                            reaction_statusRemoval(action, actor, target, reaction, param)
                        end

                        -- We're done if this is a removal operation. We won't try to add buffs.
                        return
                    end
                    
                    -- If the buff id is still nil, see if there's some other way to sort it out
                    if 
                        buffId == nil
                    then
                        -- Some actions use a reaction to indicate whether a status was applied. If the actual
                        -- reaction matches the status-indicator reaction for this action, try using that.
                        if reaction == statusReaction then
                            buffId = param
                        end
                    end

                    if buffId and buffId > 0 then
                        reaction_statusAddition(action, actor, target, reaction, param, buffId, packet)
                    end
                end
            end
        end
    end
    
    if
        category == 6 or    -- Job Ability
        category == 14      -- Unblinkable job ability
    then
        local ability = resources.job_abilities[actionId]
        if ability then
            if 
                ability.type == 'CorsairRoll'
            then
                local player = windower.ffxi.get_player()
                local targetNumber = findPacketTargetNumber(packet, player.id)
                local count = targetNumber and tonumber(packet['Target %d Action 1 Param':format(targetNumber)])

                if 
                    count and
                    actor and
                    (actor.in_party or actor.id == player.id)
                then
                    writeMessage('%s: %s %s %s':format(
                        text_player(actor.name),
                        text_buff(ability.name),
                        CHAR_RIGHT_ARROW,
                        text_number(tostring(count))
                    ))

                    actionStateManager:setRollCount(ability.id, count)
                end
            elseif
                ability.id == 177   -- Snake Eye
            then
                actionStateManager:applySnakeEye()
            elseif
                ability.id == 209 or    -- Wild Flourish
                ability.id == 320       -- Konzen-ittai
            then
                if 
                    actor and 
                    actor.in_alliance and
                    firstTarget
                then
                    -- These are abilities that act as skillchain openers.
                    setPartyWeaponSkill(actor, ability, firstTarget)

                    writeVerbose('%s: %s %s %s %s':format(
                        text_player(actor.name, Colors.verbose),
                        text_weapon_skill(ability.name, Colors.verbose),
                        CHAR_RIGHT_ARROW,
                        text_mob(firstTarget.name),
                        text_red('Chainbound!', Colors.verbose)
                    ))
                end
            elseif
                actor and
                actor.id == me.id and (
                    ability.id == 233   -- Sublimation
                )
            then
                actionStateManager:markTimedAbility(ability, target)
            end
        end
    end
end

local _handle_actionMessageChunk = function(id, data)
    local packet = packets.parse('incoming', data)

    -- Expiring actions

    local targetId = tonumber(packet['Target']) or 0
    local message = tonumber(packet['Message']) or 0
    local target = windower.ffxi.get_mob_by_id(targetId)

    if 
        target and
        target.valid_target and
        (target.spawn_type == SPAWN_TYPE_MOB or target.spawn_type == SPAWN_TYPE_TRUST) and
        (
            message == 206 or   -- These are the message codes for effects wearing off or being removed.
            message == 204 or   --  Refer to: https://github.com/Windower/Lua/wiki/Message-IDs
            message == 321 or
            message == 322 or
            message == 426 or
            message == 427
        )
    then
        local buffId = tonumber(packet['Param 1'] or 0)
        if buffId > 0 then
            local buff = resources.buffs[buffId]

            if buff then
                actionStateManager:setMobBuff(target, buffId, false)

                if settings.verbosity >= VERBOSITY_DEBUG then
                    writeDebug('%s\'s %s effect wore off.':format(
                        text_mob(target.name, Colors.debug),
                        text_spell(buff.name, Colors.debug),
                        text_number(buff.id, Colors.debug)
                    ))
                end
            end
        end
    end
end

local _handle_limitCapacityChunk = function(id, data)
    local packet = packets.parse('incoming', data)

    if packet['Order'] == 2 then
        local limitPoints = packet['Limit Points']
        local numMerits = packet['Merit Points']
        local maxMerits = packet['Max Merit Points']

        -- writeMessage('Limit Event: MERITS=%d, MAX=%d, LIMITS=%d':format(
        --     numMerits,
        --     maxMerits,
        --     limitPoints
        -- ))

        actionStateManager:setMeritPointInfo(numMerits, maxMerits, current)
    elseif packet['Order'] == 5 then
        local player = windower.ffxi.get_player()
        if player then
            local job = player.main_job_full
            local numCapacityPoints = packet[job..' Capacity Points']
            local numJobPoints = packet[job..' Job Points']

            -- writeMessage('Capacity Event: CP=%d, JP=%d':format(
            --    numCapacityPoints,
            --    numJobPoints
            -- ))

            actionStateManager:setCapacityPointInfo(numCapacityPoints, numJobPoints)
        end
    end
end

---------------------------------------------------------------------
-- Incoming chunks (chunks are individual pieces of a packet)
windower.register_event('incoming chunk', function (id, data)
    if
        id == 0x076     -- Party buffs update
    then
        _handle_partyBuffsChunk(id, data)
    elseif 
        id == 0x028     -- Action (Tracks incoming spells, abilities, etc)
    then
        _handle_actionChunk(id, data)
    elseif
        id == 0x029     -- Action message (tracks expiring effects, etc)
    then
        _handle_actionMessageChunk(id, data)
    elseif
        id == 0x063     -- Limit Point and Capacity Point updates
    then
        _handle_limitCapacityChunk(id, data)
    end
end)