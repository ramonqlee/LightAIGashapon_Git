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
require "UARTBroadcastLightup"

local TAG="Entry"
local timerId=nil

entry = {}
local mqttStarted=false
local TWINKLE_POS_1 = 1
local TWINKLE_POS_2 = 2
local TWINKLE_POS_3 = 3--not used now
local MAX_TWINKLE	= TWINKLE_POS_2
local nextTwinklePos=TWINKLE_POS_1

function allInfoCallback( ids )
	--取消定时器 
	if timerId then
		sys.timer_stop(timerId)
	end 

	if not mqttStarted then
		mqttStarted = true
		sys.taskInit(MQTTManager.startmqtt)
	end

	entry.startTwinkleTask( )
end

function entry.run()
	sys.taskInit(function()
		--首先初始化本地环境，然后成功后，启动mqtt
		UartMgr.init(Consts.UART_ID,Consts.baudRate)
		--获取所有板子id
		UartMgr.initSlaves(allInfoCallback)    
	end)
	
	-- 启动一个延时定时器，防止没有回调时无法正常启动
	timerId=sys.timer_start(function()
		LogUtil.d(TAG,"start after timeout in retrieving slaves")
		-- mywd.feed()--断网了，别忘了喂狗，否则会重启
		if not mqttStarted then
			mqttStarted = true
			sys.taskInit(MQTTManager.startmqtt)
		end

	end,30*1000)  
end


-- 让灯闪起来
-- addrs 地址数组
-- pos 扭蛋机位置，目前取值1，2
-- time 闪灯次数，每次?ms
function entry.twinkle( addrs,pos,times )
	-- 闪灯协议
	msgArray = {}

	-- bds = UARTAllInfoReport.getAllBoardIds(true)
	if addrs and #addrs >0 then
		for _,addr in pairs(addrs) do
			-- device["seq"]=v
			item = {}
			item["id"] = addr
			item["group"] = pack.pack("b",pos)--1byte
			item["color"] = pack.pack("b",2)--1bye
			item["time"] = pack.pack(">h",times)
			msgArray[#msgArray+1]=item
		end
	end
	

	r = UARTBroadcastLightup.encode(msgArray)
	UartMgr.publishMessage(r)      
end

function entry.startTwinkleTask( )
	-- 启动一个定时器，负责闪灯，当出货时停止闪灯
	sys.timer_loop_start(function()
			--出货中，不集体闪灯
			if DeliverHandler.isDelivering() then
				LogUtil.d(TAG,TAG.." DeliverHandler.isDelivering")
				return
			end

			addrs = UARTAllInfoReport.getAllBoardIds(true)

			if not addrs or 0 == #addrs then
				LogUtil.d(TAG,TAG.." no slaves found,ignore twinkle")
				return
			end

			LogUtil.d(TAG,TAG.." twinkle pos = "..nextTwinklePos)

            entry.twinkle( addrs,nextTwinklePos,Consts.TWINKLE_TIME )

            --切换闪灯位置
            nextTwinklePos = nextTwinklePos + 1
			if nextTwinklePos > MAX_TWINKLE then
				nextTwinklePos = TWINKLE_POS_1
			end

        end,Consts.TWINKLE_INTERVAL)
end



