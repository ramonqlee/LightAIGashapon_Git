--- 模块功能：网络授时
-- @module ntp
-- @author 稀饭放姜
-- @license MIT
-- @copyright openLuat
-- @release 2017.10.21
require "misc"
require "socket"
require "utils"
require "log"
local sbyte, ssub = string.byte, string.sub
module(..., package.seeall)
-- NTP服务器域名集合
local timeServer = {
     "cn.pool.ntp.org",
    "edu.ntp.org.cn",
    "cn.ntp.org.cn",
    "s2c.time.edu.cn",
    "time1.aliyun.com",
    "tw.pool.ntp.org",
    "0.cn.pool.ntp.org",
    "0.tw.pool.ntp.org",
    "1.cn.pool.ntp.org",
    "1.tw.pool.ntp.org",
    "3.cn.pool.ntp.org",
    "3.tw.pool.ntp.org",
}
-- 同步超时等待时间
local NTP_TIMEOUT = 8000
-- 同步重试次数
local NTP_RETRY = 3
-- 网络获取的时间table
local ntpTime = {}
-- 同步是否完成标记
local ntpend = false
function isEnd()
    return ntpend
end

---  自动同步时间，每个NTP服务器尝试3次，超时8秒
-- @return 无
-- @usage ntp.timeSync()
function timeSync()
    sys.taskInit(function()
        ntpend = false
        for i = 1, #timeServer do
            while not socket.isReady() do sys.wait(10000) end
            local c = socket.udp()
            while true do
                local idx = rtos.tick() % #timeServer + 1
                log.info("ntp.timeSync server: ",timeServer[idx])
                for num = 1, NTP_RETRY do if c:connect(timeServer[idx], "123") then break end sys.wait(NTP_TIMEOUT) end
                if not c:send(string.fromhex("E30006EC0000000000000000314E31340000000000000000000000000000000000000000000000000000000000000000")) then break end
                local _, data = c:recv()
                if #data ~= 48 then break end
                ntpTime = os.date("*t", (sbyte(ssub(data, 41, 41)) - 0x83) * 2 ^ 24 + (sbyte(ssub(data, 42, 42)) - 0xAA) * 2 ^ 16 + (sbyte(ssub(data, 43, 43)) - 0x7E) * 2 ^ 8 + (sbyte(ssub(data, 44, 44)) - 0x80) + 1)
                misc.setClock(ntpTime)
                break
            end
            c:close()
            sys.wait(1000)
            local date = misc.getClock()
            log.info("ntp.timeSync is date:", date.year .. "/" .. date.month .. "/" .. date.day .. "," .. date.hour .. ":" .. date.min .. ":" .. date.sec)
            if ntpTime.year == date.year and ntpTime.day == date.day and ntpTime.min == date.min then
                sys.publish('TIME_SYNC_FINISH')
                ntpTime = {}
                ntpend = true
                break
            end
        end
    end)
end
