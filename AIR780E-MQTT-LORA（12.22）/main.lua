--[[
@module main
@summary 主入口文件 - 模式选择、初始化、主逻辑调度
@version 2.0.0

================================================================================
模块概述
================================================================================

这是程序的入口文件，类似 Python 的 `if __name__ == '__main__'`。
LuaOS 会从这个文件开始执行。

【主要职责】
1. 检测工作模式（4G 或 LORA）
2. 初始化各个模块
3. 根据唤醒原因执行不同的业务逻辑
4. 协调模块间的协作

【程序流程图】

┌─────────────┐
│   上电启动   │
└──────┬──────┘
       ▼
┌─────────────┐
│  检测工作模式 │ GPIO1: 0=4G, 1=LORA
└──────┬──────┘
       ▼
┌─────────────┐
│  初始化模块  │ power, alarm, comm_4g/comm_lora
└──────┬──────┘
       ▼
┌─────────────┐
│ 解析唤醒原因 │ 上电/RTC/IO(雷达)
└──────┬──────┘
       ▼
┌─────────────────────────────────────┐
│          根据唤醒原因处理            │
├─────────────┬───────────┬───────────┤
│   上电启动   │  RTC唤醒  │   IO唤醒   │
│    ↓        │    ↓      │    ↓      │
│ 进入PSM     │ 上报状态  │ 等待报警  │
│             │ 进入PSM   │ 30分钟    │
│             │           │ 进入PSM   │
└─────────────┴───────────┴───────────┘

【LuaOS 程序结构】
LuaOS 使用协程（coroutine）实现多任务：
- sys.taskInit(fn) 创建任务
- sys.wait(ms) 任务休眠
- sys.waitUntil(event) 等待事件
- sys.run() 启动调度器（必须在最后调用）

【与 Python 的对比】
LuaOS 的协程类似 Python 的 asyncio：
```python
import asyncio

async def task1():
    while True:
        await asyncio.sleep(1)
        print("task1")

async def main():
    asyncio.create_task(task1())
    await asyncio.gather(...)

asyncio.run(main())  # 类似 sys.run()
```
]]

--------------------------------------------------------------------------------
-- 项目信息
-- 这些全局变量被 LuaOS 工具链（LuaTools）使用
-- 也用于 FOTA 升级时的版本比对
--------------------------------------------------------------------------------
PROJECT = "sczthd_780ehv_bjq_lora"  -- 项目名称
VERSION = "001.000.000"             -- 版本号
PRODUCT_KEY = "123"                 -- 产品密钥

--------------------------------------------------------------------------------
-- 系统库导入
-- _G 是 Lua 的全局表，相当于 Python 的 builtins
-- 将 sys 和 sysplus 放入全局表，其他模块可以直接使用
--------------------------------------------------------------------------------
_G.sys = require("sys")        -- LuaOS 系统库，提供任务调度、事件等
_G.sysplus = require("sysplus") -- LuaOS 扩展库，提供额外的系统功能

--------------------------------------------------------------------------------
-- 业务模块导入
-- local 关键字声明局部变量，只在本文件内可见
-- require() 类似 Python 的 import
--------------------------------------------------------------------------------
local config = require("config")  -- 配置管理模块
local power = require("power")    -- 电源管理模块
local alarm = require("alarm")    -- 报警控制模块

--------------------------------------------------------------------------------
-- 输出启动日志
-- log.info(tag, ...) 是 LuaOS 的日志 API
-- tag 用于分类日志，便于过滤
--------------------------------------------------------------------------------
log.info("main", PROJECT, VERSION)

--------------------------------------------------------------------------------
-- 检测工作模式
-- 通过读取 GPIO1 引脚的电平判断：
-- - 低电平(0) = 4G 模式（使用 MQTT 通讯）
-- - 高电平(1) = LORA 模式（使用串口+LORA 模块通讯）
--
-- 【Python 类比】
-- GPIO.setup(1, GPIO.IN)
-- is_mode_4g = (GPIO.input(1) == 0)
--------------------------------------------------------------------------------
gpio.setup(config.gpio.MODE_SELECT, nil)  -- 设置为输入模式（nil=高阻态输入）
local isMode4G = (gpio.get(config.gpio.MODE_SELECT) == 0)  -- 读取电平
log.info("main", "工作模式", isMode4G and "4G" or "LORA")
-- Lua 的三元表达式：condition and value_if_true or value_if_false

