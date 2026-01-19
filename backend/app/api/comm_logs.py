"""
通讯记录 API
"""
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from app.models import CommLog

bp = Blueprint('comm_logs', __name__)


@bp.route('/api/comm-logs', methods=['GET'])
@jwt_required()
def get_comm_logs():
    """获取通讯记录列表"""
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    
    # 筛选条件
    direction = request.args.get('direction')
    source_type = request.args.get('source_type')
    source_imei = request.args.get('source_imei')
    station_id = request.args.get('station_id', type=int)
    
    query = CommLog.query
    
    if direction:
        query = query.filter(CommLog.direction == direction)
    if source_type:
        query = query.filter(CommLog.source_type == source_type)
    if source_imei:
        query = query.filter(CommLog.source_imei.like(f'%{source_imei}%'))
    if station_id:
        query = query.filter(CommLog.station_id == station_id)
    
    # 按时间倒序
    query = query.order_by(CommLog.created_at.desc())
    
    # 分页
    pagination = query.paginate(page=page, per_page=per_page, error_out=False)
    
    return jsonify({
        'code': 0,
        'message': 'success',
        'data': {
            'items': [log.to_dict() for log in pagination.items],
            'total': pagination.total,
            'page': page,
            'per_page': per_page,
            'pages': pagination.pages
        }
    })
