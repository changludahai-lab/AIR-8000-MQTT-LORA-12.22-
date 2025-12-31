--[[
@module alarm
@summary 报警模块 - LED控制、语音播报、报警/解除报警
@version 1.0.0

================================================================================
模块概述
================================================================================

本模块负责报警器的核心业务逻辑：
1. LED 灯光闪烁（视觉报警）
2. TTS 语音播报（听觉报警）
3. 报警状态管理

【硬件组成】
- 6 个 LED 灯（1个主灯 + 5个报警灯）
- ES8311 音频编解码芯片（外接喇叭）
- 功放 PA 芯片（驱动喇叭）

【工作流程】
1. 收到报警指令 → alarm.start()
2. LED 开始闪烁（300ms 间隔）
3. 语音开始循环播报（4秒间隔）
4. 收到取消指令 → alarm.stop()
5. LED 熄灭，语音停止

【Python 类比】
这个模块类似于 Python 中的：
- threading.Timer 实现定时任务
- RPi.GPIO 控制 LED
- 音频播放库（如 pygame.mixer）

【LuaOS 定时器说明】
- sys.timerLoopStart(fn, interval) - 循环定时器，每隔 interval ms 执行一次
- sys.timerStop(timer_id) - 停止定时器
- 类似 Python 的 schedule.every(interval).do(fn)
]]

local alarm = {}
local config = require("config")

--------------------------------------------------------------------------------
-- 模块内部状态（私有变量）
-- Lua 没有 private 关键字，通过不导出变量实现私有
--------------------------------------------------------------------------------
local isAudioInit = false   -- 音频是否已初始化
local flashTimer = nil      -- LED 闪烁定时器的 ID
local audioTimer = nil      -- 语音播报定时器的 ID
local isAlarming = false    -- 当前是否在报警中

--------------------------------------------------------------------------------
-- 初始化音频硬件
-- @return boolean 是否初始化成功
--
-- 【为什么单独初始化音频？】
-- - 音频硬件初始化耗时较长（约几百毫秒）
-- - 不报警时不需要初始化，节省时间和功耗
-- - 使用 isAudioInit 标志避免重复初始化
--
-- 【硬件架构】
-- Air780E ──I2C──> ES8311（音频编解码）──> PA（功放）──> 喇叭
--          │
--          └─I2S──> ES8311（音频数据）
--
-- 【Python 类比】
-- def init_audio(self) -> bool:
--     if self._audio_initialized:
--         return True
--     # 初始化 I2C、I2S、音频芯片...
--     self._audio_initialized = True
--     return True
--------------------------------------------------------------------------------
function alarm.initAudio()
    -- 如果已经初始化过，直接返回
    -- 类似 Python 的单例模式
    if isAudioInit then
        return true
    end

    log.info("alarm", "初始化音频硬件")

    -- 获取音频配置（简化代码）
    local cfg = config.audio

    -- 【第1步】设置功放PA脚和ES8311电源脚
    -- gpio.setup(pin, value, pull) - 初始化引脚
    -- value=1 表示输出高电平，即给芯片上电
    -- gpio.PULLUP 表示内部上拉，保持高电平稳定
    gpio.setup(cfg.AUDIO_PA or config.gpio.AUDIO_PA, 1, gpio.PULLUP)
    gpio.setup(cfg.AUDIO_POWER or config.gpio.AUDIO_POWER, 1, gpio.PULLUP)

    -- 【第2步】初始化 I2C 总线
    -- I2C 用于配置 ES8311 芯片的寄存器
    -- i2c.FAST = 400kHz 速率（标准是 100kHz）
    i2c.setup(cfg.i2c_id, i2c.FAST)

    -- 【第3步】初始化 I2S 总线
    -- I2S 用于传输 PCM 音频数据到 ES8311
    -- 类似设置声卡的采样率、位深、声道等参数
    i2s.setup(
        cfg.i2s_id,           -- I2S 总线编号
        cfg.i2s_mode,         -- 主机/从机模式（0=主机）
        cfg.sample_rate,      -- 采样率（16000Hz）
        cfg.bits_per_sample,  -- 采样位深（16位）
        cfg.channel_format,   -- 声道格式（单声道右）
        cfg.comm_format,      -- 数据格式（LSB）
        cfg.channel_bits      -- 每通道位数（16位）
    )

    -- 【第4步】配置音频通道
    -- audio.config() 设置音频播放的硬件控制参数
    -- 这些参数控制 PA 和 DAC 的开关时序，防止"啪"声
    audio.config(
        cfg.multimedia_id,        -- 音频通道 ID
        config.gpio.AUDIO_PA,     -- PA 控制引脚
        cfg.pa_on_level,          -- PA 开启电平（1=高电平）
        cfg.power_delay,          -- DAC 启动前延时
        cfg.pa_delay,             -- DAC 启动后到 PA 开启的延时
        config.gpio.AUDIO_POWER,  -- ES8311 电源控制引脚
        cfg.power_on_level,       -- ES8311 电源开启电平
        cfg.power_time_delay      -- PA 与 DAC 关闭间隔
    )

    -- 【第5步】设置音频总线
    -- audio.setBus() 告诉系统使用哪种音频接口
    -- audio.BUS_I2S 表示使用 I2S 总线
    -- chip="es8311" 指定音频芯片型号
    audio.setBus(
        cfg.multimedia_id,
        audio.BUS_I2S,
        {
            chip = "es8311",      -- 芯片型号
            i2cid = cfg.i2c_id,   -- I2C 总线 ID（用于控制）
            i2sid = cfg.i2s_id    -- I2S 总线 ID（用于数据）
        }
    )

    -- 【第6步】设置音量
    -- audio.vol() 设置播放音量（0-100）
    -- audio.micVol() 设置麦克风增益（本项目可能不用）
    audio.vol(cfg.multimedia_id, cfg.voice_vol)
    audio.micVol(cfg.multimedia_id, cfg.mic_vol)

    isAudioInit = true
    log.info("alarm", "音频初始化完成")
    return true
