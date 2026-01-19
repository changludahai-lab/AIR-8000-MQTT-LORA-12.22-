"""
报警日志 API
"""
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from datetime import datetime

alarm_bp = Blueprint('alarms', __name__)


@alarm_bp.route('', methods=['GET'])
@jwt_required()
def get_alarms():
    """获取报警日志列表"""
    from app.models import AlarmLog, Station
    
    # 筛选参数
    station_id = request.args.get('station_id', type=int)
    alarm_type = request.args.get('alarm_type')  # alarm / cancel
    start_date = request.args.get('start_date')  # YYYY-MM-DD
    end_date = request.args.get('end_date')  # YYYY-MM-DD
    search = request.args.get('search', '')
    
    # 分页参数
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 10, type=int)
    
    query = AlarmLog.query.join(Station, AlarmLog.station_id == Station.id, isouter=True)
    
    # 加油站筛选
    if station_id:
        query = query.filter(AlarmLog.station_id == station_id)
    
    # 报警类型筛选
    if alarm_type in ['alarm', 'cancel']:
        query = query.filter(AlarmLog.alarm_type == alarm_type)
    
    # 时间范围筛选
    if start_date:
        try:
            start = datetime.strptime(start_date, '%Y-%m-%d')
            query = query.filter(AlarmLog.created_at >= start)
        except ValueError:
            pass
    
    if end_date:
        try:
            end = datetime.strptime(end_date, '%Y-%m-%d')
            # 包含当天，所以加一天
            end = end.replace(hour=23, minute=59, second=59)
            query = query.filter(AlarmLog.created_at <= end)
        except ValueError:
            pass
    
    # 搜索（加油站名称或 IMEI）
    if search:
        query = query.filter(
            (Station.name.like(f'%{search}%')) |
            (AlarmLog.indoor_imei.like(f'%{search}%'))
        )
    
    # 按时间倒序分页
    pagination = query.order_by(AlarmLog.created_at.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )
    
    return jsonify({
        'code': 200,
        'message': '获取成功',
        'data': {
            'items': [alarm.to_dict() for alarm in pagination.items],
            'total': pagination.total,
            'page': page,
            'per_page': per_page,
            'pages': pagination.pages
        }
    })
