local function null_log() end
local function passthrough(...) return ... end

local smartMove = {
    started = false,
    latestJobId = 0,
    queue = { },
    previousJob = nil,
    current = nil,
    tolerance = 0.33,
    mob_positions = {},
    mob_positions_by_index = {},
    getMobById = windower.ffxi.get_mob_by_id,
    getMobByIndex = windower.ffxi.get_mob_by_index,

    log = null_log,
    debug = null_log
}


local Modes = {
    position = 'position',
    follow = 'follow',
    backstab = 'backstab'
}

local FORWARD           = V({1, 0})             -- The vector representing the point on the unit circle at 0 radians
local TWO_PI            = math.pi * 2           -- 2pi
local PI_OVER_TWO       = math.pi * 0.5         -- pi / 2

local JITTER_ENABLED    = true                  -- Configure if jittering is allowed at all
local JITTER_ANGLE      = PI_OVER_TWO * 1.50    -- The angle we'll try to escape obstacles with. This is equiavlent to 135 degrees.
local MAX_JITTER        = 3                     -- The maximum duration we'll spend jittering around obstacles

local HEADING_TOLERANCE = TWO_PI * 0.0125   -- 1.25% of a unit circle, or 4.5 degrees

local resources = require('resources')

local current_settings = {}

-- ======================================================================================
-- Helpers
-- ======================================================================================

-- Returns the average of the numeric values in an array.
local function arrayAverage(array)
    local total = 0
    local count = 0
    for i, val in ipairs(array) do
        total = total + val
        count = count + 1
    end

    if count > 0 then
        return total / count
    end

    return 0
end

-- Returns 1 or -1 randomly
local function randomSign()
    return (math.random(1, 2) == 1) and -1 or 1
end

-- Returns a random number between a and b
local function randomRange(a, b)
    -- If only one argument is provided, we'll set the range from 0 to the first argument
    if b == nil then
        b = a
        a = 0        
    end

    -- Properly order the inputs
    local min = math.min(a, b)
    local max = math.max(a, b)

    local range = max - min
    return (range * math.random()) + min
end

-- Return a unit angle [0, 2pi] equivalent to the one passed in
local function normalizeAngle(rad) 
    local width   = TWO_PI
    local offset  = rad

    return (offset - (math.floor(offset / width) * width))
end

-- Absolute distance between two radian angles
local function angularDistance(rad1, rad2)
    local delta = rad2 - rad1
    return math.abs(math.atan2(math.sin(delta), math.cos(delta)))
end

-- Determines the angle between vector and from. If from is ommitted,
-- the base forward vector <1, 0> is used.
local function vectorAngle(v, from)
    local len = v:length()
    if len == 0 then return 0 end

    v = v:normalize()
    from = (from or FORWARD):normalize()

    local dot = vector.dot(from, v)
    local det = (from[1] * v[2]) - (from[2] * v[1])

    local result = -math.atan2(det, dot)
    
    --if tostring(result) == 'nan' then return 0 end

    return result
end

-- Determines if the two angles share a halfspace. Assumes that they are based on "to" vectors
-- to a fixed point from a variable start position.
local function sharesHalfspace(heading1, heading2)
    return angularDistance(heading1, heading2) <= PI_OVER_TWO
end

-- Gets a position vector from the specified coordinate (x,y)
local function coordVector(coord)
    if coord and type(coord.x) == 'number' and type(coord.y) == 'number' then
        return V({coord.x, coord.y})
    end

    return nil
end

