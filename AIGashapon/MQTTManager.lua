-- @module MQTTManager
-- @author ramonqlee
-- @copyright idreems.com
-- @release 2017.12.21

require "Consts"
if  Consts.DEVICE_ENV then
    require "misc"
    require "sys"
    require "mqtt"
    require "link"
    require "http"
end 
require "net"
require "mywd"
require "msgcache"
require "Config"
require "Consts"
require "LogUtil"
require "UartMgr"
require "Lightup"
require "CloudConsts"
require "NodeIdConfig"
require "GetMachineVars"
require "DeliverHandler"
require "GetTimeHandler"
require "ReplyTimeHandler"
require "SetConfigHandler"

local jsonex = require "jsonex"

local MAX_MQTT_FAIL_COUNT = 2--mqtt连接失败2次
local MAX_NET_FAIL_COUNT = 6*5--断网5分钟，会重启
local RETRY_TIME=10000
local DISCONNECT_WAIT_TIME=5000
local KEEPALIVE,CLEANSESSION=60,0
local CLEANSESSION_TRUE=1
local MAX_RETRY_SESSION_COUNT=2--重试n次后，如果还事变，则清理服务端的消息
local PROT,ADDR,PORT =Consts.PROTOCOL,Consts.MQTT_ADDR,Consts.MQTT_PORT
local QOS,RETAIN=2,1
local CLIENT_COMMAND_TIMEOUT = 5000
local CLIENT_COMMAND_SHORT_TIMEOUT = 1000
local MAX_MSG_CNT_PER_REQ = 1--每次最多发送的消息数
local mqttc
local toPublishMessages={}
local fdTimerId = nil

local TAG = "MQTTManager"
local wd = nil
local reconnectCount = 0
local mainLoopTime = 0--上次mqtt处理的时间，用于判断是否主循环正常进行
local timedTaskId

-- MQTT request
local MQTT_DISCONNECT_REQUEST ="disconnect"
local RESTART_REQUEST = "restart"
local MAX_MQTT_RECEIVE_COUNT = 2

local toHandleRequests={}

local function timeSync()
    if Consts.timeSynced then
        return
    end

    -- 如果超时过了重试次数，则停止，防止消息过多导致服务端消息堵塞
    if Consts.timeSyncCount > Consts.MAX_TIME_SYNC_COUNT then
        LogUtil.d(TAG," timeSync abort because count exceed,ignore this request")
        return
    end

    if Consts.gTimerId and sys.timer_is_active(Consts.gTimerId) then
        return
    end

    Consts.gTimerId=sys.timer_loop_start(function()
            Consts.timeSyncCount = Consts.timeSyncCount+1

            if Consts.timeSyncCount > Consts.MAX_TIME_SYNC_COUNT then
                LogUtil.d(TAG," timeSync abort because count exceed,now stop timer")

                if Consts.gTimerId and sys.timer_is_active(Consts.gTimerId) then
                    sys.timer_stop(Consts.gTimerId)
                end
                return
            end

            local handle = GetTimeHandler:new()
            handle:sendGetTime(os.time())

            LogUtil.d(TAG,"timeSync count =="..Consts.timeSyncCount)

        end,Consts.TIME_SYNC_INTERVAL_MS)
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

MQTTManager={}

