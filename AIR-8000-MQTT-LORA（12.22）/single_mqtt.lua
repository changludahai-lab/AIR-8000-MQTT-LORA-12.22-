-- 自动低功耗, 轻休眠模式
-- Air780E支持uart唤醒和网络数据下发唤醒, 但需要断开USB,或者pm.power(pm.USB, false) 但这样也看不到日志了
-- pm.request(pm.LIGHT)
exaudio = require("exaudio")
-- -- 根据自己的服务器修改以下参数
-- local mqtt_host = "iot.gzfit.com.cn"
-- local mqtt_port = 1883
-- local mqtt_isssl = false
-- local client_id = mobile.imei()
-- local user_name = "user"
-- local password = "password"



local mqtt_host = "47.104.166.179"
local mqtt_port = 1883
local mqtt_isssl = false
local client_id = mobile.imei()
local user_name = "mqtt_user"
local password = "mqtt_password"



local pub_topic = "/AIR8000/PUB/" .. mobile.imei()
local sub_topic = "/AIR8000/SUB/" .. mobile.imei()

local mqttc = nil
local Mqttzt = false
local KEY_state = false
-- 统一联网函数
log.info("text")

function ttsinit()
    local i2c_id = 0 -- i2c_id 0
    local pa_pin = 21 -- 喇叭pa功放脚
    local power_pin = 20 -- es8311电源脚

    local i2s_id = 0 -- i2s_id 0
    local i2s_mode = 0 -- i2s模式 0 主机 1 从机
    local i2s_sample_rate = 16000 -- 采样率
    local i2s_bits_per_sample = 16 -- 数据位数
    local i2s_channel_format = i2s.MONO_R -- 声道, 0 左声道, 1 右声道, 2 立体声
    local i2s_communication_format = i2s.MODE_LSB -- 格式, 可选MODE_I2S, MODE_LSB, MODE_MSB
    local i2s_channel_bits = 16 -- 声道的BCLK数量
    local multimedia_id = 0 -- 音频通道 0
    local pa_on_level = 1 -- PA打开电平 1 高电平 0 低电平
    local power_delay = 3 -- 在DAC启动前插入的冗余时间，单位100ms
    local pa_delay = 100 -- 在DAC启动后，延迟多长时间打开PA，单位1ms
    local power_on_level = 1 -- 电源控制IO的电平，默认拉高
    local power_time_delay = 100 -- 音频播放完毕时，PA与DAC关闭的时间间隔，单位1ms
    local voice_vol = 75 -- 喇叭音量
    local mic_vol = 80 -- 麦克风音量

    gpio.setup(pa_pin, 1, gpio.PULLUP) -- 设置功放PA脚
    gpio.setup(power_pin, 1, gpio.PULLUP) -- 设置ES83111电源脚

    i2c.setup(i2c_id, i2c.FAST)
    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample,
              i2s_channel_format, i2s_communication_format, i2s_channel_bits)

    audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay,
                 power_pin, power_on_level, power_time_delay)
    audio.setBus(multimedia_id, audio.BUS_I2S,
                 {chip = "es8311", i2cid = i2c_id, i2sid = i2s_id}) -- 通道0的硬件输出通道设置为I2S

    audio.vol(multimedia_id, voice_vol)
    audio.micVol(multimedia_id, mic_vol)
    QJ_AUDIOINIT = true
    log.info("AUDIO初始化完成.")
end
function key_func()
    log.info("按键消除")
    KEY_state = true