-- Find the point at the given distance and angle offset from the mob
local function findMobOffset(mob, angleOffset, distance)
    local player = windower.ffxi.get_mob_by_target('me')
    
    local vPlayer = V({player.x, player.y})
    local vMob = V({mob.x, mob.y})

    distance = (type(distance) == 'number') and distance or 2

    if not current_settings or not current_settings.useRawDistances then
        if not mob.model_size then
            mob = windower.ffxi.get_mob_by_id(mob.id)
        end

        if mob then
            local distance_offset = 
                (player.model_size or 0) +      -- Player model size
                (mob and mob.model_size or 0)   -- Mob model size
            distance = 
                distance + (distance_offset * 0.75)
        end
    end

    if type(angleOffset) == 'number' then
        -- When an angle offset was provided, we'll calculate that from the mob
        -- and scale it to the desired distance.
        local direction = mob.heading + angleOffset
        return vMob:add(vector.from_radian(direction):scale(distance))
    else
        -- Calculate the vector from the mob to me. This is the line we should take.
        -- Normalize it and scale by the travel distance, and added to the mob position
        -- that will give us the target location we're aiming for.
        local vOffset = vPlayer:subtract(vMob):normalize():scale(distance)
        return vMob:add(vOffset)
    end
end

-- Find the point at the given distance behind the specified mob
local function findMobRear(mob, distance)
    return findMobOffset(mob, math.pi, distance)
end

