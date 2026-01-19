-- 自动低功耗, 轻休眠模式
-- Air780E支持uart唤醒和网络数据下发唤醒, 但需要断开USB,或者pm.power(pm.USB, false) 但这样也看不到日志了
-- pm.request(pm.LIGHT)
exaudio = require("exaudio")
-- 根据自己的服务器修改以下参数
-- local mqtt_host = "iot.gzfit.com.cn"
-- local mqtt_port = 1883
-- local mqtt_isssl = false
-- local client_id = mobile.imei()
-- local user_name = "user"
-- local password = "password"
local QJ_AUDIOINIT = false



local mqtt_host = "47.104.166.179"
local mqtt_port = 1883
local mqtt_isssl = false
local client_id = mobile.imei()
local user_name = "mqtt_user"
local password = "mqtt_password"



local pub_topic = "/780EHV/PUB/" .. mobile.imei()
local sub_topic = "/780EHV/SUB/" .. mobile.imei()

local mqttc = nil

-- 统一联网函数
log.info("text")
if Q_GNIO == 0 then
    sys.taskInit(function()
        -- 等待联网
        local ret, device_id = sys.waitUntil("net_ready")
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
                log.info("=============== mqtt收到消息如下： =====================")
                log.info("mqtt", "downlink", "topic", data, "payload", payload)

                local subdata = json.decode(payload)
                if subdata ~= nil then
                    if subdata.bj == 0 then
                        msgbjqx()
                    elseif subdata.bj == 1 then
                        msgbj()
                    end
                end
            elseif event == "sent" then
                -- log.info("mqtt", "sent", "pkgid", data)
                -- elseif event == "disconnect" then
                -- 非自动重连时,按需重启mqttc
                -- mqtt_client:connect()
            end
        end)

        log.info("=============== mqtt回调函数绑定完成！ =====================")
        sys.wait(1000)


        -- mqttc自动处理重连, 除非自行关闭
        mqttc:connect()
        -- sys.waitUntil("mqtt_conack")
        sys.publish("mqttok")
        while true do
            -- 演示等待其他task发送过来的上报信息
            local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 300000)
            if ret then
                -- 提供关闭本while循环的途径, 不需要可以注释掉
                if topic == "close" then break end
                mqttc:publish(topic, data, qos)
            end
            -- 如果没有其他task上报, 可以写个空等待
            sys.wait(1000)
            log.info("=============== mqtt一直在等待接收消息！ =====================")
        end

        log.info("=============== mqtt已经关闭无法接受消息！ =====================")
        mqttc:close()
        mqttc = nil
    end)
end
local flashTimer = nil -- 闪烁定时器
local audioTimer = nil -- 闪烁定时器
function msgbjqx()
    log.info("关闭报警")
    gpio.set(28, 0)
    gpio.set(34, 0)
    gpio.set(35, 0)
    gpio.set(36, 0)
    gpio.set(37, 0)
    gpio.set(38, 0)
    sys.timerStop(flashTimer)
    flashTimer = nil
    sys.timerStop(audioTimer)
    audioTimer = nil
    sleep()
end
function msgbj()
    log.info("启动报警")
    sys.publish("bjts")
    gpio.set(28, 1)
    local ledState = 0
    flashTimer = sys.timerLoopStart(function()
        ledState = 1 - ledState -- 切换状态 (0<->1)
        if ledState == 1 then
            gpio.set(34, 1)
            gpio.set(35, 1)
            gpio.set(36, 1)
            gpio.set(37, 1)
            gpio.set(38, 1)
        else
            gpio.set(34, 0)
            gpio.set(35, 0)
            gpio.set(36, 0)
            gpio.set(37, 0)
            gpio.set(38, 0)
        end
    end, 300)
    audioTimer = sys.timerLoopStart(function()
        if QJ_AUDIOINIT == false then
            ttsinit()
            audio.tts(0, "高液位报警，请立即停止卸油！")
        else
            audio.tts(0, "高液位报警，请立即停止卸油！")
        end

    end, 4000)
end
function ttsinit()
    -- 测试音频
    local i2c_id = 0 -- i2c_id 0
    local pa_pin = 22 -- 喇叭pa功放脚
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

    local voice_vol = 90 -- 喇叭音量
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
sys.taskInit(function()
    if Q_GNIO == 0 then
    sys.waitUntil("mqttok")
    end
    log.info("开机上电、定时唤醒，上报后休眠")
    sys.wait(1000)
    gpio.close(gpio.WAKEUP1) -- 漏电流
    gpio.close(gpio.PWR_KEY) -- 漏电流系统
    pm.power(pm.USB, false)
    pm.power(pm.WORK_MODE, 2) ---切换低功耗
    gpio.setup(23, nil) -- 虚要关闭，防止浮空输入漏电流
    local ldio = gpio.get(gpio.WAKEUP0)
    log.info("ldio:", ldio)
    if open == 1 or open == 0 or ldio == 0 then
        adc.open(adc.CH_VBAT)
        local vbat = adc.get(adc.CH_VBAT)
        adc.close(adc.CH_VBAT)
        local vbatup = {
            imei = mobile.imei(),
            vbat = vbat,
            iccid = mobile.iccid()
        }
        log.info('==========================开机上报IMEI、电量、ICCID====================', json.encode(vbatup))
        if Q_GNIO == 0 then
            mqttc:publish(pub_topic, json.encode(vbatup), 2)
            sys.wait(1000)
            -- mqttc:close()
            -- mqttc = nil
        else
            if vbat < 3300 then
                uart.write(1, "DDDD") -- 电池电量低
                sys.wait(1000)
                uart.write(1, "DDDD") -- 电池电量低
                log.info("LORA:电量低发出")
            else
                uart.write(1, "EEEE") -- 电池电量足
                sys.wait(1000)
                uart.write(1, "EEEE") -- 电池电量足
                log.info("LORA:电量低解除")
            end
        end

        log.info("===========休眠之前先检查雷达状态===============")

        gpio.setup(gpio.WAKEUP0, nil) 
        local radar_level = gpio.get(gpio.WAKEUP0)

        local wait_count = 0
        while radar_level == 1 and wait_count < 5 do
            log.info("==========雷达处于高电平，等待其归零===========", wait_count)
            sys.wait(1000)
            radar_level = gpio.get(gpio.WAKEUP0)
            wait_count = wait_count + 1
        end

        log.info("===========雷达已稳定在低电平，进休眠=========进入休眠前查看open值:", open)
        sys.wait(5000)

        if open == 2 then

            log.info("===========雷达唤醒后马上要错误的进入PSM了，此时不应该进入，坚持30分钟！=====:", open)
            gpio.close(gpio.WAKEUP1) -- 漏电流
            gpio.close(gpio.PWR_KEY) -- 漏电流系统
            pm.power(pm.USB, false)
            pm.power(pm.WORK_MODE, 2) ---切换低功耗
            gpio.setup(23, nil) -- 虚要关闭，防止浮空输入漏电流
            sys.wait(30 * 60 * 1000) -- 30分钟后PSM

        end

        sleep()
    elseif open == 2 then
        gpio.close(gpio.WAKEUP1) -- 漏电流
        gpio.close(gpio.PWR_KEY) -- 漏电流系统
        pm.power(pm.USB, false)
        pm.power(pm.WORK_MODE, 2) ---切换低功耗
        gpio.setup(23, nil) -- 虚要关闭，防止浮空输入漏电流
        log.info("==================雷达唤醒，30Min后休眠==================")
        sys.wait(30 * 60 * 1000) -- 30分钟后PSM
        sleep()
    end
end)

