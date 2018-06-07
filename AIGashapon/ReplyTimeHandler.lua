
-- @module ReplyTimeHandler
-- @author ramonqlee
-- @copyright idreems.com
-- @release 2017.12.21
-- tested 2017.12.26

require "CloudBaseHandler"
require "TimeUtil"
require "CloudConsts"
require "LogUtil"
require "misc"
local json = require "jsonex"
-- module(...,package.seeall)

local TAG = "ReplyTimeHandler"

ReplyTimeHandler = CloudBaseHandler:new{
mServerTimestamp=0,
MY_TOPIC="reply_time",
TIME_OUT_IN_MILLS = 10 * 1000
}

function ReplyTimeHandler:new (o)
    o = o or CloudBaseHandler:new(o)
    setmetatable(o, self)
    self.__index = self
    return o
end

function ReplyTimeHandler:name()
    return self.MY_TOPIC
end

-- replyTimeJsonStr = [[
-- {
--     "topic": "1000001/reply_time",
--     "payload": {
--         "timestamp": 1500000009,
--         "content": {
--             "cts": 1400000001
--         }
--     }
-- }
-- ]]
function ReplyTimeHandler:handleContent( timestampInSec,content )
    local r = false
    if (timestampInSec<=0) then
        LogUtil.d(TAG,TAG.." illegal content or timestamp,handleContent return")
        return r
    end

    r = true

    self.mServerTimestamp = timestampInSec
    TimeUtil.setTimeOffset(self.mServerTimestamp-os.time())
    TimeUtil.setLastTimeInMs(TimeUtil.getCheckedCurrentTime())

    -- 设置系统时间
    ntpTime=os.date("*t",timestampInSec)
    LogUtil.d(TAG,TAG.." handleContent now timestampInSec="..timestampInSec.." ntpTime="..jsonex.encode(ntpTime))

    misc.setClock(ntpTime)
    return r
end                     