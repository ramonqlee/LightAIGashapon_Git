
-- @module Task
-- @author ramonqlee
-- @copyright idreems.com
-- @release 2017.12.27
-- @tested 2018.

require "Consts"
require "LogUtil"
require "UartMgr"
require "UARTBroadcastSlave"

if Consts.DEVICE_ENV then
	require "sys"
end

local NONE_TASK = "NONE"
local BODY_KEY = "body"
local TASK_KEY = "task"
local TOKEN_KEY = "token"

-- 重启
REBOOT_TYPE = "REBOOT"

local TAG = "Task"
Task={}

function Task.getTask()
	sys.taskInit(function()
		-- 去服务器端请求任务
		local nodeId = Consts.getUserName(false)
		local password = Consts.getPassword(false)
		local timeInSec = os.time()
	    local timestamp = ""..timeInSec
		local nonce   = crypto.sha1(timestamp,#timestamp)
		local tmp = nodeId..crypto.sha1(password,#password)..nonce..timestamp
	    sign = crypto.sha1(tmp,#tmp)

		url = string.format(Consts.MQTT_TASK_URL_FORMATTER,nodeId, nonce, timestamp, sign)
	    LogUtil.d(TAG,"url = "..url)
	    local code, header, body = http.request("GET", url, 15000)
	    if not code then
	        LogUtil.d(TAG,"http empty code,return")
	        return
	    end

	    LogUtil.d(TAG,"http code = "..code)
	    if "200" ~= code then
	        return
	    end

	    if not body then
	        LogUtil.d(TAG,"http empty body,return")
	        return
	    end

	    LogUtil.d(TAG,"http config body="..body)
	    bodyJson = jsonex.decode(body)

	    if not bodyJson then
	        return
	    end

	    bodyVal = bodyJson[BODY_KEY]
	    if not bodyVal or "table"~=type(bodyVal) then
	    	return
	    end

	    task = bodyVal[TASK_KEY]
	    -- 任务分发(目前仅仅支持重启，后续待完善框架，支持更多任务)
	    -- FIXME 待增加从板子支持
	    if task == REBOOT_TYPE then 
	    	r = UARTBroadcastSlave.encode()
			UartMgr.publishMessage(r)

			sys.wait(5000)--等待大板子发送消息完毕，目前大板子发送消息的间隔是500ms
	    	LogUtil.d(TAG,"publish cmd = "..Consts.REBOOT_DEVICE_CMD)
	    	sys.publish(Consts.REBOOT_DEVICE_CMD)
	    end

	end)

end
    


