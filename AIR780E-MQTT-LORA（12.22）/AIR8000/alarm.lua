--[[
@module alarm
@summary 报警模块 - LED控制、TTS语音播报、报警状态管理
@version 1.0.0

================================================================================
模块概述
================================================================================

本模块负责室内机的本地报警功能：
1. 报警指示灯控制（高液位报警、电池低电量）
2. TTS 语音播报
3. 音频硬件管理

【与室外机报警模块的区别】
- 室外机(AIR780E)：5个闪烁LED + 大功率喇叭，用于户外警示
- 室内机(AIR8000)：固定LED指示 + TTS语音，用于室内提示

【硬件组成】
- ALARM_LED (GPIO17): 高液位报警指示灯
- BATTERY_LED (GPIO16): 室外机电池低电量指示灯
- ES8311 + PA: 音频播放系统

【Python 类比】
类似于一个报警控制器类：
```python
class AlarmController:
    def __init__(self):
        self.audio = AudioPlayer()
        self.led_alarm = LED(17)
        self.led_battery = LED(16)

    def start_high_level_alarm(self):
        self.led_alarm.on()
        self.audio.play_tts("高液位报警...")

    def stop_alarm(self):
        self.led_alarm.off()
        self.audio.stop()
```
]]

local alarm = {}
local config = require("config")

--------------------------------------------------------------------------------
-- 模块内部状态
--------------------------------------------------------------------------------
local isAudioInit = false       -- 音频是否已初始化
local isHighLevelAlarming = false   -- 是否正在高液位报警
local isBatteryAlarming = false     -- 是否正在电池低电量报警
local highLevelTTSTimer = nil       -- 高液位语音循环定时器
local batteryTTSTimer = nil         -- 电池低电量语音循环定时器

--------------------------------------------------------------------------------
-- 初始化音频硬件
-- @return boolean 是否初始化成功
--
-- 【硬件架构】
-- Air8000 ──I2C──> ES8311（配置）──> PA ──> 喇叭
--          │
--          └─I2S──> ES8311（音频数据）
--
-- 【防重入】
-- 使用 isAudioInit 标志避免重复初始化
--
-- 【Python 类比】
-- def init_audio(self) -> bool:
--     if self._audio_init:
--         return True
--     # 初始化硬件...
--     self._audio_init = True
--     return True
--------------------------------------------------------------------------------
function alarm.initAudio()
    if isAudioInit then
        return true
    end

    log.info("alarm", "初始化音频硬件")

    local cfg = config.audio
    local gpioCfg = config.gpio

    -- 【第1步】设置功放和电源引脚
    gpio.setup(gpioCfg.AUDIO_PA, 1, gpio.PULLUP)
    gpio.setup(gpioCfg.AUDIO_POWER, 1, gpio.PULLUP)

    -- 【第2步】初始化 I2C（用于配置 ES8311）
    i2c.setup(cfg.i2c_id, i2c.FAST)

    -- 【第3步】初始化 I2S（用于传输音频数据）
    -- 运行时设置格式常量（避免配置文件中引用未定义的常量）
    local channelFormat = i2s.MONO_R     -- 单声道右
    local commFormat = i2s.MODE_LSB      -- LSB 格式

    i2s.setup(
        cfg.i2s_id,
        cfg.i2s_mode,
        cfg.sample_rate,
        cfg.bits_per_sample,
        channelFormat,
        commFormat,
        cfg.channel_bits
    )

    -- 【第4步】配置音频通道
    -- 这些参数控制 PA 和 DAC 的开关时序
    audio.config(
        cfg.multimedia_id,
        gpioCfg.AUDIO_PA,
        cfg.pa_on_level,
        cfg.power_delay,
        cfg.pa_delay,
        gpioCfg.AUDIO_POWER,
        cfg.power_on_level,
        cfg.power_time_delay
    )

    -- 【第5步】设置音频总线
    audio.setBus(
        cfg.multimedia_id,
        audio.BUS_I2S,
        {
            chip = "es8311",
            i2cid = cfg.i2c_id,
            i2sid = cfg.i2s_id
        }
    )

    -- 【第6步】设置音量
    audio.vol(cfg.multimedia_id, cfg.voice_vol)
    audio.micVol(cfg.multimedia_id, cfg.mic_vol)

    isAudioInit = true
    log.info("alarm", "音频初始化完成")
    return true
end

--------------------------------------------------------------------------------
-- 播放 TTS 语音（单次）
-- @param message string 要播放的文本
--
-- 【用途】
-- 播放一次性的语音提示，不循环
--
-- 【Python 类比】
-- def play_tts(self, message: str):
--     self.init_audio()
--     self.audio.tts(message)
--------------------------------------------------------------------------------
function alarm.playTTS(message)
    alarm.initAudio()
    audio.tts(config.audio.multimedia_id, message)
