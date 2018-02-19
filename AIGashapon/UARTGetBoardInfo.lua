
-- @module UARTGetBoardInfo
-- @author ramonqlee
-- @copyright idreems.com
-- @release 2017.12.29
-- @tested 2018.01.28

require "UARTUtils"
require "LogUtil"

UARTGetBoardInfo={
	MT = 0x10
}

function UARTGetBoardInfo.encode()
	-- TODO待根据格式组装报文
 	data = pack.pack("b",0)--type=0

 	--LogUtil.d(TAG,"UARTGetBoardInfo pack data = "..string.tohex(data))
 	
 	-- function  UARTUtils.encode( sf,addr,mt,data )
 	sf = pack.pack("b",UARTUtils.SEND)
 	addr = pack.pack("b3",0x0,0x0,0x0)
 	mt = pack.pack("b",UARTGetBoardInfo.MT)
 	return UARTUtils.encode(sf,addr,mt,data)
end        

