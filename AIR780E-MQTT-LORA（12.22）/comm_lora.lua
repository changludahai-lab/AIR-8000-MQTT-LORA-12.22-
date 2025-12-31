--[[
@module comm_lora
@summary LORA通讯模块 - 串口通讯、消息收发
@version 1.0.0

================================================================================
模块概述
================================================================================

本模块负责 LORA 模式下的通讯，通过串口与外部 LORA 模块交互。

【LORA 简介】
LORA（Long Range）是一种低功耗广域网通讯技术：
- 通讯距离远（数公里）
- 功耗低，适合电池供电设备
- 适合少量数据传输

【本项目的 LORA 架构】
Air780E ──串口──> LORA 模块 ~~无线~~> LORA 网关 ──> 控制中心

【与 4G 模式的区别】
- 4G 模式：直接通过 MQTT 与服务器通讯
- LORA 模式：通过串口与 LORA 模块通讯，LORA 模块负责无线传输

【消息协议】
使用简单的字符协议（非 JSON），提高效率和抗干扰：
- 接收指令：C/CCCC=报警, A/AAAA=取消, B/BBBB=解除
- 发送状态：DDDD=电量低, EEEE=电量正常

【Python 类比】
这个模块类似于 Python 使用 pyserial 库：
```python
import serial
ser = serial.Serial('/dev/ttyUSB0', 9600)
data = ser.read(100)
ser.write(b'DDDD')
```

【串口通讯基础】
- UART = 通用异步收发器，就是常说的"串口"
- 波特率 = 每秒传输的比特数（如 9600bps）
- 数据位 = 每帧数据的位数（通常是 8 位）
- 停止位 = 每帧结束的标志位（通常是 1 位）
]]

local comm_lora = {}
local config = require("config")

--------------------------------------------------------------------------------
-- 模块内部状态（私有变量）
--------------------------------------------------------------------------------
local messageHandler = nil  -- 外部传入的消息处理回调函数
local rxBuffer = ""         -- 接收缓冲区，累积接收到的数据

--------------------------------------------------------------------------------
-- 初始化 LORA 通讯
-- @param onMessageCallback function 收到消息时的回调函数
--
-- 【调用时机】
-- 在 main.lua 中检测到是 LORA 模式时调用
--
-- 【工作流程】
-- 1. 保存消息处理回调
-- 2. 初始化串口参数
-- 3. 注册串口接收中断
--
-- 【Python 类比】
-- def init(self, on_message_callback):
--     self.message_handler = on_message_callback
--     self.serial = serial.Serial(
--         port='/dev/ttyUSB0',
--         baudrate=9600,
--         bytesize=8,
--         stopbits=1
--     )
--     self.serial.on_receive = self.handle_receive
--------------------------------------------------------------------------------
function comm_lora.init(onMessageCallback)
    -- 保存消息处理回调
    messageHandler = onMessageCallback

    log.info("comm_lora", "初始化LORA通讯")

    -- 【初始化串口】
    -- uart.setup(id, baudrate, databits, stopbits, parity)
    -- id: 串口编号（Air780E 有多个串口）
    -- baudrate: 波特率（与 LORA 模块设置一致）
    -- databits: 数据位（8位）
    -- stopbits: 停止位（1位）
    -- parity: 校验位（默认无校验）
    uart.setup(
        config.uart.id,        -- 串口1
        config.uart.baudrate,  -- 9600bps
        config.uart.databits,  -- 8位数据
        config.uart.stopbits   -- 1位停止位
    )

    -- 【注册串口接收回调】
    -- uart.on(id, event, callback) 注册串口事件回调
    -- event="receive" 表示收到数据事件
    --
    -- 回调参数：
    -- - id: 串口编号
    -- - len: 收到的数据长度
    --
    -- 【与 Python 的区别】
    -- LuaOS 使用中断驱动模式，收到数据自动调用回调
    -- Python 通常使用轮询：data = ser.read()
    uart.on(config.uart.id, "receive", function(id, len)
        -- uart.read(id, len) 从串口读取数据
        -- 返回值是 string 类型
        local data = uart.read(id, len)
        if data and #data > 0 then
            -- 调用数据处理函数
            comm_lora.handleReceive(data)
        end
    end)

    log.info("comm_lora", "LORA串口初始化完成")
end

--------------------------------------------------------------------------------
-- 处理串口接收数据
-- @param data string 接收到的原始数据
--
-- 【为什么需要缓冲区？】
-- - 串口数据可能分多次到达
-- - 例如发送 "CCCC"，可能先收到 "CC"，再收到 "CC"
-- - 使用缓冲区累积数据，确保消息完整性
--
-- 【Python 类比】
-- def handle_receive(self, data: bytes):
--     self.rx_buffer += data.decode()
--     self.parse_message()
--------------------------------------------------------------------------------
function comm_lora.handleReceive(data)
    -- data:toHex() 将数据转为十六进制字符串，便于调试
    -- 例如 "AB" 显示为 "4142"
    log.info("comm_lora", "收到数据", data:toHex())

    -- 【累积数据到缓冲区】
    -- Lua 字符串用 .. 拼接
    rxBuffer = rxBuffer .. data

    -- 尝试解析完整消息
    comm_lora.parseMessage()
end

