-- @module LogUtil
-- @author ramonqlee
-- @copyright idreems.com
-- @release 2017.12.24
-- tested 2017.12.27
module(..., package.seeall)

function getTableLen( tab )
    local count = 0  

    if not tab then
        return 0
    end

    if "table"~=type(tab) then
        return count
    end

    for k,_ in pairs(tab) do  
        count = count + 1  
    end 

    return count
end


