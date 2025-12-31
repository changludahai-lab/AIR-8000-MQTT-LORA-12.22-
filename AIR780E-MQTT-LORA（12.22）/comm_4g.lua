--[[
@module comm_4g
@summary 4G通讯模块 - MQTT连接、消息收发、FOTA升级
@version 1.0.0

================================================================================
模块概述
================================================================================

本模块负责 4G 网络通讯，是 4G 模式下的核心通讯模块。

【主要功能】
1. MQTT 客户端连接和消息收发
2. 网络状态监控
3. FOTA（Firmware Over-The-Air）远程固件升级

【MQTT 协议简介】
MQTT 是物联网常用的轻量级消息协议：
- 发布/订阅模式（类似 Redis 的 Pub/Sub）
- 支持 QoS（服务质量）等级
- 适合弱网环境

【Topic 设计】
- 发布 Topic：/780EHV/PUB/{IMEI} - 设备向服务器发送数据
- 订阅 Topic：/780EHV/SUB/{IMEI} - 设备接收服务器指令
- IMEI 是设备的唯一标识符

【Python 类比】
这个模块类似于 Python 中使用 paho-mqtt 库：
```python
import paho.mqtt.client as mqtt
client = mqtt.Client()
client.on_message = on_message
client.connect("broker.example.com", 1883)
client.subscribe("/780EHV/SUB/12345678")
client.loop_forever()
```

【LuaOS 协程/任务模型】
- sys.taskInit(fn) 创建一个协程任务
- sys.wait(ms) 让当前任务休眠，让出 CPU
- sys.waitUntil(event) 等待某个事件
- sys.publish(event, data) 发布事件
- 类似 Python 的 asyncio，但语法更简单
]]

local comm_4g = {}
local config = require("config")

--------------------------------------------------------------------------------
-- 模块内部状态（私有变量）
--------------------------------------------------------------------------------
local mqttClient = nil       -- MQTT 客户端对象
local pubTopic = nil         -- 发布消息用的 Topic
local subTopic = nil         -- 订阅消息用的 Topic
local isConnected = false    -- MQTT 是否已连接
local messageHandler = nil   -- 外部传入的消息处理回调函数

--------------------------------------------------------------------------------
-- 初始化 MQTT 连接
-- @param onMessageCallback function 收到消息时的回调函数
--
-- 【调用时机】
-- 在 main.lua 中检测到是 4G 模式时调用
--
-- 【工作流程】
-- 1. 获取设备 IMEI 作为唯一标识
-- 2. 构建发布/订阅 Topic
-- 3. 启动三个异步任务：网络监控、MQTT、FOTA
--
-- 【Python 类比】
-- def init(self, on_message_callback):
--     self.message_handler = on_message_callback
--     imei = get_imei()
--     self.pub_topic = f"/780EHV/PUB/{imei}"
--     self.sub_topic = f"/780EHV/SUB/{imei}"
--     # 启动异步任务
--     asyncio.create_task(self.network_task())
--     asyncio.create_task(self.mqtt_task())
--     asyncio.create_task(self.fota_task())
--------------------------------------------------------------------------------
function comm_4g.init(onMessageCallback)
    -- 保存消息处理回调
    -- 这个回调会在收到 MQTT 消息时被调用
    messageHandler = onMessageCallback

    -- 【构建 Topic】
    -- mobile.imei() 获取设备的 IMEI 号
    -- IMEI = International Mobile Equipment Identity，国际移动设备识别码
    -- 每个 4G 模块都有唯一的 IMEI，类似 MAC 地址
    local imei = mobile.imei() or "unknown"
    pubTopic = config.mqtt.pub_topic_prefix .. imei  -- 字符串拼接用 ..
    subTopic = config.mqtt.sub_topic_prefix .. imei

    log.info("comm_4g", "初始化", "IMEI=" .. imei)
    log.info("comm_4g", "pub_topic=" .. pubTopic)
    log.info("comm_4g", "sub_topic=" .. subTopic)

    -- 【启动异步任务】
    -- sys.taskInit(fn) 创建一个新的协程任务
    -- 这些任务会并发执行，互不阻塞
    -- 类似 Python: asyncio.create_task(fn())
    sys.taskInit(comm_4g.networkTask)  -- 网络监控任务
    sys.taskInit(comm_4g.mqttTask)     -- MQTT 连接任务
    sys.taskInit(comm_4g.fotaTask)     -- FOTA 升级任务
end

