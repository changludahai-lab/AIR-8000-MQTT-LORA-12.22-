--[[
@module power
@summary 电源管理模块 - 休眠、唤醒、低功耗配置
@version 1.0.0

================================================================================
模块概述
================================================================================

本模块负责设备的电源管理，是低功耗户外设备的核心模块。

【为什么需要电源管理？】
- 户外设备通常使用电池供电，需要尽可能延长续航
- Air780E 支持多种功耗模式，最低可达微安级别
- 合理的休眠/唤醒策略可以让设备运行数月甚至数年

【功耗模式说明】
- 正常工作模式：功耗较高，CPU 全速运行
- 轻休眠模式（WORK_MODE=2）：CPU 降频，外设可用
- PSM 深度休眠（WORK_MODE=3）：功耗最低，仅保留 RTC 和唤醒源

【唤醒源类型】
1. RTC 定时唤醒：设备定时醒来上报状态
2. WAKEUP0（4G模式）：连接雷达，检测到人员时唤醒
3. WAKEUP6（LORA模式）：串口 RI 引脚，收到数据时唤醒

【Python 类比】
这个模块类似于 Python 中的电源管理库，但更底层：
- 类似 psutil 获取系统状态
- 类似 schedule 定时任务（RTC 唤醒）
- 类似 GPIO 中断（IO 唤醒）
]]

local power = {}
local config = require("config")

--------------------------------------------------------------------------------
-- 模块内部状态（私有变量）
-- Lua 没有 class，用闭包模拟私有变量
-- 这些变量只在本模块内可见，外部通过函数访问
--------------------------------------------------------------------------------
local wakeupReason = config.wakeup.POWER_ON  -- 当前唤醒原因
local isMode4G = true                         -- 当前运行模式（默认4G）

-- 【雷达唤醒冷却机制】
-- 使用 fskv（Flash Key-Value）存储上次雷达唤醒时间
-- fskv 在 PSM 休眠后仍然保持数据
-- KV_KEY_LAST_RADAR_WAKEUP: 存储上次雷达唤醒的时间戳
local KV_KEY_LAST_RADAR_WAKEUP = "last_radar_wakeup"

--------------------------------------------------------------------------------
-- 初始化电源管理
-- @param mode4G boolean 是否为4G模式（true=4G，false=LORA）
--
-- 【调用时机】
-- 在 main.lua 中，确定运行模式后立即调用
--
-- 【Python 类比】
-- def __init__(self, mode_4g: bool):
--     self.mode_4g = mode_4g
--     self._parse_wakeup_reason()
--     self._init_gpio()
--------------------------------------------------------------------------------
function power.init(mode4G)
    isMode4G = mode4G
    power.parseWakeupReason()  -- 解析唤醒原因
    power.initGPIO()           -- 初始化 GPIO
    log.info("power", "初始化完成", "模式=" .. (isMode4G and "4G" or "LORA"), "唤醒原因=" .. wakeupReason)
end

--------------------------------------------------------------------------------
-- 解析唤醒原因
-- @return number 唤醒原因代码（参见 config.wakeup）
--
-- 【工作原理】
-- pm.lastReson() 返回三个值(PMA, PMB, PMC)，组合判断唤醒原因：
-- - (1, 4, 0) = RTC 定时唤醒
-- - (2, 4, 0) = WAKEUP0 唤醒（雷达）
-- - (6, 4, 0) = WAKEUP6 唤醒（串口 RI）
-- - 其他 = 正常上电启动
--
-- 【Python 类比】
-- def _parse_wakeup_reason(self) -> int:
--     pma, pmb, pmc = pm.last_reason()
--     if (pma, pmb, pmc) == (1, 4, 0):
--         return WAKEUP_RTC
--     elif (pma, pmb, pmc) == (2, 4, 0):
--         return WAKEUP_IO
--     ...
--------------------------------------------------------------------------------
function power.parseWakeupReason()
    -- pm.lastReson() 是 LuaOS API，返回上次休眠前的状态信息
    -- 类似 Python 的多返回值：pma, pmb, pmc = pm.last_reason()
    local PMA, PMB, PMC = pm.lastReson()
    log.info("power", "wakeup state", PMA, PMB, PMC)

    -- 根据返回值组合判断唤醒原因
    if PMA == 1 and PMB == 4 and PMC == 0 then
        -- RTC 定时器触发唤醒
        wakeupReason = config.wakeup.RTC
        log.info("power", "RTC唤醒")
    elseif PMA == 2 and PMB == 4 and PMC == 0 then
        -- WAKEUP0 引脚触发（4G模式下是雷达）
        wakeupReason = config.wakeup.IO
        log.info("power", "雷达唤醒")
    elseif PMA == 6 and PMB == 4 and PMC == 0 then
        -- WAKEUP6 引脚触发（LORA模式下是串口 RI）
        wakeupReason = config.wakeup.IO
        log.info("power", "串口RI唤醒")
    else
        -- 其他情况视为正常上电
        wakeupReason = config.wakeup.POWER_ON
        log.info("power", "电源上电")
    end

    return wakeupReason
