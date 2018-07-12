-- @module UARTAllInfoReport
-- @author ramonqlee
-- @copyright idreems.com
-- @release 2017.12.29
-- @tested 2018.2.3

require "LogUtil"
require "jsonex"
require "Config"

local TAG = "UARTAllInfoReport"
local ALL_INFO_CACHE_KEY = "allInfos"

UARTAllInfoReport = {
MT = 0x93
}

local mAllBoardIds = {}
local myCallback = nil

function  UARTAllInfoReport.setCallback( callback )
	myCallback = callback
end

--返回最后匹配的一个字节位置
function UARTAllInfoReport.handle(bins)
	local noMatch=-1
	-- 回调
	-- 返回协议数据，上报机器状态用
	-- 首先校验合法性
	-- 开始数据，数据长度，地址，类型，校验和

	if bins == nil or type(bins) ~= "string" then return noMatch,noMatch end

		--找到开始的数据
		local ignoreHeaderLen = 2
		local startPos = -1
		for i=1,#bins do
			if UARTUtils.RCV == string.byte(bins,i) then
				startPos=i
				-- --LogUtil.d(TAG,"find startPos = "..startPos)
				break
			end
		end

		if startPos < 0 then
			return noMatch,startPos
		end

		local lenPos=startPos+1
		local boardIdAddressPos = lenPos+1
		local messageTypePos = boardIdAddressPos+3
		local dataPos = messageTypePos+1
		tmp = string.byte(bins,lenPos)

		if messageTypePos > #bins then
			return noMatch,startPos
		end
		
		mt = string.byte(bins,messageTypePos)
		if mt ~= UARTAllInfoReport.MT then
			-- --LogUtil.d(TAG,"illegal MT,mt = "..mt.." my MT = "..UARTAllInfoReport.MT)
			return noMatch,startPos
		end

		local chkPos = lenPos+tmp-1

	-- 长度是否合法
	if #bins < boardIdAddressPos then
		-- --LogUtil.d(TAG,"illegal boardIdAddressPos")
		return noMatch,startPos
	end

	len = string.byte(bins,lenPos)
	if #bins<len+ignoreHeaderLen then
		-- --LogUtil.d(TAG,"illegal length")
		return noMatch,startPos
	end

	-- 校验和是否合法
	chkInBin = string.sub(bins,chkPos,chkPos+1)
	temp = string.sub(bins,startPos+2,chkPos-1)

	chk = UARTUtils.chk(temp)
	chkInHex = string.format("%04X",chk)

	if chkInHex ~= string.tohex(chkInBin) then
		--LogUtil.d(TAG,"illegal chk,calculate chkInHex ="..chkInHex.." chkInBin="..string.tohex(chkInBin))
		return noMatch,startPos
	end


	idsLen = string.byte(bins,dataPos+1)
	idsPos = dataPos+2

	if 0 == idsLen then
		LogUtil.d(TAG,"no ids returned")
		UARTAllInfoReport.notifiyCallback()
		return chkPos+1,startPos
	end

	ids=string.sub(bins,idsPos)
	-- --LogUtil.d(TAG,"ids ="..string.tohex(ids))
	j = 1
	id1,id2,id3=0,0,0
	for i=1,idsLen do
		r = string.byte(ids,i)

		-- for next loop
		if 0 ==j then
			j = 1
		end

		if 3 == j then
			id3 = string.format("%02X",r)

			-- add to array and rest
			-- temp = pack.pack("b3",id1,id2,id3)
			temp = id1..id2..id3
			mAllBoardIds[#mAllBoardIds+1]=temp
			LogUtil.d(TAG,"find device = "..temp)
			j = 0
		end

		if 2 == j then
			id2 = string.format("%02X",r)
			j = j+1
		end

		if 1 == j then 
			id1 = string.format("%02X",r)
			j = j+1
		end
	end

	UARTAllInfoReport.notifiyCallback()

	return chkPos+1,startPos
end

function UARTAllInfoReport.getAllBoardIds(returnCacheIfEmpty)
	-- 查看内存，如果为空，则尝试返回本地的；否则直接返回内存中的
	if mAllBoardIds and #mAllBoardIds>0 then
		-- LogUtil.d(TAG,"getAllBoardIds size = "..#mAllBoardIds)
		return mAllBoardIds
	end

	if returnCacheIfEmpty then
		tmp = Config.getValue(ALL_INFO_CACHE_KEY)
		if tmp and "string"==type(tmp) and #tmp>0 then
			mAllBoardIds = jsonex.decode(tmp)
			-- LogUtil.d(TAG,"cached getAllBoardIds size = "..#mAllBoardIds)
		end
	end

	return mAllBoardIds
end

function UARTAllInfoReport.notifiyCallback()
	-- 是否保留之前获得的id
	if Consts.EANBLE_MERGE_BOARD_ID then
		tmp = Config.getValue(ALL_INFO_CACHE_KEY)
		if tmp and "string"==type(tmp) and #tmp>0 then
			local existAllBoardIds = jsonex.decode(tmp)
			if existAllBoardIds and #existAllBoardIds >0 then
				for _,addr in pairs(existAllBoardIds) do
					if not UARTAllInfoReport.hasIds(addr) then
						mAllBoardIds[#mAllBoardIds+1]=addr
					end
				end
			end
		end
	end

	-- 做缓存和更新
	-- 如果获取了新的，则直接缓存
	if mAllBoardIds and #mAllBoardIds>0 then
		Config.saveValue(ALL_INFO_CACHE_KEY,jsonex.encode(mAllBoardIds))
	end

	if myCallback then
		myCallback(mAllBoardIds)
	end
end

-- 当前内存中返回的id是否已经包含
function UARTAllInfoReport.hasIds(id)
	if not mAllBoardIds or 0 == #mAllBoardIds then
		return false
	end

	for _,addr in pairs(mAllBoardIds) do
		if addr==id then
			return true
		end
	end
	return false
end