--------------------------------------------------------------------------------
-- 网络连接任务
--
-- 【功能】
-- 监控 4G 网络连接状态，等待网络就绪后通知其他任务
--
-- 【4G 联网流程】
-- 1. SIM 卡检测
-- 2. 搜索基站
-- 3. 网络注册
-- 4. 获取 IP 地址（IP_READY 事件）
--
-- 【Python 类比】
-- async def network_task(self):
--     # 等待网络就绪
--     await wait_for_event("IP_READY")
--     # 通知其他任务
--     publish_event("net_ready", device_id)
--------------------------------------------------------------------------------
function comm_4g.networkTask()
    log.info("comm_4g", "等待网络连接...")

    local device_id = mobile.imei() or "12345678"

    -- 【等待网络就绪】
    -- sys.waitUntil(event) 阻塞当前任务，直到收到指定事件
    -- "IP_READY" 是 LuaOS 内置事件，表示已获得 IP 地址
    -- 类似 Python: await event.wait()
    sys.waitUntil("IP_READY")

    log.info("comm_4g", "网络已就绪")

    -- 【发布事件通知其他任务】
    -- sys.publish(event, data) 发布事件
    -- 所有在 waitUntil 等待这个事件的任务都会被唤醒
    sys.publish("net_ready", device_id)
    sys.publish("net_ok")
end

--------------------------------------------------------------------------------
-- MQTT 连接任务
--
-- 【功能】
-- 1. 等待网络就绪
-- 2. 创建 MQTT 客户端并连接服务器
-- 3. 订阅消息 Topic
-- 4. 处理消息发送请求
--
-- 【MQTT 连接流程】
-- 1. 创建客户端对象
-- 2. 设置认证信息（用户名/密码）
-- 3. 设置回调函数（处理连接、消息、断开事件）
-- 4. 调用 connect() 连接服务器
-- 5. 进入消息循环
--
-- 【Python 类比】
-- async def mqtt_task(self):
--     await wait_for_event("net_ready")
--     client = mqtt.Client()
--     client.username_pw_set(username, password)
--     client.on_connect = self.on_connect
--     client.on_message = self.on_message
--     client.connect(host, port)
--     client.loop_forever()
--------------------------------------------------------------------------------
function comm_4g.mqttTask()
    -- 等待网络就绪
    sys.waitUntil("net_ready")
    log.info("comm_4g", "开始建立MQTT连接", config.mqtt.host)

    -- 【检查 mqtt 库是否存在】
    -- 不同固件版本可能不包含 mqtt 库
    -- mqtt 是全局变量，如果不存在则为 nil
    if mqtt == nil then
        while true do
            sys.wait(1000)
            log.error("comm_4g", "本BSP未适配mqtt库")
        end
    end

    -- 【创建 MQTT 客户端】
    -- mqtt.create(adapter, host, port) 创建客户端对象
    -- adapter=nil 表示使用默认网络适配器
    mqttClient = mqtt.create(nil, config.mqtt.host, config.mqtt.port)

    -- 【设置认证信息】
    -- auth(client_id, username, password)
    -- 使用 IMEI 作为 client_id，确保每个设备有唯一标识
    mqttClient:auth(mobile.imei(), config.mqtt.user_name, config.mqtt.password)

    -- 【设置心跳间隔】
    -- keepalive(seconds) 设置 PING 包间隔
    -- 如果超过 1.5 倍心跳时间没有通讯，服务器会断开连接
    mqttClient:keepalive(config.mqtt.keepalive)

    -- 【启用自动重连】
    -- autoreconn(true) 连接断开后自动重连
    -- 这对于户外设备很重要，网络可能不稳定
    mqttClient:autoreconn(true)

    -- 【设置 MQTT 事件回调】
    -- on(callback) 设置统一的事件处理函数
    -- 回调参数：client=客户端对象, event=事件类型, data=数据, payload=消息内容
    --
    -- 事件类型：
    -- - "conack": 连接成功确认
    -- - "recv": 收到消息
    -- - "disconnect": 连接断开
    mqttClient:on(function(client, event, data, payload)
        log.info("comm_4g", "MQTT事件", event, data)

        if event == "conack" then
            -- ========== 连接成功 ==========
            isConnected = true
            log.info("comm_4g", "MQTT连接成功")

            -- 订阅消息 Topic
            -- subscribe(topic) 订阅指定主题
            -- 之后服务器发送到这个 Topic 的消息都会被接收
            client:subscribe(subTopic)

            -- 发布连接成功事件，通知其他模块
            sys.publish("mqtt_connected")

        elseif event == "recv" then
            -- ========== 收到消息 ==========
            -- data = Topic 名称
            -- payload = 消息内容（通常是 JSON 字符串）
            log.info("comm_4g", "收到消息", "topic=" .. tostring(data), "payload=" .. tostring(payload))

            -- 调用消息处理函数
            comm_4g.handleMessage(payload)

        elseif event == "disconnect" then
            -- ========== 连接断开 ==========
            isConnected = false
            log.info("comm_4g", "MQTT断开连接，等待自动重连")
            -- autoreconn(true) 会自动重连
            sys.publish("mqtt_disconnected")
        end
    end)

    -- 【连接服务器】
    -- connect() 发起连接（非阻塞）
    -- 连接结果通过回调的 "conack" 事件通知
    mqttClient:connect()
    sys.publish("mqtt_ready")

    -- 【消息发送循环】
    -- 这是一个无限循环，等待发送消息的请求
    -- 使用事件驱动模式，避免忙轮询
    while true do
        -- sys.waitUntil(event, timeout) 等待事件，超时返回
        -- 返回值：ret=是否收到事件, 后面是事件数据
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 300000)  -- 5分钟超时

        if ret then
            -- 收到发送请求
            if topic == "close" then
                -- 收到关闭指令，退出循环
                break
            end

            -- 发送消息
            if mqttClient and isConnected then
                -- publish(topic, payload, qos) 发布消息
                -- qos: 0=最多一次, 1=至少一次, 2=恰好一次
                mqttClient:publish(topic, data, qos)
            end
        end

        -- 短暂休眠，避免 CPU 占用过高
        sys.wait(1000)
    end

    -- 【关闭连接】
    if mqttClient then
        mqttClient:close()
        mqttClient = nil
    end
