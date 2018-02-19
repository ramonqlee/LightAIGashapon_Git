--- testSocket
-- @module testSocket
-- @author ??
-- @license MIT
-- @copyright openLuat.com
-- @release 2017.9.27
require "socket"
module(..., package.seeall)

-- tcp test
sys.taskInit(function()
    local r, s
    
    while true do
        while not socket.isReady() do sys.wait(10000) end
        local c = socket.tcp()
        while not c:connect("120.27.222.26", 60000) do
            sys.wait(2000)
        end
        while true do
            r, s = c:recv()
            if not r then
                break
            end
            log.info("test.socket.tcp: recv", s)
            if not c:send(s) then
                break
            end
        end
        c:close()
    end
end)
