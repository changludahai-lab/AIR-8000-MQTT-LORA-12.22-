--[[
@module main
@summary 主入口文件 - 模式选择、初始化、主逻辑调度
@version 2.0.0

================================================================================
AIR8000 室内机 - 主程序入口
================================================================================

【设备定位】
AIR8000 是加油站液位监控系统的"室内机"（主控制器），负责：
1. 采集液位仪数据
2. 判断是否高液位报警
3. 通知室外机(AIR780E)进行声光报警
4. 本机也有声光报警提示

【系统架构】

┌─────────────────────────────────────────────────────────────────────────────┐
│                            加油站液位监控系统                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌───────────────┐                                    ┌───────────────┐    │
│  │   液位仪       │                                    │   AIR780E     │    │
│  │(维德路特/奥柯) │                                    │   室外机      │    │
│  └───────┬───────┘                                    └───────▲───────┘    │
│          │ RS485/RS232                                        │            │
│          ▼                                              MQTT/LORA         │
│  ┌───────────────────────────────────────────────────────────┐│            │
│  │                      AIR8000 室内机                        ││            │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        ││            │
│  │  │level_sensor │→ │   alarm     │→ │ comm_mqtt   │────────┘│            │
│  │  │ 液位采集    │  │ 本机报警    │  │ comm_lora   │─────────┘            │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                      │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

【工作模式】
通过 GPIO3 电平选择：
- 低电平(0) = 4G 模式：使用 MQTT 协议通讯
- 高电平(1) = LORA 模式：使用串口+LORA 模块通讯

【程序流程】

    ┌─────────────────┐
    │     设备启动     │
    └────────┬────────┘
             ▼
    ┌─────────────────┐
    │  读取 GPIO3 电平 │
    └────────┬────────┘
             │
     ┌───────┴───────┐
     ▼               ▼
  GPIO3=0         GPIO3=1
  ┌──────┐        ┌──────┐
  │ 4G   │        │ LORA │
  │ 模式 │        │ 模式 │
  └──┬───┘        └──┬───┘
     │               │
     ▼               ▼
  关闭飞行模式    开启飞行模式
  初始化MQTT     初始化LORA串口
     │               │
     └───────┬───────┘
             ▼
    ┌─────────────────┐
    │ 初始化液位仪串口 │
    └────────┬────────┘
             ▼
    ┌─────────────────┐
    │ 启动液位轮询任务 │
    └────────┬────────┘
             ▼
    ┌─────────────────┐
    │ 启动报警判断任务 │ ← 核心业务逻辑
    └────────┬────────┘
             ▼
    ┌─────────────────┐
    │   sys.run()     │ ← 进入事件循环
    └─────────────────┘

【Python 类比】
这个文件类似 Python 的 `if __name__ == '__main__'`：
```python
import asyncio

async def main():
    mode = detect_mode()
    if mode == '4G':
        init_mqtt()
    else:
        init_lora()

    init_level_sensor()

    asyncio.create_task(poll_level_sensor())
    asyncio.create_task(alarm_logic_task())

    await asyncio.gather(...)

if __name__ == '__main__':
    asyncio.run(main())
```
]]

--------------------------------------------------------------------------------
-- 项目信息
-- LuaTools 和 FOTA 升级需要这些全局变量
--------------------------------------------------------------------------------
PROJECT = "alarmer_8000_lora"
VERSION = "2.0.0"
PRODUCT_KEY = "GYV9vpPCVN1uraiaPVXfvfTNXKInE58K"

--------------------------------------------------------------------------------
-- 系统库导入
--------------------------------------------------------------------------------
_G.sys = require("sys")
_G.sysplus = require("sysplus")

--------------------------------------------------------------------------------
-- 业务模块导入
--------------------------------------------------------------------------------
local config = require("config")
local alarm = require("alarm")
local levelSensor = require("level_sensor")

--------------------------------------------------------------------------------
-- 打印启动日志
--------------------------------------------------------------------------------
log.info("main", PROJECT, VERSION)
log.info("main", "唤醒状态", pm.lastReson())

--------------------------------------------------------------------------------
-- 检测工作模式
-- GPIO3: 低电平=4G模式，高电平=LORA模式
--
-- 【Python 类比】
-- mode = 'LORA' if GPIO.input(3) == 1 else '4G'
--------------------------------------------------------------------------------
gpio.setup(config.gpio.MODE_SELECT, nil)  -- 设为输入模式
local modeLevel = gpio.get(config.gpio.MODE_SELECT)
local isMode4G = (modeLevel == 0)

log.info("main", "工作模式", isMode4G and "4G" or "LORA")