--------------------------------------------------------------------------------
-- 飞行模式控制
-- 4G 模式需要联网，所以关闭飞行模式
-- LORA 模式不需要 4G 网络，开启飞行模式省电
--
-- mobile.flymode(sim_id, enable)
-- sim_id: SIM 卡槽编号（0 表示第一个卡槽）
-- enable: true=开启飞行模式, false=关闭飞行模式
--------------------------------------------------------------------------------
if isMode4G then
    mobile.flymode(0, false)  -- 关闭飞行模式，启用 4G
else
    mobile.flymode(0, true)   -- 开启飞行模式，禁用 4G
end

--------------------------------------------------------------------------------
-- 初始化看门狗
-- 看门狗是硬件定时器，防止程序卡死：
-- 1. wdt.init(timeout) 初始化，设置超时时间
-- 2. 定期调用 wdt.feed() "喂狗"
-- 3. 如果超时未喂狗，硬件会自动重启
--
-- 【Python 类比】
-- 类似 systemd 的 watchdog 功能：
-- sd_watchdog_enabled(...)
-- sd_notify(0, "WATCHDOG=1")
--------------------------------------------------------------------------------
wdt.init(config.power.wdt_timeout)  -- 初始化，超时 9 秒
-- sys.timerLoopStart(fn, interval) 创建循环定时器
-- 每 3 秒喂狗一次，确保程序正常运行
sys.timerLoopStart(wdt.feed, config.power.wdt_feed_interval)

--------------------------------------------------------------------------------
-- EC618 平台特殊处理
-- Air780E 使用 EC618 芯片，AT 固件默认有开机键防抖功能
-- 这里禁用该功能，避免影响 PSM 休眠
--
-- rtos.bsp() 返回当前芯片平台名称
--------------------------------------------------------------------------------
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

--------------------------------------------------------------------------------
-- 初始化电源管理模块
-- 传入工作模式，电源模块会根据模式配置不同的唤醒源
--------------------------------------------------------------------------------
power.init(isMode4G)

--------------------------------------------------------------------------------
-- 消息处理回调函数
-- 这是一个统一的消息处理器，4G 和 LORA 模式都使用这个回调
-- 接收到的消息会被解析，根据类型执行相应操作
--
-- 【消息格式】
-- 4G 模式：JSON 格式，如 {"type": "alarm"}
-- LORA 模式：简单字符，被解析为 {type: "alarm"}
--
-- 【Python 类比】
-- def on_message_received(data: dict):
--     msg_type = data.get('type') or data.get('msgType')
--     if msg_type == 'alarm':
--         alarm.start()
--     elif msg_type == 'cancel':
--         alarm.stop()
--------------------------------------------------------------------------------
local function onMessageReceived(data)
    -- 兼容两种消息格式
    local msgType = data.type or data.msgType

    if msgType == "alarm" or data.alarm then
        -- ========== 报警命令 ==========
        log.info("main", "收到报警命令")
        alarm.start()  -- 启动报警（LED 闪烁 + 语音播报）

    elseif msgType == "cancel" or data.cancel then
        -- ========== 取消报警命令 ==========
        log.info("main", "收到取消报警命令")
        alarm.stop()               -- 停止报警
        sys.publish("enter_sleep") -- 发布休眠事件

    elseif msgType == "disarm" or data.disarm then
        -- ========== 解除报警命令 ==========
        -- 与取消报警类似，但语义不同：
        -- - 取消：临时取消当前报警
        -- - 解除：彻底解除报警状态
        log.info("main", "收到解除报警命令")
        alarm.stop()
        sys.publish("enter_sleep")
    end
end