local teleporter_matches = {
    '^Home Point #%d+$',        -- Home points
    '^Ethereal Ingress #%d+$',  -- Eschan ingresses
    '^Survival Guide$',         -- Survival guides
    '^Waypoint$',               -- Adoulin Waypoints
    '^Dimensional Portal$',     -- Eschan entry points
    '^Veridical Conflux$',      -- Walk of Echoes
    '^Veridical Conflux #%d+$', -- Walk of Echoes (numbered)
    '^Affi$',                   -- Escha - Zi'tah NPC
    '^Dremi$',                  -- Escha - Ru'Aun NPC
    '^Shiftrix$',               -- Reisenjima NPC

    '^Urbiolaine$',             -- Unity (San d'Oria)
    '^Igsli$',                  -- Unity (Bastok)
    '^Teldro%-Kesdrodo$',       -- Unity (Windurst)
    '^Yonolala$',               -- Unity (Windurst)
    '^Nunaarl Bthtrogg$',       -- Unity (Adoulin)

    '^Horst$',      -- Abyssea
    '^Ernst$',      -- Abyssea
    '^Willis$',     -- Abyssea
    '^Ivan$',       -- Abyssea
    '^Vincent$',    -- Abyssea
    '^Cyril$',      -- Abyssea
    '^Kierron$',    -- Abyssea
}

local function isNearTeleporter(mobArray)
    mobArray = mobArray or windower.ffxi.get_mob_array()
    if type(mobArray) == 'table' then
        for id, mob in pairs(mobArray) do
            if
                mob.valid_target and
                mob.distance < 36 and
                (mob.spawn_type == 2 or mob.spawn_type == 34)
            then
                for i, pattern in ipairs(teleporter_matches) do
                    if mob.name:match(pattern) then
                        return true
                    end
                end
            end
        end
    end
end

-- ======================================================================================
-- Private interface
-- ======================================================================================

local function sm_movement_exp(self, job)
    
    -- Unlock the target
    local player = windower.ffxi.get_player()
    if player.target_locked then
        windower.send_command('input /lockon')
        coroutine.sleep(0.25)
    end

    local originalStatus = player.status

    -- Stop any prior movement
    windower.ffxi.follow(-1)
    windower.ffxi.run(false)

    local me = windower.ffxi.get_mob_by_target('me')
    if not me then return end
    
    local vme = coordVector(me)
    local vto = job:pos():subtract(vme) -- to = target - me
    local d = vto:length()              -- d = |vdirection|
    local hdg = vectorAngle(vto)        -- Heading to target

    local now = os.clock()
    local t0 = now
    local runtime = 0
    local iterationTime = 0

    local paused = false
    local continue = true

    local MAX_SPEEDS        = 20    -- Max number of speeds to track
    local MIN_AVERAGING     = 20    -- Minimum number of speeds for us to do the averaging check

    local speeds = {}
    local nextSpeed = 1

    local jittering = false
    local shouldJitter = false
    local jitterUntil = 0

    local iteration = function ()
        local sleepDuration = 0.25
        local wasJittering = jittering

        -- Update the 'me' mob
        me = windower.ffxi.get_mob_by_target('me')
        
        -- Get the new vectors
        local vme2 = coordVector(me)
        local vto2 = job:pos():subtract(vme2)
        local d2 = vto2:length()
        local hdg2 = vectorAngle(vto2)

        -- Calculate the distance traveled since the last iteration
        local delta = vme2:subtract(vme):length()
        local iterationSpeed = (iterationTime > 0 and (delta / iterationTime)) or nil

        -- Cancel jittering if we've reached the limit time
        if jittering and now >= jitterUntil then
            jittering = false
            jitterUntil = 0
        end

        -- Store the last MAX_SPEEDS speeds for averaging
        if not paused then
            if iterationSpeed ~= nil then
                speeds[nextSpeed] = iterationSpeed
                nextSpeed = nextSpeed + 1
                if nextSpeed > MAX_SPEEDS then
                    nextSpeed = 1
                end
            end

            if 
                JITTER_ENABLED and
                job.canJitter and
                originalStatus == 1 and -- Only allow jittering during battle???
                #speeds >= MIN_AVERAGING
            then
                local avg = arrayAverage(speeds)
                local minAvg = 1.5

                -- Increase the minimum averaging speed when mounted
                --if me.status == 85 or me.status == 5 then minAvg = 1 end

                if avg < minAvg and d2 > 3 then
                    if 
                        me.status == 1 -- Engaged
                    then
                        -- Jittering mid-battle can lead to undesired behavior. We'll only allow it
                        -- when one or more specific conditions is met.
                        local bt = windower.ffxi.get_mob_by_target('t') or windower.ffxi.get_mob_by_target('bt')
                        if 
                            bt == nil or            -- No battle target
                            bt.spawn_type ~= 16 or  -- Battle target is not a mob
                            not bt.valid_target or  -- Not a valid battle target
                            bt.hpp <= 0 or          -- Battle target is dead
                            bt.status ~= 1 or       -- The battle target mob is not engaged
                            bt.claim_id == 0        -- The battle target is not claimed
                        then
                            shouldJitter = true
                        end
                    else
                        shouldJitter = true
                    end
                end
            end
        end

        -- Reset jittering if requested
        if self.resettingJitter then
            speeds = {}
            nextSpeed = 1
            iterationTime = nil
            jittering = false
            jitterUntil = 0

            shouldJitter = false
            self.resettingJitter = false
        end

        -- Start jittering if necessary
        if shouldJitter then
            -- Reset speed averaging
            speeds = {}
            nextSpeed = 1

            shouldJitter = false
            jittering = true

            -- Pick a jittering exit angle that is 45 degrees off of the exact opposite angle to
            --  the target, either left or right. 
            --local degrees = (math.random() < 0.5) and 135.0 or 225.0
            local degrees = ((225 - 135) * math.random()) + 135
            local escapeAngle = hdg2 + (degrees * math.pi / 180.0)

            writeVerbose('Jittering at %.1f degrees from target':format(degrees))

            jitterUntil = now + 2 + (math.random() * 3.0)
            windower.ffxi.run(escapeAngle)
        end

        if paused then
            if d2 > 1.0 then
                -- Unpause if we've put some distance between us and the target
                paused = false
            end

            -- Stay paused (potentially), but turn to face the target if it's moved further out
            windower.ffxi.turn(hdg2)
        end
        
        if not paused then
            -- If we're within the desired distance, or if we passed right by the target but are still
            -- reasonably close, then we'll call ourselves done.
            if 
                d2 < self.tolerance or
                (d2 < 1.0 and not sharesHalfspace(hdg, hdg2))
            then
                paused = true

                -- Reset the average speed tally
                speeds = {}
                nextSpeed = 1
                iterationTime = nil
                jittering = false
                jitterUntil = 0

                -- Stop moving and face the target
                windower.ffxi.run(false)
                windower.ffxi.turn(hdg2)

                -- For jobs that allow auto-comletion, we will return now
                if job.autoComplete then
                    return
                end
            else
                if not jittering then
                    -- Use a shorter sleep as we get closer to the target
                    sleepDuration = d2 < 8 and 0.15 or sleepDuration
                    
                    if wasJittering then
                        -- Let's randomize the jitter recovery a little bit
                        windower.ffxi.run(hdg2 + randomSign() * math.pi / 4)
                        sleepDuration = sleepDuration * 3
                    else
                        -- Keep running toward the target
                        windower.ffxi.turn(hdg2)
                        windower.ffxi.run(hdg2)
                    end
                end
            end
        end

        -- Save this iteration's data for use by the next iteration
        vme = vme2
        vto = vto2
        d = d2
        hdg = hdg2

        return sleepDuration
    end
    
    while
        continue and            -- Updated each iteration indicating whether the job should self-terminate
        not self.cancel and     -- Updated by the main class for external termination of the job
        job:cycle()             -- Have the job update its state, returning true if it's still valid
    do
        local istart = os.clock()
        local result = iteration()

        -- The iteration returns the sleep time on success, or indicates completion on any other result
        if type(result) == 'number' and result > 0 then

            -- Sleep for the requested duration
            coroutine.sleep(result)

            -- Update clock-related things just before the next iteration begins
            now = os.clock()
            runtime = now - t0

            -- Stop if a duration limit was set and exceeded
            if job.max_duration and runtime >= job.max_duration then
                continue = false
            end
        else
            continue = false
        end

        -- Calculate the total iteration time
        iterationTime = os.clock() - istart
    end

    -- If there's a completion function, call it
    if type(job.oncomplete) == 'function' then
        job:oncomplete()
    else
        -- If there's no completion handler, we'll just stop moving
        windower.ffxi.run(false)
    end
end

local sm_movement = sm_movement_exp

function sm_coroutine(self)
    while true do
        --self.cancel = false

        local job = self.queue[1]
        if #self.queue > 0 then
            -- For now we only allow one item, so we'll remove ALL jobs (there shouldn't really be multiples anyway)
            --table.remove(self.queue, 1)
            self.queue = {}
        end

        if job ~= nil and job:is_valid() then
            self.current = job

            --if job.mode == Modes.position or job.mode == Modes.follow then
            if Modes[job.mode] then
                self.previousJob = job

                self.verbose('Dequeued: %s':format(job.description))
                sm_movement(self, job)
                self.verbose('Completed: %s':format(job.description))
            end
        end

        self.cancel = false
        self.current = nil
        self.resettingJitter = false

        coroutine.sleep(0.25)
    end
