"""
MQTT 转发服务
"""
import json
import threading
from datetime import datetime
import paho.mqtt.client as mqtt


# 全局 MQTT 客户端
mqtt_client = None
flask_app = None
_mqtt_started = False  # 防止重复启动标志


def start_mqtt_service(app):
    """启动 MQTT 服务"""
    global mqtt_client, flask_app, _mqtt_started
    
    # 防止重复启动
    if _mqtt_started:
        print("MQTT 服务已在运行，跳过重复启动")
        return
    
    _mqtt_started = True
    flask_app = app
    
    # 使用唯一的 client_id 避免 broker 端的重复连接问题
    import uuid
    client_id = f"gas_station_monitor_{uuid.uuid4().hex[:8]}"
    
    mqtt_client = mqtt.Client(client_id=client_id, clean_session=True)
    mqtt_client.username_pw_set(
        app.config['MQTT_USERNAME'],
        app.config['MQTT_PASSWORD']
    )
    mqtt_client.on_connect = on_connect
    mqtt_client.on_message = on_message
    mqtt_client.on_disconnect = on_disconnect
    
    def connect_mqtt():
        try:
            mqtt_client.connect(
                app.config['MQTT_BROKER_HOST'],
                app.config['MQTT_BROKER_PORT'],
                60
            )
            mqtt_client.loop_forever()
        except Exception as e:
            print(f"MQTT 连接失败: {e}")
    
    # 在单独线程中运行 MQTT
    mqtt_thread = threading.Thread(target=connect_mqtt, daemon=True)
    mqtt_thread.start()
    print(f"MQTT 服务已启动 (client_id: {client_id})")


def on_connect(client, userdata, flags, rc):
    """MQTT 连接回调"""
    if rc == 0:
        print("MQTT 连接成功")
        # 订阅室内机和室外机的发布主题
        client.subscribe(flask_app.config['INDOOR_PUB_PREFIX'] + '+')
        client.subscribe(flask_app.config['OUTDOOR_PUB_PREFIX'] + '+')
        print(f"已订阅: {flask_app.config['INDOOR_PUB_PREFIX']}+")
        print(f"已订阅: {flask_app.config['OUTDOOR_PUB_PREFIX']}+")
    else:
        print(f"MQTT 连接失败，返回码: {rc}")


def on_disconnect(client, userdata, rc):
    """MQTT 断开连接回调"""
    print(f"MQTT 断开连接，返回码: {rc}")


def on_message(client, userdata, msg):
    """MQTT 消息回调"""
    try:
        topic = msg.topic
        payload = msg.payload.decode('utf-8')
        
        print(f"收到消息: {topic} -> {payload}")
        
        with flask_app.app_context():
            if topic.startswith(flask_app.config['INDOOR_PUB_PREFIX']):
                # 室内机消息
                imei = topic.split('/')[-1]
                handle_indoor_message(imei, payload)
            elif topic.startswith(flask_app.config['OUTDOOR_PUB_PREFIX']):
                # 室外机消息
                imei = topic.split('/')[-1]
                handle_outdoor_message(imei, payload)
    except Exception as e:
        print(f"处理消息出错: {e}")


