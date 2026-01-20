"""
设备管理 API
"""
from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import jwt_required
from datetime import datetime, timedelta
from app.api.users import admin_required

device_bp = Blueprint('devices', __name__)


@device_bp.route('', methods=['GET'])
@jwt_required()
def get_devices():
    """获取设备列表"""
    from app.models import Device, Station
    
    # 筛选参数
    device_type = request.args.get('type')  # indoor / outdoor
    online = request.args.get('online')  # 1 / 0
    station_id = request.args.get('station_id', type=int)
    search = request.args.get('search', '')
    
    # 分页参数
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 10, type=int)
    
    query = Device.query
    
    # 类型筛选
    if device_type in ['indoor', 'outdoor']:
        query = query.filter(Device.type == device_type)
    
    # 加油站筛选
    if station_id:
        query = query.filter(Device.station_id == station_id)
    
    # 搜索（IMEI 或加油站名称）
    if search:
        query = query.outerjoin(Station).filter(
            (Device.imei.like(f'%{search}%')) |
            (Station.name.like(f'%{search}%'))
        )
    
    # 分页
    pagination = query.order_by(Device.created_at.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )
    
    # 计算在线状态
    offline_threshold = datetime.now() - timedelta(hours=current_app.config['DEVICE_OFFLINE_HOURS'])
    
    devices = []
    for device in pagination.items:
        device_dict = device.to_dict()
        # 计算在线状态
        if device.last_seen and device.last_seen > offline_threshold:
            device_dict['online'] = True
        else:
            device_dict['online'] = False
        # 低电量警告
        device_dict['low_battery'] = device.vbat is not None and device.vbat < 3300
        devices.append(device_dict)
    
    # 在线状态筛选（在内存中筛选，因为是计算字段）
    if online is not None:
        online_bool = online == '1'
        devices = [d for d in devices if d['online'] == online_bool]
    
    return jsonify({
        'code': 200,
        'message': '获取成功',
        'data': {
            'items': devices,
            'total': pagination.total,
            'page': page,
            'per_page': per_page,
            'pages': pagination.pages
        }
    })


@device_bp.route('', methods=['POST'])
@admin_required
def create_device():
    """手动添加设备"""
    from app.models import Device
    from app import db
    
    data = request.get_json()
    if not data:
        return jsonify({'code': 400, 'message': '请求数据为空', 'data': None}), 400
    
    imei = data.get('imei', '').strip()
    device_type = data.get('type', 'indoor')
    name = data.get('name', '')
    
    if not imei:
        return jsonify({'code': 400, 'message': 'IMEI不能为空', 'data': None}), 400
    
    if device_type not in ['indoor', 'outdoor']:
        return jsonify({'code': 400, 'message': '设备类型只能是 indoor 或 outdoor', 'data': None}), 400
    
    # 检查 IMEI 是否已存在
    existing = Device.query.filter_by(imei=imei).first()
    if existing:
        return jsonify({'code': 409, 'message': f'IMEI {imei} 已存在', 'data': None}), 409
    
    device = Device(
        imei=imei,
        type=device_type,
        name=name or f'手动添加-{imei}'
    )
    
    db.session.add(device)
    db.session.commit()
    
    return jsonify({
        'code': 200,
        'message': '添加成功',
        'data': device.to_dict()
    })


@device_bp.route('/<string:imei>', methods=['GET'])
@jwt_required()
def get_device(imei):
    """获取设备详情"""
    from app.models import Device
    
    device = Device.query.filter_by(imei=imei).first()
    if not device:
        return jsonify({'code': 404, 'message': '设备不存在', 'data': None}), 404
    
    # 计算在线状态
    offline_threshold = datetime.now() - timedelta(hours=current_app.config['DEVICE_OFFLINE_HOURS'])
    device_dict = device.to_dict()
    device_dict['online'] = device.last_seen and device.last_seen > offline_threshold
    device_dict['low_battery'] = device.vbat is not None and device.vbat < 3300
    
    return jsonify({
        'code': 200,
        'message': '获取成功',
        'data': device_dict
    })


@device_bp.route('/<string:imei>/bind', methods=['POST'])
@admin_required
def bind_device(imei):
    """绑定设备到加油站"""
    from app.models import Device, Station
    from app import db
    
    device = Device.query.filter_by(imei=imei).first()
    if not device:
        return jsonify({'code': 404, 'message': '设备不存在', 'data': None}), 404
    
    data = request.get_json()
    if not data or 'station_id' not in data:
        return jsonify({'code': 400, 'message': '请指定加油站ID', 'data': None}), 400
    
    station_id = data['station_id']
    station = Station.query.get(station_id)
    if not station:
        return jsonify({'code': 404, 'message': '加油站不存在', 'data': None}), 404
    
    # 检查设备是否已被其他加油站绑定
    if device.station_id and device.station_id != station_id:
        bound_station = Station.query.get(device.station_id)
        bound_station_name = bound_station.name if bound_station else '未知加油站'
        return jsonify({
            'code': 409,
            'message': f'该设备已被【{bound_station_name}】绑定，无法再次绑定',
            'data': None
        }), 409
    
    # 室内机绑定检查：每个加油站只能有一个室内机
    if device.type == 'indoor':
        existing_indoor = Device.query.filter_by(
            station_id=station_id, type='indoor'
        ).first()
        if existing_indoor and existing_indoor.imei != imei:
            return jsonify({
                'code': 409,
                'message': f'该加油站已绑定室内机 {existing_indoor.imei}',
                'data': None
            }), 409
    
    device.station_id = station_id
    db.session.commit()
    
    return jsonify({
        'code': 200,
        'message': '绑定成功',
        'data': device.to_dict()
    })


@device_bp.route('/<string:imei>/unbind', methods=['POST'])
@admin_required
def unbind_device(imei):
    """解绑设备"""
    from app.models import Device
    from app import db
    
    device = Device.query.filter_by(imei=imei).first()
    if not device:
        return jsonify({'code': 404, 'message': '设备不存在', 'data': None}), 404
    
    device.station_id = None
    db.session.commit()
    
    return jsonify({
        'code': 200,
        'message': '解绑成功',
        'data': device.to_dict()
    })
