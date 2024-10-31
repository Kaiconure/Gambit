local function null_log() end

local smartMove = {
    started = false,
    latestJobId = 0,
    queue = { },
    previousJob = nil,
    current = nil,
    tolerance = 0.5,
    log = null_log
}


local Modes = {
    position = 'position',
    follow = 'follow'
}

local FORWARD           = V({1, 0})             -- The vector representing the point on the unit circle at 0 radians
local TWO_PI            = math.pi * 2           -- 2pi
local PI_OVER_TWO       = math.pi * 0.5         -- pi / 2

local JITTER_ANGLE      = PI_OVER_TWO * 1.25    -- The angle we'll try to escape obstacles with
local MAX_JITTER        = 3                     -- The maximum duration we'll spend jittering around obstacles

local HEADING_TOLERANCE = TWO_PI * 0.0125   -- 1.25% of a unit circle, or 4.5 degrees

local resources = require('resources')

-- ======================================================================================
-- Helpers
-- ======================================================================================

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
    heading1 = normalizeAngle(heading1)
    heading2 = normalizeAngle(heading2)

    -- Determine if the headings are within half a circle of each other
    return math.abs(heading1 - heading2) <= PI_OVER_TWO
end

-- Gets a position vector from the specified coordinate (x,y)
local function coordVector(coord)
    return V({coord.x, coord.y})
end

-- ======================================================================================
-- Private interface
-- ======================================================================================

local function sm_movement(self, job)
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

    while 
        continue and
        job:cycle() and
        not self.cancel
    do
        local pos = job:pos()

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
            velocity = math.abs(distance - newDistance) / sleepDuration
        end

        local t = os.clock()

        wasJittering = isJittering
        isJittering = t < jitterStopTime

        if not isJittering then
            jitterPause = math.max(jitterPause - 0.05, 0)

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
                    windower.ffxi.run(newHeading)
                end
            end
        end

        if 
            pausing
        then
            -- Use a slightly longer sleep if we're paused
            sleepDuration = 0.5
        elseif 
            ((not wasJittering and not sharesHalfspace(heading, newHeading)) and newDistance < 1.5) or
            newDistance < self.tolerance
        then
            -- We've reached our target distance, it's time to stop moving
            windower.ffxi.run(false)

            -- Reset other traversal states
            jitterStopTime = 0
            jitterPause = 0

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
            -- Initiate some obstacle avoidance jitter if we're not making any forward progress
            local canJitter = 
                ((isJittering and velocity < 0.125) or (not isJittering and velocity < 0.5)) and 
                distance > 2 and
                sleepDuration > 0

            if canJitter then
                jitterPause = math.min(jitterPause + 1, MAX_JITTER)

                self.log('Initiating obstacle avoidance measures with jitterPause=%.2f':format(jitterPause))

                -- Apply a randomized escape angle based on our configured base value
                local jitterAngle = JITTER_ANGLE * randomSign() * randomRange(0.95, 1.05)

                -- Calculate our new heading, and start moving in that direction
                newHeading = player_mob.heading + jitterAngle
                windower.ffxi.run(newHeading)

                -- Give ourselves a bit of time to continue moving along
                jitterStopTime = t + jitterPause
            end

            sleepDuration = 0.25
        end

        -- Update our tracking info
        heading = newHeading
        distance = newDistance

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

    -- Stop moving and pause
    windower.ffxi.run(false)

    if job:is_valid() then
        -- If the job is still valid, we should make sure we're pointed at the target before exiting
        vpos = V({player_mob.x, player_mob.y})
        toTarget = job:pos():subtract(vpos)
        windower.ffxi.turn(vectorAngle(toTarget))
    end
end

function sm_coroutine(self)
    while true do
        self.cancel = false

        local job = self.queue[1]
        if #self.queue > 0 then
            -- For now we only allow one item, so we'll remove ALL jobs (there shouldn't really be multiples anyway)
            --table.remove(self.queue, 1)
            self.queue = {}
        end

        if job ~= nil and job:is_valid() then
            self.current = job

            if job.mode == Modes.position or job.mode == Modes.follow then
                self.previousJob = job

                self.log('Job %d (%s) is starting!':format(job.jobId, job.mode))

                sm_movement(self, job)

                self.log('Job %d has completed.':format(job.jobId))
            end
        end

        self.cancel = false
        self.current = nil

        coroutine.sleep(0.5)
    end
end

local function sm_createBaseJob(self, mode)
    local info = windower.ffxi.get_info()
    if type(info.zone) ~= 'number' or info.zone < 1 or resources.zones[info.zone] == nil then
        return nil
    end

    local jobId = self.latestJobId + 1
    
    self.latestJobId = jobId
    self.jobId = jobId

    local job = {
        jobId = jobId,
        time = os.clock(),
        mode = mode,
        zone = info.zone
    }

    -- By default, jobs will remain valid forever. This can be overridden by 
    -- the specific job type implementations.
    job.is_valid = function (self) return true end
    job.cycle = function (self) return self.is_valid() end

    return job
end

-- ======================================================================================
-- Exposed interface
-- ======================================================================================

-------------------------------------------------------------------------------
-- Cancels a job. If no job id is provided, all jobs in the queue are cancelled.
function smartMove:cancelJob(jobId, wait)
    local job = self.current
    local canCancel = 
        (jobId == nil) or
        (job and job.jobId == jobId)

    if canCancel then
        self.cancel = true
    end

    if canCancel and wait then
        -- If waiting was configured, we'll wait until either the job schedule has completed the job
        -- and flipped the flag -OR- our job isn't running anymore.
        while 
            self.cancel or
            (self.current == nil or self.current.jobId ~= current.jobId) 
        do
            coroutine.sleep(0.25)
        end
    end

    return job and job.JobId or nil
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
    
    -- Enqueue the new job. For now we only allow one item.
    self.queue = { job }

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

    -- Reschedule the job
    job.reschedule = function (self)
        return smartMove:followIndex(follow_index, distance)
    end

    -- Determine if the job is still valid
    job.is_valid = function(self)
        local valid = self.mob and self.mob.valid_target
        return valid
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
            
                --print('distance: %.2f':format(distance))
            local scale = 0
            if distance > 0 then
                scale = (distance - job.follow_distance) / distance
                if scale < 0 then
                    scale = 0.01
                end
            end

            pos = pos:add(toTarget:scale(scale))

            --print('pos: (%.2f, %.2f)':format(pos[1], pos[2]))

            return pos
        end

        -- Otherwise, just head straight to the mob
        return V({self.mob.x, self.mob.y})
    end
    
    -- Enqueue the new job. For now we only allow one item.
    self.queue = { job }

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

function smartMove:setLogger(fn)
    if type(fn) == 'function' then
        self.log = fn
    else
        self.log = null_log
    end
end

-- -------------------------------------------------------------------------------
-- Starts the pipeline processor

local cr = coroutine.schedule(function ()
    smartMove.started = true
    sm_coroutine(smartMove)
end, 0)

return smartMove