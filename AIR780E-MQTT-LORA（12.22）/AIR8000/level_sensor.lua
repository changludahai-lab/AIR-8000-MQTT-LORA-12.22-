--[[
@module level_sensor
@summary 液位仪模块 - 串口通讯、协议解析、液位状态获取
@version 2.1.0

================================================================================
模块概述
================================================================================

本模块负责与加油站液位仪通讯，获取油罐液位状态。
支持两种常见的液位仪品牌：维德路特(Veeder-Root) 和 奥科(Aoke)。

【硬件连接】
Air8000 UART1 ←──RS232──→ 液位仪

【工作流程】
1. 定期发送查询命令到液位仪
2. 解析液位仪返回的数据
3. 判断是否存在高液位报警
4. 将报警状态暴露给其他模块

【支持的液位仪协议】

================================================================================
协议1: 维德路特(Veeder-Root)
================================================================================

发送查询命令:
┌──────────────────────────────────────────────────────────────┐
│  [0x01] i  2  0  5  0  0                                     │
│   SOH   协议标识  查询类型                                    │
│  十六进制: 01 69 32 30 35 30 30                              │
└──────────────────────────────────────────────────────────────┘

接收响应（正常无报警）:
┌──────────────────────────────────────────────────────────────┐
│  [0x01] i205 00 24 07 02 15 15 01 0100 0200 0300 0400 0500 &&F889│
│   │      │   │  │              │   │                    │   │   │
│   │      │   │  │              │   └─ 各罐状态数据 ─────┘   │   │
│   │      │   │  └─日期时间────┘                             │   │
│   │      │   └─ 固定头00                                   │   │
│   │      └─ 协议标识                                        │   │
│   └─ SOH (0x01)                                     结束符 ─┘   │
│                                                     校验码 ────┘│
└──────────────────────────────────────────────────────────────┘

罐状态数据格式（每4字符一组）:
  01 00 = 1号罐正常
  01 07 = 1号罐高液位报警!

================================================================================
协议2: 奥科(Aoke) PD-3 Modbus RTU
================================================================================

发送查询命令（查询全部油罐报警信息）:
┌──────────────────────────────────────────────────────────────┐
│  01 03 00 04 00 00 04 0B                                     │
│  │  │  │     │     │                                         │
│  │  │  │     │     └─ CRC校验                                │
│  │  │  │     └─ 油罐编号(00=全部)                            │
│  │  │  └─ 命令编号 00 04                                     │
│  │  └─ 功能码 03                                             │
│  └─ 设备地址 01                                              │
└──────────────────────────────────────────────────────────────┘

接收响应:
┌──────────────────────────────────────────────────────────────┐
│  01 03 <记录数> [<罐号><日期6字节><报警码2字节>] ... CRC      │
│                                                              │
│  示例（有报警）:                                              │
│  01 03 02 02 07 D5 0A 06 0A 1C 01 00 0E ...                  │
│        │  │  │              │  │     │                       │
│        │  │  │              │  │     └─ 报警码 00 0E         │
│        │  │  │              │  └─ 罐号 01                    │
│        │  │  └─ 日期时间 ───┘                                │
│        │  └─ 罐号 02                                         │
│        └─ 记录数 02（有2条报警记录）                          │
│                                                              │
│  报警码说明:                                                 │
│  00 0A = 高液位报警    ⚠️ 触发                               │
│  00 0B = 高液位预警    ⚠️ 触发                               │
│  00 0C = 低液位预警                                          │
│  00 0D = 低液位报警                                          │
│  00 0E = 水位高报警                                          │
│  00 0F = 测漏失败                                            │
└──────────────────────────────────────────────────────────────┘

【Python 类比】
这个模块类似于 Python 中的串口通讯库：
```python
import serial

class LevelSensor:
    def __init__(self, port='/dev/ttyUSB0', baudrate=9600):
        self.ser = serial.Serial(port, baudrate)
        self.sensor_type = 'weidelu'  # 或 'aoke'

    def query(self):
        if self.sensor_type == 'weidelu':
            self.ser.write(b'\x01i20500')
        else:
            self.ser.write(bytes([0x01, 0x03, 0x00, 0x04, 0x00, 0x00, 0x04, 0x0B]))
```
]]