end

--------------------------------------------------------------------------------
-- 获取唤醒原因
-- @return number 唤醒原因代码
--
-- 【用途】
-- 外部模块（如 main.lua）通过这个函数获取唤醒原因，决定后续处理逻辑
--
-- 【Python 类比】
-- @property
-- def wakeup_reason(self) -> int:
--     return self._wakeup_reason
--------------------------------------------------------------------------------
function power.getWakeupReason()
    return wakeupReason
end

--------------------------------------------------------------------------------
-- 初始化 GPIO（低功耗配置）
--
-- 【工作原理】
-- 1. 将所有 LED 引脚初始化为输出模式，默认低电平（灯灭）
-- 2. 关闭可能导致漏电流的引脚
--
-- 【为什么 LED 默认关闭？】
-- - 上电时 GPIO 状态不确定，可能导致 LED 闪烁
-- - 统一初始化为低电平，确保状态可控
--
-- 【Python 类比】(以 RPi.GPIO 为例)
-- def _init_gpio(self):
--     for pin in LED_PINS:
--         GPIO.setup(pin, GPIO.OUT, initial=GPIO.LOW)
--------------------------------------------------------------------------------
function power.initGPIO()
    -- gpio.setup(pin, default_value) 初始化为输出模式
    -- 第二个参数是默认输出值：0=低电平，1=高电平
    gpio.setup(config.gpio.LED_MAIN, 0)
    gpio.setup(config.gpio.LED_1, 0)
    gpio.setup(config.gpio.LED_2, 0)
    gpio.setup(config.gpio.LED_3, 0)
    gpio.setup(config.gpio.LED_4, 0)
    gpio.setup(config.gpio.LED_5, 0)

    -- 关闭可能导致漏电流的 GPIO
    power.reducePowerLeak()
end

--------------------------------------------------------------------------------
-- 减少漏电流配置
--
-- 【为什么有漏电流？】
-- - GPIO 引脚如果处于"浮空"状态（既不是高也不是低），会产生漏电流
-- - 某些内部引脚（如 WAKEUP1、PWR_KEY）在不使用时也会有漏电流
-- - 这些微小电流累积起来会显著影响电池续航
--
-- 【解决方案】
-- - gpio.close(pin) 关闭引脚功能，释放资源
-- - gpio.setup(pin, nil) 将引脚设为高阻态（Hi-Z）
--
-- 【Python 类比】
-- def _reduce_power_leak(self):
--     GPIO.cleanup([WAKEUP1, PWR_KEY])  # 释放引脚
--------------------------------------------------------------------------------
function power.reducePowerLeak()
    -- gpio.close() 关闭指定引脚，释放资源
    gpio.close(gpio.WAKEUP1)
    gpio.close(gpio.PWR_KEY)
    -- gpio.setup(pin, nil) 设置为高阻态，防止浮空输入漏电流
    gpio.setup(config.gpio.FLOAT_INPUT, nil)
end

--------------------------------------------------------------------------------
-- 进入低功耗模式（轻休眠）
--
-- 【轻休眠 vs 深度休眠】
-- - 轻休眠：CPU 降频，外设可用，可以响应中断，唤醒快
-- - 深度休眠（PSM）：几乎完全关机，只保留 RTC 和唤醒源，功耗最低
--
-- 【使用场景】
-- - 雷达唤醒后，等待报警指令期间使用轻休眠
-- - 可以随时被 MQTT 消息或串口数据唤醒处理
--
-- 【Python 类比】
-- def enter_light_sleep(self):
--     self._reduce_power_leak()
--     pm.power(pm.USB, False)       # 关闭 USB
--     pm.power(pm.WORK_MODE, 2)     # 进入轻休眠
--------------------------------------------------------------------------------
function power.enterLightSleep()
    log.info("power", "进入轻休眠模式")
    power.reducePowerLeak()
    pm.power(pm.USB, false)       -- 关闭 USB 供电（省电）
    pm.power(pm.WORK_MODE, 2)     -- 设置工作模式为轻休眠（2）
end