end

--------------------------------------------------------------------------------
-- 处理收到的 MQTT 消息
-- @param payload string MQTT 消息内容（通常是 JSON 字符串）
--
-- 【消息格式】
-- 期望收到 JSON 格式的消息，例如：
-- {"type": "alarm"} - 报警指令
-- {"type": "cancel"} - 取消报警
--
-- 【Python 类比】
-- def handle_message(self, payload: str):
--     try:
--         data = json.loads(payload)
--     except json.JSONDecodeError:
--         logger.warning("消息解析失败")
--         return
--     if self.message_handler:
--         self.message_handler(data)
--------------------------------------------------------------------------------
function comm_4g.handleMessage(payload)
    -- 空消息直接返回
    if not payload then
        return
    end

    -- 【解析 JSON】
    -- json.decode(str) 将 JSON 字符串解析为 Lua 表
    -- 类似 Python: json.loads(payload)
    -- 如果解析失败返回 nil
    local data = json.decode(payload)
    if data == nil then
        log.warn("comm_4g", "消息解析失败", payload)
        return
    end

    -- 【调用外部消息处理器】
    -- messageHandler 是初始化时传入的回调函数
    -- 由 main.lua 提供，负责根据消息类型执行相应操作
    if messageHandler then
        messageHandler(data)
    end

    -- 【发布消息事件】
    -- 其他模块也可以通过监听这个事件来处理消息
    sys.publish("mqtt_message", data)
end

--------------------------------------------------------------------------------
-- FOTA 升级任务
--
-- 【FOTA = Firmware Over-The-Air】
-- 远程固件升级，无需物理接触设备即可更新固件
--
-- 【工作流程】
-- 1. 等待网络就绪
-- 2. 向合宙云平台查询是否有新版本
-- 3. 如果有新版本，下载并安装
-- 4. 安装成功后自动重启
--
-- 【版本比对】
-- 云平台通过 PROJECT 和 VERSION 判断是否需要升级
-- 如果云平台上的版本号大于当前版本，就会触发升级
--
-- 【Python 类比】
-- async def fota_task(self):
--     await wait_for_network()
--     result = await check_for_update()
--     if result == SUCCESS:
--         os.system('reboot')
--------------------------------------------------------------------------------
function comm_4g.fotaTask()
    -- 【加载 libfota2 库】
    -- libfota2 是合宙提供的 FOTA 升级库
    local libfota2 = require("libfota2")

    -- 【等待网络就绪】
    -- socket.adapter() 检查网络适配器是否可用
    -- socket.dft() 返回默认适配器 ID
    while not socket.adapter(socket.dft()) do
        log.warn("comm_4g", "FOTA等待网络...")
        sys.waitUntil("IP_READY", 1000)  -- 等待最多 1 秒
    end

    log.info("comm_4g", "开始检查升级")

    -- 【发起升级请求】
    -- libfota2.request(callback, opts) 检查并下载升级包
    -- callback: 结果回调函数
    -- opts: 额外选项（这里为空）
    --
    -- 回调参数 ret 的含义：
    -- 0 = 下载成功，准备安装
    -- 1 = 连接失败
    -- 2 = URL 错误
    -- 3 = 服务器断开
    -- 4 = 失败或已是最新版本
    libfota2.request(function(ret)
        log.info("comm_4g", "FOTA结果", ret)

        if ret == 0 then
            -- 升级包下载成功
            log.info("comm_4g", "升级包下载成功，重启模块")
            -- rtos.reboot() 重启模块
            -- 重启后会自动安装新固件
            rtos.reboot()
        elseif ret == 1 then
            log.info("comm_4g", "FOTA连接失败")
        elseif ret == 2 then
            log.info("comm_4g", "FOTA URL错误")
        elseif ret == 3 then
            log.info("comm_4g", "FOTA服务器断开")
        elseif ret == 4 then
            -- 这是正常情况，表示当前已是最新版本
            log.info("comm_4g", "FOTA失败或已是最新版本")
        end
    end, {})
