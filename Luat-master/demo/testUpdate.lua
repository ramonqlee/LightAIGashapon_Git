--- 模块功能：testUpdate
-- @module test
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.1.10
-- @describe 检查是否有更新包
require"update"
require"sys"
module(...,package.seeall)

update.run()				 -- 检测是否有更新包

local function restart()
	print("update success")
	rtos.restart()				--重启更新包生效
end

sys.taskInit(function()
	while true do
		print("version",_G.VERSION)
		sys.wait(3000)	--挂起5s
	end
end)

sys.subscribe("FOTA_DOWNLOAD_FINISH",restart)	--升级完成会发布FOTA_DOWNLOAD_FINISH消息


