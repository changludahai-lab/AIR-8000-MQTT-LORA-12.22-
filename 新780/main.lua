-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sczthd_780ehv_bjq_lora"
VERSION = "001.000.000"
PRODUCT_KEY = "123" -- 到 iot.openluat.com 创建项目,获取正确的项目id
--[[
本demo需要mqtt库, 大部分能联网的设备都具有这个库
mqtt也是内置库, 无需require
]]
-- 正式版关闭调试信息
-- pm.power(pm.USB, false)
log.info("main", PROJECT, VERSION)
-- 关闭飞行模式

gpio.setup(1, nil) -- 初始功能设为纯MCU-IO
Q_GNIO = gpio.get(1)
log.info("功能IO：", Q_GNIO)
if Q_GNIO == 0 then
    mobile.flymode(0, false)
else
    mobile.flymode(0, true)
end
-- 添加硬狗防止程序卡死
wdt.init(9000)
sys.timerLoopStart(wdt.feed, 3000)
-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")
require "single_mqtt"
-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then pm.power(pm.PWK_MODE, false) end
if Q_GNIO == 0 then
    log.info("启用4G模式")
    libfota2 = require "libfota2"
    sys.taskInit(function()
        local device_id = mcu.unique_id():toHex()
        -----------------------------
        -- 统一联网函数, 可自行删减
        ----------------------------
        if wlan and wlan.connect then
            -- wifi 联网, ESP32系列均支持
            local ssid = "luatos1234"
            local password = "12341234"
            log.info("wifi", ssid, password)
            -- TODO 改成自动配网
            -- LED = gpio.setup(12, 0, gpio.PULLUP)
            wlan.init()
            wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
            device_id = wlan.getMac()
            wlan.connect(ssid, password, 1)
        elseif mobile then
            -- Air780E/Air600E系列
            -- mobile.simid(2) -- 自动切换SIM卡
            -- LED = gpio.setup(27, 0, gpio.PULLUP)
            device_id = mobile.imei() or "12345678"
            -- pm.power(pm.USB, false)

        elseif w5500 then
            -- w5500 以太网, 当前仅Air105支持
            w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
            w5500.config() -- 默认是DHCP模式
            w5500.bind(socket.ETH0)
            -- LED = gpio.setup(62, 0, gpio.PULLUP)
        elseif socket or mqtt then
            -- 适配的socket库也OK
            -- 没有其他操作, 单纯给个注释说明
        else
            -- 其他不认识的bsp, 循环提示一下吧
            while 1 do
                sys.wait(1000)
                log.info("bsp", "本bsp可能未适配网络层, 请查证")
            end
        end
        -- 默认都等到联网成功
        sys.waitUntil("IP_READY")
        sys.publish("net_ready", device_id)
        sys.publish("net_ok")
        sys.publish("IP_READY_2")
    end)
