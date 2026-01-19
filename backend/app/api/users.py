"""
用户管理 API
"""
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from functools import wraps

user_bp = Blueprint('users', __name__)


def admin_required(fn):
    """超级管理员权限装饰器"""
    @wraps(fn)
    @jwt_required()
    def wrapper(*args, **kwargs):
        from app.models import User
        
        user_id = get_jwt_identity()
        user = User.query.get(user_id)
        
        if not user or user.role != 'admin':
            return jsonify({'code': 403, 'message': '需要管理员权限', 'data': None}), 403
        
        return fn(*args, **kwargs)
    return wrapper


@user_bp.route('', methods=['GET'])
@admin_required
def get_users():
    """获取用户列表"""
    from app.models import User
    
    users = User.query.all()
    return jsonify({
        'code': 200,
        'message': '获取成功',
        'data': [user.to_dict() for user in users]
    })


@user_bp.route('', methods=['POST'])
@admin_required
def create_user():
    """创建用户"""
    from app.models import User
    from app import db
    
    data = request.get_json()
    if not data:
        return jsonify({'code': 400, 'message': '请求数据为空', 'data': None}), 400
    
    username = data.get('username')
    password = data.get('password')
    role = data.get('role', 'user')
    
    if not username or not password:
        return jsonify({'code': 400, 'message': '用户名和密码不能为空', 'data': None}), 400
    
    if role not in ['admin', 'user']:
        return jsonify({'code': 400, 'message': '角色只能是 admin 或 user', 'data': None}), 400
    
    # 检查用户名是否已存在
    if User.query.filter_by(username=username).first():
        return jsonify({'code': 409, 'message': '用户名已存在', 'data': None}), 409
    
    user = User(username=username, role=role, status=1)
    user.set_password(password)
    
    db.session.add(user)
    db.session.commit()
    
    return jsonify({
        'code': 200,
        'message': '创建成功',
        'data': user.to_dict()
    })


@user_bp.route('/<int:user_id>', methods=['PUT'])
@admin_required
def update_user(user_id):
    """更新用户"""
    from app.models import User
    from app import db
    
    user = User.query.get(user_id)
    if not user:
        return jsonify({'code': 404, 'message': '用户不存在', 'data': None}), 404
    
    data = request.get_json()
    if not data:
        return jsonify({'code': 400, 'message': '请求数据为空', 'data': None}), 400
    
    # 更新用户名
    if 'username' in data and data['username'] != user.username:
        if User.query.filter_by(username=data['username']).first():
            return jsonify({'code': 409, 'message': '用户名已存在', 'data': None}), 409
        user.username = data['username']
    
    # 更新密码
    if 'password' in data and data['password']:
        user.set_password(data['password'])
    
    # 更新角色
    if 'role' in data:
        if data['role'] not in ['admin', 'user']:
            return jsonify({'code': 400, 'message': '角色只能是 admin 或 user', 'data': None}), 400
        user.role = data['role']
    
    # 更新状态
    if 'status' in data:
        user.status = 1 if data['status'] else 0
    
    db.session.commit()
    
    return jsonify({
        'code': 200,
        'message': '更新成功',
        'data': user.to_dict()
    })


@user_bp.route('/<int:user_id>', methods=['DELETE'])
@admin_required
def delete_user(user_id):
    """删除用户"""
    from app.models import User
    from app import db
    
    user = User.query.get(user_id)
    if not user:
        return jsonify({'code': 404, 'message': '用户不存在', 'data': None}), 404
    
    # 不能删除自己
    current_user_id = get_jwt_identity()
    if user_id == current_user_id:
        return jsonify({'code': 400, 'message': '不能删除自己', 'data': None}), 400
    
    db.session.delete(user)
    db.session.commit()
    
    return jsonify({
        'code': 200,
        'message': '删除成功',
        'data': None
    })
