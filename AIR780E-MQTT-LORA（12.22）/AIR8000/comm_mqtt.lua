--[[
@module comm_mqtt
@summary MQTT通讯模块 - 4G模式下的消息收发
@version 1.0.0

================================================================================
模块概述
================================================================================

本模块负责 4G 模式下的 MQTT 通讯：
1. 连接 MQTT 服务器
2. 发送报警/取消/解除消息给室外机
3. 接收室外机上报的电池状态

【通讯架构】

┌─────────────┐       ┌─────────────┐       ┌─────────────┐
│   AIR8000   │──────→│ MQTT Server │──────→│   AIR780E   │
│   室内机    │       │             │       │   室外机    │
│             │←──────│             │←──────│             │
└─────────────┘       └─────────────┘       └─────────────┘
       │                                           │
       │  PUB: /AIR8000/PUB/{IMEI}                │
       │  SUB: /AIR8000/SUB/{IMEI}                │
       │                                           │
       │  发送: {type:"alarm"}                     │
       │        {type:"cancel"}                    │
       │        {type:"disarm"}                    │
       │                                           │
       │  接收: {vbat:3700}  (室外机电池电压)       │
       └───────────────────────────────────────────┘

【消息格式】
发送给室外机的消息必须与室外机期望的格式一致：
- 报警: {"type": "alarm"}
- 取消: {"type": "cancel"}
- 解除: {"type": "disarm"}

【Python 类比】
类似 paho-mqtt 的使用方式：
```python
import paho.mqtt.client as mqtt

class MQTTComm:
    def __init__(self):
        self.client = mqtt.Client()
        self.client.on_message = self._on_message

    def connect(self, host, port):
        self.client.connect(host, port)
        self.client.loop_start()

    def send_alarm(self):
        self.client.publish(self.pub_topic, '{"type":"alarm"}')
```
]]

local commMqtt = {}
local config = require("config")

--------------------------------------------------------------------------------
-- 模块内部状态
--------------------------------------------------------------------------------
local mqttClient = nil          -- MQTT 客户端实例
local isConnected = false       -- 是否已连接
local pubTopic = nil            -- 发布 Topic
local subTopic = nil            -- 订阅 Topic
local messageCallback = nil     -- 消息回调函数

--------------------------------------------------------------------------------
-- 初始化 MQTT 模块
-- @param callback function 消息接收回调函数
--
-- 【调用时机】
-- 在 main.lua 中，确定为 4G 模式后调用
--
-- 【回调函数格式】
-- function callback(data)
--     -- data 是解析后的 JSON 对象
--     if data.vbat then
--         -- 处理电池状态
--     end
-- end
--
-- 【Python 类比】
-- def init(self, callback):
--     self.on_message = callback
--     self._setup_mqtt()
--------------------------------------------------------------------------------
function commMqtt.init(callback)
    messageCallback = callback

    -- 构建 Topic（包含设备 IMEI）
    local imei = mobile.imei()
    pubTopic = config.mqtt.pub_topic_prefix .. imei
    subTopic = config.mqtt.sub_topic_prefix .. imei

    log.info("commMqtt", "Topic配置", "发布=" .. pubTopic, "订阅=" .. subTopic)

    -- 启动 MQTT 连接任务
    sys.taskInit(function()
        commMqtt.connectTask()
    end)
end

--------------------------------------------------------------------------------
-- MQTT 连接任务
-- 这是一个后台任务，负责建立和维护 MQTT 连接
--
-- 【工作流程】
-- 1. 等待网络就绪 (IP_READY)
-- 2. 创建 MQTT 客户端
-- 3. 连接服务器
-- 4. 订阅 Topic
-- 5. 进入消息循环
--
-- 【与官方实现的区别】
-- 官方使用 sys.taskInitEx + sys.sendMsg/waitMsg 模式
-- 我们使用更简单的 sys.taskInit + sys.publish/waitUntil 模式
-- 对于低频消息（报警/取消/解除），当前实现已足够
--------------------------------------------------------------------------------
function commMqtt.connectTask()
    -- 【第1步】等待网络就绪
    local ret, ip = sys.waitUntil("IP_READY", config.mqtt.connect_timeout)
    if not ret then
        log.warn("commMqtt", "等待网络超时，继续尝试连接")
    end

    log.info("commMqtt", "网络就绪，开始连接MQTT")

    -- 检查 mqtt 库是否可用
    if mqtt == nil then
        log.error("commMqtt", "MQTT库不可用")
        return
    end

    -- 【第2步】创建 MQTT 客户端
    local cfg = config.mqtt
    mqttClient = mqtt.create(nil, cfg.host, cfg.port, cfg.isssl)

    -- 设置认证信息
    local clientId = mobile.imei()
    mqttClient:auth(clientId, cfg.user_name, cfg.password)

    -- 设置心跳
    mqttClient:keepalive(cfg.keepalive)

    -- 设置自动重连
    mqttClient:autoreconn(cfg.auto_reconnect)

    -- 【第3步】设置事件回调
    mqttClient:on(function(client, event, data, payload)
        commMqtt.onEvent(client, event, data, payload)
    end)

    -- 【第4步】发起连接
    log.info("commMqtt", "连接MQTT服务器", cfg.host, cfg.port)
    mqttClient:connect()

    -- 【第5步】等待连接成功
    sys.waitUntil("mqtt_connected")
    log.info("commMqtt", "MQTT连接成功")

    -- 【第6步】进入消息发送循环
    -- 等待其他模块通过 sys.publish("mqtt_send", topic, data) 发送消息
    while true do
        local ret, topic, data, qos = sys.waitUntil("mqtt_send", 300000)
        if ret then
            if topic == "close" then
                break
            end
            mqttClient:publish(topic, data, qos or 1)
            log.info("commMqtt", "消息已发送", topic)
        end
    end

    -- 关闭连接
    mqttClient:close()
    mqttClient = nil
