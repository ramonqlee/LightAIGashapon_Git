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
require "mywd"
require "msgcache"
require "Config"
require "Consts"
require "LogUtil"
require "UartMgr"
require "Lightup"
require "TimeUtil"
require "ScanQrCode"
require "CloudConsts"
require "NodeIdConfig"
require "GetMachineVars"
require "DeliverHandler"
require "GetTimeHandler"
require "ReplyTimeHandler"
require "SetConfigHandler"
require "GetLatestSaleLog"


local jsonex = require "jsonex"

-- FIXME username and password to be retrieved from server
local MAX_MQTT_FAIL_COUNT = 20
local RETRY_TIME=10000
local DISCONNECT_WAIT_TIME=5000
local KEEPALIVE,CLEANSESSION=10,0
local PROT,ADDR,PORT =Consts.PROTOCOL,Consts.MQTT_ADDR,Consts.MQTT_PORT
local QOS,RETAIN=2,1
local CLIENT_COMMAND_TIMEOUT = 5000
local MAX_MSG_CNT_PER_REQ = 1--每次最多发送的消息数
-- local RETRY_COUNT = 3
local mqttc
local toPublishMessages={}
local fdTimerId = nil


local TAG = "MQTTManager"
local wd = nil
local mqttFailCount=0
local timeUpdated=false
local mainLoopTime = 0--上次mqtt处理的时间，用于判断是否主循环正常进行

-- MQTT request
local MQTT_DISCONNECT_REQUEST ="disconnect"
local MAX_MQTT_RECEIVE_COUNT = 2

local toHandleRequests={}
local lastUpdateCheckCount = 0
local lastCheckTaskCount = 0

local function timeSync()

    if Consts.gTimerId and sys.timer_is_active(Consts.gTimerId) then
        return
    end

    Consts.gTimerId=sys.timer_loop_start(function()
            local handle = GetTimeHandler:new()
            handle:sendGetTime(os.time())
            LogUtil.d(TAG,"timeSync now")
        end,Consts.TIME_SYNC_INTERVAL_MS)
end

-- 自动升级检测
function checkUpdate()
    --避免出现升级失败时，多次升级
    lastUpdateCheckCount = lastUpdateCheckCount+1

    if  lastUpdateCheckCount<Consts.MIN_UPDATE_INTERVAL then
        local left = Consts.MIN_TASK_INTERVAL - lastUpdateCheckCount
        LogUtil.d(TAG,"checkUpdate left count= "..left)
        return
    end

    update.run() -- 检测是否有更新包
    lastUpdateCheckCount = 0--reset count
    LogUtil.d(TAG,"start checkUpdate now")

    sys.wait(Consts.TASK_WAIT_IN_MS)--强制延时,等待完成
    local cnt=1
    local max_cnt = 5
    while update.isDownloading() do
        sys.wait(Consts.TASK_WAIT_IN_MS)--强制延时

        cnt = cnt+1
        if cnt > max_cnt then
            break
        end
    end
end


--任务检测
function checkTask()
   --避免出现升级失败时，多次升级
    lastCheckTaskCount = lastCheckTaskCount+1

    if lastCheckTaskCount<Consts.MIN_TASK_INTERVAL then
        local left = Consts.MIN_TASK_INTERVAL -lastCheckTaskCount
        LogUtil.d(TAG,"checkTask left count ="..left)
        return
    end

    LogUtil.d(TAG,"start checkTask now")
    Task.getTask()               -- 检测是否有新任务 
    lastCheckTaskCount = 0

    sys.wait(Consts.TASK_WAIT_IN_MS)--强制延时,等待完成
    local cnt=1
    local max_cnt = 5
    while Task.isRunning() do
        sys.wait(Consts.TASK_WAIT_IN_MS)--强制延时

        cnt = cnt+1
        if cnt > max_cnt then
            break
        end
    end
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