--------------------------------------------------------------------------------
-- 飞行模式控制
-- 4G模式需要联网，LORA模式关闭4G省电
--------------------------------------------------------------------------------
if isMode4G then
    mobile.flymode(0, false)  -- 关闭飞行模式
else
    mobile.flymode(0, true)   -- 开启飞行模式
end

--------------------------------------------------------------------------------
-- 初始化看门狗
-- 防止程序卡死
--------------------------------------------------------------------------------
if wdt then
    wdt.init(config.watchdog.timeout)
    sys.timerLoopStart(wdt.feed, config.watchdog.feed_interval)
    log.info("main", "看门狗已启动")
end

--------------------------------------------------------------------------------
-- EC618 平台特殊处理
--------------------------------------------------------------------------------
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

--------------------------------------------------------------------------------
-- 初始化 GPIO（LED 指示灯）
--------------------------------------------------------------------------------
alarm.initGPIO()

--------------------------------------------------------------------------------
-- 初始化液位仪串口
--------------------------------------------------------------------------------
levelSensor.init()

--------------------------------------------------------------------------------
-- 模块级状态变量
-- 用于跟踪报警状态，避免重复发送
--------------------------------------------------------------------------------
local lastAlarmSent = false     -- 上次是否发送了报警
local isKeyPressed = false      -- 是否按下了解除按键
local isCommReady = false       -- 通讯是否就绪

--------------------------------------------------------------------------------
-- 室外机电池状态回调（MQTT模式）
-- @param data table 接收到的消息数据
--
-- 【消息格式】
-- {vbat: 3700}  -- 电压单位 mV
--------------------------------------------------------------------------------
local function onMqttMessage(data)
    if data and data.vbat then
        log.info("main", "收到室外机电池状态", data.vbat, "mV")

        if data.vbat < config.lora_msg.BATTERY_THRESHOLD then
            alarm.startBatteryAlarm()
        else
            alarm.stopBatteryAlarm()
        end
    end
end

--------------------------------------------------------------------------------
-- 室外机电池状态回调（LORA模式）
-- @param msgType string "battery_low" 或 "battery_ok"
--------------------------------------------------------------------------------
local function onLoraMessage(msgType)
    log.info("main", "收到LORA消息", msgType)

    if msgType == "battery_low" then
        alarm.startBatteryAlarm()
    elseif msgType == "battery_ok" then
        alarm.stopBatteryAlarm()
    end
end

--------------------------------------------------------------------------------
-- 初始化通讯模块（根据模式）
--------------------------------------------------------------------------------
local commModule = nil  -- 当前使用的通讯模块

if isMode4G then
    log.info("main", "初始化4G/MQTT通讯")
    commModule = require("comm_mqtt")
    commModule.init(onMqttMessage)
else
    log.info("main", "初始化LORA通讯")
    commModule = require("comm_lora")
    commModule.init(onLoraMessage)
end

--------------------------------------------------------------------------------
-- 网络状态监听（4G模式）
-- 监听 IP_READY 和 IP_LOSE 事件
--------------------------------------------------------------------------------
if isMode4G then
    -- IP 就绪回调
    local function onIpReady(ip, adapter)
        if adapter == socket.LWIP_GP then
            -- 设置备用 DNS
            socket.setDNS(adapter, 1, config.dns.primary)
            socket.setDNS(adapter, 2, config.dns.secondary)

            log.info("main", "网络就绪", socket.localIP(socket.LWIP_GP))
            alarm.setNetLed(1)  -- 点亮网络指示灯
            isCommReady = true
        end
    end

    -- IP 丢失回调
    local function onIpLose(adapter)
        if adapter == socket.LWIP_GP then
            log.warn("main", "网络断开")
            alarm.setNetLed(0)  -- 熄灭网络指示灯
            isCommReady = false
        end
    end

    sys.subscribe("IP_READY", onIpReady)
    sys.subscribe("IP_LOSE", onIpLose)
else
    -- LORA 模式默认通讯就绪
    isCommReady = true
end

--------------------------------------------------------------------------------
-- FOTA 远程升级（4G模式）
--------------------------------------------------------------------------------
if isMode4G then
    local libfota2 = require("libfota2")

    local function fotaCallback(ret)
        if ret == 0 then
            log.info("fota", "升级包下载成功，重启安装")
            rtos.reboot()
        elseif ret == 1 then
            log.info("fota", "连接失败")
        elseif ret == 2 then
            log.info("fota", "URL错误")
        elseif ret == 3 then
            log.info("fota", "服务器断开")
        elseif ret == 4 then
            log.info("fota", "已是最新版本或升级包不存在")
        else
            log.info("fota", "其他错误", ret)
        end
    end

    sys.taskInit(function()
        -- 等待网络就绪
        while not socket.adapter(socket.dft()) do
            sys.waitUntil("IP_READY", 1000)
        end
        log.info("fota", "开始检查升级")
        libfota2.request(fotaCallback, {})
    end)