local levelSensor = {}
local config = require("config")

--------------------------------------------------------------------------------
-- 模块内部状态
--------------------------------------------------------------------------------
local isHighLevel = false       -- 当前是否高液位报警
local highLevelTankId = nil     -- 报警的罐号（用于日志）
local lastRxBuffer = ""         -- 接收缓冲区（处理分包）
local alarmType = nil           -- 报警类型（用于奥科协议）

--------------------------------------------------------------------------------
-- 维德路特报警状态码定义
--------------------------------------------------------------------------------
local WEIDELU_STATUS = {
    NORMAL = "00",          -- 正常
    HIGH_LEVEL = "07",      -- 高液位报警
}

--------------------------------------------------------------------------------
-- 奥科报警码定义
-- 只有高液位报警和高液位预警需要触发室外机报警
--------------------------------------------------------------------------------
local AOKE_ALARM_CODE = {
    HIGH_LEVEL_ALARM = 0x0A,    -- 高液位报警
    HIGH_LEVEL_WARNING = 0x0B,  -- 高液位预警
    LOW_LEVEL_WARNING = 0x0C,   -- 低液位预警（不触发）
    LOW_LEVEL_ALARM = 0x0D,     -- 低液位报警（不触发）
    WATER_HIGH_ALARM = 0x0E,    -- 水位高报警（不触发）
    LEAK_DETECT_FAIL = 0x0F,    -- 测漏失败（不触发）
}

--------------------------------------------------------------------------------
-- 初始化液位仪串口
--
-- 【调用时机】
-- 在 main.lua 中设备启动时调用一次
--
-- 【Python 类比】
-- def init(self):
--     self.ser = serial.Serial('/dev/ttyUSB0', 9600)
--     self.ser.on_receive = self._on_receive
--------------------------------------------------------------------------------
function levelSensor.init()
    local cfg = config.uart.level_sensor

    -- 初始化串口参数
    uart.setup(
        cfg.id,           -- 串口 ID
        cfg.baudrate,     -- 波特率
        cfg.databits,     -- 数据位
        cfg.stopbits      -- 停止位
    )

    -- 注册串口接收回调
    uart.on(cfg.id, "receive", function(id, len)
        levelSensor.onReceive(id, len)
    end)

    local sensorType = config.level_sensor.sensor_type or "weidelu"
    log.info("levelSensor", "初始化完成",
        "类型=" .. sensorType,
        "串口ID=" .. cfg.id,
        "波特率=" .. cfg.baudrate)
end

