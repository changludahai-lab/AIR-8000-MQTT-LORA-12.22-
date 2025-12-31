--[[
@module comm_lora
@summary LORA通讯模块 - LORA模式下的串口消息收发
@version 1.0.0

================================================================================
模块概述
================================================================================

本模块负责 LORA 模式下的通讯：
1. 通过串口(UART11)与 LORA 模块通讯
2. 发送报警/取消/解除指令给室外机
3. 接收室外机上报的电池状态

【硬件架构】

┌─────────────┐       ┌─────────────┐       ┌─────────────┐       ┌─────────────┐
│   AIR8000   │──────→│ LORA 模块   │ ~~~>  │ LORA 模块   │──────→│   AIR780E   │
│   UART11    │       │ (室内机)    │ 无线  │ (室外机)    │       │   UART1     │
└─────────────┘       └─────────────┘       └─────────────┘       └─────────────┘

【消息协议】
与室外机的协议必须一致（参见 config.lora_msg）：

┌────────────────────────────────────────────────────────────────┐
│                    室内机 → 室外机                              │
├────────────────┬───────────────────────────────────────────────┤
│  消息          │  含义                                          │
├────────────────┼───────────────────────────────────────────────┤
│  CCCC          │  报警指令（室外机识别 C 或 CCCC）               │
│  AAAA          │  取消报警                                      │
│  BBBB          │  解除报警                                      │
└────────────────┴───────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│                    室外机 → 室内机                              │
├────────────────┬───────────────────────────────────────────────┤
│  消息          │  含义                                          │
├────────────────┼───────────────────────────────────────────────┤
│  D 或 DDDD     │  电池电量低                                    │
│  E 或 EEEE     │  电池电量正常                                  │
└────────────────┴───────────────────────────────────────────────┘

【Python 类比】
```python
import serial

class LORAComm:
    def __init__(self, port='/dev/ttyUSB1'):
        self.ser = serial.Serial(port, 9600)
        self.on_battery_low = None
        self.on_battery_ok = None

    def send_alarm(self):
        self.ser.write(b'CCCC')

    def _receive_loop(self):
        while True:
            data = self.ser.read(128)
            if 'D' in data:
                self.on_battery_low()
            elif 'E' in data:
                self.on_battery_ok()
```
]]

local commLora = {}
local config = require("config")

--------------------------------------------------------------------------------
-- 模块内部状态
--------------------------------------------------------------------------------
local messageCallback = nil     -- 消息回调函数
local isInitialized = false     -- 是否已初始化

--------------------------------------------------------------------------------
-- 初始化 LORA 模块
-- @param callback function 消息接收回调函数
--
-- 【调用时机】
-- 在 main.lua 中，确定为 LORA 模式后调用
--
-- 【回调函数格式】
-- function callback(msgType)
--     -- msgType: "battery_low" 或 "battery_ok"
-- end
--------------------------------------------------------------------------------
function commLora.init(callback)
    if isInitialized then
        return
    end

    messageCallback = callback

    local cfg = config.uart.lora

    -- 初始化串口
    uart.setup(
        cfg.id,
        cfg.baudrate,
        cfg.databits,
        cfg.stopbits
    )

    -- 注册接收回调
    uart.on(cfg.id, "receive", function(id, len)
        commLora.onReceive(id, len)
    end)

    isInitialized = true
    log.info("commLora", "初始化完成", "串口ID=" .. cfg.id)
end