--------------------------------------------------------------------------------
-- 进入 PSM 深度休眠模式
--
-- 【PSM = Power Save Mode】
-- 这是最低功耗模式，设备几乎完全关机：
-- - CPU 停止运行
-- - 所有外设关闭
-- - 只保留 RTC（实时时钟）和配置好的唤醒源
-- - 功耗可低至微安级别
--
-- 【唤醒方式】
-- 1. RTC 定时唤醒：pm.dtimerStart() 设置的定时器
-- 2. IO 唤醒：配置好的 WAKEUP 引脚电平变化
--
-- 【注意事项】
-- - 进入 PSM 后，代码不会继续执行
-- - 唤醒后相当于重新启动，从 main.lua 开始执行
-- - 所有 RAM 中的变量都会丢失
--
-- 【Python 类比】
-- 这在纯 Python 中没有直接对应，类似于：
-- def enter_psm(self):
--     # 关闭所有外设
--     self._shutdown_all_peripherals()
--     # 设置闹钟（RTC）
--     schedule_wakeup(hours=6)
--     # 关机（唤醒后重新启动）
--     os.system('shutdown now')
--------------------------------------------------------------------------------
function power.enterPSM()
    log.info("power", "进入PSM深度休眠模式")

    -- 【第1步】彻底关闭音频
    -- audio.pm(id, mode) 设置音频电源状态
    -- audio.POWEROFF 表示完全断电
    audio.pm(0, audio.POWEROFF)

    -- 【第2步】进入飞行模式
    -- 关闭 4G 基带，停止与基站通讯
    -- 这是 4G 模块最耗电的部分
    mobile.flymode(0, true)  -- 0=SIM卡槽编号，true=开启飞行模式

    -- 【第3步】关闭 PWR_KEY
    -- PWR_KEY 是电源按键引脚，不使用时需要关闭
    gpio.close(gpio.PWR_KEY)

    -- 【第4步】根据模式配置唤醒源
    -- 4G 模式和 LORA 模式使用不同的唤醒源
    if isMode4G then
        -- ========== 4G 模式 ==========
        -- 使用 WAKEUP0 作为唤醒源（连接雷达）
        -- 雷达检测到人员时输出高电平，触发唤醒

        -- gpio.setup(pin, callback, pull, trigger) 配置中断
        -- callback: 中断触发时执行的函数
        -- gpio.PULLDOWN: 内部下拉电阻（默认低电平）
        -- gpio.RISING: 上升沿触发（低→高）
        gpio.setup(gpio.WAKEUP0, function()
            log.info("power", "WAKEUP0触发")
        end, gpio.PULLDOWN, gpio.RISING)

        -- 关闭不使用的 WAKEUP6
        gpio.close(gpio.WAKEUP6)
    else
        -- ========== LORA 模式 ==========
        -- 使用 WAKEUP6 作为唤醒源（连接串口 RI）
        -- LORA 模块收到数据时通过 RI 引脚通知 Air780E

        gpio.close(gpio.WAKEUP0)  -- 关闭不使用的 WAKEUP0

        -- gpio.PULLUP: 内部上拉电阻（默认高电平）
        -- gpio.BOTH: 双边沿触发（高→低 或 低→高 都触发）
        gpio.setup(gpio.WAKEUP6, function()
            log.info("power", "WAKEUP6触发")
        end, gpio.PULLUP, gpio.BOTH)

        -- 关闭串口（休眠时不需要）
        uart.close(config.uart.id)
    end

    -- 【第5步】设置 RTC 定时唤醒
    -- pm.dtimerStart(id, milliseconds) 启动深度休眠定时器
    -- id=3 是定时器编号，可以设置多个定时器
    -- 到时间后设备会被唤醒（相当于重启）
    pm.dtimerStart(3, config.power.rtc_wakeup_interval)  -- 6小时后唤醒

    -- 【第6步】关闭其他可能漏电的 GPIO
    -- 这些引脚在不同版本的模块上可能有不同的默认状态
    gpio.setup(config.gpio.FLOAT_INPUT, nil)  -- 设为高阻态
    gpio.close(33)   -- WAKEUPPAD1
    gpio.close(20)   -- AGPIOWU0
    gpio.close(35)

    -- 【第7步】关闭设备电源
    -- pm.power(device, on/off) 控制各个模块的电源
    pm.power(pm.GPS, false)   -- 关闭 GPS（如果有）
    pm.power(pm.USB, false)   -- 关闭 USB

    -- 【第8步】进入深度休眠
    -- WORK_MODE = 3 表示 PSM 模式
    -- 执行这行后，CPU 会停止，代码不再执行
    pm.power(pm.WORK_MODE, 3)

    -- ========== 以下代码正常情况下不会执行 ==========
    -- 如果代码继续执行，说明 PSM 进入失败
    sys.wait(config.power.psm_fail_timeout)  -- 等待 15 秒
    log.error("power", "进入PSM模式失败，准备重启设备")

    -- PSM 失败时重启设备，避免设备长期高功耗运行
    -- 重启后会重新尝试进入 PSM
    rtos.reboot()