end

-------------------------------------------------------------------------------
-- Create the basic job entry
local function sm_createBaseJob(self, mode, skipcancel)
    local info = windower.ffxi.get_info()
    if type(info.zone) ~= 'number' or info.zone < 1 or resources.zones[info.zone] == nil then
        return nil
    end

    if not skipcancel then
        self:cancelJob(nil, false)
    end

    local jobId = self.latestJobId + 1
    
    self.latestJobId = jobId
    self.jobId = jobId

    local job = {
        jobId = jobId,
        time = os.clock(),
        description = 'Job #%d / %s':format(jobId, mode),
        mode = mode,
        zone = info.zone,
        canJitter = true
    }

    -- By default, jobs will remain valid forever. This can be overridden by 
    -- the specific job type implementations.
    job.is_valid = function (self) return true end
    job.cycle = function (self) return self.is_valid() end

    job.oncomplete = function (self)
        windower.ffxi.run(false)
        coroutine.sleep(0.125)

        if self:is_valid() then
            local player = windower.ffxi.get_player()
            local me = windower.ffxi.get_mob_by_target('me')
            local mob = self.mob
            local point = self:pos()

            if mob and mob.valid_target then
                if self.autolock then
                    -- packets.inject(packets.new('incoming', 0x058, {
                    --     ['Player'] = me.id,
                    --     ['Target'] = mob.id,
                    --     ['Player Index'] = me.index,
                    -- }))
                    if not player.target_locked then
                        windower.send_command('input /lockon')
                    end
                    coroutine.sleep(0.125)
                end

                point = coordVector(mob)
            end

            if point then
                local vme = coordVector(me)
                local vto = point:subtract(vme)

                if vto:length() > 0 then
                    local heading = vectorAngle(vto)
                    
                    -- All of this is necessary because of some weirdness in the game actually honoring the
                    -- heading change request. TODO: Investigate why.
                    windower.ffxi.turn(heading)
                    coroutine.sleep(0.125)

                    -- windower.ffxi.turn(heading)
                    -- coroutine.sleep(0.125)
                    -- windower.ffxi.turn(heading)
                    -- coroutine.sleep(0.125)                
                end
            end
        end
    end

    return job
