"""
加油站管理 API
"""
from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import jwt_required
from datetime import datetime, timedelta
from app.api.users import admin_required

station_bp = Blueprint('stations', __name__)


@station_bp.route('/stats', methods=['GET'])
@jwt_required()
def get_stats():
    """获取平台统计数据"""
    from app.models import Station, Device, AlarmLog
    
    # 加油站总数
    station_count = Station.query.count()
    
    # 设备总数
    device_count = Device.query.count()
    
    # 在线设备数（last_seen 在 13 小时内）
    offline_threshold = datetime.now() - timedelta(hours=current_app.config['DEVICE_OFFLINE_HOURS'])
    online_count = Device.query.filter(Device.last_seen > offline_threshold).count()
    
    # 最近报警记录（最近10条）
    recent_alarms = AlarmLog.query.join(
        Station, AlarmLog.station_id == Station.id, isouter=True
    ).order_by(AlarmLog.created_at.desc()).limit(10).all()
    
    return jsonify({
        'code': 200,
        'message': '获取成功',
        'data': {
            'station_count': station_count,
            'device_count': device_count,
            'online_count': online_count,
            'recent_alarms': [alarm.to_dict() for alarm in recent_alarms]
        }
    })


@station_bp.route('', methods=['GET'])
@jwt_required()
def get_stations():
    """获取加油站列表"""
    from app.models import Station
    
    # 分页参数
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 10, type=int)
    
    # 搜索参数
    search = request.args.get('search', '')
    
    query = Station.query
    
    # 搜索过滤
    if search:
        query = query.filter(
            (Station.name.like(f'%{search}%')) |
            (Station.code.like(f'%{search}%'))
        )
    
    # 分页
    pagination = query.order_by(Station.created_at.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )
    
    return jsonify({
        'code': 200,
        'message': '获取成功',
        'data': {
            'items': [station.to_dict() for station in pagination.items],
            'total': pagination.total,
            'page': page,
            'per_page': per_page,
            'pages': pagination.pages
        }
    })


@station_bp.route('/<int:station_id>', methods=['GET'])
@jwt_required()
def get_station(station_id):
    """获取加油站详情"""
    from app.models import Station, Device
    
    station = Station.query.get(station_id)
    if not station:
        return jsonify({'code': 404, 'message': '加油站不存在', 'data': None}), 404
    
    # 获取绑定的设备
    devices = Device.query.filter_by(station_id=station_id).all()
    indoor_device = None
    outdoor_devices = []
    
    for device in devices:
        if device.type == 'indoor':
            indoor_device = device.to_dict()
        else:
            outdoor_devices.append(device.to_dict())
    
    result = station.to_dict()
    result['indoor_device'] = indoor_device
    result['outdoor_devices'] = outdoor_devices
    
    return jsonify({
        'code': 200,
        'message': '获取成功',
        'data': result
    })


@station_bp.route('', methods=['POST'])
@admin_required
def create_station():
    """创建加油站"""
    from app.models import Station
    from app import db
    
    data = request.get_json()
    if not data:
        return jsonify({'code': 400, 'message': '请求数据为空', 'data': None}), 400
    
    name = data.get('name')
    code = data.get('code')
    
    if not name or not code:
        return jsonify({'code': 400, 'message': '名称和编号不能为空', 'data': None}), 400
    
    # 检查编号是否已存在
    if Station.query.filter_by(code=code).first():
        return jsonify({'code': 409, 'message': '加油站编号已存在', 'data': None}), 409
    
    station = Station(
        name=name,
        code=code,
        address=data.get('address', ''),
        contact=data.get('contact', ''),
        phone=data.get('phone', ''),
        status=1
    )
    
    db.session.add(station)
    db.session.commit()
    
    return jsonify({
        'code': 200,
        'message': '创建成功',
        'data': station.to_dict()
    })


@station_bp.route('/<int:station_id>', methods=['PUT'])
@admin_required
def update_station(station_id):
    """更新加油站"""
    from app.models import Station
    from app import db
    
    station = Station.query.get(station_id)
    if not station:
        return jsonify({'code': 404, 'message': '加油站不存在', 'data': None}), 404
    
    data = request.get_json()
    if not data:
        return jsonify({'code': 400, 'message': '请求数据为空', 'data': None}), 400
    
    # 更新编号时检查是否重复
    if 'code' in data and data['code'] != station.code:
        if Station.query.filter_by(code=data['code']).first():
            return jsonify({'code': 409, 'message': '加油站编号已存在', 'data': None}), 409
        station.code = data['code']
    
    if 'name' in data:
        station.name = data['name']
    if 'address' in data:
        station.address = data['address']
    if 'contact' in data:
        station.contact = data['contact']
    if 'phone' in data:
        station.phone = data['phone']
    if 'status' in data:
        station.status = 1 if data['status'] else 0
    
    db.session.commit()
    
    return jsonify({
        'code': 200,
        'message': '更新成功',
        'data': station.to_dict()
    })


@station_bp.route('/<int:station_id>', methods=['DELETE'])
@admin_required
def delete_station(station_id):
    """删除加油站"""
    from app.models import Station, Device
    from app import db
    
    station = Station.query.get(station_id)
    if not station:
        return jsonify({'code': 404, 'message': '加油站不存在', 'data': None}), 404
    
    # 检查是否有绑定设备
    bound_devices = Device.query.filter_by(station_id=station_id).count()
    if bound_devices > 0:
        return jsonify({'code': 409, 'message': '该加油站有绑定设备，请先解绑', 'data': None}), 409
    
    db.session.delete(station)
    db.session.commit()
    
    return jsonify({
        'code': 200,
        'message': '删除成功',
        'data': None
    })