end

--------------------------------------------------------------------------------
-- 设置所有报警 LED 的状态
-- @param state number 状态值（0=灭，1=亮）
--
-- 【这是本地函数（私有函数）】
-- local function 定义的函数只在本文件内可见
-- 类似 Python 中用下划线开头的 _private_method
--
-- 【Python 类比】
-- def _set_all_leds(self, state: int):
--     for pin in self.LED_PINS:
--         GPIO.output(pin, state)
--------------------------------------------------------------------------------
local function setAllLeds(state)
    -- gpio.set(pin, value) 设置引脚输出电平
    -- state=1 时 LED 亮，state=0 时 LED 灭
    gpio.set(config.gpio.LED_1, state)
    gpio.set(config.gpio.LED_2, state)
    gpio.set(config.gpio.LED_3, state)
    gpio.set(config.gpio.LED_4, state)
    gpio.set(config.gpio.LED_5, state)
end

--------------------------------------------------------------------------------
-- 关闭所有 LED（包括主 LED）
-- 本地函数，用于停止报警时调用
--------------------------------------------------------------------------------
local function turnOffAllLeds()
    gpio.set(config.gpio.LED_MAIN, 0)  -- 关闭主 LED
    setAllLeds(0)                       -- 关闭所有报警 LED
end

--------------------------------------------------------------------------------
-- 开始报警
--
-- 【功能】
-- 1. 打开主 LED（常亮）
-- 2. 启动报警 LED 闪烁（300ms 间隔交替亮灭）
-- 3. 启动语音循环播报（每 4 秒播报一次）
-- 4. 发布 "ALARM_STARTED" 事件
--
-- 【防重入机制】
-- - 使用 isAlarming 标志防止重复启动报警
-- - 避免创建多个定时器造成资源泄漏
--
-- 【Python 类比】
-- def start(self):
--     if self._is_alarming:
--         return
--     self._is_alarming = True
--     GPIO.output(LED_MAIN, GPIO.HIGH)
--     self._flash_timer = Timer(0.3, self._flash_callback)
--     self._audio_timer = Timer(4.0, self._tts_callback)
--------------------------------------------------------------------------------
function alarm.start()
    -- 防止重复触发
    if isAlarming then
        log.info("alarm", "已在报警中，忽略重复触发")
        return
    end

    log.info("alarm", "启动报警")
    isAlarming = true

    -- 打开主 LED（常亮，表示设备在报警状态）
    gpio.set(config.gpio.LED_MAIN, 1)

    -- 【启动 LED 闪烁定时器】
    -- sys.timerLoopStart(callback, interval) 创建循环定时器
    -- 返回定时器 ID，用于后续停止
    --
    -- ledState 使用闭包保持状态（类似 Python 的闭包）
    -- 每次触发时 ledState 在 0 和 1 之间切换
    local ledState = 0
    flashTimer = sys.timerLoopStart(function()
        -- 1 - ledState 实现 0→1→0→1 的切换
        -- ledState=0 时，1-0=1（亮）
        -- ledState=1 时，1-1=0（灭）
        ledState = 1 - ledState
        setAllLeds(ledState)
    end, config.alarm.led_flash_interval)  -- 300ms 间隔

    -- 【修复】立即播放第一次语音，避免等待 4 秒
    -- 先初始化音频并播放第一次，提升响应速度
    alarm.initAudio()
    audio.tts(config.audio.multimedia_id, config.alarm.tts_message)

    -- 【启动语音播报循环定时器】
    -- 后续每 4 秒播报一次报警语音
    audioTimer = sys.timerLoopStart(function()
        -- 每次播放前检查音频是否已初始化
        -- initAudio() 内部有防重入逻辑
        alarm.initAudio()
        -- audio.tts() 播放 TTS 语音
        -- 参数：音频通道 ID，要播放的文本
        audio.tts(config.audio.multimedia_id, config.alarm.tts_message)
    end, config.alarm.tts_repeat_interval)  -- 4000ms 间隔

    -- 【发布报警开始事件】
    -- sys.publish(event_name) 发布系统事件
    -- 其他模块可以通过 sys.waitUntil("ALARM_STARTED") 等待这个事件
    -- 类似 Python 的 Event 或信号机制
    sys.publish("ALARM_STARTED")