else
    log.info("启用SOC模式")
    uart.setup(1, -- 串口id
    9600, -- 波特率
    8, -- 数据位
    1 -- 停止位
    )
    uart.on(1, "receive", function(id, len) -- LORA接收
        local s = ""
        repeat
            s = uart.read(id, 128)
            if #s > 0 then -- #s 是取字符串的长度
                -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
                log.info("uart", "receive", id, #s, s)
                -- 对收到的进行处理
                data = s:gsub("^%s*(.-)%s*$", "%1")
                if string.find(data, "C") or string.find(data, "CCCC") then -- 收到了，需要报警
                    msgbj()
                elseif string.find(data, "A") or string.find(data, "AAAA") then -- 收到了，取消报多警
                    sys.publish("lora_sleep")
                elseif string.find(data, "B") or string.find(data, "BBBB") then -- 收到了，解除报警
                    sys.publish("lora_sleep")
                end
                -- log.info("uart", "receive", id, #s, s:toHex()) --如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
            end
        until s == ""
    end)
end

function mcuset() -- 默认设置调用
    gpio.close(gpio.WAKEUP1) -- 漏电流
    gpio.close(gpio.PWR_KEY) -- 漏电流系统
    gpio.setup(23, nil) -- 虚要关闭，防止浮空输入漏电流
end
local function fota_cb(ret)
    log.info("fota", ret)
    if ret == 0 then
        log.info("升级包下载成功,重启模块")
        rtos.reboot()
    elseif ret == 1 then
        log.info("连接失败",
                 "请检查url拼写或服务器配置(是否为内网)")
    elseif ret == 2 then
        log.info("url错误", "检查url拼写")
    elseif ret == 3 then
        log.info("服务器断开", "检查服务器白名单配置")
    elseif ret == 4 then
        log.error("FOTA 失败", "原因可能有：\n" ..
                      "1) 服务器返回 200/206 但报文体为空(0 字节）—— 通常是升级包文件缺失或 URL 指向空文件；\n" ..
                      "2) 服务器返回 4xx/5xx 等异常状态码 —— 请确认升级包已上传、URL 正确、鉴权信息有效；\n" ..
                      "3) 已经是最新版本，无需升级")
    elseif ret == 5 then
        log.info("缺少必要的PROJECT_KEY参数")
    else
        log.info("不是上面几种情况 ret为", ret)
    end
end
local ota_opts = {}
function fota_task_func()
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("fota_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用libnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当libnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY_2", 1000)
    end

    -- 检测到了IP_READY_2消息
    log.info("fota_task_func", "recv IP_READY", socket.dft())
    log.info("开始检查升级")
    libfota2.request(fota_cb, ota_opts)
end
if Q_GNIO == 0 then sys.taskInit(fota_task_func) end

sys.taskInit(function()
    if Q_GNIO == 0 then
        sys.waitUntil("net_ok")
        log.info("net_ok")
    end
    local PMA, PMB, PMC = pm.lastReson() -- 获取唤醒原因
    if PMA == 1 and PMB == 4 and PMC == 0 then
        open = 1 -- RTC唤醒
    elseif PMA == 2 and PMB == 4 and PMC == 0 then--雷达唤醒
        open = 2 -- IO唤醒
    elseif PMA == 6 and PMB == 4 and PMC == 0 then--串口RI唤醒
        open = 2 -- IO唤醒
    else
        open = 0 -- 电源上电
    end
    log.info("wakeup state", PMA, PMB, PMC)
    gpio.setup(28, 0)
    gpio.setup(35, 0)
    gpio.setup(38, 0)
    gpio.setup(37, 0)
    gpio.setup(36, 0)
    gpio.setup(34, 0)
    mcuset()
end)
function sleep()
    log.info("进入PSM功耗模式")
    -- 彻底关闭音频
    audio.pm(0, audio.POWEROFF)
    mobile.flymode(0, true)
    gpio.close(gpio.PWR_KEY) -- 这里pwrkey接地才需要，不接地通过按键控制的不需要
    if Q_GNIO == 0 then  -- 4g模式
        gpio.setup(gpio.WAKEUP0,
                   function() -- 配置 wakeup0 中断，外部唤醒用
            log.info("WAKEUP0")
        end, gpio.PULLDOWN, gpio.RISING)  -- psm唤醒引脚
        gpio.close(gpio.WAKEUP6)
    else
        gpio.close(gpio.WAKEUP0)
        gpio.setup(gpio.WAKEUP6,
                   function() -- 配置 wakeup6 中断，外部唤醒用
            log.info("WAKEUP6")
        end, gpio.PULLUP, gpio.BOTH)
        uart.close(1)
    end
    pm.dtimerStart(3, 6 * 60 * 60 * 1000) -- 60S唤醒一次
    -- 配置GPIO达到最低功耗
    gpio.setup(23, nil)
    gpio.close(33) -- 如果功耗偏高，开始尝试关闭WAKEUPPAD1
    gpio.close(20) -- 如果功耗偏高，开始尝试关闭AGPIOWU0
    gpio.close(35) -- 这里pwrkey接地才需要，不接地通过按键控制的不需要

    -- 关闭设备电源相关
    pm.power(pm.GPS, false) -- 关闭GPS电源(没有~)
    pm.power(pm.USB, false) -- 关闭USB电源
    -- 进入深度休眠模式
    pm.power(pm.WORK_MODE, 3)

    sys.wait(15000) -- 如果15s后模块重启，则说明进入极致功耗模式失败，
    log.info("进入极致功耗模式失败，尝试重启")
    rtos.reboot()
end
-- GPIO引脚
sys.taskInit(function()
        sys.waitUntil("lora_sleep")
        sys.wait(10000)--
        msgbjqx()
end)
sys.taskInit(function()
    while true do
        sys.wait(5000)
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
        log.info("WLAN", mobile.status())
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