end

--------------------------------------------------------------------------------
-- 等待雷达稳定后再休眠
--
-- 【为什么需要等待？】
-- - 雷达检测到人员后会持续输出高电平
-- - 如果雷达还在高电平时就进入休眠，会立即被再次唤醒
-- - 需要等待雷达输出归零后再休眠
--
-- 【工作流程】
-- 1. 检查雷达电平
-- 2. 如果是高电平，等待 1 秒再检查
-- 3. 最多等待 5 次（5秒）
-- 4. 无论是否归零，最终都会继续执行
--
-- 【Python 类比】
-- def wait_radar_stable(self):
--     for _ in range(5):
--         if GPIO.input(WAKEUP0) == 0:
--             break
--         time.sleep(1)
--------------------------------------------------------------------------------
function power.waitRadarStable()
    -- 先将引脚设为普通输入模式（不是中断模式）
    gpio.setup(gpio.WAKEUP0, nil)
    local radar_level = gpio.get(gpio.WAKEUP0)  -- 读取当前电平
    local wait_count = 0

    -- Lua 的 while 循环，类似 Python 的 while
    while radar_level == 1 and wait_count < 5 do
        log.info("power", "雷达高电平，等待归零", wait_count)
        sys.wait(1000)  -- 等待 1000ms（1秒）
        radar_level = gpio.get(gpio.WAKEUP0)  -- 再次读取
        wait_count = wait_count + 1
    end

    log.info("power", "雷达已稳定")
end

--------------------------------------------------------------------------------
-- 雷达唤醒后保持清醒
--
-- 【使用场景】
-- - 雷达检测到人员后，设备唤醒
-- - 此时需要保持清醒一段时间，等待服务器下发报警指令
-- - 使用轻休眠模式，既省电又能响应消息
--
-- 【为什么是 30 分钟？】
-- - 雷达唤醒说明现场有人员活动
-- - 30 分钟内可能会收到报警指令
-- - 如果 30 分钟内没有指令，说明是虚警，可以继续休眠
--
-- 【Python 类比】
-- def keep_awake_after_radar(self):
--     self._reduce_power_leak()
--     pm.power(pm.USB, False)
--     pm.power(pm.WORK_MODE, 2)  # 轻休眠
--     time.sleep(30 * 60)        # 等待 30 分钟
--------------------------------------------------------------------------------
function power.keepAwakeAfterRadar()
    log.info("power", "雷达唤醒后保持清醒", config.power.radar_keep_awake_time / 1000 / 60, "分钟")
    power.reducePowerLeak()
    pm.power(pm.USB, false)
    pm.power(pm.WORK_MODE, 2)  -- 轻休眠模式
    -- sys.wait() 是 LuaOS 的协程等待，不会阻塞其他任务
    sys.wait(config.power.radar_keep_awake_time)  -- 等待 30 分钟
end

--------------------------------------------------------------------------------
-- 检查雷达状态
-- @return number 雷达引脚电平（0=无人，1=有人）
--
-- 【Python 类比】
-- def get_radar_level(self) -> int:
--     return GPIO.input(WAKEUP0)
--------------------------------------------------------------------------------
function power.getRadarLevel()
    gpio.setup(gpio.WAKEUP0, nil)  -- 设为输入模式
    return gpio.get(gpio.WAKEUP0)  -- 读取电平
end

--------------------------------------------------------------------------------
-- 获取电池电压
-- @return number 电池电压（毫伏 mV）
--
-- 【工作原理】
-- - adc.CH_VBAT 是 Air780E 内置的电池电压检测通道
-- - 返回值单位是毫伏（mV），如 3700 表示 3.7V
--
-- 【Python 类比】
-- def get_battery_voltage(self) -> int:
--     adc.open(adc.CH_VBAT)
--     voltage = adc.read(adc.CH_VBAT)
--     adc.close(adc.CH_VBAT)
--     return voltage
--------------------------------------------------------------------------------
function power.getBatteryVoltage()
    adc.open(adc.CH_VBAT)           -- 打开 ADC 通道
    local vbat = adc.get(adc.CH_VBAT)  -- 读取电压值
    adc.close(adc.CH_VBAT)          -- 关闭 ADC 通道（省电）
    return vbat
end

