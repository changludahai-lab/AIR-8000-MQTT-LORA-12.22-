"""
应用配置文件
"""
import os
from datetime import timedelta


class Config:
    """基础配置"""
    # Flask 配置
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'gas-station-monitor-secret-key-2024'
    
    # 数据库配置
    MYSQL_HOST = os.environ.get('MYSQL_HOST') or '47.104.166.179'
    MYSQL_PORT = os.environ.get('MYSQL_PORT') or '16768'
    MYSQL_USER = os.environ.get('MYSQL_USER') or 'snsy_alarm'
    MYSQL_PASSWORD = os.environ.get('MYSQL_PASSWORD') or 'BT3GYBXJFsaeyRzX'
    MYSQL_DATABASE = os.environ.get('MYSQL_DATABASE') or 'snsy_alarm'
    
    SQLALCHEMY_DATABASE_URI = (
        f"mysql+pymysql://{MYSQL_USER}:{MYSQL_PASSWORD}@{MYSQL_HOST}:{MYSQL_PORT}/{MYSQL_DATABASE}?charset=utf8mb4"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ECHO = False  # 设为 True 可打印 SQL 语句
    
    # JWT 配置
    JWT_SECRET_KEY = os.environ.get('JWT_SECRET_KEY') or 'jwt-secret-key-2024'
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(hours=24)
    JWT_TOKEN_LOCATION = ['headers']
    JWT_HEADER_NAME = 'Authorization'
    JWT_HEADER_TYPE = 'Bearer'
    
    # MQTT 配置
    MQTT_BROKER_HOST = os.environ.get('MQTT_BROKER_HOST') or '47.104.166.179'
    MQTT_BROKER_PORT = int(os.environ.get('MQTT_BROKER_PORT') or '1883')
    MQTT_USERNAME = os.environ.get('MQTT_USERNAME') or 'mqtt_user'
    MQTT_PASSWORD = os.environ.get('MQTT_PASSWORD') or 'mqtt_password'
    
    # MQTT Topic 前缀
    INDOOR_PUB_PREFIX = '/AIR8000/PUB/'
    INDOOR_SUB_PREFIX = '/AIR8000/SUB/'
    OUTDOOR_PUB_PREFIX = '/780EHV/PUB/'
    OUTDOOR_SUB_PREFIX = '/780EHV/SUB/'
    
    # 设备离线判定时间（小时）
    DEVICE_OFFLINE_HOURS = 13
    
    # 默认管理员账号
    DEFAULT_ADMIN_USERNAME = 'admin'
    DEFAULT_ADMIN_PASSWORD = 'admin123'


class DevelopmentConfig(Config):
    """开发环境配置"""
    DEBUG = True
    SQLALCHEMY_ECHO = True


class ProductionConfig(Config):
    """生产环境配置"""
    DEBUG = False


class TestingConfig(Config):
    """测试环境配置"""
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'


# 配置映射
config_map = {
    'development': DevelopmentConfig,
    'production': ProductionConfig,
    'testing': TestingConfig,
    'default': DevelopmentConfig
}