function MQTTManager.startmqtt()
    LogUtil.d(TAG,"MQTTManager.startmqtt")
    if not Consts.DEVICE_ENV then
        return
    end

    mainLoopTime =os.time()

    -- 定时喂狗
    if not fdTimerId then
        fdTimerId = sys.timer_loop_start(function()
            -- 如果主玄循环停止超过一定时间，，则认为程序出问题了，重启
            if os.time()-mainLoopTime> Consts.MAX_LOOP_INTERVAL then
                sys.timer_stop(fdTimerId)--停止看门狗喂狗，等待重启
                fdTimerId = nil

                LogUtil.d(TAG,"............softReboot when not mainloop stop")
                sys.restart("deadMainLoop")--重启更新包生效
                return
            end

            mywd.feed()--断网了，别忘了喂狗，否则会重启
        end,Consts.FEEDDOG_PERIOD)
    end

    LogUtil.d(TAG,"feeddog started")

    local count = 0
    local okCount = 0
    local COUNT_MAX = 60*60*24--一天
    local reconnectCount = 0

    netFailCount = 0

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

    while true do

        while not link.isReady() do
            LogUtil.d(TAG,".............................socket not ready.............................")
            mainLoopTime =os.time()

            if netFailCount >= MAX_MQTT_FAIL_COUNT then
                -- 修改为看门狗和软重启交替进行的方式
                if CloudConsts.SOFT_REBOOT == rebootMethod then
                    LogUtil.d(TAG,"............softReboot when not link.isReady")
                    sys.restart("netFailTooLong")--重启更新包生效
                elseif fdTimerId then
                    LogUtil.d(TAG,"............wdReboot when not link.isReady")
                    sys.timer_stop(fdTimerId)--停止看门狗喂狗，等待重启
                    fdTimerId = nil
                end
            end

            netFailCount = netFailCount+1
            sys.wait(RETRY_TIME)
         end

         netFailCount = 0

         mqttFailCount = 0
         USERNAME = Consts.getUserName(false)
         PASSWORD = Consts.getPassword(false)
         while not USERNAME or 0==#USERNAME or not PASSWORD or 0==#PASSWORD do
            mainLoopTime =os.time()
            -- mywd.feed()--获取配置中，别忘了喂狗，否则会重启
            USERNAME,PASSWORD = MQTTManager.getNodeIdAndPasswordFromServer()
            -- mywd.feed()--获取配置中，别忘了喂狗，否则会重启
            LogUtil.d(TAG,".............................startmqtt retry to USERNAME="..USERNAME.." and ver=".._G.VERSION)
            sys.wait(RETRY_TIME)
        end   

        LogUtil.d(TAG,".............................startmqtt username="..USERNAME.." PASSWORD="..PASSWORD)
        if not mqttc then
            mqttc = mqtt.client(USERNAME,KEEPALIVE,USERNAME,PASSWORD,CLEANSESSION)
        end
        
        while not mqttc:connect(ADDR,PORT) do
            -- mywd.feed()--获取配置中，别忘了喂狗，否则会重启
            LogUtil.d(TAG,"fail to connect mqtt,try after 10s")
            mainLoopTime =os.time()

            if mqttFailCount >= MAX_MQTT_FAIL_COUNT then
                -- 修改为看门狗和软重启交替进行的方式
                if CloudConsts.SOFT_REBOOT == rebootMethod then
                    LogUtil.d(TAG,"............softReboot when not mqtt.connect")
                   sys.restart("netFailTooLong")--重启更新包生效
                elseif fdTimerId then
                    LogUtil.d(TAG,"............wdReboot when not mqtt.connect")
                    sys.timer_stop(fdTimerId)--停止看门狗喂狗，等待重启
                    fdTimerId = nil
                end
            end

            mqttFailCount = mqttFailCount+1
            sys.wait(RETRY_TIME)
        end

        LogUtil.d(TAG,"subscribe mqtt now")
        -- local topic=string.format("%s/#", USERNAME)
        reconnectCount = reconnectCount + 1

        local mMqttProtocolHandlerPool={}
        mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=ReplyTimeHandler:new(nil)
        mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=SetConfigHandler:new(nil)
        mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=GetMachineVars:new(nil)
        mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=GetLatestSaleLog:new(nil)
        mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=DeliverHandler:new(nil)
        mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=Lightup:new(nil)
        mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=ScanQrCode:new(nil)

        local topics = {}
        for _,v in pairs(mMqttProtocolHandlerPool) do
            topics[string.format("%s/%s", USERNAME,v:name())]=QOS
        end

        --先取消之前的订阅
        unsubscribe = Config.getValue(Consts.UNSUBSCRIBE_KEY)
        if not unsubscribe then
            local unsubscribeTopic = string.format("%s/#",USERNAME)
            local r = mqttc:unsubscribe(unsubscribeTopic)
            if r then
                Config.saveValue(Consts.UNSUBSCRIBE_KEY,"1")
            end
            local result = r and "true" or "false"
            LogUtil.d(TAG,".............................unsubscribe topic = "..unsubscribeTopic.." result = "..result)
        end

        if mqttc.connected and mqttc:subscribe(topics) then
            LogUtil.d(TAG,".............................subscribe topic ="..jsonex.encode(topics))
            mqttFailCount = 0
            -- 迁移到新的文件中，单独保存用户名和密码
            NodeIdConfig.saveValue(CloudConsts.NODE_ID,USERNAME)
            NodeIdConfig.saveValue(CloudConsts.PASSWORD,PASSWORD)
            
            Config.saveValue(CloudConsts.NODE_ID,USERNAME)
            Config.saveValue(CloudConsts.PASSWORD,PASSWORD)

            local mqttReceiveErrCount=0
            
            while true do
                if not mqttc.connected then
                    LogUtil.d(TAG," mqttc.disconnected,break") 
                    break
                end

            -- 发送待发送的消息，设定条数，防止出现多条带发送时，出现消息堆积
            MQTTManager.publishMessageQueue(MAX_MSG_CNT_PER_REQ)

            if TimeUtil.timeSync() and not Consts.LAST_REBOOT then
                Consts.LAST_REBOOT = os.time()
            end

            -- send get_time
            if not timeUpdated then
                local handle = GetTimeHandler:new()
                handle:sendGetTime(os.time())
                timeUpdated = true
            end

            -- mywd.feed()--等待返回数据，别忘了喂狗，否则会重启
            local r, data = mqttc:receive(CLIENT_COMMAND_TIMEOUT)

            if not data then
                LogUtil.d(TAG," mqttc.receive error,break") 
            end

            MQTTManager.handleRequst()
            mainLoopTime =os.time()

            if Consts.LAST_REBOOT then
                okCount = os.time()-Consts.LAST_REBOOT
                if okCount > COUNT_MAX then
                    okCount = 0
                end
            end

            if r and data then
                -- dataStr = jsonex.encode(data)
                -- LogUtil.d(TAG,".............................receive str="..dataStr)
                
                -- 去除重复的sn消息
                if msgcache.addMsg2Cache(data) then
                    for k,v in pairs(mMqttProtocolHandlerPool) do
                        --LogUtil.d(TAG,v:name())
                        if v:handle(data) then
                            --LogUtil.d(TAG,v:name())
                            break
                        end
                    end
                end
            else
                if data and okCount then
                    log.info(TAG, "msg = "..data.." timeSinceBoot="..okCount.." reconnectCount="..reconnectCount.." ver=".._G.VERSION.." ostime="..os.time())
                end
                
                -- collectgarbage("collect")
                -- c = collectgarbage("count")
                --LogUtil.d("Mem"," line:"..debug.getinfo(1).currentline.." memory count ="..c)
            end

            --oopse disconnect
            if not mqttc.connected then
                LogUtil.d(TAG," mqttc.disconnected,break")
                break
            end
        end
    end
    mqttc:disconnect()
    LogUtil.d(TAG," mqttc.disconnected")