end

-- ======================================================================================
-- Exposed interface
-- ======================================================================================

-------------------------------------------------------------------------------
-- If there's a job running, this will cause its jitter tracker to reset.
-- The result will be termination of any in-progress jitter, or a reset
-- of any impending jitter operation.
function smartMove:resetJitter()
    -- TODO: Consider if we should have a pause/resume jitter operation?
    if self.current then
        self.resettingJitter = true
    end
end

-------------------------------------------------------------------------------
-- Cancels a job. If no job id is provided, all jobs in the queue are cancelled.
function smartMove:cancelJob(jobId, immediate)
    local job = self.current
    local canCancel = job and (
        (jobId == nil) or
        (job.jobId == jobId)
    )

    if canCancel then
        self.verbose('Cancelling: %s':format(job.description))
        self.cancel = true

        if not immediate then
            -- If we weren't asked for an immediate exit, we'll wait for the job
            -- to finish before returning. We'll give it a little bit of buffer time
            -- afterward as well.
            while 
                self.cancel or (jobId and self.current and self.current.jobId == jobId)
            do
                coroutine.sleep(0.125)
            end

            coroutine.sleep(0.25)
        end
    else
        -- If we were unable to cancel due to there being no job at all, we'll just
        -- go ahead and stop movement and follow. This is already handled by the
        -- job if one was running. And if a job other than the one we wanted to
        -- cancel was running, then we don't want to upend it.
        if not job then
            windower.ffxi.follow(-1)
            windower.ffxi.run(false)
            --coroutine.sleep(0.25)
        end
    end

    return job and job.jobId or nil
end


-------------------------------------------------------------------------------
-- Returns the job id of the new item on success, or 0 on failure
function smartMove:moveTo(x, y)
    local job = sm_createBaseJob(self, Modes.position)
    if not job then
        return
    end

    -- Cancel the current job
    self:cancelJob()

    -- Reschedule the job
    job.reschedule = function (self)
        return smartMove:moveTo(x, y)
    end

    -- Fill in the new job details
    job.position = V({x, y})

    -- Position is always based on the originally provided point
    job.pos = function (self) return self.position end

    -- Move to operations should complete when the target is reached
    job.autoComplete    = true

    -- Follow exactly to the point
    job.follow_distance = 0

    -- Update the job description
    job.description = job.description .. ' (%.1f, %.1f)':format(x, y)
    
    -- Enqueue the new job. For now we only allow one item.
    self.queue = { job }

    self.verbose('Requested: %s':format(job.description))

    -- Add a bit of sleep time to give the job a chance to pick up
    coroutine.sleep(0.25)

    return job.jobId
end

-----------------------------------------------------------------------------------------
-- Find the location that is offsetDistance from the specified mob, and an offset
-- of offsetAngle radians from its forward direction. An offset of 0 will be
-- directly in front of the mob; an offset of PI will be directly behind the
-- mob; and so on.
function smartMove:findMobOffset(mob, offsetAngle, offsetDistance)
    return findMobOffset(mob, offsetAngle, offsetDistance)
