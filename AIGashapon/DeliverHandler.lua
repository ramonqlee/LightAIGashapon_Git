-- @module DeliverHandler
-- @author ramonqlee
-- @copyright idreems.com
-- @release 2017.12.23
-- tested 2018.1.7

require "Config"
require "Consts"
require "jsonex"
require "UartMgr"
require "TimeUtil"
require "UARTUtils"
require "CloudConsts"
require "UARTControlInd"
require "CloudBaseHandler"
require "ReplyDeliverHandler"
require "UploadSaleLogHandler"
require "CloudReplyBaseHandler"
require "UARTControlIndClose"
require "UploadDetection"

local TAG = "DeliverHandler"
local gBusyMap={}--是否在占用的记录

local mTimerId
DeliverHandler = CloudBaseHandler:new{
    MY_TOPIC = "deliver",
    ORDER_TIMEOUT_TIME_IN_SEC = "orderTimeOutTime",
    --支付方式
    PAY_ONLINE = "online",
    -- PAY_CASH = "cash",
    -- PAY_CARD = "card",
    DEFAULT_EXPIRE_TIME_IN_SEC=60,
    LOOP_TIME_IN_MS = 5*1000,-- 检查是否超时的时间间隔
    -- FIXME TEMP CODE
    ORDER_EXTRA_TIMEOUT_IN_SEC = 0--一个location的订单，如果超过了这个时间，则认为订单周期结束了(真的超时了)
}

-- 上传销售日志的的位置
local UPLOAD_POSITION="uploadPos"
local UPLOAD_NORMAL = "normal"--正常出货
local UPLOAD_TIMEOUT_ARRIVAL = "timeoutArrival"--到达即超时
local UPLOAD_BUSY_ARRIVAL = "busyArrival"--到达时有订单在处理
local UPLOAD_ARRIVAL_TRIGGER_TIMEOUT = "arrivalTriggerTimeout"--到达时，有订单超时了
local UPLOAD_TIMER_TIMEOUT= "TimerTimeout"--定时器检测到超时
local UPLOAD_DELIVER_AFTER_TIMEOUT= "DeliverAfterTimeout"--超时后出货
local UPLOAD_LOCK_TIMEOUT= "LockTimeout"--锁超时

--发送出货指令后，锁的状态
local LOCK_OPEN_STATE="s1state"
local LOCK_STATE_OPEN = "1"
local LOCK_STATE_CLOSED = "0"