end

--------------------------------------------------------------------------------
-- 停止报警
--
-- 【功能】
-- 1. 关闭所有 LED
-- 2. 停止 LED 闪烁定时器
-- 3. 停止语音播报定时器
-- 4. 发布 "ALARM_STOPPED" 事件
--
-- 【资源清理】
-- - 必须停止定时器，否则会继续执行造成资源泄漏
-- - 停止后将定时器 ID 设为 nil，避免重复停止
--
-- 【Python 类比】
-- def stop(self):
--     self._is_alarming = False
--     self._turn_off_all_leds()
--     if self._flash_timer:
--         self._flash_timer.cancel()
--         self._flash_timer = None
--------------------------------------------------------------------------------
function alarm.stop()
    log.info("alarm", "停止报警")
    isAlarming = false

    -- 关闭所有 LED
    turnOffAllLeds()

    -- 【停止 LED 闪烁定时器】
    -- sys.timerStop(timer_id) 停止指定定时器
    -- 需要先检查定时器是否存在（防止空指针）
    if flashTimer then
        sys.timerStop(flashTimer)
        flashTimer = nil  -- 清空引用，便于下次判断
    end

    -- 【停止语音播报定时器】
    if audioTimer then
        sys.timerStop(audioTimer)
        audioTimer = nil
    end

    -- 发布报警停止事件
    sys.publish("ALARM_STOPPED")
end

--------------------------------------------------------------------------------
-- 获取报警状态
-- @return boolean 是否正在报警
--
-- 【用途】
-- 其他模块可以查询当前是否在报警状态
-- 例如：决定是否进入休眠（报警时不能休眠）
--
-- 【Python 类比】
-- @property
-- def is_active(self) -> bool:
--     return self._is_alarming
--------------------------------------------------------------------------------
function alarm.isActive()
    return isAlarming
end

--------------------------------------------------------------------------------
-- 播放一次 TTS 语音
-- @param message string 要播放的文本（可选，默认使用配置中的报警语音）
--
-- 【用途】
-- - 单次语音播报，不循环
-- - 用于非报警场景的语音提示（如"设备启动"、"电量低"等）
--
-- 【Python 类比】
-- def play_tts(self, message: str = None):
--     self.init_audio()
--     audio.tts(message or DEFAULT_MESSAGE)
--------------------------------------------------------------------------------
function alarm.playTTS(message)
    alarm.initAudio()  -- 确保音频已初始化
    -- message or config.alarm.tts_message 类似 Python 的 message or default
    -- 如果 message 为 nil，则使用默认消息
    audio.tts(config.audio.multimedia_id, message or config.alarm.tts_message)
end

--------------------------------------------------------------------------------
-- 关闭音频电源
--
-- 【调用时机】
-- 进入休眠前调用，彻底关闭音频硬件以降低功耗
--
-- 【注意事项】
-- - 关闭后 isAudioInit 设为 false
-- - 下次使用音频需要重新初始化
--
-- 【Python 类比】
-- def shutdown_audio(self):
--     audio.power_off(self.AUDIO_ID)
--     self._audio_initialized = False
--------------------------------------------------------------------------------
function alarm.shutdownAudio()
    log.info("alarm", "关闭音频电源")
    -- audio.pm(id, mode) 设置音频电源模式
    -- audio.POWEROFF 表示完全断电
    audio.pm(config.audio.multimedia_id, audio.POWEROFF)
    isAudioInit = false  -- 标记为未初始化，下次需要重新初始化
end

--------------------------------------------------------------------------------
-- 返回模块
-- 其他文件通过 require("alarm") 获取这个表
--------------------------------------------------------------------------------
return alarm
