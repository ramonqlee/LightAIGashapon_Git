--必须在这个位置定义PROJECT和VERSION变量
--PROJECT：ascii string类型，可以随便定义，只要不使用,就行
--VERSION：ascii string类型，如果使用Luat物联云平台固件升级的功能，必须按照"X.X.X"定义，X表示1位数字；否则可随便定义
MODULE_TYPE = "Air202"
PROJECT = "AIGashapon"
VERSION = "1.1.20"

--[[
使用Luat物联云平台固件升级的功能，必须按照以下步骤操作：
1、打开Luat物联云平台前端页面：https://iot.openluat.com/
2、如果没有用户名，注册用户
3、注册用户之后，如果没有对应的项目，创建一个新项目
4、进入对应的项目，点击左边的项目信息，右边会出现信息内容，找到ProductKey：把ProductKey的内容，赋值给PRODUCT_KEY变量
]]
PRODUCT_KEY = "ysXG3WqbjNsSyRr0Y5T7LARnkgavKWw7"

-- FIXME 暂时注释掉
-- 日志级别
require "Consts"
require "log"
LOG_LEVEL = log.LOGLEVEL_TRACE--log.LOG_SILENT-
require "sys"
require "mywd"
require "update"
require "Config"
require "Task"

local LAST_UPDATE_TIME="lastUpdateTime"
local LAST_TASK_TIME="lastTaskTime"

local function restart()
	print("receive restart cmd ")
	current = os.time()

	if current then
		Config.saveValue(LAST_UPDATE_TIME,current)
		print("updateNewVersionTime = "..current.." from version=".._G.VERSION)
	end

	sys.restart("restart")--重启更新包生效
end

sys.subscribe("FOTA_DOWNLOAD_FINISH",restart)	--升级完成会发布FOTA_DOWNLOAD_FINISH消息
sys.subscribe(Consts.REBOOT_DEVICE_CMD,restart)	--重启设备命令

-- 自动升级检测
sys.timer_loop_start(function()
	--避免出现升级失败时，多次升级
	time = Config.getValue(LAST_UPDATE_TIME)
	print("type(time)="..type(time))
	if not time or "number"~=type(time) then
		Config.saveValue(LAST_UPDATE_TIME,0)
		time = 0
	end

	current = os.time()
	if current then
		print("lastUpdateTime = "..time.." current ="..current.." MIN_UPDATE_INTERVAL="..Consts.MIN_UPDATE_INTERVAL )
		if (current-time)<Consts.MIN_UPDATE_INTERVAL then
			print("update too often,ignore")
			return
		end
	end
	update.run() -- 检测是否有更新包
end,Consts.UPDATE_PERIOD)



--任务检测
sys.timer_loop_start(function()
	--避免出现升级失败时，多次升级
	time = Config.getValue(LAST_TASK_TIME)
	print("type(time)="..type(time))
	if not time or "number"~=type(time) then
		Config.saveValue(LAST_TASK_TIME,0)
		time = 0
	end

	current = os.time()
	if current then
		print("lastTaskTime = "..time.." current ="..current.." MIN_TASK_INTERVAL="..Consts.MIN_TASK_INTERVAL )
		if (current-time)<Consts.MIN_TASK_INTERVAL then
			print("task check too often,ignore")
			return
		end
	end
	Task.getTask()				 -- 检测是否有新任务
end,Consts.TASK_PERIOD)


require "utils"
-- 加载GSM
require "net"
--8秒后查询第一次csq
net.startQueryAll(5 * 1000, 600 * 1000)
-- 控制台
require "console"
console.setup(2, 115200)--默认为1，和现有app冲突，修改为2
-- 系统工具
require "misc"
-- 看门狗
require "wdt"
wdt.setup(pio.P0_31, pio.P0_29)

require "ntp"
ntp.timeSync()
require "http"
require "audio"

-- FIXME 暂时注释掉，测试用
require "entry"
entry.run()

-- require "testUart"

-- 启动系统框架
sys.init(0, 0)
sys.run()