--------------------------------------------------------------------------------
-- 根据模式初始化通讯模块
-- 只加载需要的模块，节省内存
--------------------------------------------------------------------------------
if isMode4G then
    log.info("main", "启用4G模式")
    local comm_4g = require("comm_4g")  -- 加载 4G 通讯模块
    comm_4g.init(onMessageReceived)      -- 初始化并传入回调
else
    log.info("main", "启用LORA模式")
    local comm_lora = require("comm_lora")  -- 加载 LORA 通讯模块
    comm_lora.init(onMessageReceived)        -- 初始化并传入回调
end

--------------------------------------------------------------------------------
-- 主状态机任务
-- 根据唤醒原因执行不同的业务逻辑
--
-- 【状态机逻辑】
-- 1. POWER_ON（上电启动）→ 等待初始化 → 进入 PSM
-- 2. RTC（定时唤醒）→ 上报状态 → 进入 PSM
-- 3. IO（雷达唤醒）→ 上报状态 → 保持唤醒 30 分钟 → 进入 PSM
--
-- 【Python 类比】
-- async def main_state_machine():
--     wakeup_reason = power.get_wakeup_reason()
--     if wakeup_reason == POWER_ON:
--         await asyncio.sleep(5)
--         power.enter_psm()
--     elif wakeup_reason == RTC:
--         await report_status()
--         power.enter_psm()
--     ...
--------------------------------------------------------------------------------
sys.taskInit(function()
    -- 获取唤醒原因
    local wakeupReason = power.getWakeupReason()

    -- 【4G 模式：等待 MQTT 连接】
    -- 必须先建立网络连接才能通讯
    -- sys.waitUntil(event, timeout) 等待事件或超时
    -- 返回 true 表示收到事件，false 表示超时
    if isMode4G then
        sys.waitUntil("mqtt_connected", 30000)  -- 最多等待 30 秒
        log.info("main", "MQTT连接完成或超时")
    end

    -- ========== 根据唤醒原因处理 ==========

    if wakeupReason == config.wakeup.POWER_ON then
        -- 【上电启动】
        -- 设备首次上电或重启后
        -- 简单初始化后直接进入 PSM 休眠，等待唤醒
        log.info("main", "上电启动，准备进入PSM")
        sys.wait(5000)    -- 等待 5 秒，确保初始化完成
        power.enterPSM()  -- 进入深度休眠

    elseif wakeupReason == config.wakeup.RTC then
        -- 【RTC 定时唤醒】
        -- 每 6 小时唤醒一次，上报设备状态（心跳包）
        log.info("main", "RTC唤醒，上报状态")

        if isMode4G then
            -- 4G 模式：通过 MQTT 上报
            local comm_4g = require("comm_4g")
            sys.waitUntil("mqtt_connected", 30000)  -- 等待连接
            local vbat = power.getBatteryVoltage()  -- 获取电池电压
            comm_4g.reportStatus(vbat)              -- 上报状态
            sys.wait(3000)  -- 等待消息发送完成
        else
            -- LORA 模式：通过串口上报电池状态
            local comm_lora = require("comm_lora")
            local isLow, vbat = power.isBatteryLow()  -- 检查电量
            if isLow then
                comm_lora.sendBatteryLow()   -- 发送 "DDDD"
            else
                comm_lora.sendBatteryOK()    -- 发送 "EEEE"
            end
            sys.wait(1000)
        end

        power.enterPSM()  -- 上报完成，进入休眠

    elseif wakeupReason == config.wakeup.IO then
        -- 【IO 唤醒（雷达检测到人员）】
        -- 这是最复杂的情况：
        -- 1. 检查是否在冷却期内（30分钟内不重复唤醒）
        -- 2. 上报唤醒事件
        -- 3. 保持清醒 30 分钟，等待可能的报警指令
        -- 4. 如果 30 分钟内没有报警，进入休眠
        log.info("main", "IO唤醒，检查冷却状态")

        -- 【防重复唤醒机制】
        -- 需求：30分钟内不会重复唤醒
        -- 如果在冷却期内，直接进入休眠，不处理
        if power.isRadarInCooldown() then
            log.info("main", "雷达在冷却期内，直接进入休眠")
            power.waitRadarStable()  -- 等待雷达信号稳定
            power.enterPSM()
            return  -- 退出任务函数（不会执行到这里，因为 PSM 会暂停）
        end

        -- 记录本次唤醒时间（用于下次冷却判断）
        power.recordRadarWakeup()
        log.info("main", "IO唤醒，保持唤醒状态")

        if isMode4G then
            -- ========== 4G 模式处理 ==========
            local comm_4g = require("comm_4g")

            -- 上报唤醒事件（告诉服务器雷达检测到人员）
            sys.waitUntil("mqtt_connected", config.power.mqtt_connect_timeout)
            local vbat = power.getBatteryVoltage()
            comm_4g.reportStatus(vbat)

            -- 保持唤醒一段时间
            -- 在此期间，如果收到报警指令，会触发 alarm.start()
            power.keepAwakeAfterRadar()  -- 保持清醒 30 分钟

            -- 等待雷达信号稳定后再休眠
            -- 避免雷达仍在高电平时休眠，导致立即再次唤醒
            power.waitRadarStable()
        else
            -- ========== LORA 模式处理 ==========
            -- 【修复】之前 LORA 模式缺少 IO 唤醒处理
            local comm_lora = require("comm_lora")

            -- 上报电池状态
            local isLow, vbat = power.isBatteryLow()
            if isLow then
                comm_lora.sendBatteryLow()
            else
                comm_lora.sendBatteryOK()
            end

            -- LORA 模式也需要保持唤醒 30 分钟
            -- 等待主控制器可能发送的报警指令
            power.keepAwakeAfterRadar()

            -- 等待雷达信号稳定
            power.waitRadarStable()
        end

        power.enterPSM()  -- 进入休眠
    end
end)