end
gpio.setup(34, key_func, gpio.PULLDOWN, gpio.RISING)
sys.taskInit(function()
    -- 等待联网
    ttsinit()
    if Q_GNIO == 0 then
        local ret, device_id = sys.waitUntil("IP_READY")
        -- 下面的是mqtt的参数均可自行修改

        -- 打印一下上报(pub)和下发(sub)的topic名称
        -- 上报: 设备 ---> 服务器
        -- 下发: 设备 <--- 服务器
        -- 可使用mqtt.x等客户端进行调试
        log.info("mqtt", "pub", pub_topic)
        log.info("mqtt", "sub", sub_topic)
        -- 打印一下支持的加密套件, 通常来说, 固件已包含常见的99%的加密套件
        -- if crypto.cipher_suites then
        --     log.info("cipher", "suites", json.encode(crypto.cipher_suites()))
        -- end
        if mqtt == nil then
            while 1 do
                sys.wait(1000)
                log.info("bsp", "本bsp未适配mqtt库, 请查证")
            end
        end

        -------------------------------------
        -------- MQTT 演示代码 --------------
        -------------------------------------

        -- mqttc = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_isssl)

        -- mqttc:auth(client_id, user_name, password) -- client_id必填,其余选填
        -- mqttc:keepalive(240) -- 默认值240s
        -- mqttc:autoreconn(true, 3000) -- 自动重连机制

        log.info("MQTT ================= 开始建立连接！", "Connecting to", mqtt_host)
        mqttc = mqtt.create(nil, mqtt_host, mqtt_port)
        mqttc:auth(client_id, "mqtt_user", "mqtt_password")
        mqttc:keepalive(240)
        mqttc:autoreconn(true)


        mqttc:on(function(mqtt_client, event, data, payload)
            -- 用户自定义代码
            log.info("mqtt", "event", event, mqtt_client, data, payload)
            if event == "conack" then
                -- 联上了

                log.info("=============== mqtt连接成功！ =====================")

                sys.publish("mqtt_conack")
                mqtt_client:subscribe(sub_topic) -- 单主题订阅
                -- mqtt_client:subscribe({[topic1]=1,[topic2]=1,[topic3]=1})--多主题订阅
            elseif event == "recv" then
                log.info("mqtt", "downlink", "topic", data, "payload", payload)
                local subdata = json.decode(payload)
                if subdata ~= nil or subdata.vbat ~= nil then
                    if subdata.vbat < 3300 then
                        vbatbj()
                    else
                        qxvbatbj()
                    end
                end
            elseif event == "sent" then
                -- log.info("mqtt", "sent", "pkgid", data)
                -- elseif event == "disconnect" then
                -- 非自动重连时,按需重启mqttc
                -- mqtt_client:connect()
            end
        end)

        -- mqttc自动处理重连, 除非自行关闭
        mqttc:connect()
        sys.waitUntil("mqtt_conack")
        sys.publish("MQTT_READYOK")
        Mqttzt = true
        while true do
            -- 演示等待其他task发送过来的上报信息
            local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 300000)
            if ret then
                -- 提供关闭本while循环的途径, 不需要可以注释掉
                if topic == "close" then break end
                mqttc:publish(topic, data, qos)
            end
            -- 如果没有其他task上报, 可以写个空等待
            -- sys.wait(1000)
        end
        mqttc:close()
        mqttc = nil
    else
        Mqttzt = true
    end

end)
local ywalarmTimer = nil -- 闪烁定时器
local audioTimer = nil -- 闪烁定时器
local scbjzt = false
local dqbjzt = false
local alarm_pin = 17
local ttsywzt = false
local ttsbatzt = false
function qxvbatbj()
    log.info("关闭电池报警")
    gpio.set(battery_pin, 0)
    if ttsbatzt == true then
        ttsbatzt = false
        sys.timerStop(audioTimer)
        audioTimer = nil
    end
end
function vbatbj()
    log.info("开启电池报警")
    gpio.set(battery_pin, 1)
    if ttsbatzt == false then
        ttsbatzt = true
        audioTimer = sys.timerLoopStart(function()
            audio.tts(0, "灯光报警电量低，请更换")
        end, 4000)
    end
end
function qxYWSB()
    -- log.info("关闭高液位报警")
    gpio.set(alarm_pin, 0)
end
function YWSB()
    -- log.info("高液位报警")
    gpio.set(alarm_pin, 1)
    audio.tts(0, "高液位报警，请立即停止卸油！")
    sys.wait(4000)
end
sys.taskInit(function()
    while true do
        if Q_IOBJ == true or Q_TXBJ == true then
            dqbjzt = true
            YWSB()
        else
            qxYWSB()
            dqbjzt = false
        end
        if scbjzt == false and dqbjzt == true and Mqttzt == true then
            local bjup = {bj = 1}
            log.info(json.encode(vbatup))
            if Q_GNIO == 0 then
                sys.publish("mqtt_pub", pub_topic, json.encode(bjup), 2)
                log.info("MQTT上报液位报警")
            else
                uart.write(11, "CCCC") -- 液位报警
                sys.wait(2000)
                uart.write(11, "CCCC") -- 液位报警
                log.info("LORA上报液位报警")
            end
            scbjzt = true
        elseif scbjzt == true and dqbjzt == false and Mqttzt == true then
            local bjup = {bj = 0}
            log.info(json.encode(vbatup))
            if Q_GNIO == 0 then
                sys.publish("mqtt_pub", pub_topic, json.encode(bjup), 2)
                log.info("MQTT上报液位报警取消")
            else
                uart.write(11, "BBBB") -- 液位报警取消
                sys.wait(2000)
                uart.write(11, "BBBB") -- 液位报警取消
                log.info("LORA上报液位报警取消")
            end
            scbjzt = false
        end
        sys.wait(1000)
        log.info("比较值", scbjzt, dqbjzt, Mqttzt)
        if KEY_state == true then
            qxYWSB()
            audio.tts(0, "报警已解除！")
            dqbjzt = false
            local bjup = {bj = 0}
            log.info(json.encode(vbatup))
            if Q_GNIO == 0 then
                log.info("MQTT上报液位报警报警解除")
                sys.publish("mqtt_pub", pub_topic, json.encode(bjup), 2)
            else
                uart.write(11, "AAAA") -- 液位报警解除
                sys.wait(2000)
                uart.write(11, "AAAA") -- 液位报警解除
                log.info("LORA上报液位报警报警解除")
            end
            scbjzt = false
            sys.wait(10 * 60 * 1000)
            KEY_state = false
        end
    end
end)