end

--------------------------------------------------------------------------------
-- MQTT 事件回调
-- @param client MQTT 客户端实例
-- @param event string 事件类型
-- @param data 事件数据
-- @param payload 消息内容（仅 recv 事件）
--
-- 【事件类型】
-- - "conack": 连接成功
-- - "recv": 收到消息
-- - "sent": 消息发送完成
-- - "disconnect": 断开连接
--------------------------------------------------------------------------------
function commMqtt.onEvent(client, event, data, payload)
    log.info("commMqtt", "事件", event)

    if event == "conack" then
        -- ========== 连接成功 ==========
        isConnected = true

        -- 订阅 Topic
        client:subscribe(subTopic)
        log.info("commMqtt", "已订阅", subTopic)

        -- 发布连接成功事件
        sys.publish("mqtt_connected")

    elseif event == "recv" then
        -- ========== 收到消息 ==========
        log.info("commMqtt", "收到消息", "topic=" .. tostring(data), "payload=" .. tostring(payload))

        -- 解析 JSON
        local ok, msgData = pcall(json.decode, payload)
        if ok and msgData then
            -- 调用回调函数
            if messageCallback then
                messageCallback(msgData)
            end
        else
            log.warn("commMqtt", "JSON解析失败", payload)
        end

    elseif event == "sent" then
        -- ========== 消息发送完成 ==========
        -- log.info("commMqtt", "消息发送完成", data)

    elseif event == "disconnect" then
        -- ========== 断开连接 ==========
        isConnected = false
        log.warn("commMqtt", "连接断开，等待自动重连")
        -- autoreconn(true) 会自动重连，这里只需更新状态
        sys.publish("mqtt_disconnected")
    end
end

--------------------------------------------------------------------------------
-- 发送报警消息
-- 通知室外机开始报警
--
-- 【消息格式】
-- {"type": "alarm"}
--
-- 【Python 类比】
-- def send_alarm(self):
--     self.client.publish(self.pub_topic, json.dumps({"type": "alarm"}))
--------------------------------------------------------------------------------
function commMqtt.sendAlarm()
    if not isConnected then
        log.warn("commMqtt", "MQTT未连接，无法发送报警")
        return false
    end

    local msg = {type = config.mqtt_msg.TYPE_ALARM}
    local payload = json.encode(msg)

    sys.publish("mqtt_send", pubTopic, payload, 2)  -- QoS=2 确保送达
    log.info("commMqtt", "发送报警消息", payload)

    return true
end

--------------------------------------------------------------------------------
-- 发送取消报警消息
-- 通知室外机停止报警
--
-- 【消息格式】
-- {"type": "cancel"}
--------------------------------------------------------------------------------
function commMqtt.sendCancel()
    if not isConnected then
        log.warn("commMqtt", "MQTT未连接，无法发送取消")
        return false
    end

    local msg = {type = config.mqtt_msg.TYPE_CANCEL}
    local payload = json.encode(msg)

    sys.publish("mqtt_send", pubTopic, payload, 2)
    log.info("commMqtt", "发送取消报警消息", payload)

    return true
end

--------------------------------------------------------------------------------
-- 发送解除报警消息
-- 通知室外机解除报警状态
--
-- 【消息格式】
-- {"type": "disarm"}
--
-- 【与取消的区别】
-- - 取消(cancel): 临时停止当前报警
-- - 解除(disarm): 彻底解除，通常是人工确认后
--------------------------------------------------------------------------------
function commMqtt.sendDisarm()
    if not isConnected then
        log.warn("commMqtt", "MQTT未连接，无法发送解除")
        return false
    end

    local msg = {type = config.mqtt_msg.TYPE_DISARM}
    local payload = json.encode(msg)

    sys.publish("mqtt_send", pubTopic, payload, 2)
    log.info("commMqtt", "发送解除报警消息", payload)

    return true
end

--------------------------------------------------------------------------------
-- 检查是否已连接
-- @return boolean 是否已连接
--------------------------------------------------------------------------------
function commMqtt.isConnected()
    return isConnected
end

--------------------------------------------------------------------------------
-- 返回模块
--------------------------------------------------------------------------------
return commMqtt