end

-----------------------------------------------------------------------------------------
-- Determines if the player is at the location represented by the specified
-- offset angle and distance relative to the mob.
function smartMove:atMobOffset(mob, offsetAngle, offsetDistance)
    local target = self:findMobOffset(mob, offsetAngle, offsetDistance)
    local player = windower.ffxi.get_mob_by_target('me')

    return target:subtract(V({player.x, player.y})):length() <= self.tolerance
end

-----------------------------------------------------------------------------------------
-- Check if we're at the mob's rear
function smartMove:atMobRear(index)
    local mob = smartMove.getMobByIndex(index or 0)--windower.ffxi.get_mob_by_index(index or 0)
    if mob == nil or not mob.valid_target then
        return false
    end

    local target = findMobRear(mob, 2)
    local player = windower.ffxi.get_mob_by_target('me')

    return target:subtract(V({player.x, player.y})):length() <= self.tolerance
end

-----------------------------------------------------------------------------------------
-- Move behind the mob, taking at most a given number of seconds. Use atMobRear to
-- determine if the movement completed successfully.
function smartMove:moveBehindMob(mob, maxDuration)
    return self:moveBehindIndex(mob and mob.index or 0, maxDuration)
end

-----------------------------------------------------------------------------------------
-- Move behind the mob with the given index, taking at most a given number of seconds.
-- Use atMobRear to determine if the movement completed successfully.
function smartMove:moveBehindIndex(follow_index, maxDuration)
    -- Validate the target
    local mob = smartMove.getMobByIndex(follow_index)--windower.ffxi.get_mob_by_index(follow_index)
    if mob == nil or not mob.valid_target then
        return
    end

    -- Create and validate the basic job parameters
    local job = sm_createBaseJob(self, Modes.backstab)
    if not job then
        return
    end

    job.follow_index = follow_index -- Store the follow index
    job.mob = mob                   -- Store the target mob
    job.autoComplete = true         -- We want this job to stop once we get into position
    job.follow_distance = 2         -- How far behind the mob to get
    job.max_duration = 
        tonumber(maxDuration) or 5  -- The most time we'll spend waiting to get into position
    job.canJitter = false           -- Don't allow jittering
    job.autolock = true             -- Force target lock once in position (only if the target is valid)

    -- Reschedule the job
    job.reschedule = function (self)
        return smartMove:moveBehindIndex(follow_index)
    end

    -- Determine if the job is still valid
    job.is_valid = function(self)
        local valid = self.mob and self.mob.valid_target and self.mob.hpp > 0
        return valid
    end

    -- Cycling involves syncing up with the current state of our target mob
    job.cycle = function(self)
        self.mob = smartMove.getMobByIndex(self.follow_index)--windower.ffxi.get_mob_by_index(self.follow_index)
        return self:is_valid()
    end

    -- Positioning is based on the mob and any offsets
    job.pos = function (self)
        return findMobRear(self.mob, self.follow_distance)
        -- -- If we're doing a follow distance, we'll need to run the position calculation
        -- local player = windower.ffxi.get_mob_by_target('me')
        -- local vPlayer = V({player.x, player.y})
        
        -- local rearDirection = self.mob.heading + math.pi

        -- local vMob = V({self.mob.x, self.mob.y})
        -- local vTarget = vMob:add(vector.from_radian(rearDirection):scale(job.follow_distance))

        -- return vTarget
    end

    job.description = job.description .. ' %d (%03X)':format(follow_index, follow_index)
    
    -- Enqueue the new job. For now we only allow one item.
    self.queue = { job }

    self.verbose('Requested: %s':format(job.description))

    -- Add a bit of sleep time to give the job a chance to pick up
    coroutine.sleep(0.25)

    return job.jobId
