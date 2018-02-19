--- MenuTitle Demo
-- @module testLcd
-- @author hotdll
-- @license MIT
-- @copyright openLuat
-- @release 2017.10.17
require "ui"
local newList = ui.newList
module(..., package.seeall)
local menuBar = {"menu", "set", "message", "alarm", "device", "help", "mange", "test", "user", }
local menuItems = {"menu�˵�2��1", "menu�˵�2��2", "menu�˵�2��3", "menu�˵�2��4", "menu�˵�2��5", "menu�˵�2��6"}
local setItems = {"set�˵�2��1", "set�˵�2��2", "set�˵�2��3", "set�˵�2��4", "set�˵�2��5", "set�˵�2��6"}
local msgItems = {"msg�˵�2��1", "msg�˵�2��2", "msg�˵�2��3", "msg�˵�2��4", "msg�˵�2��5", "msg�˵�2��6"}
local alarmItems = {"alarm�˵�2��1", "alarm�˵�2��2", "alarm�˵�2��3", "alarm�˵�2��4", "alarm�˵�2��5", "alarm�˵�2��6"}
local deviceItems = {"device�˵�2��1", "device�˵�2��2", "device�˵�2��3", "device�˵�2��4", "device�˵�2��5", "device�˵�2��6"}
local helpItems = {"help�˵�2��1", "help�˵�2��2", "help�˵�2��3", "help�˵�2��4", "help�˵�2��5", "help�˵�2��6"}
local mangeItems = {"mange�˵�2��1", "mange�˵�2��2", "mange�˵�2��3", "mange�˵�2��4", "mange�˵�2��5", "mange�˵�2��6"}
local testItems = {"test�˵�2��1", "test�˵�2��2", "test�˵�2��3", "test�˵�2��4", "test�˵�2��5", "test�˵�2��6"}
local userItems = {"user�˵�2��1", "user�˵�2��2", "user�˵�2��3", "user�˵�2��4", "user�˵�2��5", "user�˵�2��6"}
local userItems2 = {"user�˵�3��1", "user�˵�3��2", "user�˵�3��3", "user�˵�3��4", "user�˵�3��5", "user�˵�3��6"}

local rootMenu = newList(menuBar)
local menuItem = newList(menuItems, true)
local setItem = newList(setItems, true)
local msgItem = newList(msgItems, true)
local alarmItem = newList(alarmItems, true)
local deviceItem = newList(deviceItems, true)
local helpItem = newList(helpItems, true)
local mangeItem = newList(mangeItems, true)
local testItem = newList(testItems, true)
local userItem = newList(userItems, true)
local userItem2 = newList(userItems2, true)

userItem.append(userItems[1], userItem2)

rootMenu.append(menuBar[1], menuItem)
rootMenu.append(menuBar[2], setItem)
rootMenu.append(menuBar[3], msgItem)
rootMenu.append(menuBar[4], alarmItem)
rootMenu.append(menuBar[5], deviceItem)
rootMenu.append(menuBar[6], helpItem)
rootMenu.append(menuBar[7], mangeItem)
rootMenu.append(menuBar[8], testItem)
rootMenu.append(menuBar[9], userItem)

rootMenu.display()
