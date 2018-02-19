-- @module FileUtil
-- @author ramonqlee
-- @copyright idreems.com
-- @release 2017.12.21
-- tested 2017.12.27

FileUtil={}

--[[��demo�ṩ���ֽӿڣ���һ��readfile(filename)���ļ����ڶ���writevala(filename,value)��д�ļ����ݣ�����ģʽ��
������function writevalw(filename,value)��д�ļ����ݣ�����ģʽ��������deletefile(filename)��ɾ���ļ���--]]

function FileUtil.exists( filename )
	return io.exists(filename)
end
--[[
    ��������readfile(filename)
	���ܣ����������ļ������ļ�����������������������
	�������ļ���
	����ֵ����                     ]]
 function FileUtil.readfile(filename)--��ָ���ļ����������
	
    local filehandle=io.open(filename,"r")--��һ���������ļ������ڶ����Ǵ򿪷�ʽ��'r'��ģʽ,'w'дģʽ�������ݽ��и���,'a'����ģʽ,'b'����ģʽ�����ʾ�Զ�������ʽ��
	if filehandle then          --�ж��ļ��Ƿ����
	    local fileval=filehandle:read("*all")--�����ļ�����
	  if  fileval  then
	       -- print(fileval)  --����ļ����ڣ���ӡ�ļ�����
		   filehandle:close()--�ر��ļ�
		   return fileval
	  else 
	       print("�ļ�Ϊ��")--�ļ�������
	       return ""
	  end
	else 
	    print("�ļ������ڻ��ļ������ʽ����ȷ") --��ʧ��  
	    return ""
	end 
	return ""
end



--[[
    �������� writevala(filename,value)
	���ܣ���������ļ���������ݣ����ݸ�����ԭ�ļ�����֮��
	��������һ���ļ������ڶ�����Ҫ��ӵ�����
	����ֵ����                         --]]
 function FileUtil.writevala(filename,value)--��ָ���ļ����������,���������һλ���Ǵ򿪵�ģʽ

	local filehandle = io.open(filename,"a+")--��һ���������ļ�������һ���Ǵ�ģʽ'r'��ģʽ,'w'дģʽ�������ݽ��и���,'a'����ģʽ,'b'����ģʽ�����ʾ�Զ�������ʽ��
	if filehandle then
	    filehandle:write(value)--д��Ҫд�������
	    filehandle:close()
	else
	    print("�ļ������ڻ��ļ������ʽ����ȷ") --��ʧ��  
	end
end



--[[
    ��������writevalw(filename,value)
	���ܣ��������ļ���������ݣ�����ӵ����ݻḲ�ǵ�ԭ�ļ��е�����
	������ͬ��
	����ֵ����                 --]]
 function FileUtil.writevalw(filename,value)--��ָ���ļ����������
	local filehandle = io.open(filename,"w")--��һ���������ļ�������һ���Ǵ�ģʽ'r'��ģʽ,'w'дģʽ�������ݽ��и���,'a'����ģʽ,'b'����ģʽ�����ʾ�Զ�������ʽ��
	if filehandle then
	    filehandle:write(value)--д��Ҫд�������
	    filehandle:close()
	else
	    print("�ļ������ڻ��ļ������ʽ����ȷ") --��ʧ��  
	end
end


--[[��������deletefile(filename)
    ���ܣ�ɾ��ָ���ļ��е���������
	�������ļ���
	����ֵ����             --]]
function FileUtil.deletefile(filename)--ɾ��ָ���ļ����е���������
	local filehandle = io.open(filename,"w")
	if filehandle then
	    filehandle:write()--д��յ�����
	    print("ɾ���ɹ�")
		filehandle:close()
	else
	    print("�ļ������ڻ��ļ������ʽ����ȷ") --��ʧ��  
	end
end

--��ӡ�ļ�ϵͳ��ʣ��ռ�
-- print("get_fs_free_size: "..rtos.get_fs_free_size().." Bytes")
-- --�ɹ�����һ��Ŀ¼(Ŀ¼�Ѵ��ڣ�Ҳ����true��ʾ�����ɹ�)
-- if rtos.make_dir(USER_DIR_PATH) then
-- 	readfile(USER_DIR_PATH.."/3.txt")

-- 	writevala(USER_DIR_PATH.."/3.txt","great")

-- 	readfile(USER_DIR_PATH.."/3.txt")
-- 	writevalw(USER_DIR_PATH.."/3.txt","great")
-- 	readfile(USER_DIR_PATH.."/3.txt")

-- 	deletefile(USER_DIR_PATH.."/3.txt")
-- 	readfile(USER_DIR_PATH.."/3.txt")
-- end