end

function smartMove:followMob(mob, distance)
    return self:followIndex(mob and mob.index or 0, distance)
end

function smartMove:followIndex(follow_index, distance)
    -- Validate the target
    local mob = smartMove.getMobByIndex(follow_index)--windower.ffxi.get_mob_by_index(follow_index)
    if mob == nil or not mob.valid_target then
        return
    end

    -- Validate ourself. This can be nil on zoning, we'll just try again later.
    local _me = windower.ffxi.get_mob_by_target('me')
    if
        _me == nil or
        not _me.valid_target or
        not _me.x or
        not _me.y
    then
        return
    end

    -- Create and validate the basic job parameters
    local job = sm_createBaseJob(self, Modes.follow)
    if not job then
        return
    end

    -- Cancel the current job
    self:cancelJob()

    -- Fill in the new job details
    
    job.follow_index = follow_index -- Store the follow index
    job.mob = mob                   -- Store the target mob
    job.autoComplete = false        -- Follow operations should not complete when we reach the target (keep following if it moves)
    job.follow_distance =           -- How far behind the mob we should follow
        math.max(tonumber(distance) or 0, 0)

    if not current_settings or not current_settings.useRawDistances then
        local _p = windower.ffxi.get_mob_by_target('me')
        local distance_offset = 
            (_p and _p.model_size or 0) +           -- Player size offset
            (mob.model_size or 0)                   -- Mob size offset
        job.follow_distance = 
            job.follow_distance + (distance_offset * 0.75)

        -- local tick = os.clock()
        -- if tick - (last_raw_output_tick or 0) > 3 then
        --     print('base: %.2f, final: %.2f':format(distance, job.follow_distance))
        --     last_raw_output_tick = tick
        -- end
    end

    --job.autolock = true             -- Automatically lock onto the target on completion

    job.lost_mob_time = nil
    job.lost_mob_pos = nil
    job.last_mob = nil

    -- Reschedule the job
    job.reschedule = function (self)
        return smartMove:followIndex(follow_index, job.follow_distance)
    end

    -- Determine if the job is still valid
    job.is_valid = function(self)
        if 
            self.lost_mob_time and
            self.lost_mob_pos and
            (os.clock() < self.lost_mob_time + 5)
        then
            local player = windower.ffxi.get_mob_by_target('me')
            if 
                    player and
                    player.heading and
                    player.x and
                    player.y
            then
                local vToTarget = self.lost_mob_pos:subtract(V{player.x, player.y})
                if vToTarget:length() > 0.5 then
                    return true
                end
            end
        end

        return self.mob and self.mob.valid_target and self.mob.hpp > 0
    end

    -- Cycling involves syncing up with the current state of our target mob
    job.cycle = function(self)
        self.mob = smartMove.getMobByIndex(self.follow_index)--windower.ffxi.get_mob_by_index(self.follow_index)

        if 
            self.mob == nil or
            self.mob.x == nil or
            self.mob.y == nil or
            not self.mob.valid_target
        then
            if self.lost_mob_time == nil then
                if 
                    self.last_mob and
                    (self.last_mob.spawn_type == 13 or self.last_mob.spawn_type == 1) and   -- 13 = Player in party/alliance, 1 = Player out of party/alliance
                    self.last_mob.x and
                    self.last_mob.y and
                    self.last_mob.heading
                then
                    self.mob = nil
                    self.lost_mob_time = os.clock()

                    local vMob = V({self.last_mob.x, self.last_mob.y})
                    local vMobForward = vector.from_radian(self.last_mob.heading)

                    local delta_t = self.last_mob.last_updated and (os.clock() - self.last_mob.last_updated) or 0

                    --print('Lost player mob: %s (%d) with delta_t=%.2f':format(self.last_mob.name, self.last_mob.id, delta_t))

                    if 
                        delta_t <= 3 or
                        not isNearTeleporter()
                    then
                        -- Don't try to follow the target if we're near a teleporter, or if they
                        -- haven't moved in 2 seconds or more. We'll just stay put in those cases.
                        self.lost_mob_pos = vMob:add(vMobForward:scale(2))
                    else
                        local player = windower.ffxi.get_mob_by_target('me')
                        if player and player.valid_target then
                            -- Use our own current position if available
                            self.lost_mob_pos = V({player.x, player.y})
                        else
                            -- Otherwise just use the last known position of the mob
                            self.lost_mob_pos = vMob
                        end
                    end
                end
            end
        else
            self.lost_mob_time = nil
            self.lost_mob_pos = nil
            self.last_mob = self.mob
        end

        return self:is_valid()
    end


    -- Positioning is based on the mob and any offsets
    job.pos = function (self)
        if 
            self.lost_mob_pos
        then
            return self.lost_mob_pos
        end

        -- If we're doing a follow distance, we'll need to run the position calculation
        if job.follow_distance > 0 then
            local player = windower.ffxi.get_mob_by_target('me')

            if player then
                local vPlayer = V({player.x, player.y})
                local vMob = V({self.mob.x, self.mob.y})

                local toTarget = vMob:subtract(vPlayer)
                local distance = toTarget:length()
                
                local pos = vPlayer
                local scale = 0
                if distance >= job.follow_distance + 2 then
                    -- If we're further than the follow distance (by a certain margin),
                    -- we will simply aim directly at the target. This gets us within
                    -- the vicinity in a more direct way, and we'll worry about distance
                    -- precision only when we're relatively close.
                    scale = 1
                elseif distance > 0 then
                    scale = (distance - job.follow_distance) / distance
                    if scale < 0 then
                        scale = 0.01
                    end
                end

                pos = pos:add(toTarget:scale(scale))

                return pos
            end
        end

        -- Otherwise, just head straight to the mob
        return V({self.mob.x, self.mob.y})
    end

    job.description = job.description .. ' %d (%03X)':format(follow_index, follow_index)
    
    -- Enqueue the new job. For now we only allow one item.
    self.queue = { job }

    self.verbose('Requested: %s':format(job.description))

    -- Add a bit of sleep time to give the job a chance to pick up
    coroutine.sleep(0.25)

    return job.jobId