function DeliverHandler.isDelivering()
    return (not gBusyMap and #gBusyMap>0)
end

local function getTableLen( tab )
    local count = 0  

    if "table"~=type(tab) then
        return count
    end

    for k,_ in pairs(tab) do  
        count = count + 1  
    end 

    return count 
end


function DeliverHandler:new (o)
    o = o or CloudBaseHandler:new(o)
    setmetatable(o, self)
    self.__index = self
    return o
end

function DeliverHandler:getDeliveringSize()
	return #mOrderVectors
end

function DeliverHandler:name()
    return self.MY_TOPIC
end

-- testPushStr = [[
-- {
--     "dup": 0,
--     "topic": "1000002/deliver",
--     "id": 3,
--     "payload": {
--         "timestamp": 1515284801,
--         "content": {
--             "device_seq": "1",
--             "location": "1",
--             "online_order_id": 1564010,
--             "sn": "9svwd1ql5m",
--             "expires": 1515284921,
--             "amount": 1
--         }
--     },
--     "qos": 2,
--     "packetId": 2
-- }
-- ]]

function DeliverHandler:handleContent( content )
 	-- TODO to be coded
    -- 出货
    -- 监听出货情况
    -- 超时未出货，上传超时错误
    if Consts.LOG_ENABLED then
        LogUtil.d(TAG,TAG.." handleContent content="..jsonex.encode(content))
    end

    local r = false
    if (not content) then
        return
    end

    -- 1. 合法性校验：字段全，没有超时，如果超时了，则直接发送出货日志，标志位超时
    -- 2. 收到出货通知后的回应
    -- 3. 否则开锁，然后启动定时器监控超时；
    -- 4. 超时后，上传超时出货日志；
    -- 5. 收到出货成功后，删除超时等待队列中的订单信息，然后上传出货日志
    local expired = content[CloudConsts.EXPIRED]
    local orderId = content[CloudConsts.ONLINE_ORDER_ID]
    local device_seq = content[CloudConsts.DEVICE_SEQ]
    local location = content[CloudConsts.LOCATION]
    local sn = content[CloudConsts.SN]
    if not expired or not orderId or not device_seq or not location or not sn then 
        LogUtil.d(TAG,TAG.." oopse,missing key")
        return
    end

    local saleLogMap = {}
    saleLogMap[CloudConsts.SN]= sn
    saleLogMap[CloudConsts.DEVICE_SEQ]= device_seq
    saleLogMap[CloudConsts.LOCATION]= location
    saleLogMap[CloudConsts.VM_ORDER_ID] = orderId
    saleLogMap[CloudConsts.ONLINE_ORDER_ID]= orderId
    saleLogMap[CloudConsts.DEVICE_ORDER_ID]= orderId

    saleLogMap[CloudConsts.SP_ID]= ""
    saleLogMap[CloudConsts.PAYER]= self.PAY_ONLINE
    saleLogMap[CloudConsts.PAID_AMOUNT]= 1
    saleLogMap[CloudConsts.VM_S2STATE]= "0"
    saleLogMap[DeliverHandler.ORDER_TIMEOUT_TIME_IN_SEC]= expired
    saleLogMap[LOCK_OPEN_STATE] = LOCK_STATE_CLOSED--出货时设置锁的状态为关闭

    if expired<os.time() then
        LogUtil.d(TAG,TAG.." timeout orderId="..orderId.." expired ="..expired.." os.time()="..os.time())
        saleLogMap[CloudConsts.CTS]=os.time()
        saleLogMap[UPLOAD_POSITION]=UPLOAD_TIMEOUT_ARRIVAL
        saleLogHandler = UploadSaleLogHandler:new()
        saleLogHandler:setMap(saleLogMap)
        saleLogHandler:send(CloudReplyBaseHandler.TIMEOUT_WHEN_ARRIVE)--超时的话，直接上报失败状态
        return
    end

    local map={}
    map[CloudConsts.SN] = sn
    MqttReplyHandlerMgr.replyWith(ReplyDeliverHandler.MY_TOPIC,map)
    
    timeoutInSec = expired-os.time()
    LogUtil.d(TAG," expired ="..expired.." orderId="..orderId.." device_seq="..device_seq.." location="..location.." sn="..sn.." timeoutInSec ="..timeoutInSec)

    -- 2. 同一location，产生了新的订单(新的订单id),之前较早是的location对应的订单就该删除了
    for key,saleTable in pairs(gBusyMap) do
        if saleTable then
            -- 同一个弹仓，如果没超过订单本身的expired，则认为当前location对应的上次订单还没处理完，则将当前订单报繁忙(如果是出货成功了，则不会在这个缓存列表中)
            -- 如果超过订单本身的expired，则认为可以处理下一个出货了
            tmpOrderId = saleTable[CloudConsts.ONLINE_ORDER_ID]
            tmpLoc = saleTable[CloudConsts.LOCATION]
            tmpDeviceSeq = saleTable[CloudConsts.DEVICE_SEQ]

            -- 同一个扭蛋机的同一个弹仓
            if tmpOrderId and tmpLoc and tmpDeviceSeq and tmpDeviceSeq == device_seq and tmpLoc == location and orderId ~= tmpOrderId  then
                saleLogHandler = UploadSaleLogHandler:new()

                --相同location，之前的订单还没到过期时间,那么当前的订单直接上报硬件繁忙
                if os.time()<saleTable[DeliverHandler.ORDER_TIMEOUT_TIME_IN_SEC] then
                    saleLogMap[CloudConsts.CTS]=os.time()
                    saleLogMap[UPLOAD_POSITION]=UPLOAD_BUSY_ARRIVAL

                    saleLogHandler:setMap(saleLogMap)
                    saleLogHandler:send(CloudReplyBaseHandler.BUSY)

                    LogUtil.d(TAG,TAG.." oopse, duplicate request for device_seq = "..device_seq.." location = "..location.." ignored order ="..orderId)
                    --当前的location，有订单在处理中，上报后，直接返回，不再继续开锁
                    return
                else
                    --之前的订单已经超时了，那么上报状态，并且从缓存中删除
                    saleTable[DeliverHandler.ORDER_TIMEOUT_TIME_IN_SEC]=nil--remove this key
                    saleTable[CloudConsts.CTS]=os.time()
                    saleTable[UPLOAD_POSITION]=UPLOAD_ARRIVAL_TRIGGER_TIMEOUT

                    saleLogHandler:setMap(saleTable)
                    saleLogHandler:send(CloudReplyBaseHandler.NOT_ROTATE)

                    gBusyMap[key]=nil
                    LogUtil.d(TAG,TAG.." in deliver, previous order timeout, orderId ="..tmpOrderId)
                    break
                end
            end 
        end
    end 


    -- 开锁
    if "string" == type(device_seq) then
        addr = string.fromhex(device_seq)--pack.pack("b3",0x00,0x00,0x06)  
        elseif "number"==type(device_seq) then
            addr = string.format("%2X",device_seq)
        end

        if not addr then
            return
        end

        UARTStatusReport.setCallback(openLockCallback)
        r = UARTControlInd.encode(addr,location,timeoutInSec)

        UartMgr.publishMessage(r)

        LogUtil.d(TAG,TAG.." Deliver openLock,addr = "..string.tohex(addr))
        
        local key = device_seq.."_"..location
        gBusyMap[key]=saleLogMap

        LogUtil.d(TAG,TAG.." add to gBusyMap len="..getTableLen(gBusyMap))

        if Consts.DEVICE_ENV then
        --start timer monitor already
        if sys.timer_is_active(mTimerId) then
            LogUtil.d(TAG,TAG.." timer_is_active id ="..mTimerId)
        else
            mTimerId = sys.timer_loop_start(TimerFunc,self.LOOP_TIME_IN_MS)
        end
        
        -- 待增加最近一次出货的id
        Config.saveValue(CloudConsts.LAST_ID,orderId)

        audio.setVolume(7)
        audio.play(Consts.LOCK_AUDIO)
    end

end 

-- 开锁的回调
-- flagTable:二维数组
function  openLockCallback(addr,flagsTable)
    -- 订单开锁，并且出货成功了，直接删除，否则还需要等待如下条件
    -- 如下条件，在定时中实现
    -- 1. 订单过期了，现在是30分钟
    -- 2. 同一location，产生了新的订单

    -- 从订单中查找，如果有的话，则上传相应的销售日志
    if not addr or not flagsTable then
        return
    end

    LogUtil.d(TAG,TAG.."in openLockCallback gBusyMap len="..getTableLen(gBusyMap).." addr="..addr)

    local toRemove = {}
    for key,saleTable in pairs(gBusyMap) do
        if saleTable then
            seq = saleTable[CloudConsts.DEVICE_SEQ]
            loc = saleTable[CloudConsts.LOCATION]
            orderId = saleTable[CloudConsts.VM_ORDER_ID]

            LogUtil.d(TAG,TAG.." openLockCallback handled orderId ="..orderId.." seq = "..seq.." loc = "..loc)

            if loc and seq and seq == addr  then

                --  确认订单状态
                -- 旋扭锁控制状态(S1):
                --     指示当前的旋钮锁，是处于打开还是关闭状态:0 = 关闭;1=打开 
                -- 出货状态(S2):
                --      0为初始化状态  1为出货成功   2为出货超时（在协议设定的时间内用户未操作，锁已恢复锁止状态）
                
                loc = tonumber(loc)
                ok = UARTStatusReport.isDeliverOK(loc)

                -- 锁曾经开过，则将其增加到订单状态中，下次不再更新
                lockOpen = UARTStatusReport.isLockOpen(loc)
                if lockOpen then
                    saleTable[LOCK_OPEN_STATE] = LOCK_STATE_OPEN
                end

                -- 锁曾经开过，现在关上了，但是没出货
                if LOCK_STATE_OPEN==saleTable[LOCK_OPEN_STATE] and not lockOpen and not ok then
                        -- 上报超时日志
                        LogUtil.d(TAG,TAG.." openLockCallback delivered timeout")

                        saleTable[CloudConsts.CTS]=os.time()
                        saleTable[UPLOAD_POSITION]=UPLOAD_LOCK_TIMEOUT
                        local saleLogHandler = UploadSaleLogHandler:new()
                        saleLogHandler:setMap(saleTable)
                        
                        saleLogHandler:send(CloudReplyBaseHandler.NOT_ROTATE)

                        -- 添加到待删除列表中
                        toRemove[key] = 1
                        LogUtil.d(TAG,TAG.." add to to-remove tab,key = "..key)
                end

                -- 出货成功了
                if ok then
                    LogUtil.d(TAG,TAG.." openLockCallback delivered OK")

                    -- 上报出货检测
                    local detectTable = {}
                    detectTable[CloudConsts.AMOUNT]=1
                    detectTable[CloudConsts.SN]=saleTable[CloudConsts.SN]
                    detectTable[CloudConsts.ONLINE_ORDER_ID]=saleTable[CloudConsts.ONLINE_ORDER_ID]

                    detectionHandler = UploadDetection:new()
                    detectionHandler:setMap(detectTable)
                    detectionHandler:send()

                    -- 上报出货日志(如果已经上报过超时，就不再上报了)
                    if not saleTable[UPLOAD_POSITION] then
                        saleTable[CloudConsts.CTS]=os.time()
                        saleTable[UPLOAD_POSITION]=UPLOAD_NORMAL
                        local saleLogHandler = UploadSaleLogHandler:new()
                        saleLogHandler:setMap(saleTable)

                        s = CloudReplyBaseHandler.SUCCESS
                        if os.time() > saleTable[DeliverHandler.ORDER_TIMEOUT_TIME_IN_SEC] then
                            s = CloudReplyBaseHandler.DELIVER_AFTER_TIMEOUT--超时出货
                            saleTable[UPLOAD_POSITION]=UPLOAD_DELIVER_AFTER_TIMEOUT
                        end
                        saleLogHandler:send(s)
                    end

                    -- 添加到待删除列表中
                    toRemove[key] = 1
                    LogUtil.d(TAG,TAG.." add to to-remove tab,key = "..key)
                else
                    lockstate="close"
                    if lockOpen then
                        lockstate = "open"
                    end
                    LogUtil.d(TAG,TAG.." openLockCallback deliver lockstate = "..lockstate)
                end
            end
        end
    end

    --删除已经出货的订单,需要从最大到最小删除，
    if getTableLen(toRemove)>0 then
        LogUtil.d(TAG,TAG.." to remove gBusyMap len="..getTableLen(gBusyMap))
        for key,_ in pairs(toRemove) do
            gBusyMap[key]=nil
            LogUtil.d(TAG,TAG.." remove order with key = "..key)
        end
        LogUtil.d(TAG,TAG.." after remove gBusyMap len="..getTableLen(gBusyMap))
    end
end

function TimerFunc(id)
    if not gBusyMap then
        --LogUtil.d(TAG,TAG.." in TimerFunc gBusyMap is nil")
        sys.timer_stop(mTimerId)
        LogUtil.d(TAG,TAG.." deliver queue is empty, stop timer id ="..mTimerId)
        return
    end

    if 0 == getTableLen(gBusyMap) then
        LogUtil.d(TAG,TAG.." in TimerFunc gBusyMap len="..getTableLen(gBusyMap))
        sys.timer_stop(mTimerId)
        LogUtil.d(TAG,TAG.." deliver queue is empty, stop timer id ="..mTimerId)
        return
    end

-- 接上条件，在定时中实现（所有如下都基于一个前提，location对应的订单，出货失败时，会自动上报超时，然后触发超时操作）
    -- 1. 订单对应的出货，超过了超时时间；
    --修改为下次同一弹仓出货时，移除这次的或者等待底层硬件上报出货成功后，移除

    for key,saleTable in pairs(gBusyMap) do
        if saleTable then
           -- 是否超时了
           orderTimeoutTime=saleTable[DeliverHandler.ORDER_TIMEOUT_TIME_IN_SEC]
           if orderTimeoutTime then
               systemTime = os.time()
               orderId = saleTable[CloudConsts.ONLINE_ORDER_ID]
               seq = saleTable[CloudConsts.DEVICE_SEQ]
               loc = saleTable[CloudConsts.LOCATION]
               LogUtil.d(TAG,"TimeoutTable orderId = "..orderId.." timeoutTime at "..orderTimeoutTime.." seq = "..seq.." location="..loc)
               if systemTime > orderTimeoutTime then
                LogUtil.d(TAG,TAG.."in TimerFunc timeouted orderId ="..orderId)
                
                --上传超时，如果已经上传过，则不再上传
                if not saleTable[UPLOAD_POSITION] then
                    saleTable[UPLOAD_POSITION]=UPLOAD_TIMER_TIMEOUT
                    saleTable[CloudConsts.CTS]=systemTime

                    local saleLogHandler = UploadSaleLogHandler:new()
                    saleLogHandler:setMap(saleTable)
                    saleLogHandler:send(CloudReplyBaseHandler.NOT_ROTATE)
                end

                end
          end
    end
end

end     