package.path='./?.lua;./?/init.lua;'..package.path

package.loaded['./lib/follow-distance']=nil
local followDistance=require('./lib/follow-distance')
local settings={followCommandDistance=4}

assert(followDistance.get(settings)==4)

local value,transient=followDistance.set(0)
assert(value==0 and transient==true)
assert(followDistance.get(settings)==0)
assert(settings.followCommandDistance==4)

assert(followDistance.resetTransient()==true)
assert(followDistance.get(settings)==1)
assert(followDistance.resetTransient()==false)

value,transient=followDistance.set(3)
assert(value==3 and transient==false)
assert(followDistance.get(settings)==4)

settings.followCommandDistance=0
assert(followDistance.get(settings)==1)

print('follow-distance tests passed')
