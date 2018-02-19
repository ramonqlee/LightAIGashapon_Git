-- @module msgcache
-- @author ramonqlee
-- @copyright idreems.com
-- @release 2018.2.8

require "LogUtil"
require "Config"
require "jsonex"

local MAX_MQTT_CACHE_COUNT = 30--缓存的最大数量
local DECR_MQTT_CACHE_COUNT = 15--超过条数后，每次删除的数量
local SN_SET_PERSISTENCE_KEY="msg_sn_set"

local TAG = "MSGCACHE"

msgcache={}
function msgcache.clear()
    Config.saveValue(SN_SET_PERSISTENCE_KEY,"")
end


--添加到msg缓存,如果不存在，则返回true；如果已经存在，则返回false
function msgcache.addMsg2Cache(msg)
    r = false
    --解析msg中的sn
    if not msg then
        return r
    end

    local tableObj = msg
    if "string"==type(tableObj) then
        tableObj = jsonex.decode(msg)
    end

    if not tableObj or "table"~=type(tableObj) then
        return r
    end

    payload = tableObj[CloudConsts.PAYLOAD]
    if "string"==type(payload) then
      payload = jsonex.decode(payload)
  end

  if not payload or "table" ~= type(payload) then
    return r
  end

    content = payload[CloudConsts.CONTENT]
    if not content or "table" ~= type(content) then
        return r
    end

    sn = content[CloudConsts.SN]
    if not sn then 
        return r
    end


    --从文件中提取历史消息，然后进行追加
    local mqttMsgSet = {}
    allset = Config.getValue(SN_SET_PERSISTENCE_KEY)
    if allset and "string"==type(allset) and #allset>0 then
        mqttMsgSet = jsonex.decode(allset)
    end 

    if not mqttMsgSet then
        mqttMsgSet = {}
    end  

    --缓存数量超了，删除最早加入的那个
    if #mqttMsgSet >= MAX_MQTT_CACHE_COUNT then
        --从头部开始删除
        for i=1,DECR_MQTT_CACHE_COUNT do
            if 0 == #mqttMsgSet then
                break
            end
            table.remove(mqttMsgSet,1)
        end
        
        Config.saveValue(SN_SET_PERSISTENCE_KEY,jsonex.encode(mqttMsgSet))
    end

    for _,value in ipairs(mqttMsgSet) do
        if value == sn then
         LogUtil.d(TAG,sn.." duplicate sn in queue,size="..#mqttMsgSet)
         return false
        end
    end

    mqttMsgSet[#mqttMsgSet+1]=sn--不存在的话，则记录下
    Config.saveValue(SN_SET_PERSISTENCE_KEY,jsonex.encode(mqttMsgSet))

    LogUtil.d(TAG,sn.." added to queue,size="..#mqttMsgSet)

    return true
end     