end

--------------------------------------------------------------------------------
-- 发布消息到服务器
-- @param data table 要发送的数据（会被 JSON 编码）
-- @param qos number QoS 等级（0/1/2，默认为 1）
-- @return boolean 是否发送成功
--
-- 【QoS 等级说明】
-- - QoS 0: 最多一次，消息可能丢失
-- - QoS 1: 至少一次，消息可能重复
-- - QoS 2: 恰好一次，保证不丢失不重复（开销最大）
--
-- 【Python 类比】
-- def publish(self, data: dict, qos: int = 1) -> bool:
--     if not self.is_connected:
--         return False
--     payload = json.dumps(data)
--     self.client.publish(self.pub_topic, payload, qos)
--     return True
--------------------------------------------------------------------------------
function comm_4g.publish(data, qos)
    -- 检查连接状态
    if not mqttClient or not isConnected then
        log.warn("comm_4g", "MQTT未连接，无法发送消息")
        return false
    end

    -- 【编码为 JSON】
    -- json.encode(table) 将 Lua 表编码为 JSON 字符串
    -- 类似 Python: json.dumps(data)
    local payload = json.encode(data)

    -- 【通过事件发送消息】
    -- 这里不直接调用 publish，而是发布事件
    -- mqttTask 中的循环会收到这个事件并执行实际发送
    -- 这样设计可以在单个协程中串行处理所有发送请求
    sys.publish("mqtt_pub", pubTopic, payload, qos or 1)

    log.info("comm_4g", "发送消息", payload)
    return true
end

--------------------------------------------------------------------------------
-- 上报设备状态
-- @param vbat number 电池电压（mV）
-- @return boolean 是否发送成功
--
-- 【用途】
-- 定期向服务器上报设备状态，包括：
-- - IMEI：设备标识
-- - vbat：电池电压
-- - ICCID：SIM 卡标识
--
-- 【Python 类比】
-- def report_status(self, vbat: int) -> bool:
--     data = {
--         "imei": get_imei(),
--         "vbat": vbat,
--         "iccid": get_iccid()
--     }
--     return self.publish(data, qos=2)
--------------------------------------------------------------------------------
function comm_4g.reportStatus(vbat)
    -- 构建状态数据
    local data = {
        imei = mobile.imei(),    -- 设备 IMEI
        vbat = vbat,             -- 电池电压
        iccid = mobile.iccid()   -- SIM 卡 ICCID
    }

    log.info("comm_4g", "上报状态", json.encode(data))

    -- 使用 QoS 2 发送，确保消息不丢失
    return comm_4g.publish(data, 2)
end

--------------------------------------------------------------------------------
-- 获取连接状态
-- @return boolean MQTT 是否已连接
--
-- 【Python 类比】
-- @property
-- def is_connected(self) -> bool:
--     return self._connected
--------------------------------------------------------------------------------
function comm_4g.isConnected()
    return isConnected
end

--------------------------------------------------------------------------------
-- 关闭 MQTT 连接
--
-- 【调用时机】
-- 进入休眠前调用，优雅地关闭 MQTT 连接
--
-- 【工作原理】
-- 发布 "close" 事件，mqttTask 收到后会退出循环并关闭连接
--
-- 【Python 类比】
-- def close(self):
--     self.client.disconnect()
--------------------------------------------------------------------------------
function comm_4g.close()
    -- 发布关闭事件
    -- mqttTask 中的 waitUntil 会收到这个事件
    -- topic="close" 是一个特殊标记，表示要关闭连接
    sys.publish("mqtt_pub", "close", "", 0)
end

--------------------------------------------------------------------------------
-- 返回模块
-- 其他文件通过 require("comm_4g") 获取这个表
--------------------------------------------------------------------------------
return comm_4g