--------------------------------------------------------------------------------
-- 检查电池是否低电量
-- @return boolean 是否低电量
-- @return number 当前电压（mV）
--
-- 【返回多个值】
-- Lua 函数可以返回多个值，类似 Python 的元组拆包：
-- is_low, voltage = power.isBatteryLow()
--
-- 【Python 类比】
-- def is_battery_low(self) -> tuple[bool, int]:
--     voltage = self.get_battery_voltage()
--     return voltage < THRESHOLD, voltage
--------------------------------------------------------------------------------
function power.isBatteryLow()
    local vbat = power.getBatteryVoltage()
    -- 返回两个值：是否低电量，当前电压
    return vbat < config.lora_msg.BATTERY_THRESHOLD, vbat
end

--------------------------------------------------------------------------------
-- 检查雷达是否在冷却期内
-- @return boolean 是否在冷却期内（true=应该跳过本次唤醒）
--
-- 【防重复唤醒机制】
-- 需求：30分钟内不会重复唤醒
-- 实现：
-- 1. 使用 fskv（Flash KV 存储）记录上次雷达唤醒的时间戳
-- 2. 每次 IO 唤醒时检查距离上次唤醒是否超过冷却时间
-- 3. 如果在冷却期内，直接返回 true，调用者应跳过处理
--
-- 【为什么用 fskv？】
-- - PSM 休眠后 RAM 会丢失，普通变量无法保存
-- - fskv 存储在 Flash 中，掉电不丢失
-- - 类似 Python 的 pickle 或 sqlite 持久化
--
-- 【Python 类比】
-- def is_radar_in_cooldown(self) -> bool:
--     last_time = self._read_from_flash("last_radar_wakeup")
--     if last_time is None:
--         return False
--     elapsed = time.time() - last_time
--     return elapsed < COOLDOWN_TIME
--------------------------------------------------------------------------------
function power.isRadarInCooldown()
    -- 初始化 fskv（如果尚未初始化）
    if fskv then
        fskv.init()
    else
        -- 如果没有 fskv 库，直接返回 false（不启用冷却机制）
        log.warn("power", "fskv库不可用，冷却机制禁用")
        return false
    end

    -- 读取上次雷达唤醒时间
    local lastWakeupTime = fskv.get(KV_KEY_LAST_RADAR_WAKEUP)
    if not lastWakeupTime then
        -- 没有记录，说明是第一次或记录已清除
        log.info("power", "无上次雷达唤醒记录")
        return false
    end

    -- 获取当前时间戳（毫秒）
    -- mcu.ticks() 返回系统启动后的毫秒数，但 PSM 后会重置
    -- 使用 os.time() 获取 Unix 时间戳（秒），转换为毫秒
    local currentTime = os.time() * 1000

    -- 计算距离上次唤醒的时间
    local elapsed = currentTime - lastWakeupTime

    log.info("power", "雷达冷却检查",
             "上次唤醒=" .. lastWakeupTime,
             "当前时间=" .. currentTime,
             "已过去=" .. (elapsed / 1000 / 60) .. "分钟",
             "冷却时间=" .. (config.power.radar_cooldown_time / 1000 / 60) .. "分钟")

    -- 判断是否在冷却期内
    if elapsed < config.power.radar_cooldown_time then
        log.info("power", "雷达在冷却期内，跳过本次唤醒处理")
        return true
    end

    return false
end

--------------------------------------------------------------------------------
-- 记录雷达唤醒时间
-- 在成功处理雷达唤醒后调用，记录当前时间
--
-- 【调用时机】
-- 在 main.lua 的 IO 唤醒处理开始时调用
-- 只有真正开始处理（不在冷却期内）时才记录
--------------------------------------------------------------------------------
function power.recordRadarWakeup()
    if not fskv then
        log.warn("power", "fskv库不可用，无法记录唤醒时间")
        return
    end

    fskv.init()
    local currentTime = os.time() * 1000
    fskv.set(KV_KEY_LAST_RADAR_WAKEUP, currentTime)
    log.info("power", "记录雷达唤醒时间", currentTime)
end

--------------------------------------------------------------------------------
-- 清除雷达唤醒记录
-- 可选：在某些情况下需要重置冷却期
--------------------------------------------------------------------------------
function power.clearRadarWakeupRecord()
    if not fskv then
        return
    end
    fskv.init()
    fskv.del(KV_KEY_LAST_RADAR_WAKEUP)
    log.info("power", "清除雷达唤醒记录")
end

--------------------------------------------------------------------------------
-- 返回模块
-- 其他文件通过 require("power") 获取这个表
--------------------------------------------------------------------------------
return power
