--- 模块功能：testAdc
-- @module test
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2018.1.3
-- @describe 每隔5s发送0x01,0x20

-- module(...,package.seeall)
require "sys"
require"clib"
require"utils"
require "LogUtil"
require "UartMgr"
require "MQTTManager"

local TAG="Entry"
local timerId=nil

entry = {}
local mqttStarted=false

function allInfoCallback( ids )
	--取消定时器 
	if timerId then
		sys.timer_stop(timerId)
	end 

	if not mqttStarted then
		mqttStarted = true
		sys.taskInit(MQTTManager.startmqtt)
	end
	mywd.feed()--断网了，别忘了喂狗，否则会重启
end

function entry.run()
	sys.taskInit(function()
		--首先初始化本地环境，然后成功后，启动mqtt
		UartMgr.init(Consts.UART_ID,Consts.baudRate)
		--获取所有板子id
		UartMgr.initSlaves(allInfoCallback)    
	end)

	mywd.feed()--断网了，别忘了喂狗，否则会重启
	-- 启动一个延时定时器，防止没有回调时无法正常启动
	timerId=sys.timer_start(function()
		LogUtil.d(TAG,"start after timeout in retrieving slaves")
		mywd.feed()--断网了，别忘了喂狗，否则会重启
		if not mqttStarted then
			mqttStarted = true
			sys.taskInit(MQTTManager.startmqtt)
		end

	end,30*1000)  
end



