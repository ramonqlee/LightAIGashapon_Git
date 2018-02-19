# OpenLuat　各模块发布消息ID和值详解

## link.lua
- ipStatus 多链接状态的值：
    - "IP INITIAL"  : 初始化PDP
    - "IP START"    ：启动PDP注册
    - "IP CONFIG"   ：配置场景
    - "IP GPRSACT"  ：场景已激活
    - "IP PROCESSING"   ： IP 数据阶段
    - "IP STATUS"   ：获得本地 IP 状态
    - "PDP DEACT"   : 场景被释放
- GPRS附着状态:
    - sys.publish("NET_GPRS_READY")
    - sys.publish("CONNECTION_LINK_ERROR") 

- IP 链路链接状态无效
    - sys.publish("LINK_STATE_INVALID")
- 未整理的

		--如果打开了通话功能 并且当前正在通话中使用异步通知连接失败
		print("link.connect:failed cause call exist")
		sys.dispatch("LINK_ASYNC_LOCAL_EVENT",statusind,id,"CONNECT FAIL")

	    --产生一个内部消息"USER_SOCKET_CONNECT"，通知“用户创建的socket连接状态发生变化”
	    if not linklist[id].tag then sys.dispatch("USER_SOCKET_CONNECT",usersckisactive()) end

        sys.dispatch("IP_STATUS_IND",status=="IP GPRSACT" or status=="IP PROCESSING" or status=="IP STATUS")
## sim.lua 
- SIM 卡正常情况
    - sys.publish("SIM_IND", "RDY")
- SIM 卡未检测到
    - sys.publish("SIM_IND", "NIST")
- SIM 卡开启PIN
    - sys.publish("SIM_IND_SIM_PIN")
- SIM 卡没准备好
    - sys.publish("SIM_IND", "NORDY")
- SIM 卡已读取IMSI
    - sys.publish("IMSI_READY")

## net.lua
- GSM 状态发生变化
    - sys.publish("NET_STATE_REGISTERED")
    - sys.publish("NET_STATE_UNREGISTER")
- GSM 小区号发生变化
    - sys.publish("NET_CELL_CHANGED")
- GSM 有效小区号发布
    - sys.publish("CELL_INFO_IND", cellinfo)
- GSM 读取到信号质量
    - sys.publish("GSM_SIGNAL_REPORT_IND", success, rssi)

## pins.lua
- GPIO 中断消息
    - sys.publish("INT_GPIO_TRIGGER", pio.pin, "NEG")
