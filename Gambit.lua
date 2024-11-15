__version = '0.91.4'
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
    autoFollowIndex = nil
}

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
    
    --if previous_id == STATUS_ENGAGED and new_id == STATUS_IDLE then
    if
        new_id == STATUS_IDLE
    then
        resetCurrentMob(nil, true)

        -- We'll unfollow once battle has ended to avoid the possibility of running
        -- off into space if autofollow was enabled
        windower.ffxi.follow(-1)
    elseif 
        new_id == 2 or  -- Dead
        new_id == 3 or  -- Dead while engaged
        new_id == 5 or  -- On a chocobo
        new_id == 85    -- On a mount that is not a chocobo
    then
        resetCurrentMob(nil, true)
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

    smartMove:setLogger(writeDebug)

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

            writeVerbose('  %s has %s!':format(
                globals.currentSpell and (text_spell(globals.currentSpell.name, Colors.verbose)) or 'Casting',
                isSpellSuccessful and text_green('completed successfully') or text_red('been interrupted')
            ))
            
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
    
    local action = nil
    local actionStatus = nil
    local statusReaction = nil
    local buffId = nil
    local duration = nil
    if
        category == 4   -- Category 4 means this was a spell        
    then
        action = resources.spells[actionId]
        buffId = tonumber(action.status) or 0
    elseif
        category == 14  -- Unblinkable job abilities
    then
        action = resources.job_abilities[actionId]
        buffId = tonumber(action.status) or 0
    elseif
        category == 5   -- Category 4 means item
    then
        action = resources.items[actionId]
        statusReaction = 8
    end

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

                if buffId == nil then
                    if reaction == statusReaction then
                        buffId = param
                    end
                end

                -- The param will be the buff id by default, unless the buff has a secondary effect (damage, etc).
                -- In the case of a secondary effect, the param will reflect that effect (the amount of HP taken, etc).
                -- If the buff did not land at all, the param will be 0.
                local canTrack = param > 0 and buffId > 0
                if canTrack then
                    local buff = resources.buffs[buffId]
                    if buff then
                        local duration = action.duration or 15
                        local byMe = actorId == me.id
                        
                        actionStateManager:setMobBuff(
                            target,
                            buffId,
                            true,
                            duration,
                            byMe
                        )

                        writeVerbose('Mob %s gained effect %s (%s)':format(
                            text_mob(target.name, Colors.verbose),
                            text_spell(buff.name, Colors.verbose),
                            text_number(buff.id, Colors.verbose),
                            duration and tostring(duration) or '--'
                        ))
                    end
                end
            end
        end
    end
end

local _handle_actionMessageChunk = function(id, data)
    local packet = packets.parse('incoming', data)

    -- Expiring actions

    local targetId = tonumber(packet['Target']) or 0
    local target = windower.ffxi.get_mob_by_id(targetId)

    if 
        target and
        target.valid_target and
        (target.in_party or target.in_alliance) and
        (target.spawn_type == SPAWN_TYPE_TRUST or target.spawn_type == SPAWN_TYPE_MOB)
    then
        local buffId = tonumber(packet['Param 1'] or 0)
        if buffId > 0 then
            local buff = resources.buffs[buffId]

            if buff then
                actionStateManager:setMobBuff(target, buffId, false)

                writeVerbose('Mob %s lost %s (%s)':format(
                    text_mob(target.name, Colors.verbose),
                    text_spell(buff.name, Colors.verbose),
                    text_number(buff.id, Colors.verbose)
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