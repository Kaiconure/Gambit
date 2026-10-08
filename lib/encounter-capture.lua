-- Opt-in Plouton diagnostics. No packet or message is assumed to indicate a proc.
local capture = {}
local weakness = require('./lib/elemental-weakness')
local handle, path
local bytes, sequence = 0, 0
local LIMIT = 32 * 1024 * 1024
local CONFIRM_SECONDS = 20
local state = {}
local cycle = {enabled=false, index=1, interval=8, next_at=0}
local probes = {
    {element='fire', spell='Fire'}, {element='ice', spell='Blizzard'},
    {element='wind', spell='Aero'}, {element='earth', spell='Stone'},
    {element='thunder', spell='Thunder'}, {element='water', spell='Water'},
}
local elements = {fire=true, ice=true, wind=true, earth=true, thunder=true,
    water=true, light=true, dark=true}
local packetIds = {[0x028]=true, [0x029]=true, [0x02A]=true,
    [0x036]=true, [0x038]=true, [0x039]=true}

local function reset()
    state = {}
end

local function close()
    if handle then pcall(handle.close, handle) end
    handle = nil
    cycle.enabled = false
    cycle.target_id = nil
    reset()
end

local function record(kind, data)
    if not handle then return end
    local ok, err = pcall(function()
        local info = windower.ffxi.get_info() or {}
        local row = {kind=kind, sequence=sequence+1, time=os.time(), clock=os.clock(), zone=info.zone, data=data}
        local line = json.stringify(row) .. '\n'
        if bytes + #line > LIMIT then error('32 MiB session limit reached') end
        assert(handle:write(line))
        bytes = bytes + #line
        sequence = sequence + 1
        if sequence % 50 == 0 or kind ~= 'packet' then assert(handle:flush()) end
    end)
    if not ok then
        close()
        writeMessage('Encounter capture stopped: ' .. tostring(err))
    end
end

local function target()
    local mob = windower.ffxi.get_mob_by_name('Plouton')
    if mob and mob.valid_target and mob.hpp > 0 then return mob end
end

function capture.getState()
    local mob = target()
    if not handle or not mob or state.target_id ~= mob.id then reset() end
    if state.expires and os.time() >= state.expires then
        record('state_expired', {target_id=state.target_id})
        reset()
    end
    -- Return a snapshot, not mutable internal state. Never grants permission to attack.
    return {active=handle ~= nil, target_id=mob and mob.id,
        weakness_known=state.element ~= nil, weak_element=state.element,
        source=state.element and (state.source or 'manual') or 'unknown', expires=state.expires}
end

function capture.start()
    if handle then return 'Capture already running: ' .. path end
    local player = windower.ffxi.get_player()
    if not player then return 'Log in before starting capture.' end
    local relativeDirectory = '.data/encounter-capture/'
    local directory = windower.addon_path .. relativeDirectory
    local ok, err = files.create_path(relativeDirectory)
    if not ok then return 'Cannot create capture directory: ' .. tostring(err) end
    local name = player.name:gsub('[^%w_-]', '_')
    local stem = directory .. name .. '-plouton-' .. os.date('%Y%m%d-%H%M%S')
    local suffix = 0
    repeat
        path = stem .. '-' .. suffix .. '.jsonl'
        local existing = io.open(path, 'r')
        if not existing then break end
        existing:close()
        suffix = suffix + 1
    until false
    handle, err = io.open(path, 'w')
    if not handle then return 'Cannot open capture: ' .. tostring(err) end
    bytes, sequence = 0, 0
    reset()
    record('start', {character=player.name, schema=1, manual_confirmation_seconds=CONFIRM_SECONDS})
    if not handle then return 'Capture could not start.' end
    return 'Capture started: ' .. path
end

function capture.stop(reason)
    if not handle then return 'Capture is not running.' end
    record('stop', {reason=reason or 'manual'})
    close()
    return 'Capture saved: ' .. path
end

function capture.probeDue()
    return handle ~= nil and cycle.enabled and os.time() >= cycle.next_at
end

-- Called by the BLM profile, not an independent coroutine. Normal action scheduling
-- still controls execution. An annotation records an attempt, not a confirmed hit.
function capture.probe(context)
    if not capture.probeDue() then return end
    if not context.me or context.me.main_job ~= 'BLM' then return end
    cycle.next_at = os.time() + cycle.interval
    local mob = context.findByName('Plouton')
    if not mob or mob.hpp <= 0 or not mob.has_claim then
        record('probe_wait', {reason='No live party-claimed Plouton'})
        return
    end
    if cycle.target_id and cycle.target_id ~= mob.id then
        cycle.enabled = false
        record('cycle_stopped', {reason='target changed', target_id=mob.id})
        return
    end
    cycle.target_id = mob.id
    local current = capture.getState()
    local probe = probes[cycle.index]
    if cycle.adaptive and cycle.candidate then
        for _,entry in ipairs(probes) do
            if entry.element == cycle.candidate then probe=entry;break end
        end
        cycle.candidate = nil
    end
    if cycle.adaptive and current.source == 'message_8495' and current.weakness_known then
        for _,entry in ipairs(probes) do
            if entry.element == current.weak_element then
                probe = {element=entry.element,spell=entry.spell .. ' IV'}
                break
            end
        end
    end
    cycle.index = cycle.index % #probes + 1
    if not context.canUseSpell(probe.spell) then
        record('probe_skipped', {spell=probe.spell, element=probe.element, target_id=mob.id,
            reason='Spell unavailable'})
        return
    end
    record('probe_attempt', {spell=probe.spell, spell_id=context.spell and context.spell.id,
        adaptive=cycle.adaptive == true, confirmation=current.source,
        element=probe.element, target_id=mob.id, hpp=mob.hpp})
    -- A recording failure must stop probes as well.
    if handle and cycle.enabled then return context.useSpell(mob) end