--------------------------------------------------------------------------------
-- 串口接收回调
-- @param id number 串口 ID
-- @param len number 接收数据长度
--
-- 【工作流程】
-- 1. 读取所有数据
-- 2. 去除首尾空白
-- 3. 匹配协议消息
-- 4. 调用回调函数
--------------------------------------------------------------------------------
function commLora.onReceive(id, len)
    local s = ""
    repeat
        s = uart.read(id, 128)
        if #s > 0 then
            log.info("commLora", "收到数据", #s, "字节", s)

            -- 去除首尾空白字符
            -- Lua 的 gsub 类似 Python 的 re.sub
            local data = s:gsub("^%s*(.-)%s*$", "%1")

            -- 解析消息
            commLora.parseMessage(data)
        end
    until s == ""
end

--------------------------------------------------------------------------------
-- 解析接收到的消息
-- @param data string 接收到的原始数据
--
-- 【协议匹配】
-- 室外机发送的消息可能是单字符或四字符：
-- - "D" 或 "DDDD" = 电池低电量
-- - "E" 或 "EEEE" = 电池正常
--
-- 【Python 类比】
-- def parse_message(self, data: str):
--     if 'D' in data or 'DDDD' in data:
--         self.on_battery_low()
--     elif 'E' in data or 'EEEE' in data:
--         self.on_battery_ok()
--------------------------------------------------------------------------------
function commLora.parseMessage(data)
    local loraCfg = config.lora_msg

    -- 检查是否是电池低电量消息
    -- string.find() 返回匹配位置，类似 Python 的 str.find()
    for _, pattern in ipairs(loraCfg.BATTERY_LOW) do
        if string.find(data, pattern) then
            log.info("commLora", "收到电池低电量消息")
            if messageCallback then
                messageCallback("battery_low")
            end
            return
        end
    end

    -- 检查是否是电池正常消息
    for _, pattern in ipairs(loraCfg.BATTERY_OK) do
        if string.find(data, pattern) then
            log.info("commLora", "收到电池正常消息")
            if messageCallback then
                messageCallback("battery_ok")
            end
            return
        end
    end

    -- 未识别的消息
    log.warn("commLora", "未识别的消息", data)
end

--------------------------------------------------------------------------------
-- 发送报警指令
-- 通知室外机开始声光报警
--
-- 【消息格式】
-- "CCCC"
--
-- 【为什么发送两次？】
-- LORA 无线传输可能丢包，发送两次提高可靠性
-- 两次之间间隔 2 秒，避免冲突
--------------------------------------------------------------------------------
function commLora.sendAlarm()
    local cfg = config.uart.lora
    local msg = config.lora_msg.ALARM

    uart.write(cfg.id, msg)
    log.info("commLora", "发送报警指令", msg)

    -- 延迟后再发一次（提高可靠性）
    sys.timerStart(function()
        uart.write(cfg.id, msg)
        log.info("commLora", "重发报警指令", msg)
    end, 2000)

    return true
end

--------------------------------------------------------------------------------
-- 发送取消报警指令
--
-- 【消息格式】
-- "AAAA"
--------------------------------------------------------------------------------
function commLora.sendCancel()
    local cfg = config.uart.lora
    local msg = config.lora_msg.CANCEL

    uart.write(cfg.id, msg)
    log.info("commLora", "发送取消报警指令", msg)

    -- 延迟后再发一次
    sys.timerStart(function()
        uart.write(cfg.id, msg)
        log.info("commLora", "重发取消报警指令", msg)
    end, 2000)

    return true
end

--------------------------------------------------------------------------------
-- 发送解除报警指令
--
-- 【消息格式】
-- "BBBB"
--
-- 【与取消的区别】
-- - 取消(AAAA): 液位恢复正常后自动发送
-- - 解除(BBBB): 人工按键确认后发送
--------------------------------------------------------------------------------
function commLora.sendDisarm()
    local cfg = config.uart.lora
    local msg = config.lora_msg.DISARM

    uart.write(cfg.id, msg)
    log.info("commLora", "发送解除报警指令", msg)

    -- 延迟后再发一次
    sys.timerStart(function()
        uart.write(cfg.id, msg)
        log.info("commLora", "重发解除报警指令", msg)
    end, 2000)

    return true
end

--------------------------------------------------------------------------------
-- 返回模块
--------------------------------------------------------------------------------
return commLora