--------------------------------------------------------------------------------
-- 解析消息
--
-- 【协议格式】
-- 本项目使用简单的字符协议：
-- - "C" 或 "CCCC" = 报警指令
-- - "A" 或 "AAAA" = 取消报警
-- - "B" 或 "BBBB" = 解除报警
--
-- 为什么支持两种格式？
-- - 单字符格式：传输快，但容易受干扰
-- - 四字符格式：冗余校验，抗干扰能力强
--
-- 【解析算法】
-- 1. 从缓冲区开头匹配已知模式
-- 2. 匹配成功则提取消息类型
-- 3. 从缓冲区移除已解析的数据
-- 4. 递归解析剩余数据
--
-- 【Python 类比】
-- def parse_message(self):
--     while self.rx_buffer:
--         if self.rx_buffer.startswith('CCCC'):
--             msg_type = 'alarm'
--             self.rx_buffer = self.rx_buffer[4:]
--         elif self.rx_buffer.startswith('C'):
--             msg_type = 'alarm'
--             self.rx_buffer = self.rx_buffer[1:]
--         ...
--------------------------------------------------------------------------------
function comm_lora.parseMessage()
    -- 缓冲区为空，直接返回
    if #rxBuffer == 0 then
        return
    end

    local msgType = nil    -- 解析出的消息类型
    local consumed = 0     -- 消费的字符数

    -- 【模式匹配语法说明】
    -- Lua 使用自己的模式匹配语法（类似但不完全等于正则表达式）：
    -- - ^ 表示字符串开头
    -- - [^X] 表示非 X 的任意字符
    -- - string:find(pattern) 查找模式，返回起始和结束位置

    -- ========== 检查报警消息 (C 或 CCCC) ==========
    if rxBuffer:find("^CCCC") then
        -- 优先匹配四字符格式
        msgType = "alarm"
        consumed = 4
    elseif rxBuffer:find("^C[^C]") or (rxBuffer == "C") then
        -- 单字符 C 后面跟着非 C 的字符，或者缓冲区只有一个 C
        msgType = "alarm"
        consumed = 1

    -- ========== 检查取消报警消息 (A 或 AAAA) ==========
    elseif rxBuffer:find("^AAAA") then
        msgType = "cancel"
        consumed = 4
    elseif rxBuffer:find("^A[^A]") or (rxBuffer == "A") then
        msgType = "cancel"
        consumed = 1

    -- ========== 检查解除报警消息 (B 或 BBBB) ==========
    elseif rxBuffer:find("^BBBB") then
        msgType = "disarm"
        consumed = 4
    elseif rxBuffer:find("^B[^B]") or (rxBuffer == "B") then
        msgType = "disarm"
        consumed = 1

    else
        -- ========== 未知数据 ==========
        -- 无法识别的数据，丢弃第一个字节，继续解析
        -- string:sub(start, end) 提取子串
        -- 索引从 1 开始（Lua 特性）
        rxBuffer = rxBuffer:sub(2)
        return
    end

    -- 【消费已解析的数据】
    -- 从缓冲区移除已处理的字符
    if consumed > 0 then
        -- sub(2) 表示从第2个字符开始取（即去掉第1个字符）
        -- sub(consumed + 1) 去掉前 consumed 个字符
        rxBuffer = rxBuffer:sub(consumed + 1)
    end

    -- 【处理消息】
    if msgType then
        log.info("comm_lora", "解析消息", msgType)

        -- 调用外部消息处理器
        -- 构造与 MQTT 消息相同格式的数据，便于统一处理
        if messageHandler then
            messageHandler({type = msgType})
        end

        -- 发布消息事件
        -- 其他模块可以通过 sys.waitUntil("lora_message") 监听
        sys.publish("lora_message", msgType)
    end

    -- 【继续解析剩余数据】
    -- 递归调用，直到缓冲区清空或无法识别
    if #rxBuffer > 0 then
        comm_lora.parseMessage()
    end
end

--------------------------------------------------------------------------------
-- 发送消息
-- @param data string 要发送的数据
--
-- 【Python 类比】
-- def send(self, data: str):
--     self.serial.write(data.encode())
--------------------------------------------------------------------------------
function comm_lora.send(data)
    log.info("comm_lora", "发送数据", data)
    -- uart.write(id, data) 向串口写入数据
    uart.write(config.uart.id, data)
end

--------------------------------------------------------------------------------
-- 发送电池电量低消息
--
-- 【用途】
-- 当检测到电池电压低于阈值时，向控制中心发送告警
-- 控制中心收到后可以提醒运维人员更换电池
--
-- 【消息格式】
-- 发送 "DDDD"（四个 D）
--------------------------------------------------------------------------------
function comm_lora.sendBatteryLow()
    log.info("comm_lora", "发送电池电量低")
    comm_lora.send(config.lora_msg.BATTERY_LOW)  -- "DDDD"
end

--------------------------------------------------------------------------------
-- 发送电池电量正常消息
--
-- 【用途】
-- 定期上报状态时，告知控制中心电池正常
--
-- 【消息格式】
-- 发送 "EEEE"（四个 E）
--------------------------------------------------------------------------------
function comm_lora.sendBatteryOK()
    log.info("comm_lora", "发送电池电量正常")
    comm_lora.send(config.lora_msg.BATTERY_OK)  -- "EEEE"
end

--------------------------------------------------------------------------------
-- 关闭串口
--
-- 【调用时机】
-- 进入休眠前调用，关闭串口以降低功耗
--
-- 【Python 类比】
-- def close(self):
--     self.serial.close()
--------------------------------------------------------------------------------
function comm_lora.close()
    log.info("comm_lora", "关闭串口")
    uart.close(config.uart.id)
end

--------------------------------------------------------------------------------
-- 清空接收缓冲区
--
-- 【用途】
-- - 重置串口状态
-- - 丢弃可能残留的垃圾数据
--------------------------------------------------------------------------------
function comm_lora.clearBuffer()
    rxBuffer = ""
end

--------------------------------------------------------------------------------
-- 返回模块
-- 其他文件通过 require("comm_lora") 获取这个表
--------------------------------------------------------------------------------
return comm_lora
