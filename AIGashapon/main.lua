--必须在这个位置定义PROJECT和VERSION变量
--PROJECT：ascii string类型，可以随便定义，只要不使用,就行
--VERSION：ascii string类型，如果使用Luat物联云平台固件升级的功能，必须按照"X.X.X"定义，X表示1位数字；否则可随便定义
MODULE_TYPE = "Air202"
PROJECT = "AIGashapon"

VERSION = "1.1.74"


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
require "sys"
require "mywd"
require "Config"
require "update"
require "Task"


LOG_LEVEL=log.LOGLEVEL_TRACE

local function restart()
	print("receive restart cmd ")
	sys.restart("restart")--重启更新包生效
end

sys.subscribe("FOTA_DOWNLOAD_FINISH",restart)	--升级完成会发布FOTA_DOWNLOAD_FINISH消息
sys.subscribe(Consts.REBOOT_DEVICE_CMD,restart)	--重启设备命令

require "utils"
-- 加载GSM
require "net"
--5秒后查询第一次csq
-- net.startQueryAll(5 * 1000, 600 * 1000)
-- 控制台
require "console"
local CONSOLE_UART_ID = 2
console.setup(CONSOLE_UART_ID, 115200)--默认为1，和现有app冲突，修改为2
-- 系统工具
require "misc"
-- 看门狗
-- require "wdt"
-- wdt.setup(pio.P0_31, pio.P0_29)

require "ntp"
ntp.timeSync()
require "http"
require "audio"

-- FIXME 暂时注释掉，测试用
require "entry"
entry.run()

-- 启动系统框架
sys.init(0, 0)
sys.run()