--------------------------------------------------------------------------------
-- 串口接收回调
-- @param id number 串口 ID
-- @param len number 接收到的数据长度
--------------------------------------------------------------------------------
function levelSensor.onReceive(id, len)
    local s = ""
    repeat
        s = uart.read(id, 128)
        if #s > 0 then
            -- 打印十六进制便于调试
            log.info("levelSensor", "收到数据", #s, "字节", s:toHex())

            -- 追加到缓冲区
            lastRxBuffer = lastRxBuffer .. s

            -- 根据配置的液位仪类型选择解析方式
            levelSensor.tryParse()
        end
    until s == ""
end

--------------------------------------------------------------------------------
-- 尝试解析接收到的数据
-- 根据配置的液位仪类型选择不同的解析策略
--------------------------------------------------------------------------------
function levelSensor.tryParse()
    local sensorType = config.level_sensor.sensor_type or "weidelu"

    if sensorType == "aoke" then
        levelSensor.tryParseAoke()
    else
        levelSensor.tryParseWeidelu()
    end
end

--------------------------------------------------------------------------------
-- 尝试解析维德路特协议
--------------------------------------------------------------------------------
function levelSensor.tryParseWeidelu()
    -- 数据太短，等待更多数据
    if #lastRxBuffer < 20 then
        return
    end

    -- 检查是否有完整的响应（包含结束符 &&）
    local endPos = lastRxBuffer:find("&&")
    if not endPos then
        if #lastRxBuffer > 256 then
            log.warn("levelSensor", "缓冲区过长无结束符，清空")
            lastRxBuffer = ""
        end
        return
    end

    -- 提取完整消息（&& 后还有4位校验码）
    local completeMsg = lastRxBuffer:sub(1, endPos + 5)
    log.info("levelSensor", "完整消息", completeMsg)

    -- 解析
    levelSensor.parseWeidelu(completeMsg)

    -- 清空已处理的数据
    if endPos + 6 <= #lastRxBuffer then
        lastRxBuffer = lastRxBuffer:sub(endPos + 6)
    else
        lastRxBuffer = ""
    end
end

--------------------------------------------------------------------------------
-- 尝试解析奥科协议
--
-- 【奥科 Modbus 响应格式】
-- 响应可能分多包到达，需要判断完整性
-- 完整响应: 01 03 <记录数> [<罐号><日期6字节><报警码2字节>] * 记录数 + CRC(2字节)
--
-- 每条报警记录 = 1(罐号) + 6(日期时间) + 2(报警码) = 9 字节
-- 总长度 = 3(头) + 记录数 * 9 + 2(CRC) = 5 + 记录数 * 9
--------------------------------------------------------------------------------
function levelSensor.tryParseAoke()
    -- 最小响应长度: 01 03 00 + CRC(2) = 5 字节（无报警时）
    if #lastRxBuffer < 5 then
        return
    end

    -- 检查响应头
    local byte1 = lastRxBuffer:byte(1)
    local byte2 = lastRxBuffer:byte(2)
    local cfg = config.level_sensor.aoke

    if byte1 ~= cfg.header_byte1 or byte2 ~= cfg.header_byte2 then
        -- 不是奥科响应，可能是垃圾数据
        log.warn("levelSensor", "非奥科响应头，丢弃", lastRxBuffer:toHex())
        lastRxBuffer = ""
        return
    end

    -- 获取记录数
    local recordCount = lastRxBuffer:byte(3)
    if recordCount == nil then
        return  -- 等待更多数据
    end

    -- 计算期望的总长度
    -- 头(3字节) + 记录数 * 9字节 + CRC(2字节)
    local expectedLen = 3 + recordCount * 9 + 2
    log.info("levelSensor", "奥科响应", "记录数=" .. recordCount, "期望长度=" .. expectedLen, "当前长度=" .. #lastRxBuffer)

    if #lastRxBuffer < expectedLen then
        -- 数据不完整，等待更多
        -- 但如果等太久可能是错误数据
        if #lastRxBuffer > 100 then
            log.warn("levelSensor", "奥科数据过长但不完整，清空")
            lastRxBuffer = ""
        end
        return
    end

    -- 提取完整响应
    local completeMsg = lastRxBuffer:sub(1, expectedLen)
    log.info("levelSensor", "奥科完整响应", completeMsg:toHex())

    -- 解析
    levelSensor.parseAoke(completeMsg, recordCount)

    -- 清空已处理的数据
    if expectedLen < #lastRxBuffer then
        lastRxBuffer = lastRxBuffer:sub(expectedLen + 1)
    else
        lastRxBuffer = ""
    end
end

--------------------------------------------------------------------------------
-- 解析维德路特协议
-- @param buf string 完整的响应消息
-- @return boolean 是否解析成功
--------------------------------------------------------------------------------
function levelSensor.parseWeidelu(buf)
    -- 检查协议头
    local startPos = buf:find("i205")
    if not startPos then
        log.warn("levelSensor", "未找到协议头i205")
        return false
    end

    log.info("levelSensor", "识别到维德路特协议")

    -- 提取协议头后的数据
    local dataAfterHeader = buf:sub(startPos + 4)

    -- 查找结束符
    local endMarkerPos = dataAfterHeader:find("&&")
    if not endMarkerPos then
        log.warn("levelSensor", "未找到结束符&&")
        return false
    end

    -- 提取有效数据
    local validData = dataAfterHeader:sub(1, endMarkerPos - 1)
    log.info("levelSensor", "有效数据", validData, "长度=" .. #validData)

    -- 跳过固定头(00)和日期时间(12字符)
    if #validData < 14 then
        log.warn("levelSensor", "数据长度不足")
        return false
    end

    local tankDataStr = validData:sub(15)
    log.info("levelSensor", "罐状态数据", tankDataStr)

    -- 解析罐状态数据（每4字符一组: TTSS）
    local foundHighLevel = false
    local alarmTankId = nil
    local tankCount = 0

    for i = 1, #tankDataStr - 3, 4 do
        local tankIdStr = tankDataStr:sub(i, i + 1)
        local statusStr = tankDataStr:sub(i + 2, i + 3)

        local tankId = tonumber(tankIdStr)
        tankCount = tankCount + 1

        log.info("levelSensor", "罐" .. tankIdStr, "状态=" .. statusStr)

        if statusStr == WEIDELU_STATUS.HIGH_LEVEL then
            foundHighLevel = true
            alarmTankId = tankId
            log.warn("levelSensor", "!!!检测到高液位报警!!!", "罐号=" .. tankIdStr)
        end
    end

    log.info("levelSensor", "解析完成", "罐数=" .. tankCount, "报警=" .. tostring(foundHighLevel))

    -- 更新模块状态
    if foundHighLevel then
        isHighLevel = true
        highLevelTankId = alarmTankId
        alarmType = "high_level"
    else
        isHighLevel = false
        highLevelTankId = nil
        alarmType = nil
    end

    return true
end

--------------------------------------------------------------------------------
-- 解析奥科协议 (PD-3 Modbus RTU)
-- @param buf string 完整的响应数据
-- @param recordCount number 报警记录数
-- @return boolean 是否解析成功
--
-- 【响应格式】
-- 01 03 <记录数> [<罐号1字节><日期时间6字节><报警码2字节>] * 记录数 + CRC
--
-- 【报警记录结构】（共9字节）
-- 位置0: 罐号 (01~10)
-- 位置1-6: 日期时间 YYYY MM DD hh mm ss
-- 位置7-8: 报警码 (如 00 0A = 高液位报警)
--
-- 【示例数据】
-- 01 03 02 02 07D5 0A06 0A1C 01 000E 01 07D5 0A06 0A1D 0B 000E
--       │  │  │         │    │  │    │  │         │    └─报警码2
--       │  │  │         │    │  │    │  └─日期时间2
--       │  │  │         │    │  │    └─罐号2=01
--       │  │  │         │    │  └─报警码1=000E
--       │  │  │         │    └─罐号1=01
--       │  │  └─日期时间1
--       │  └─罐号1=02
--       └─记录数=02
--------------------------------------------------------------------------------
function levelSensor.parseAoke(buf, recordCount)
    log.info("levelSensor", "解析奥科协议", "记录数=" .. recordCount)

    -- 如果没有报警记录
    if recordCount == 0 then
        log.info("levelSensor", "奥科: 无报警记录")
        isHighLevel = false
        highLevelTankId = nil
        alarmType = nil
        return true
    end

    local foundHighLevel = false
    local alarmTankId = nil
    local foundAlarmType = nil

    -- 遍历每条报警记录
    -- 每条记录9字节，从第4字节开始（前3字节是 01 03 记录数）
    for i = 0, recordCount - 1 do
        local offset = 4 + i * 9  -- 记录起始位置（Lua索引从1开始，这里是偏移量）

        -- 提取罐号（1字节）
        local tankId = buf:byte(offset)

        -- 提取报警码（2字节，在位置 offset+7 和 offset+8）
        -- 报警码格式: 00 0A (高字节在前，低字节在后)
        local alarmCodeHigh = buf:byte(offset + 7)
        local alarmCodeLow = buf:byte(offset + 8)

        log.info("levelSensor", "奥科报警记录",
            "罐号=" .. (tankId or "nil"),
            "报警码=" .. string.format("%02X %02X", alarmCodeHigh or 0, alarmCodeLow or 0))

        -- 检查是否是高液位报警或高液位预警
        -- 报警码低字节: 0A=高液位报警, 0B=高液位预警
        if alarmCodeLow == AOKE_ALARM_CODE.HIGH_LEVEL_ALARM then
            foundHighLevel = true
            alarmTankId = tankId
            foundAlarmType = "high_level_alarm"
            log.warn("levelSensor", "!!!奥科检测到高液位报警!!!", "罐号=" .. tankId)

        elseif alarmCodeLow == AOKE_ALARM_CODE.HIGH_LEVEL_WARNING then
            foundHighLevel = true
            alarmTankId = tankId
            foundAlarmType = "high_level_warning"
            log.warn("levelSensor", "!!!奥科检测到高液位预警!!!", "罐号=" .. tankId)
        else
            -- 其他报警类型，记录但不触发室外机
            local alarmName = "未知"
            if alarmCodeLow == AOKE_ALARM_CODE.LOW_LEVEL_WARNING then
                alarmName = "低液位预警"
            elseif alarmCodeLow == AOKE_ALARM_CODE.LOW_LEVEL_ALARM then
                alarmName = "低液位报警"
            elseif alarmCodeLow == AOKE_ALARM_CODE.WATER_HIGH_ALARM then
                alarmName = "水位高报警"
            elseif alarmCodeLow == AOKE_ALARM_CODE.LEAK_DETECT_FAIL then
                alarmName = "测漏失败"
            end
            log.info("levelSensor", "奥科其他报警(不触发)", "类型=" .. alarmName, "罐号=" .. tankId)
        end
    end

    -- 更新模块状态
    if foundHighLevel then
        isHighLevel = true
        highLevelTankId = alarmTankId
        alarmType = foundAlarmType
    else
        -- 虽然有报警记录，但不是高液位相关的
        isHighLevel = false
        highLevelTankId = nil
        alarmType = nil
    end

    log.info("levelSensor", "奥科解析完成",
        "触发报警=" .. tostring(foundHighLevel),
        "罐号=" .. tostring(alarmTankId),
        "类型=" .. tostring(foundAlarmType))

    return true
end

--------------------------------------------------------------------------------
-- 发送查询命令到液位仪
-- 根据配置的液位仪类型发送对应的查询命令
--------------------------------------------------------------------------------
function levelSensor.sendQuery()
    local uartId = config.uart.level_sensor.id
    local sensorType = config.level_sensor.sensor_type or "weidelu"

    if sensorType == "aoke" then
        -- 发送奥科查询命令
        local cmd = config.level_sensor.aoke.query_cmd
        uart.write(uartId, cmd)
        log.info("levelSensor", "发送奥科查询命令", cmd:toHex())
    else
        -- 发送维德路特查询命令
        local cmd = config.level_sensor.weidelu.query_cmd
        uart.write(uartId, cmd)
        log.info("levelSensor", "发送维德路特查询命令")
    end
end

--------------------------------------------------------------------------------
-- 获取当前是否高液位报警
-- @return boolean 是否高液位
--------------------------------------------------------------------------------
function levelSensor.isHighLevel()
    return isHighLevel
end

--------------------------------------------------------------------------------
-- 获取高液位报警的罐号
-- @return number|nil 罐号
--------------------------------------------------------------------------------
function levelSensor.getHighLevelTankId()
    return highLevelTankId
end

--------------------------------------------------------------------------------
-- 获取报警类型
-- @return string|nil 报警类型
--   维德路特: "high_level"
--   奥科: "high_level_alarm" 或 "high_level_warning"
--------------------------------------------------------------------------------
function levelSensor.getAlarmType()
    return alarmType
end

--------------------------------------------------------------------------------
-- 手动设置液位状态（用于 IO 输入方式）
-- @param state boolean 是否高液位
--------------------------------------------------------------------------------
function levelSensor.setHighLevel(state)
    isHighLevel = state
    if not state then
        highLevelTankId = nil
        alarmType = nil
    end
end

--------------------------------------------------------------------------------
-- 清除报警状态
-- 用于手动解除报警
--------------------------------------------------------------------------------
function levelSensor.clearAlarm()
    isHighLevel = false
    highLevelTankId = nil
    alarmType = nil
    log.info("levelSensor", "液位报警状态已清除")
end

--------------------------------------------------------------------------------
-- 启动液位轮询任务
--------------------------------------------------------------------------------
function levelSensor.startPolling()
    sys.taskInit(function()
        while true do
            levelSensor.sendQuery()
            sys.wait(config.level_sensor.poll_interval)
        end
    end)

    local sensorType = config.level_sensor.sensor_type or "weidelu"
    log.info("levelSensor", "液位轮询任务已启动",
        "类型=" .. sensorType,
        "间隔=" .. config.level_sensor.poll_interval .. "ms")
end

--------------------------------------------------------------------------------
-- 返回模块
--------------------------------------------------------------------------------
return levelSensor