def handle_indoor_message(imei, payload):
    """处理室内机消息"""
    from app.models import Device, AlarmLog, CommLog
    from app import db
    
    # 自动注册或更新设备
    device = auto_register_device(imei, 'indoor')
    if not device:
        return
    
    # 更新在线时间
    device.last_seen = datetime.now()
    db.session.commit()
    
    # 记录接收通讯日志
    receive_log = CommLog(
        direction='receive',
        source_type='indoor',
        source_imei=imei,
        topic=flask_app.config['INDOOR_PUB_PREFIX'] + imei,
        payload=payload,
        station_id=device.station_id
    )
    db.session.add(receive_log)
    db.session.commit()
    
    # 解析消息
    try:
        data = json.loads(payload)
    except:
        print(f"无法解析消息: {payload}")
        return
    
    # 检查是否绑定加油站
    if not device.station_id:
        print(f"设备 {imei} 未绑定加油站，不转发")
        return
    
    # 获取同站室外机
    outdoor_devices = Device.query.filter_by(
        station_id=device.station_id,
        type='outdoor'
    ).all()
    
    if not outdoor_devices:
        print(f"加油站 {device.station_id} 没有室外机")
        return
    
    # 转发消息给所有室外机
    outdoor_imeis = []
    for outdoor in outdoor_devices:
        target_topic = flask_app.config['OUTDOOR_SUB_PREFIX'] + outdoor.imei
        mqtt_client.publish(target_topic, payload)
        outdoor_imeis.append(outdoor.imei)
        print(f"转发到室外机: {target_topic}")
        
        # 记录转发通讯日志
        forward_log = CommLog(
            direction='forward',
            source_type='indoor',
            source_imei=imei,
            target_type='outdoor',
            target_imei=outdoor.imei,
            topic=target_topic,
            payload=payload,
            station_id=device.station_id
        )
        db.session.add(forward_log)
    
    db.session.commit()
    
    # 记录报警日志
    if 'bj' in data:
        # 兼容字符串和整数类型的 bj 值
        bj_value = data['bj']
        if isinstance(bj_value, str):
            bj_value = int(bj_value)
        alarm_type = 'alarm' if bj_value == 1 else 'cancel'
        alarm_log = AlarmLog(
            station_id=device.station_id,
            indoor_imei=imei,
            alarm_type=alarm_type,
            outdoor_imeis=json.dumps(outdoor_imeis),
            forward_status=1
        )
        db.session.add(alarm_log)
        db.session.commit()
        print(f"记录报警日志: {alarm_type}")


def handle_outdoor_message(imei, payload):
    """处理室外机消息"""
    from app.models import Device, CommLog
    from app import db
    
    # 自动注册或更新设备
    device = auto_register_device(imei, 'outdoor')
    if not device:
        return
    
    # 更新在线时间
    device.last_seen = datetime.now()
    
    # 解析消息，更新电池电量
    try:
        data = json.loads(payload)
        if 'vbat' in data:
            device.vbat = data['vbat']
    except:
        pass
    
    db.session.commit()
    
    # 记录接收通讯日志
    receive_log = CommLog(
        direction='receive',
        source_type='outdoor',
        source_imei=imei,
        topic=flask_app.config['OUTDOOR_PUB_PREFIX'] + imei,
        payload=payload,
        station_id=device.station_id
    )
    db.session.add(receive_log)
    db.session.commit()
    
    # 检查是否绑定加油站
    if not device.station_id:
        print(f"设备 {imei} 未绑定加油站，不转发")
        return
    
    # 获取同站室内机
    indoor_device = Device.query.filter_by(
        station_id=device.station_id,
        type='indoor'
    ).first()
    
    if not indoor_device:
        print(f"加油站 {device.station_id} 没有室内机")
        return
    
    # 转发消息给室内机
    target_topic = flask_app.config['INDOOR_SUB_PREFIX'] + indoor_device.imei
    mqtt_client.publish(target_topic, payload)
    print(f"转发到室内机: {target_topic}")
    
    # 记录转发通讯日志
    forward_log = CommLog(
        direction='forward',
        source_type='outdoor',
        source_imei=imei,
        target_type='indoor',
        target_imei=indoor_device.imei,
        topic=target_topic,
        payload=payload,
        station_id=device.station_id
    )
    db.session.add(forward_log)
    db.session.commit()


def auto_register_device(imei, device_type):
    """自动注册设备"""
    from app.models import Device
    from app import db
    
    device = Device.query.filter_by(imei=imei).first()
    
    if not device:
        # 自动创建设备
        device = Device(
            imei=imei,
            type=device_type,
            name=f"自动注册-{imei}",
            last_seen=datetime.now()
        )
        db.session.add(device)
        db.session.commit()
        print(f"自动注册设备: {imei} ({device_type})")
    
    return device