--------------------------------------------------------------------------------
-- 休眠触发任务
-- 监听 "enter_sleep" 事件，收到后执行休眠流程
--
-- 【触发时机】
-- - 收到取消报警命令
-- - 收到解除报警命令
--
-- 【Python 类比】
-- async def sleep_trigger_task():
--     while True:
--         await wait_for_event("enter_sleep")
--         await asyncio.sleep(10)  # 等待业务完成
--         alarm.stop()
--         power.enter_psm()
--------------------------------------------------------------------------------
sys.taskInit(function()
    while true do
        -- 等待休眠事件
        sys.waitUntil("enter_sleep")
        log.info("main", "收到休眠指令")

        -- 等待一段时间，确保业务完成
        -- 例如：语音播报完成、消息发送完成
        sys.wait(10000)  -- 等待 10 秒

        -- 停止报警（如果正在报警的话）
        alarm.stop()
        alarm.shutdownAudio()  -- 关闭音频硬件

        -- 进入深度休眠
        power.enterPSM()
    end
end)

--------------------------------------------------------------------------------
-- 内存监控任务（调试用）
-- 定期输出内存使用情况，用于发现内存泄漏
-- 正式发布时可以注释掉这段代码
--
-- rtos.meminfo() 返回 Lua 虚拟机的内存使用
-- rtos.meminfo("sys") 返回系统内存使用
--------------------------------------------------------------------------------
sys.taskInit(function()
    while true do
        sys.wait(30000)  -- 每 30 秒输出一次
        log.info("mem", "lua", rtos.meminfo())      -- Lua 内存
        log.info("mem", "sys", rtos.meminfo("sys")) -- 系统内存
    end
end)

--------------------------------------------------------------------------------
-- 程序结束标记
-- sys.run() 启动 LuaOS 的任务调度器
-- 这是整个程序的入口点，必须放在最后
-- 调用 sys.run() 后，程序进入事件循环，不会返回
--
-- 【重要】
-- sys.run() 之后不要添加任何代码，它们永远不会被执行
--
-- 【Python 类比】
-- asyncio.run(main())  # 启动事件循环，阻塞直到完成
--------------------------------------------------------------------------------
sys.run()
-- sys.run() 之后不要加任何语句
