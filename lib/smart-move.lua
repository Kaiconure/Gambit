local function null_log() end

local smartMove = {
    started = false,
    latestJobId = 0,
    queue = { },
    previousJob = nil,
    current = nil,
    tolerance = 0.5,

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
    --heading1 = normalizeAngle(heading1)
    --heading2 = normalizeAngle(heading2)

    -- Determine if the headings are within half a circle of each other
    --return math.abs(heading1 - heading2) <= PI_OVER_TWO

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
    
    local direction = mob.heading + angleOffset

    local vMob = V({mob.x, mob.y})
    local vTarget = vMob:add(vector.from_radian(direction):scale(distance))

    return vTarget
end

-- Find the point at the given distance behind the specified mob
local function findMobRear(mob, distance)
    return findMobOffset(mob, math.pi, distance)
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

    -- Stop any prior movement
    windower.ffxi.follow(-1)
    windower.ffxi.run(false)

    local me = windower.ffxi.get_mob_by_target('me')
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

    local MAX_SPEEDS        = 10    -- Max number of speeds to track
    local MIN_AVERAGING     = 10    -- Minimum number of speeds for us to do the averaging check

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
                #speeds >= MIN_AVERAGING
            then
                local avg = arrayAverage(speeds)
                local minAvg = 1

                -- Increase the minimum averaging speed when mounted
                --if me.status == 85 or me.status == 5 then minAvg = 1 end

                if avg < minAvg and d2 > 3 then
                    shouldJitter = true
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
            local degrees = (math.random() < 0.5) and 135.0 or 225.0
            local escapeAngle = hdg2 + (degrees * math.pi / 180.0)

            writeVerbose('Jittering at %.1f degrees from target':format(degrees))

            jitterUntil = now + 1 + (math.random() * 3.0)
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
                    sleepDuration = d2 < 5 and 0.15 or sleepDuration
                    
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

local function sm_movement_orig(self, job)
    local player_mob = windower.ffxi.get_mob_by_target('me')
    
    local vpos = coordVector(player_mob)
    local toTarget = job:pos():subtract(vpos)
    local distance = toTarget:length()

    -- Prepare to get started: Clear our follow target, movement, and target lock, if any
    local player = windower.ffxi.get_player()
    local target_locked = player.target_locked
    local follow_index = player.follow_index

    windower.ffxi.follow(-1)
    windower.ffxi.run(false)
    if target_locked then
        windower.send_command('input /lockon;')
        coroutine.sleep(0.5)
    end

    -- Start moving toward the target
    local heading = vectorAngle(toTarget)
    if tostring(heading) == 'nan' then
        heading = 0 
    else
        windower.ffxi.run(heading)
    end

    local sleepDuration = 0
    local velocity = 0
    local isJittering = false
    local wasJittering = false
    local jitterStopTime = 0
    local jitterPause = 0

    local continue = true
    local pausing = false
    local zeroSpeedCycles = 0

    local startTime = os.clock()
    local endTime = (job.max_duration and (startTime + job.max_duration)) or nil

    local previousPosition = vpos

    while 
        continue and
        job:cycle() and
        (endTime == nil or os.clock() < endTime) and
        not self.cancel
    do
        local pos = job:pos()

        -- We can't freely move if we're target locked
        local player = windower.ffxi.get_player()
        if player.target_locked then
            windower.send_command('input /lockon;')
            coroutine.sleep(0.5)
        else
            coroutine.sleep(0.25)
        end

        -- Refresh our vectors
        player_mob = windower.ffxi.get_mob_by_target('me')
        vpos = V({player_mob.x, player_mob.y})
        toTarget = pos:subtract(vpos)

        -- Calculate the new heading to target and distance
        local newDistance = toTarget:length()
        local newHeading = vectorAngle(toTarget)
        
        if tostring(newHeading) == 'nan' then newHeading = heading end

        -- Essentially start over if we're paused and our distance has increased
        if pausing then
            if newDistance > 1.5 then
                pausing = false
                sleepDuration = 0

                windower.ffxi.run(newHeading)
            else
                windower.ffxi.turn(newHeading)
            end
        end

        -- Calculate our current and averaged velocity
        if sleepDuration > 0 then
            local movement = vpos:subtract(previousPosition)
            velocity = movement:length() / sleepDuration

            --velocity = currentVelocity
        end

        local t = os.clock()

        wasJittering = isJittering
        isJittering = t < jitterStopTime

        if not isJittering then
            jitterPause = math.max(jitterPause - 0.025, 0)

            -- We'll re-point at the target if:
            --      1. Our aim is off, or
            --      2. If just came off a random jitter and need to get back on track
            local headingDelta = math.abs(newHeading - heading)
            if 
                headingDelta > HEADING_TOLERANCE
                or wasJittering
            then
                jitterStopTime = 0
                if not pausing then
                    if wasJittering then
                        local adjustment = randomRange(-math.pi / 4, math.pi / 4)
                        ---print('Adjusting heading by %.1f degrees':format(adjustment * 180 / math.pi))
                        sleepDuration = 0.5
                        windower.ffxi.run(newHeading + adjustment)
                    else
                        windower.ffxi.run(newHeading)
                    end
                end
            end
        else
            -- local adjustment = randomRange(-math.pi, math.pi)
            -- print('Adjusting heading by %.1f degrees':format(adjustment * 180 / math.pi))
            -- windower.ffxi.run(player_mob.heading + adjustment)
        end

        if 
            pausing
        then
            -- Use a slightly longer sleep if we're paused, and stop tracking zero speed
            sleepDuration = 0.5
            zeroSpeedCycles = 0
        elseif 
            ((not wasJittering and not sharesHalfspace(heading, newHeading)) and newDistance < 1.25) or
            newDistance < self.tolerance
        then
            -- We've reached our target distance, it's time to stop moving
            windower.ffxi.run(false)

            -- Reset other traversal states
            jitterStopTime = 0
            jitterPause = 0
            zeroSpeedCycles = 0

            if job.autoComplete then
                -- This job has been configured to auto-complete on reaching the target,
                -- clear the continuation flag and prepare to exit
                continue = false
            else
                -- This job has been configured to keep at it after reaching the target. 
                -- Flag as paused, face the target, and wait for the next cycle.
                pausing = true
                sleepDuration = 0.5
                windower.ffxi.turn(newHeading)
            end            
        else
            local isZeroSpeed = ((isJittering and velocity < 0.125) or (not isJittering and velocity < 0.25))
            if isZeroSpeed then
                zeroSpeedCycles = zeroSpeedCycles + 1
            else
                zeroSpeedCycles = math.max(0, zeroSpeedCycles - 0.125)
            end


            -- Initiate some obstacle avoidance jitter if we're not making any forward progress
            local canJitter = 
                JITTER_ENABLED and
                job.canJitter and
                (isZeroSpeed and zeroSpeedCycles > 8) and
                --((isJittering and velocity < 0.125) or (not isJittering and velocity < 0.5)) and 
                distance > 2 and
                sleepDuration > 0

            if canJitter then
                jitterPause = math.min(jitterPause + 0.5, MAX_JITTER)

                self.log('Initiating obstacle avoidance measures with jitterPause=%.2f / zeroSpeed=%.2f':format(jitterPause, zeroSpeedCycles))

                -- Apply a randomized escape angle based on our configured base value
                local jitterAngle = JITTER_ANGLE * randomSign() * randomRange(0.95, 1.05)

                -- Calculate our new heading, and start moving in that direction
                newHeading = player_mob.heading + jitterAngle     -- Base new heading on the heading of the player. Which is better?
                --newHeading = newHeading + jitterAngle               -- Base new heading on the trajectory to the mob. Which is better?
                windower.ffxi.run(newHeading)

                -- Give ourselves a bit of time to continue moving along
                jitterStopTime = t + jitterPause
            end

            if newDistance < 3 then
                sleepDuration = 0.125
            else
                sleepDuration = 0.25
            end
        end

        -- Update our tracking info
        heading = newHeading
        distance = newDistance
        previousPosition = vpos

        -- local player = windower.ffxi.get_player()
        -- if type(player.follow_index) == 'number' and player.follow_index > 0 then
        --     print('follow index: %d':format(player.follow_index))
        --     continue = false
        -- end

        -- Sleep a bit before continuing the next iteration
        if continue and sleepDuration > 0 then
            coroutine.sleep(sleepDuration)
        end
    end

    -- Stop any follow more movement that may be active
    windower.ffxi.follow(-1)
    windower.ffxi.run(false)

    if job:is_valid() then
        -- If the job is still valid, we should make sure we're pointed at the target before exiting
        vpos = V({player_mob.x, player_mob.y})
        toTarget = job:pos():subtract(vpos)
        windower.ffxi.turn(vectorAngle(toTarget))
    end

    -- We need to space this out a little bit
    coroutine.sleep(0.25)
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
            coroutine.sleep(0.25)
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
    offsetAngle = tonumber(offsetAngle) or 0
    offsetDistance = tonumber(offsetDistance) or 2
    
    return findMobOffset(mob, offsetAngle, offsetDistance)
end

-----------------------------------------------------------------------------------------
-- Determines if the player is at the location represented by the specified
-- offset angle and distance relative to the mob.
function smartMove:atMobOffset(mob, offsetAngle, offsetDistance)
    offsetAngle = tonumber(offsetAngle) or 0
    offsetDistance = tonumber(offsetDistance) or 2

    local target = self:findMobOffset(mob, offsetAngle, offsetDistance)
    local player = windower.ffxi.get_mob_by_target('me')

    return target:subtract(V({player.x, player.y})):length() <= self.tolerance
end

-----------------------------------------------------------------------------------------
-- Check if we're at the mob's rear
function smartMove:atMobRear(index)
    local mob = windower.ffxi.get_mob_by_index(index or 0)
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
    local mob = windower.ffxi.get_mob_by_index(follow_index)
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
        self.mob = windower.ffxi.get_mob_by_index(self.follow_index)
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
    local mob = windower.ffxi.get_mob_by_index(follow_index)
    if mob == nil or not mob.valid_target then
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
    --job.autolock = true             -- Automatically lock onto the target on completion

    -- Reschedule the job
    job.reschedule = function (self)
        return smartMove:followIndex(follow_index, distance)
    end

    -- Determine if the job is still valid
    job.is_valid = function(self)
        return self.mob and self.mob.valid_target and self.mob.hpp > 0
    end

    -- Cycling involves syncing up with the current state of our target mob
    job.cycle = function(self)
        self.mob = windower.ffxi.get_mob_by_index(self.follow_index)
        return self:is_valid()
    end

    -- Positioning is based on the mob and any offsets
    job.pos = function (self)
        -- If we're doing a follow distance, we'll need to run the position calculation
        if job.follow_distance > 0 then
            local player = windower.ffxi.get_mob_by_target('me')

            local vPlayer = V({player.x, player.y})
            local vMob = V({self.mob.x, self.mob.y})

            local toTarget = vMob:subtract(vPlayer)
            local distance = toTarget:length()
            
            local pos = vPlayer
            local scale = 0
            if distance > 0 then
                scale = (distance - job.follow_distance) / distance
                if scale < 0 then
                    scale = 0.01
                end
            end

            pos = pos:add(toTarget:scale(scale))

            return pos
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

function smartMove:getJobInfo(jobId)
    local current = self.current
    if current and (jobId == nil or jobId == current.jobId) then
        if current:is_valid() then
            return {
                jobId = current.jobId,
                mode = current.type,
                time = current.time,
                follow_index = current.follow_index,
                position = current:pos()
            }
        end
    end
end

-- smartMove:onZoneChange = function ()
--     -- Stop on zone change
--     smartMove:cancelJob()
-- end

-- smartMove:onStatusChange = function (newStatus)
--     -- Stop if we've changed to a status that doesn't make sense. We can't follow if dead, sitting, resting, etc
--     if 
--         newStatus ~= STATUS_IDLE and
--         newStatus ~= STATUS_ENGAGED and 
--         newStatus ~= 5 and  -- Riding a chocobo
--         newStatus ~= 85     -- Riding a mount other than a chocobo
--     then
--         smartMove:cancelJob()
--     end
-- end



-- -------------------------------------------------------------------------------
-- Starts the pipeline processor

local cr = coroutine.schedule(function ()
    smartMove.started = true
    sm_coroutine(smartMove)
end, 0)

-- windower.register_event('zone change', function ()
--     -- Stop on zone change
--     smartMove:cancelJob()
-- end)

-- windower.register_event('status change', function (newStatus)
--     -- Stop if we've changed to a status that doesn't make sense. We can't follow if dead, sitting, resting, etc
--     if 
--         newStatus ~= STATUS_IDLE and
--         newStatus ~= STATUS_ENGAGED and 
--         newStatus ~= 5 and  -- Riding a chocobo
--         newStatus ~= 85     -- Riding a mount other than a chocobo
--     then
--         smartMove:cancelJob()
--     end
-- end)

return smartMove