end
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
        maxMsgPerRequest = 1
    end

    local toRemove={}
    local count=0
    for key,msg in pairs(toPublishMessages) do
        topic = msg.topic
        payload = msg.payload

        if topic and payload  then
            LogUtil.d(TAG,"publish topic="..topic.." payload="..payload)
            -- mywd.feed()--等待返回数据，别忘了喂狗，否则会重启
            local r = mqttc:publish(topic,payload,QOS,RETAIN)
            
            -- 添加到待删除队列
            if r then
                toRemove[key]=1
            end

            count = count+1
            if count>=maxMsgPerRequest then
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

    LogUtil.d(TAG,"mqtt handleRequst")
    if not toHandleRequests or 0 == #toHandleRequests then
        return
    end

    if not mqttc then
        return
    end

    for _,req in ipairs(toHandleRequests) do
        if MQTT_DISCONNECT_REQUEST == req then
            sys.wait(DISCONNECT_WAIT_TIME)
            LogUtil.d(TAG,"mqtt MQTT_DISCONNECT_REQUEST")
            mqttc:disconnect()
        end
    end

    toHandleRequests={}
end

-- 检查后台配置的任务和升级,防止和mqtt的联网出现冲突
function MQTTManager.handleExtraRequest()
    checkTask()
    checkUpdate()
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