function MQTTManager.getNodeIdAndPasswordFromServer()
    nodeId,password="",""
    -- TODO 
    imei = misc.getimei()
    sn = crypto.md5(imei,#imei)

    url = string.format(Consts.MQTT_CONFIG_NODEID_URL_FORMATTER,imei,sn)
    --LogUtil.d(TAG,"url = "..url)
    local code, header, body = http.request("GET", url, 15000)
    -- local code, header, body = http.request(url, "POST")
    if not code then
        --LogUtil.d(TAG,"http empty code,return")
        return nodeId,password
    end

    --LogUtil.d(TAG,"http code = "..code)
    if "200" ~= code then
        return nodeId,password
    end

    if not body then
        --LogUtil.d(TAG,"http empty body,return")
        return nodeId,password
    end

    --LogUtil.d(TAG,"http config body="..body)
    bodyJson = jsonex.decode(body)

    if bodyJson then
        nodeId = bodyJson['node_id']
        password = bodyJson['password']
    end

    return nodeId,password
end

function MQTTManager.loopFeedDog()
    if not fdTimerId then
        fdTimerId = sys.timer_loop_start(function()

            LogUtil.d(TAG,"feeddog started")

            -- 如果主玄循环停止超过一定时间，，则认为程序出问题了，重启
            local timeOffset = os.time()-mainLoopTime
            if timeOffset < 0 then
                timeOffset = -timeOffset
            end

            if Consts.timeSynced and timeOffset > Consts.MAX_LOOP_INTERVAL then
                -- 如果在出货中，则不重启，防止出现数据丢失
                if DeliverHandler.isDelivering() then
                    LogUtil.d(TAG,TAG.." DeliverHandler.isDelivering,ignore reboot")
                    return
                end

                sys.timer_stop(fdTimerId)--停止看门狗喂狗，等待重启
                fdTimerId = nil

                LogUtil.d(TAG,"............softReboot when mainloop stop,timeOffset="..timeOffset.." os.time()="..os.time().." mainLoopTime="..mainLoopTime)
                sys.restart("deadMainLoop")--重启更新包生效
                return
            end

            mywd.feed()--断网了，别忘了喂狗，否则会重启
        end,Consts.FEEDDOG_PERIOD)
    end
end

function MQTTManager.checkMQTTUser()
    username = Consts.getUserName(false)
    password = Consts.getPassword(false)
    while not username or 0==#username or not password or 0==#password do
        mainLoopTime =os.time()
         -- mywd.feed()--获取配置中，别忘了喂狗，否则会重启
        username,password = MQTTManager.getNodeIdAndPasswordFromServer()
         -- mywd.feed()--获取配置中，别忘了喂狗，否则会重启
        if  username and password then
            LogUtil.d(TAG,".............................startmqtt retry to username="..username.." and ver=".._G.VERSION)
            -- 迁移到新的文件中，单独保存用户名和密码
            Consts.saveUserName(username)
            Consts.savePassword(password)
        end
        sys.wait(RETRY_TIME)
    end
    return username,password
end

function MQTTManager.checkNetwork()
    LogUtil.d(TAG,"prepare to switch reboot mode")
    -- 切换下次的重启方式
    local rebootMethod = Config.getValue(CloudConsts.REBOOT_METHOD)
    if not rebootMethod or #rebootMethod <=0 then
        rebootMethod = CloudConsts.SOFT_REBOOT
    end

    local nextRebootMethod = CloudConsts.WD_REBOOT--代表其他重启方式，目前为通过看门狗重启
    if CloudConsts.WD_REBOOT == rebootMethod then
        nextRebootMethod = CloudConsts.SOFT_REBOOT
    end
    Config.saveValue(CloudConsts.REBOOT_METHOD,nextRebootMethod)
    LogUtil.d(TAG,"rebootMethod ="..rebootMethod.." nextRebootMethod = "..nextRebootMethod)

    local netFailCount = 0
    while not link.isReady() do
        LogUtil.d(TAG,".............................socket not ready.............................")
        mainLoopTime =os.time()

        if netFailCount >= MAX_NET_FAIL_COUNT then
            -- 修改为看门狗和软重启交替进行的方式
            if CloudConsts.SOFT_REBOOT == rebootMethod then
                LogUtil.d(TAG,"............softReboot when not link.isReady")
                sys.restart("netFailTooLong")--重启更新包生效
                break
            end

            if nil ~= fdTimerId then
                LogUtil.d(TAG,"............wdReboot when not link.isReady")
                sys.timer_stop(fdTimerId)--停止看门狗喂狗，等待重启
                fdTimerId = nil
                break
            end
        end

        netFailCount = netFailCount+1
        sys.wait(RETRY_TIME)
    end
    sys.wait(RETRY_TIME)--wait for next loop
end

function MQTTManager.checkMQTTConnectivity()
    local mqttFailCount = 0
    LogUtil.d(TAG,"checkMQTTConnectivity in ")
    while not mqttc:connect(ADDR,PORT) do
        -- mywd.feed()--获取配置中，别忘了喂狗，否则会重启
        LogUtil.d(TAG,"fail to connect mqtt,mqttc:disconnect,try after 10s")
        mqttc:disconnect()
        mainLoopTime =os.time()

        mqttFailCount = mqttFailCount+1

        if mqttFailCount >= MAX_MQTT_FAIL_COUNT then
            Consts.clearUserName()
            Consts.clearPassword()--是否用户名，密码修改了
            break
        end
    end
    LogUtil.d(TAG,"checkMQTTConnectivity out ")
end

local startmqtted = false
local unsubscribe = false

function MQTTManager.startmqtt()
    --prevent re-entry
    if startmqtt then
        return
    end
    startmqtt = true

    LogUtil.d(TAG,"MQTTManager.startmqtt ver=".._G.VERSION.." reconnectCount = "..reconnectCount)
    if not Consts.DEVICE_ENV then
        return
    end

    mainLoopTime =os.time()

    -- 定时喂狗
    MQTTManager.loopFeedDog()

    while true do
        --检查网络，网络不可用时，会重启机器
        MQTTManager.checkNetwork()
        local USERNAME,PASSWORD = MQTTManager.checkMQTTUser()
        
        local mMqttProtocolHandlerPool={}
        mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=ReplyTimeHandler:new(nil)
        mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=SetConfigHandler:new(nil)
        mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=GetMachineVars:new(nil)
        mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=DeliverHandler:new(nil)
        mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=Lightup:new(nil)

        local topics = {}
        for _,v in pairs(mMqttProtocolHandlerPool) do
            topics[string.format("%s/%s", USERNAME,v:name())]=QOS
        end

        LogUtil.d(TAG,".............................startmqtt username="..USERNAME.." ver=".._G.VERSION.." reconnectCount = "..reconnectCount)
        if mqttc then
            mqttc:disconnect()
        end

        --清理服务端的消息
        if reconnectCount>=MAX_RETRY_SESSION_COUNT then
            LogUtil.d(TAG,".............................startmqtt CLEANSESSION all ".." reconnectCount = "..reconnectCount)
            mqttc = mqtt.client(USERNAME,KEEPALIVE,USERNAME,PASSWORD,CLEANSESSION_TRUE)
            MQTTManager.checkMQTTConnectivity()
            mqttc:disconnect()

            MQTTManager.emptyMessageQueue()
            MQTTManager.emptyExtraRequest()
            reconnectCount = 0
        end

        mqttc = mqtt.client(USERNAME,KEEPALIVE,USERNAME,PASSWORD,CLEANSESSION)

        MQTTManager.checkMQTTConnectivity()

        -- 先处理下之前的累计的消息
        MQTTManager.loopPreviousMessage(mMqttProtocolHandlerPool)

        --先取消之前的订阅
        if mqttc.connected and not unsubscribe then
            local unsubscribeTopic = string.format("%s/#",USERNAME)
            local r = mqttc:unsubscribe(unsubscribeTopic)
            if r then
                unsubscribe = true
            end
            local result = r and "true" or "false"
            LogUtil.d(TAG,".............................unsubscribe topic = "..unsubscribeTopic.." result = "..result)
        end
        
        if mqttc.connected and mqttc:subscribe(topics) then
            unsubscribe = false
            LogUtil.d(TAG,".............................subscribe topic ="..jsonex.encode(topics))

            MQTTManager.loopMessage(mMqttProtocolHandlerPool)
        end

        reconnectCount = reconnectCount + 1
    end
end

function MQTTManager.loopPreviousMessage( mqttProtocolHandlerPool )
    log.info(TAG, "loopPreviousMessage now")

    while true do
        if not mqttc.connected then
            break
        end

        local r, data = mqttc:receive(CLIENT_COMMAND_TIMEOUT)

        if not data then
            break
        end

        mainLoopTime =os.time()

        if r and data then
            -- 去除重复的sn消息
            if msgcache.addMsg2Cache(data) then
                for k,v in pairs(mqttProtocolHandlerPool) do
                    if v:handle(data) then
                        log.info(TAG, "loopPreviousMessage reconnectCount="..reconnectCount.." ver=".._G.VERSION.." ostime="..os.time())
                        mainLoopTime =os.time()
                        break
                    end
                end
            else
                log.info(TAG, "loopPreviousMessage dup msg")
            end
        else
            log.info(TAG, "loopPreviousMessage no more msg")
            break
        end
    end
    MQTTManager.emptyExtraRequest()--忽略请求
    log.info(TAG, "loopPreviousMessage done")
end


function MQTTManager.loopMessage(mqttProtocolHandlerPool)
    while true do
        if not mqttc.connected then
            mqttc:disconnect()
            LogUtil.d(TAG," mqttc.disconnected and no message,mqttc:disconnect() and break") 
            break
        end

        local timeout = CLIENT_COMMAND_TIMEOUT
        if MQTTManager.hasMessage() then
            timeout = CLIENT_COMMAND_SHORT_TIMEOUT
        end
        local r, data = mqttc:receive(timeout)

        if not data then
            mqttc:disconnect()
            LogUtil.d(TAG," mqttc.receive error,mqttc:disconnect() and break") 
            break
        end

        mainLoopTime =os.time()

        if r and data then
            -- 去除重复的sn消息
            if msgcache.addMsg2Cache(data) then
                for k,v in pairs(mqttProtocolHandlerPool) do
                    if v:handle(data) then
                        log.info(TAG, "reconnectCount="..reconnectCount.." ver=".._G.VERSION.." ostime="..os.time())
                        mainLoopTime =os.time()
                        break
                    end
                end
            else
                log.info(TAG, "loopMessage dup msg")
            end
        else
            if data then
                log.info(TAG, "msg = "..data.." reconnectCount="..reconnectCount.." ver=".._G.VERSION.." ostime="..os.time())
            end
            -- 发送待发送的消息，设定条数，防止出现多条带发送时，出现消息堆积
            MQTTManager.publishMessageQueue(MAX_MSG_CNT_PER_REQ)
            MQTTManager.handleRequst()
            -- collectgarbage("collect")
            -- c = collectgarbage("count")
            --LogUtil.d("Mem"," line:"..debug.getinfo(1).currentline.." memory count ="..c)
        end

        --oopse disconnect
        if not mqttc.connected then
            mqttc:disconnect()
            LogUtil.d(TAG," mqttc.disconnected and no message,mqttc:disconnect() and break")
            break
        end
    end
end

function MQTTManager.hasMessage()
    return toPublishMessages and  0~= getTableLen(toPublishMessages)
end
--控制每次调用，发送的消息数，防止发送消息，影响了收取消息
function MQTTManager.publishMessageQueue(maxMsgPerRequest)
    -- 在此发送消息,避免在不同coroutine中发送的bug
    if not toPublishMessages or 0 == getTableLen(toPublishMessages) then
        MQTTManager.handleExtraRequest()--没有消息发送时，请求额外的任务，防止出现联网冲突
        LogUtil.d(TAG,"publish message queue is empty")
        return
    end

    if not Consts.DEVICE_ENV then
        --LogUtil.d(TAG,"not device,publish and return")
        return
    end

    if not mqttc then
        --LogUtil.d(TAG,"mqtt empty,ignore this publish")
        return
    end

    if not mqttc.connected then
        --LogUtil.d(TAG,"mqtt not connected,ignore this publish")
        return
    end

    if maxMsgPerRequest <= 0 then
        maxMsgPerRequest = 0
    end

    local toRemove={}
    local count=0
    for key,msg in pairs(toPublishMessages) do
        topic = msg.topic
        payload = msg.payload

        if topic and payload  then
            LogUtil.d(TAG,"publish topic="..topic.." queue size = "..getTableLen(toPublishMessages))
            local r = mqttc:publish(topic,payload,QOS,RETAIN)
            
            -- 添加到待删除队列
            if r then
                toRemove[key]=1
            end

            count = count+1
            if maxMsgPerRequest>0 and count>=maxMsgPerRequest then
                LogUtil.d(TAG,"publish count = "..maxMsgPerRequest)
                break
            end
        end 
    end

    -- 清除已经成功的消息
    for key,_ in pairs(toRemove) do
        if key then
            toPublishMessages[key]=nil
        end
    end

end

function MQTTManager.handleRequst()
    timeSync()

    if MQTTManager.hasMessage() then
        return
    end

    if not toHandleRequests or 0 == #toHandleRequests then
        return
    end

    if not mqttc then
        return
    end

    LogUtil.d(TAG,"mqtt handleRequst")
    for _,req in pairs(toHandleRequests) do
        if MQTT_DISCONNECT_REQUEST == req then
            sys.wait(DISCONNECT_WAIT_TIME)
            LogUtil.d(TAG,"mqtt MQTT_DISCONNECT_REQUEST")
            mqttc:disconnect()
        end

        if RESTART_REQUEST == req then
            LogUtil.d(TAG,"............softReboot when timeout order arrive")
            sys.restart("netFailTooLong")--重启更新包生效
        end
    end

    toHandleRequests={}
end

-- 检查后台配置的任务和升级,防止和mqtt的联网出现冲突
function MQTTManager.handleExtraRequest()
end

function MQTTManager.publish(topic, payload)
    toPublishMessages=toPublishMessages or{}
    
    msg={}
    msg.topic=topic
    msg.payload=payload
    toPublishMessages[crypto.md5(payload,#payload)]=msg
    
    -- TODO 修改为持久化方式，发送消息

    LogUtil.d(TAG,"add to publish queue,topic="..topic.." toPublishMessages len="..getTableLen(toPublishMessages))
end


function MQTTManager.disconnect()
    if not mqttc then
        return
    end

    if not toHandleRequests then
        toHandleRequests = {}
    end

    toHandleRequests[#toHandleRequests+1] = MQTT_DISCONNECT_REQUEST
    LogUtil.d(TAG,"add to request queur,request="..MQTT_DISCONNECT_REQUEST.." #toHandleRequests="..#toHandleRequests)
end   

function MQTTManager.restart()
     if not toHandleRequests then
        toHandleRequests = {}
    end

    toHandleRequests[#toHandleRequests+1] = RESTART_REQUEST
 end

function MQTTManager.emptyExtraRequest()
      toHandleRequests={}
end 

function MQTTManager.emptyMessageQueue()
      toPublishMessages={}
end 