end

--------------------------------------------------------------------------------
-- 解除报警按键处理
-- GPIO34 连接物理按键，按下时触发解除报警
--------------------------------------------------------------------------------
gpio.setup(config.gpio.KEY_CANCEL, function()
    log.info("main", "解除报警按键按下")
    isKeyPressed = true
end, gpio.PULLDOWN, gpio.RISING)

--------------------------------------------------------------------------------
-- 液位 IO 输入监控任务
-- 部分液位仪直接输出高电平表示报警，不通过串口协议
-- 这里定期检查 GPIO2 (LEVEL_INPUT) 的电平
--------------------------------------------------------------------------------
sys.taskInit(function()
    gpio.setup(config.gpio.LEVEL_INPUT, nil)  -- 设为输入

    while true do
        local level = gpio.get(config.gpio.LEVEL_INPUT)

        -- 如果 IO 检测到高电平，设置报警状态
        if level == 1 then
            levelSensor.setHighLevel(true)
        end

        sys.wait(1000)  -- 每秒检查一次
    end
end)

--------------------------------------------------------------------------------
-- 启动液位轮询任务
-- 定期向液位仪发送查询命令
--------------------------------------------------------------------------------
levelSensor.startPolling()

--------------------------------------------------------------------------------
-- 核心业务逻辑任务
-- 这是整个系统的核心：判断液位状态并发送报警
--
-- 【状态机】
--
--     ┌─────────────┐
--     │   空闲      │
--     │  IDLE       │
--     └──────┬──────┘
--            │ 检测到高液位
--            ▼
--     ┌─────────────┐
--     │   报警中    │ ← 本机LED亮 + TTS播报
--     │  ALARMING   │ ← 发送报警指令给室外机
--     └──────┬──────┘
--            │ 液位恢复 或 按键解除
--            ▼
--     ┌─────────────┐
--     │   空闲      │ ← 发送取消/解除指令
--     │  IDLE       │
--     └─────────────┘
--------------------------------------------------------------------------------
sys.taskInit(function()
    -- 等待通讯就绪（4G模式等待MQTT连接）
    if isMode4G then
        sys.waitUntil("mqtt_connected", 30000)
        log.info("main", "MQTT连接完成")
    end

    while true do
        -- 获取当前液位状态
        local isHighLevel = levelSensor.isHighLevel()
        local currentAlarming = alarm.isHighLevelActive()

        -- ========== 检测到高液位，且之前未报警 ==========
        if isHighLevel and not lastAlarmSent then
            log.info("main", "检测到高液位，触发报警")

            -- 本机报警
            alarm.startHighLevelAlarm()

            -- 发送报警指令给室外机
            if isCommReady then
                commModule.sendAlarm()
                log.info("main", "报警指令已发送")
            end

            lastAlarmSent = true

        -- ========== 液位恢复正常，且之前在报警 ==========
        elseif not isHighLevel and lastAlarmSent and not isKeyPressed then
            log.info("main", "液位恢复正常，取消报警")

            -- 停止本机报警
            alarm.stopHighLevelAlarm()

            -- 发送取消指令给室外机
            if isCommReady then
                commModule.sendCancel()
                log.info("main", "取消指令已发送")
            end

            lastAlarmSent = false
        end

        -- ========== 按键解除报警 ==========
        if isKeyPressed then
            log.info("main", "按键解除报警")

            -- 停止本机报警
            alarm.stopHighLevelAlarm()

            -- 播放解除提示音
            alarm.playAlarmCleared()

            -- 清除液位报警状态
            levelSensor.clearAlarm()

            -- 发送解除指令给室外机
            if isCommReady then
                commModule.sendDisarm()
                log.info("main", "解除指令已发送")
            end

            lastAlarmSent = false

            -- 按键冷却期（防止误操作后立即再次报警）
            sys.wait(config.alarm.key_cooldown_time)

            isKeyPressed = false
            log.info("main", "按键冷却期结束")
        end

        -- 主循环间隔
        sys.wait(1000)
    end
end)

--------------------------------------------------------------------------------
-- 内存监控任务（调试用）
--------------------------------------------------------------------------------
sys.taskInit(function()
    while true do
        sys.wait(30000)  -- 每 30 秒输出一次
        log.info("mem", "lua", rtos.meminfo())
        log.info("mem", "sys", rtos.meminfo("sys"))
        if isMode4G then
            log.info("net", "状态", mobile.status())
        end
    end
end)

--------------------------------------------------------------------------------
-- 启动调度器
-- 这是程序的入口点，必须放在最后
-- sys.run() 之后不要添加任何代码
--------------------------------------------------------------------------------
sys.run()
