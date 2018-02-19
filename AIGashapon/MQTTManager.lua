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
require "TimeUtil"
require "CloudConsts"
require "Lightup"
require "DeliverHandler"
require "GetTimeHandler"
require "ReplyTimeHandler"
require "SetConfigHandler"
require "GetLatestSaleLog"
require "GetMachineVars"
local jsonex = require "jsonex"

-- FIXME username and password to be retrieved from server
local RETRY_TIME=10000
local DISCONNECT_WAIT_TIME=5000
local KEEPALIVE,CLEANSESSION=5,1
local PROT,ADDR,PORT =Consts.PROTOCOL,Consts.MQTT_ADDR,Consts.MQTT_PORT
local QOS,RETAIN=2,0
-- local RETRY_COUNT = 3
local mqttc
local toPublishMessages={}


local TAG = "MQTTManager"
local wd = nil


-- MQTT request
local MQTT_DISCONNECT_REQUEST ="disconnect"

local toHandleRequests={}

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
    if not Consts.DEVICE_ENV then
        --LogUtil.d(TAG,"not device,startmqtt and return")
        return
    end

    local count = 0
    local okCount = 0
    local COUNT_MAX = 100

    while true do
        -- collectgarbage("collect")
        -- c = collectgarbage("count")
        --LogUtil.d("Mem"," line:"..debug.getinfo(1).currentline.." memory count ="..c)

        while not link.isReady() do
            LogUtil.d(TAG,".............................socket not ready.............................")
             mywd.feed()--断网了，别忘了喂狗，否则会重启
             sys.wait(RETRY_TIME)
         end

         USERNAME = Consts.getUserName(false)
         PASSWORD = Consts.getPassword(false)
         while not USERNAME or 0==#USERNAME or not PASSWORD or 0==#PASSWORD do
            mywd.feed()--获取配置中，别忘了喂狗，否则会重启
            USERNAME,PASSWORD = MQTTManager.getNodeIdAndPasswordFromServer()
            mywd.feed()--获取配置中，别忘了喂狗，否则会重启
            LogUtil.d(TAG,".............................startmqtt retry to USERNAME="..USERNAME.." and ver=".._G.VERSION)
            sys.wait(RETRY_TIME)
        end   

        LogUtil.d(TAG,".............................startmqtt username="..USERNAME.." PASSWORD="..PASSWORD)
        if not mqttc then
            mqttc = mqtt.client(USERNAME,KEEPALIVE,USERNAME,PASSWORD,CLEANSESSION)
        end

        while not mqttc.connected and not mqttc:connect(ADDR,PORT) do
            mywd.feed()--获取配置中，别忘了喂狗，否则会重启
            LogUtil.d(TAG,"fail to connect mqtt,try after 10s")
            sys.wait(RETRY_TIME)
        end

        mywd.feed()--准备启动主逻辑了，别忘了喂狗，否则会重启

        LogUtil.d(TAG,"subscribe mqtt now")
        local topic=string.format("%s/#", USERNAME)
        if mqttc.connected and mqttc:subscribe(topic,QOS) then

            Config.saveValue(CloudConsts.NODE_ID,USERNAME)
            Config.saveValue(CloudConsts.PASSWORD,PASSWORD)

            LogUtil.d(TAG,".............................subscribe topic ="..topic)

            local mMqttProtocolHandlerPool={}
            mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=ReplyTimeHandler:new(nil)
            mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=SetConfigHandler:new(nil)
            mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=GetMachineVars:new(nil)
            mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=GetLatestSaleLog:new(nil)
            mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=DeliverHandler:new(nil)
            mMqttProtocolHandlerPool[#mMqttProtocolHandlerPool+1]=Lightup:new(nil)

            while true do
                if not mqttc.connected then
                    LogUtil.d(TAG," mqttc.disconnected,break") 
                    break
                end

            -- 发送待发送的消息
            MQTTManager.publishMessageQueue()

            if ntp.isEnd() and not Consts.LAST_REBOOT then
                Consts.LAST_REBOOT = os.time()
            end

            mywd.feed()--等待返回数据，别忘了喂狗，否则会重启
            local r, data = mqttc:receive(1000)

            if not data then
                LogUtil.d(TAG," mqttc.receive error,break") 
                break
            end
            MQTTManager.handleRequst()

            --oopse disconnect
            if not mqttc.connected then
                LogUtil.d(TAG," mqttc.disconnected,break")
                break
            end

            if r and data then
                okCount = okCount+1
                if okCount > COUNT_MAX then
                    okCount = 0
                end
                -- dataStr = jsonex.encode(data)
                --LogUtil.d(TAG,".............................receive str="..dataStr)
                
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
                count = count + 1
                if count > COUNT_MAX then--每隔100次为一个计数周期
                    count = 0
                end

                if data and count and okCount then
                    log.info('testMqtt.publish', "error message = "..data, count.." okCount="..okCount.." ver=".._G.VERSION)
                end
                
                -- collectgarbage("collect")
                -- c = collectgarbage("count")
                --LogUtil.d("Mem"," line:"..debug.getinfo(1).currentline.." memory count ="..c)
            end
        end
    end
    mqttc:disconnect()
end
end

function MQTTManager.publishMessageQueue()
    -- 在此发送消息,避免在不同coroutine中发送的bug
    if not toPublishMessages or 0 == #toPublishMessages then
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

    for _,msg in pairs(toPublishMessages) do
        topic = msg.topic
        payload = msg.payload

        if topic and payload  then
            LogUtil.d(TAG,"publish topic="..topic.." payload="..payload)
            local r = mqttc:publish(topic,payload,QOS,RETAIN)
            val = "false"
            if r then
                val = "true"
            end
            -- LogUtil.d(TAG,"publish result = "..val)
        end 
    end

    toPublishMessages={}
end

function MQTTManager.handleRequst()
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

function MQTTManager.publish(topic, payload)
    toPublishMessages=toPublishMessages or{}
    
    msg={}
    msg.topic=topic
    msg.payload=payload
    toPublishMessages[#toPublishMessages+1]=msg

    --LogUtil.d(TAG,"add to publish queue,topic="..topic.." #toPublishMessages="..#toPublishMessages)
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











