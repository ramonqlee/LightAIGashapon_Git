## link.lua的执行逻辑

# 正常流程：

- 获取APN信息
    - SIM卡注册成功发送 "IMSI_READY" 消息，回调getApn(id,para) 函数设置apn。


- 启动connectionTask 任务

    > connectionTask任务是个死循环，它等待net.lua模块发送的消息`“NET_STATE_REGISTERED”`,然后启动该任务。

- 注册PDP以及链接网络所需要配置的参数

    > initial() 函数包括以下指令：

     - "AT+CIIRMODE=2"
     - "AT+CIPMUX = 1"
     - "AT+CIPQSEND = 0"
     - "AT+CIPHEAD = 1"
- 每隔2秒查询GPRS附着
    - "AT+CGATT?" 当返回 AT+CGATT=1 时，附着成功

- GPRS附着成功执行PDP注册
    - "AT+CSTT=\"" .. apnname .. '\",\"' .. username .. '\",\"' .. password .. "\"" 
    - "AT+CIICR"
    - "AT+CIFSR"

- 查询网络链接状态
    - "AT+CIPSTATUS" 如果返回IP STATUS 表示 IP地址获取成功

# 异常流程

- 