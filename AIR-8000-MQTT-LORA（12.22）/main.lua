-- Luatools需要PROJECT和VERSION这两个信息
PROJECT = "alarmer_8000_lora"
VERSION = "1.0.0"
-- 产品Key, 请根据实际产品修改
PRODUCT_KEY = "GYV9vpPCVN1uraiaPVXfvfTNXKInE58K"
-- 打印版本信息
log.info("main", PROJECT, VERSION)
local reason, slp_state = pm.lastReson() -- 获取唤醒原因
log.info("wakeup state", pm.lastReson())
-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
require "single_mqtt"
gpio.setup(3, nil) -- 初始功能设为纯MCU-IO
Q_GNIO = gpio.get(3)
log.info("功能IO：", Q_GNIO)
if Q_GNIO == 0 then
    libfota2 = require "libfota2"
    mobile.flymode(0, false)
else
    mobile.flymode(0, true)
end
local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_GP then
        -- 在位置1和2设置自定义的DNS服务器ip地址：
        -- "223.5.5.5"，这个DNS服务器IP地址是阿里云提供的DNS服务器IP地址；
        -- "114.114.114.114"，这个DNS服务器IP地址是国内通用的DNS服务器IP地址；
        -- 可以加上以下两行代码，在自动获取的DNS服务器工作不稳定的情况下，这两个新增的DNS服务器会使DNS服务更加稳定可靠；
        -- 如果使用专网卡，不要使用这两行代码；
        -- 如果使用国外的网络，不要使用这两行代码；
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        log.info("netdrv_4g.ip_ready_func", "IP_READY",
                 socket.localIP(socket.LWIP_GP))
        gpio.set(1, 1)
    end
end
local function ip_lose_func(adapter)
    if adapter == socket.LWIP_GP then
        log.warn("netdrv_4g.ip_lose_func", "IP_LOSE")
        gpio.set(1, 0)
    end
end

-- 此处订阅"IP_READY"和"IP_LOSE"两种消息
-- 在消息的处理函数中，仅仅打印了一些信息，便于实时观察4G网络的连接状态
-- 也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
if Q_GNIO == 0 then
    sys.subscribe("IP_READY", ip_ready_func)
    sys.subscribe("IP_LOSE", ip_lose_func)
end

if wdt then
    -- 添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(15000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 2000) -- 3s喂一次狗
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
Q_IOBJ = false
Q_TXBJ = false
sys_pin = 20
net_pin = 1
alarm_pin = 17
battery_pin = 16
levelStatePin = 2 -- IO2
gpio.setup(sys_pin, 1)
gpio.setup(net_pin, 0)
gpio.setup(alarm_pin, 0)
gpio.setup(levelStatePin, nil)
gpio.setup(battery_pin,0)
-- 网络连接成功，亮灯
sys.taskInit(function()
    gpio.set(20, 1)
    sys.waitUntil("IP_READY")
    gpio.set(1, 1)
end)
local uartid = 1 -- 根据实际设备选取不同的uartid
local uartid2 = 11 -- 根据实际设备选取不同的uartid
-- 初始化串口参数
uart.setup(uartid, -- 串口id
9600, -- 波特率
8, -- 数据位
1 -- 停止位
)
uart.setup(uartid2, -- 串口id--LORA的串口
9600, -- 波特率
8, -- 数据位
1 -- 停止位
)
-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid, "receive", function(id, len)
    local s = ""
    repeat
        s = uart.read(id, 128)
        if #s > 0 then -- #s 是取字符串的长度
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            log.info("uart", "receive", id, #s, s)
            weidelu_rx(s)
            -- log.info("uart", "receive", id, #s, s:toHex()) --如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
        end
    until s == ""
end)
-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid2, "receive", function(id, len) -- LORA接收
    local s = ""
    repeat
        s = uart.read(id, 128)
        if #s > 0 then -- #s 是取字符串的长度
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            log.info("uart", "receive", id, #s, s)
            -- 对收到的进行处理
            data = s:gsub("^%s*(.-)%s*$", "%1")
            if string.find(data, "D") or string.find(data, "DDDD") then -- 收到了，电池低的信息。
                vbatbj()
            elseif string.find(data, "E") or string.find(data, "EEEE") then -- 收到了，电量充足
                qxvbatbj()
            end
            -- log.info("uart", "receive", id, #s, s:toHex()) --如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
        end
    until s == ""
end)
function weidelu_rx(buf)
    -- 回复 [01]i205TTYYMMDDHHmmTTnnNN...TTnnNN....&&CCCC， TT罐号，nn报警罐号，NN报警类型

    if buf[1] ~= 0x01 or buf:sub(2, 5) ~= "i205" then
        log.error("level", "液位计数据格式错误")
        return nil
    end
    local tank_num = buf[6]
    buf:sub(11)
    for i = 1, tank_count, 1 do
        local status = buf:byte(59 * i + 3)
        if status == 0x0A then
            Q_TXBJ = true
            log.warn("level", "液位计罐体" .. i .. "高液位报警")
        end
    end

end
function weidelu_tx()
    -- 写入可见字符串-- 维德路特发送读取指令 [01]i20500
    uart.write(uartid, "\x01i20500")
    -- 写入十六进制字符串
    -- uart.write(uartid, string.char(0x55,0xAA,0x4B,0x03,0x86))
end
function aoke_tx()
    -- 发送 010401010000a036
    uart.write("\x01\x04\x01\x01\x00\x00\xa0\x36") -- 发送读取指令
end

function aoke_rx(buf)
    -- 回复 0104 05罐数 07e9年 0703月日 102520时分秒 016400.. 025f00.. 035c00... 040000... 056200... 每段59字节
    if buf[1] ~= 0x01 or buf[2] ~= 0x04 then
        log.error("level", "液位计数据格式错误")
        return nil
    end
    local tank_count = buf[3]
    buf:sub(11)
    for i = 1, tank_count, 1 do
        local status = buf:byte(59 * i + 3)
        if status == 0x0A then
            Q_TXBJ = true
            log.warn("level", "液位计罐体" .. i .. "高液位报警")
        end
    end
end
sys.taskInit(function()
    while true do
        local ywalarm = gpio.get(levelStatePin)
        -- log.info("IO2:",  ywalarm)
        if ywalarm == 1 then
            Q_IOBJ = true
        else
            Q_IOBJ = false
        end
        weidelu_tx()
        sys.wait(2000)
    end
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
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
