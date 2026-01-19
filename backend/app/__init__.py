"""
Flask 应用工厂
"""
from flask import Flask, request
from flask_sqlalchemy import SQLAlchemy
from flask_jwt_extended import JWTManager
from flask_cors import CORS

# 初始化扩展
db = SQLAlchemy()
jwt = JWTManager()


def create_app(config_name='default'):
    """应用工厂函数"""
    from config import config_map
    
    app = Flask(__name__, static_folder='../static', static_url_path='')
    app.config.from_object(config_map[config_name])
    
    # 初始化扩展
    db.init_app(app)
    jwt.init_app(app)
    CORS(app)
    
    # 注册蓝图
    from app.api.auth import auth_bp
    from app.api.users import user_bp
    from app.api.stations import station_bp
    from app.api.devices import device_bp
    from app.api.alarms import alarm_bp
    from app.api.comm_logs import bp as comm_logs_bp
    
    app.register_blueprint(auth_bp, url_prefix='/api/auth')
    app.register_blueprint(user_bp, url_prefix='/api/users')
    app.register_blueprint(station_bp, url_prefix='/api/stations')
    app.register_blueprint(device_bp, url_prefix='/api/devices')
    app.register_blueprint(alarm_bp, url_prefix='/api/alarms')
    app.register_blueprint(comm_logs_bp)
    
    # 前端静态文件路由
    @app.route('/')
    def index():
        return app.send_static_file('index.html')
    
    # SPA 路由支持 - 处理所有前端路由
    @app.route('/login')
    @app.route('/users')
    @app.route('/stations')
    @app.route('/devices')
    @app.route('/monitor')
    @app.route('/alarms')
    @app.route('/comm-logs')
    def spa_routes():
        return app.send_static_file('index.html')
    
    @app.errorhandler(404)
    def not_found(e):
        # API 路由返回 JSON 错误
        if request.path.startswith('/api/'):
            return {'code': 404, 'message': '资源不存在', 'data': None}, 404
        # SPA 路由支持，返回 index.html
        return app.send_static_file('index.html')
    
    # 创建数据库表和默认管理员
    with app.app_context():
        db.create_all()
        create_default_admin(app)
    
    return app


def create_default_admin(app):
    """创建默认超级管理员"""
    from app.models import User
    
    admin = User.query.filter_by(username=app.config['DEFAULT_ADMIN_USERNAME']).first()
    if not admin:
        admin = User(
            username=app.config['DEFAULT_ADMIN_USERNAME'],
            role='admin',
            status=1
        )
        admin.set_password(app.config['DEFAULT_ADMIN_PASSWORD'])
        db.session.add(admin)
        db.session.commit()
        print(f"默认管理员已创建: {app.config['DEFAULT_ADMIN_USERNAME']}")
