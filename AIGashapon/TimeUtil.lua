-- @module TimeUtil
-- @author ramonqlee
-- @copyright idreems.com
-- @release 2017.12.22
-- tested 2017.12.27

TimeUtil = {}
require "LogUtil"

local TAG = "TimeUtil"

local sTimeOffsetInMs = 0
local sLastTimeInMs = 0
local sTimeSync = false

function TimeUtil.timeSync(  )
	return sTimeSync
end
function TimeUtil.setTimeOffset(offsetInMs) 
    sTimeOffsetInMs = offsetInMs
    sTimeSync = true
end


function TimeUtil.getCheckedCurrentTime() 
    return os.time() + sTimeOffsetInMs
end

function TimeUtil.setLastTimeInMs( time) 
    sLastTimeInMs = time
    --LogUtil.d(TAG,"Time.setLastTimeInMs = "..time)
end

function TimeUtil.getLastCheckTime()
    if (0 == sLastTimeInMs) then
        sLastTimeInMs = os.time()
    end
    return sLastTimeInMs
end