end

--------------------------------------------------------------------------------
-- 开始高液位报警
--
-- 【功能】
-- 1. 点亮报警指示灯
-- 2. 立即播放一次报警语音
-- 3. 启动循环语音播报（每4秒一次）
--
-- 【防重入】
-- 如果已经在报警中，不重复触发
--------------------------------------------------------------------------------
function alarm.startHighLevelAlarm()
    if isHighLevelAlarming then
        log.info("alarm", "已在高液位报警中，忽略重复触发")
        return
    end

    log.info("alarm", "启动高液位报警")
    isHighLevelAlarming = true

    -- 点亮报警指示灯
    gpio.set(config.gpio.ALARM_LED, 1)

    -- 立即播放第一次语音
    alarm.initAudio()
    audio.tts(config.audio.multimedia_id, config.alarm.tts_high_level)

    -- 启动循环语音播报
    highLevelTTSTimer = sys.timerLoopStart(function()
        alarm.initAudio()
        audio.tts(config.audio.multimedia_id, config.alarm.tts_high_level)
    end, config.alarm.tts_repeat_interval)
end

--------------------------------------------------------------------------------
-- 停止高液位报警
--
-- 【功能】
-- 1. 熄灭报警指示灯
-- 2. 停止循环语音
--------------------------------------------------------------------------------
function alarm.stopHighLevelAlarm()
    log.info("alarm", "停止高液位报警")
    isHighLevelAlarming = false

    -- 熄灭报警灯
    gpio.set(config.gpio.ALARM_LED, 0)

    -- 停止语音定时器
    if highLevelTTSTimer then
        sys.timerStop(highLevelTTSTimer)
        highLevelTTSTimer = nil
    end
end

--------------------------------------------------------------------------------
-- 开始电池低电量报警
--
-- 【触发条件】
-- 室外机上报电池电压低于阈值
--
-- 【功能】
-- 1. 点亮电池低电量指示灯
-- 2. 启动循环语音提示
--------------------------------------------------------------------------------
function alarm.startBatteryAlarm()
    if isBatteryAlarming then
        log.info("alarm", "已在电池报警中，忽略重复触发")
        return
    end

    log.info("alarm", "启动电池低电量报警")
    isBatteryAlarming = true

    -- 点亮电池指示灯
    gpio.set(config.gpio.BATTERY_LED, 1)

    -- 启动循环语音
    batteryTTSTimer = sys.timerLoopStart(function()
        alarm.initAudio()
        audio.tts(config.audio.multimedia_id, config.alarm.tts_battery_low)
    end, config.alarm.tts_repeat_interval)
end

--------------------------------------------------------------------------------
-- 停止电池低电量报警
--------------------------------------------------------------------------------
function alarm.stopBatteryAlarm()
    log.info("alarm", "停止电池低电量报警")
    isBatteryAlarming = false

    -- 熄灭电池指示灯
    gpio.set(config.gpio.BATTERY_LED, 0)

    -- 停止语音定时器
    if batteryTTSTimer then
        sys.timerStop(batteryTTSTimer)
        batteryTTSTimer = nil
    end
end

--------------------------------------------------------------------------------
-- 播放解除报警提示音
--------------------------------------------------------------------------------
function alarm.playAlarmCleared()
    alarm.initAudio()
    audio.tts(config.audio.multimedia_id, config.alarm.tts_alarm_cleared)
end

--------------------------------------------------------------------------------
-- 获取高液位报警状态
-- @return boolean 是否正在高液位报警
--------------------------------------------------------------------------------
function alarm.isHighLevelActive()
    return isHighLevelAlarming
end

--------------------------------------------------------------------------------
-- 获取电池报警状态
-- @return boolean 是否正在电池报警
--------------------------------------------------------------------------------
function alarm.isBatteryActive()
    return isBatteryAlarming
end

--------------------------------------------------------------------------------
-- 初始化 GPIO（LED 引脚）
-- 在启动时调用，确保 LED 默认关闭
--------------------------------------------------------------------------------
function alarm.initGPIO()
    gpio.setup(config.gpio.ALARM_LED, 0)     -- 报警灯默认关
    gpio.setup(config.gpio.BATTERY_LED, 0)   -- 电池灯默认关
    gpio.setup(config.gpio.SYS_LED, 1)       -- 系统灯默认亮
    gpio.setup(config.gpio.NET_LED, 0)       -- 网络灯默认关

    log.info("alarm", "GPIO初始化完成")
end

--------------------------------------------------------------------------------
-- 设置网络指示灯状态
-- @param state number 0=关闭, 1=点亮
--------------------------------------------------------------------------------
function alarm.setNetLed(state)
    gpio.set(config.gpio.NET_LED, state)
end

--------------------------------------------------------------------------------
-- 返回模块
--------------------------------------------------------------------------------
return alarm