end

function capture.command(args)
    local operation = (args[1] or 'status'):lower()
    if operation == 'start' then return capture.start() end
    if operation == 'stop' then return capture.stop() end
    if operation == 'cycle' or operation == 'adaptive' then
        if args[2] == 'off' then
            cycle.enabled = false
            record('cycle_stopped', {reason='manual'})
            return 'Probe cycle stopped (an in-flight spell is not cancelled).'
        end
        if args[2] ~= 'on' then return 'Usage: gbt capture cycle on [seconds] | off' end
        local player = windower.ffxi.get_player()
        if not player or player.main_job ~= 'BLM' then return 'Start the probe cycle on the BLM client.' end
        if not handle then return 'Start capture first: gbt capture start' end
        if operation == 'adaptive' and (windower.ffxi.get_info() or {}).zone ~= 277 then
            return 'Adaptive rules are verified only for Plouton in Ra\'Kaznar Turris (277).'
        end
        local interval = 8
        if args[3] ~= nil then interval = tonumber(args[3]) end
        if not interval or interval ~= interval or interval < 5 or interval > 60 then
            return 'Probe interval must be 5 to 60 seconds.'
        end
        cycle = {enabled=true, index=1, interval=interval, next_at=0,adaptive=operation=='adaptive'}
        reset()
        record('cycle_started', {interval=interval})
        return (cycle.adaptive and 'Adaptive elemental routine' or 'Tier-I probe cycle') ..
            ' enabled; requires the Plouton BLM profile and enabled automation.'
    end
    if operation == 'status' then
        local current = capture.getState()
        return 'Capture: ' .. (current.active and path or 'off') ..
            '; weakness: ' .. (current.weak_element or 'unknown') .. ' (' .. current.source .. ')' ..
            '; routine: ' .. (cycle.enabled and ((cycle.adaptive and 'adaptive' or 'collection') .. ', ' .. cycle.interval .. 's') or 'off')
    end
    if operation == 'mark' or operation == 'unknown' or operation == 'element' then
        if not handle then return 'Start capture first: gbt capture start' end
        local mob = target()
        local label = table.concat(args, ' ', 2)
        if operation == 'element' then
            local element = (args[2] or ''):lower()
            if not elements[element] then return 'Specify fire, ice, wind, earth, thunder, water, light, or dark.' end
            if not mob then return 'No live Plouton found; weakness remains unconfirmed.' end
            state = {target_id=mob.id, element=element, expires=os.time()+CONFIRM_SECONDS}
        elseif operation == 'unknown' then reset() end
        record('manual_' .. operation, {label=label, target_id=mob and mob.id, hpp=mob and mob.hpp})
        return 'Recorded ' .. operation .. ': ' .. label
    end
    return 'Usage: gbt capture start|stop|status|cycle on [seconds]|adaptive on [seconds]|cycle off|mark <note>|element <element>|unknown'
end

windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)
    if not handle or injected or not packetIds[id] then return end
    -- Preserve original bytes so future decoders can inspect signals not yet understood.
    local hex = data:gsub('.', function(c) return string.format('%02X', string.byte(c)) end)
    local mob = target()
    record('packet', {id=id, hex=hex, blocked=blocked == true,
        target_id=mob and mob.id, hpp=mob and mob.hpp})
    if not handle or not cycle.adaptive or not cycle.enabled or not mob then return end
    local zone=(windower.ffxi.get_info() or {}).zone
    local event
    if id == 0x02A then
        event=weakness.message(data,zone,mob)
    elseif id == 0x028 then
        local ok,action=pcall(windower.packets.parse_action,data)
        if ok and action then event=weakness.action(action,zone,mob,resources.spells,state.element) end
    end
    if event then
        reset()
        cycle.candidate=event.kind=='inferred' and event.element or nil
        if event.kind=='confirmed' then
            state={target_id=mob.id,element=event.element,source=event.source,
                expires=os.time()+CONFIRM_SECONDS}
        end
        record('weakness_'..event.kind,event)
    end
end)

windower.register_event('incoming text', function(original, modified, originalMode, modifiedMode, blocked)
    if handle then
        record('text', {text=original, mode=originalMode, blocked=blocked == true})
    end
end)

windower.register_event('zone change', function() capture.stop('zone change') end)
windower.register_event('logout', function() capture.stop('logout') end)
windower.register_event('unload', function() capture.stop('unload') end)

return capture
