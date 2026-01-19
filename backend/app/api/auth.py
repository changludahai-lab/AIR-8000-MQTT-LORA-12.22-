"""
认证 API
"""
from flask import Blueprint, request, jsonify
from flask_jwt_extended import create_access_token, jwt_required, get_jwt_identity

auth_bp = Blueprint('auth', __name__)


@auth_bp.route('/login', methods=['POST'])
def login():
    """用户登录"""
    from app.models import User
    
    data = request.get_json()
    if not data:
        return jsonify({'code': 400, 'message': '请求数据为空', 'data': None}), 400
    
    username = data.get('username')
    password = data.get('password')
    
    if not username or not password:
        return jsonify({'code': 400, 'message': '用户名和密码不能为空', 'data': None}), 400
    
    user = User.query.filter_by(username=username).first()
    
    if not user or not user.check_password(password):
        return jsonify({'code': 401, 'message': '用户名或密码错误', 'data': None}), 401
    
    if user.status != 1:
        return jsonify({'code': 403, 'message': '账号已被禁用', 'data': None}), 403
    
    # 生成 JWT Token
    access_token = create_access_token(identity=user.id)
    
    return jsonify({
        'code': 200,
        'message': '登录成功',
        'data': {
            'token': access_token,
            'user': user.to_dict()
        }
    })


@auth_bp.route('/logout', methods=['POST'])
@jwt_required()
def logout():
    """用户登出"""
    # JWT 是无状态的，客户端删除 token 即可
    return jsonify({
        'code': 200,
        'message': '登出成功',
        'data': None
    })


@auth_bp.route('/me', methods=['GET'])
@jwt_required()
def get_current_user():
    """获取当前用户信息"""
    from app.models import User
    
    user_id = get_jwt_identity()
    user = User.query.get(user_id)
    
    if not user:
        return jsonify({'code': 404, 'message': '用户不存在', 'data': None}), 404
    
    return jsonify({
        'code': 200,
        'message': '获取成功',
        'data': user.to_dict()
    })