end

-------------------------------------------------------------------------------
-- Gets the id of the currently running job, or 0 if idle
function smartMove:getJobId()
    return self.current and self.current.jobId or 0
end

---------------------------------------------------------------------------------
-- Reschedules the specified jobId. If no joIb is provided, the most recent
-- job is scheduled automatically. Returns the new job id, or nil if none.
function smartMove:reschedule(jobId)
    local previousJob = self.previousJob
    if previousJob then
        if jobId == nil or jobId == previousJob.jobId then
            if type(previousJob.reschedule) == 'function' then
                return previousJob.reschedule()
            end
        end
    end
end

function smartMove:setLogger(log, verbose)
    self.log        = (type(log) == 'function') and log or null_log
    self.verbose    = (type(verbose) == 'function') and verbose or null_log
end

function smartMove:applySettings(settings)
    self.settings = settings or {}
    current_settings = self.settings
end

function smartMove:setMobLookupFunctions(byId, byIndex)
    smartMove.getMobById = byId or windower.ffxi.get_mob_by_id
    smartMove.getMobByIndex = byIndex or windower.ffxi.get_mob_by_index
end

function smartMove:getJobInfo(jobId)
    local current = self.current
    if current and (jobId == nil or jobId == current.jobId) then
        if current:is_valid() then
            return {
                jobId = current.jobId,
                mode = current.mode,
                time = current.time,
                follow_index = current.follow_index,
                position = current:pos()
            }
        end
    end
end

-- -------------------------------------------------------------------------------
-- Starts the pipeline processor

local cr = coroutine.schedule(function ()
    smartMove.started = true
    sm_coroutine(smartMove)
end, 0)

return smartMove