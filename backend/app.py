"""
应用入口文件
"""
import os
import sys

# 添加当前目录到路径
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app import create_app

# 获取配置环境
config_name = os.environ.get('FLASK_ENV') or 'development'

# 创建应用
app = create_app(config_name)

if __name__ == '__main__':
    # 启动 Flask 应用
    host = os.environ.get('FLASK_HOST') or '0.0.0.0'
    port = int(os.environ.get('FLASK_PORT') or 5000)
    
    # 启动 MQTT 服务
    from app.services.mqtt_service import start_mqtt_service
    start_mqtt_service(app)
    
    print(f"启动服务: http://{host}:{port}")
    # 禁用 reloader 避免 MQTT 重复连接问题
    # 如果需要热重载，请手动重启服务
    app.run(host=host, port=port, debug=app.config['DEBUG'], threaded=True, use_reloader=False)
