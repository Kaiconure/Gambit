__version = '0.95.0'
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
meta.dispel = require('./meta/dispel') or {}
meta.monster_abilities = require('./meta/monster_abilities') or {}
meta.trusts = require('./meta/trusts')
meta.jobs_with_mp = require('./meta/jobs_with_mp')

require('./lib/logging')
require('./lib/helpers')
require('./lib/settings')
require('./lib/resx')
require('./lib/eventing')
require('./lib/commands')
require('./lib/target-processing')

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

    -- Disable all the things
    sendSelfCommand('disable -quiet')
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

    windower.send_command('unbind !~G; bind !~G ' .. makeSelfCommand('toggle')) -- Use Shift+Alt+G to toggle automation

    windower.send_command('unbind @R; bind @R ' .. makeSelfCommand('run -start'))
    windower.send_command('unbind @~R; bind @~R ' .. makeSelfCommand('run -stop'))

    -- Store the current zone
    local info = windower.ffxi.get_info()
    globals.currentZone = info and info.zone > 0 and resources.zones[info.zone] or nil
    globals.language = info.language
    
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
    if action == nil or
        action.actor_id == nil or
        action.param == nil
    then
        return
    end

    local player    = windower.ffxi.get_player()
    local playerId  = player.id
    local actorId   = action.actor_id
    local isSelf    = actorId == playerId

    if isSelf then
        local isSpellStart              = action.category == CATEGORY_SPELL_START and action.param == PARAM_STARTED
        local isSpellInterrupted        = action.category == CATEGORY_SPELL_INTERRUPT and action.param == PARAM_INTERRUPTED
        local isSpellSuccessful         = action.category == CATEGORY_SPELL_END
        local isSpellCastingComplete    = isSpellInterrupted or isSpellSuccessful

        local isRangedStart         = action.category == CATEGORY_RANGED_START and action.param == PARAM_STARTED
        local isRangedInterrupted   = action.category == CATEGORY_RANGED_INTERRUPT and action.param == PARAM_INTERRUPTED
        local isRangedSuccessful    = action.category == CATEGORY_RANGED_END
        local isRangedComplete      = isRangedInterrupted or isRangedSuccessful

        if isSpellStart then            
            globals.isSpellCasting = true
            globals.currentSpell = nil
            globals.spellTarget = nil

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

            -- writeVerbose('  %s has %s':format(
            --     globals.currentSpell and (text_spell(globals.currentSpell.name, Colors.verbose)) or 'Casting',
            --     isSpellSuccessful and text_green('completed') or text_red('been interrupted')
            -- ))

            if not isSpellSuccessful then
                writeVerbose('  %s has %s!':format(
                    globals.currentSpell and (text_spell(globals.currentSpell.name, Colors.verbose)) or 'Casting',
                    text_red('been interrupted')
                ))
            end
            
            globals.isSpellCasting = false
            globals.currentSpell = nil
            globals.spellTarget = nil
        end

        if isRangedStart then
            actionStateManager:markRangedAttackStart()
        elseif isRangedComplete then
            actionStateManager:markRangedAttackCompleted(isRangedSuccessful)
        end
    end
end)

---------------------------------------------------------------------
-- Job change
windower.register_event('job change', function()
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
        writeVerbose('Buffs already removed. Untracking %s of %s buffs from %s!':format(
            text_number(count, Colors.verbose),
            text_number(total, Colors.verbose),
            text_mob(mob.name, Colors.verbose)
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
        writeDebug('Untracking %s / %s debuffs from %s!':format(
            text_number(count),
            text_number(total),
            text_mob(mob.name, Colors.debug)
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
            removeTrackedBuffs(target)
        else
            -- R0, P<buffId>: Successful removal of <param> buff
            
            local buff = resources.buffs[param or 0]
            if buff then                
                actionStateManager:setMobBuff(target, buff.id, false)

                writeDebug('%s\'s %s effect was removed by %s':format(
                    text_mob(target.name, Colors.debug),
                    text_spell(buff.name, Colors.debug),
                    text_mob(actor and actor.name or '???', Colors.debug)
                ))
            end
        end
    else
        -- R1, P0: Resisted. No-op, as the buff is still present.

        writeDebug('%s resisted %s\'s %s!':format(
            text_mob(target.name, Colors.debug),
            text_mob(actor and actor.name or '???', Colors.debug),
            text_spell(action.name, Colors.debug)
        ))
    end
end

local function reaction_statusAddition(action, actor, target, reaction, param, buffId)
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

                    writeDebug('%s\'s %s on %s had no effect!':format(
                        text_mob(actor.name, Colors.debug),
                        text_spell(action.name, Colors.debug),
                        text_mob(target.name, Colors.debug)
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

                writeDebug('%s resisted %s\'s %s!':format(
                    text_mob(target.name, Colors.debug),
                    text_mob(actor.name, Colors.debug),
                    text_spell(action.name, Colors.debug)
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

        writeDebug('%s received %s from %s\'s %s!':format(
            text_mob(target.name, Colors.debug),
            text_spell(buff.name, Colors.debug),
            text_mob(actor.name, Colors.debug),
            text_spell(action.name, Colors.debug)
        ))
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

    -- Certain buffs can be automatically removed if we see activity from the actor
    if actor and (actor.spawn_type == SPAWN_TYPE_MOB or actor.spawn_type == SPAWN_TYPE_PLAYER) then
        actionStateManager:setMobBuff(actor, BUFF_SLEEP1, false)
        actionStateManager:setMobBuff(actor, BUFF_SLEEP2, false)
        actionStateManager:setMobBuff(actor, BUFF_PETRIFIED, false)
    end

    if
        category == 4   -- Category 4 means this was a spell        
    then
        action = resources.spells[actionId]
        buffId = tonumber(action.status) or 0
        
        if action then
            isDispel = arrayIndexOf(meta.dispel.spells, action.id)
        end
    elseif
        category == 14  -- Unblinkable job abilities
    then
        action = resources.job_abilities[actionId]
        buffId = tonumber(action.status) or 0

        if action then
            isDispel = arrayIndexOf(meta.dispel.job_abilities, action.id)
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

    -- TODO: Change this later; for now, dispel is the only removal action we track
    isRemoval = isDispel

    if action then
        for i = 1, count do
            local targetId = tonumber(packet['Target %d ID':format(i)]) or 0
            local target = windower.ffxi.get_mob_by_id(targetId)

            -- We only track this event for trusts in our party. Actual player
            -- buffs are tracked in a better way via event 0x076.
            if
                target and
                target.valid_target and
                (target.spawn_type == SPAWN_TYPE_TRUST or target.spawn_type == SPAWN_TYPE_MOB) -- and
                --(actorId == me.id or target.spawn_type == SPAWN_TYPE_MOB)
            then
                local message = tonumber(packet['Target %d Action 1 Message':format(i)]) or 0
                local reaction = tonumber(packet['Target %d Action 1 Reaction':format(i)]) or 0
                local param = tonumber(packet['Target %d Action 1 Param':format(i)]) or 0

                -- Handle removal operations; dispel, erase, -na spells, etc
                if isRemoval then

                    if isDispel then
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
                    reaction_statusAddition(action, actor, target, reaction, param, buffId)
                end
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

                writeDebug('%s\'s %s effect wore off.':format(
                    text_mob(target.name, Colors.debug),
                    text_spell(buff.name, Colors.debug),
                    text_number(buff.id, Colors.debug)
                ))
            end
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
    end
end)