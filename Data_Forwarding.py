import paho.mqtt.client as mqtt

# ================= 配置区域 =================
BROKER_HOST = "47.104.166.179"
BROKER_PORT = 1883
MQTT_USER = "mqtt_user"
MQTT_PASS = "mqtt_password"

HOST_PUB_PREFIX = "/AIR8000/PUB/"
HOST_SUB_PREFIX = "/AIR8000/SUB/"

SLAVE_PUB_PREFIX = "/780EHV/PUB/"
SLAVE_SUB_PREFIX = "/780EHV/SUB/"

# 主机IMEI
HOST_IMEI = "864793080106318"
# 从机IMEI
SLAVE_IMEI = "866965083776697"

BINDING_MAP = {
    HOST_IMEI: [SLAVE_IMEI], 
    SLAVE_IMEI: [HOST_IMEI]
}
# ===========================================

def on_connect(client, userdata, flags, rc):
    print(f"服务器连接成功! 双向监听已启动...")
    
    # 订阅 主机 的发布通道
    client.subscribe(HOST_PUB_PREFIX + "+")
    print(f"监听主机: {HOST_PUB_PREFIX}+")
    
    # 订阅 从机 的发布通道
    client.subscribe(SLAVE_PUB_PREFIX + "+")
    print(f"监听从机: {SLAVE_PUB_PREFIX}+")

def on_message(client, userdata, msg):
    try:
        topic = msg.topic
        payload = msg.payload.decode('utf-8')
        sender_imei = ""
        target_sub_prefix = "" 

        if topic.startswith(HOST_PUB_PREFIX):
            sender_imei = topic.split(HOST_PUB_PREFIX)[1]
            target_sub_prefix = SLAVE_SUB_PREFIX
            print(f"\n主机消息: {sender_imei} -> 发送: {payload}")

        elif topic.startswith(SLAVE_PUB_PREFIX):
            sender_imei = topic.split(SLAVE_PUB_PREFIX)[1]
            target_sub_prefix = HOST_SUB_PREFIX
            print(f"\n从机消息: {sender_imei} -> 发送: {payload}")
        
        else:
            return 

        if sender_imei in BINDING_MAP:
            receivers = BINDING_MAP[sender_imei]
            for receiver in receivers:
                target_topic = target_sub_prefix + receiver
                client.publish(target_topic, payload)
                print(f"转发成功 -> 目标设备: {receiver}")
                print(f"(目标Topic: {target_topic})")
        else:
            print(f"未找到绑定关系，不转发")

    except Exception as e:
        print(f"系统错误: {e}")

if __name__ == '__main__':
    client = mqtt.Client()
    client.username_pw_set(MQTT_USER, MQTT_PASS)
    client.on_connect = on_connect
    client.on_message = on_message
    print("正在连接 MQTT Broker...")
    client.connect(BROKER_HOST, BROKER_PORT, 60)
    client.loop_forever()
