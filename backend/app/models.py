"""
数据模型定义
"""
from datetime import datetime
from app import db
import bcrypt
import json


# 用户-加油站关联表
user_stations = db.Table(
    'user_stations',
    db.Column('id', db.Integer, primary_key=True),
    db.Column('user_id', db.Integer, db.ForeignKey('users.id'), nullable=False),
    db.Column('station_id', db.Integer, db.ForeignKey('stations.id'), nullable=False)
)


class User(db.Model):
    """用户模型"""
    __tablename__ = 'users'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    username = db.Column(db.String(50), unique=True, nullable=False, comment='用户名')
    password_hash = db.Column(db.String(255), nullable=False, comment='密码哈希')
    role = db.Column(db.Enum('admin', 'user'), default='user', comment='角色')
    status = db.Column(db.SmallInteger, default=1, comment='状态：1启用，0禁用')
    created_at = db.Column(db.DateTime, default=datetime.now, comment='创建时间')
    updated_at = db.Column(db.DateTime, default=datetime.now, onupdate=datetime.now, comment='更新时间')
    
    # 关联的加油站
    stations = db.relationship('Station', secondary=user_stations, backref='users')
    
    def set_password(self, password):
        """设置密码"""
        self.password_hash = bcrypt.hashpw(
            password.encode('utf-8'),
            bcrypt.gensalt()
        ).decode('utf-8')
    
    def check_password(self, password):
        """验证密码"""
        return bcrypt.checkpw(
            password.encode('utf-8'),
            self.password_hash.encode('utf-8')
        )
    
    def to_dict(self):
        """转换为字典"""
        return {
            'id': self.id,
            'username': self.username,
            'role': self.role,
            'status': self.status,
            'created_at': self.created_at.strftime('%Y-%m-%d %H:%M:%S') if self.created_at else None,
            'updated_at': self.updated_at.strftime('%Y-%m-%d %H:%M:%S') if self.updated_at else None
        }


class Station(db.Model):
    """加油站模型"""
    __tablename__ = 'stations'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name = db.Column(db.String(100), nullable=False, comment='加油站名称')
    code = db.Column(db.String(50), unique=True, nullable=False, comment='加油站编号')
    address = db.Column(db.String(255), default='', comment='地址')
    contact = db.Column(db.String(50), default='', comment='联系人')
    phone = db.Column(db.String(20), default='', comment='联系电话')
    status = db.Column(db.SmallInteger, default=1, comment='状态：1启用，0禁用')
    created_at = db.Column(db.DateTime, default=datetime.now, comment='创建时间')
    updated_at = db.Column(db.DateTime, default=datetime.now, onupdate=datetime.now, comment='更新时间')
    
    # 关联的设备
    devices = db.relationship('Device', backref='station', lazy='dynamic')
    
    def to_dict(self):
        """转换为字典"""
        return {
            'id': self.id,
            'name': self.name,
            'code': self.code,
            'address': self.address,
            'contact': self.contact,
            'phone': self.phone,
            'status': self.status,
            'created_at': self.created_at.strftime('%Y-%m-%d %H:%M:%S') if self.created_at else None,
            'updated_at': self.updated_at.strftime('%Y-%m-%d %H:%M:%S') if self.updated_at else None
        }


class Device(db.Model):
    """设备模型"""
    __tablename__ = 'devices'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    imei = db.Column(db.String(20), unique=True, nullable=False, comment='IMEI')
    type = db.Column(db.Enum('indoor', 'outdoor'), nullable=False, comment='设备类型')
    name = db.Column(db.String(100), default='', comment='设备名称/备注')
    station_id = db.Column(db.Integer, db.ForeignKey('stations.id'), nullable=True, comment='绑定的加油站ID')
    last_seen = db.Column(db.DateTime, nullable=True, comment='最后在线时间')
    vbat = db.Column(db.Float, nullable=True, comment='电池电压（V）')
    created_at = db.Column(db.DateTime, default=datetime.now, comment='创建时间')
    updated_at = db.Column(db.DateTime, default=datetime.now, onupdate=datetime.now, comment='更新时间')
    
    def to_dict(self):
        """转换为字典"""
        return {
            'id': self.id,
            'imei': self.imei,
            'type': self.type,
            'name': self.name,
            'station_id': self.station_id,
            'station_name': self.station.name if self.station else None,
            'last_seen': self.last_seen.strftime('%Y-%m-%d %H:%M:%S') if self.last_seen else None,
            'vbat': self.vbat,
            'created_at': self.created_at.strftime('%Y-%m-%d %H:%M:%S') if self.created_at else None,
            'updated_at': self.updated_at.strftime('%Y-%m-%d %H:%M:%S') if self.updated_at else None
        }


class AlarmLog(db.Model):
    """报警日志模型"""
    __tablename__ = 'alarm_logs'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    station_id = db.Column(db.Integer, db.ForeignKey('stations.id'), nullable=True, comment='加油站ID')
    indoor_imei = db.Column(db.String(20), nullable=False, comment='室内机IMEI')
    alarm_type = db.Column(db.Enum('alarm', 'cancel'), nullable=False, comment='报警类型')
    outdoor_imeis = db.Column(db.Text, default='[]', comment='转发的室外机IMEI列表（JSON数组）')
    forward_status = db.Column(db.SmallInteger, default=1, comment='转发状态：1成功，0失败')
    created_at = db.Column(db.DateTime, default=datetime.now, comment='创建时间')
    
    # 关联加油站
    station = db.relationship('Station', backref='alarm_logs')
    
    def to_dict(self):
        """转换为字典"""
        try:
            outdoor_list = json.loads(self.outdoor_imeis) if self.outdoor_imeis else []
        except:
            outdoor_list = []
        
        return {
            'id': self.id,
            'station_id': self.station_id,
            'station_name': self.station.name if self.station else None,
            'indoor_imei': self.indoor_imei,
            'alarm_type': self.alarm_type,
            'outdoor_imeis': outdoor_list,
            'forward_status': self.forward_status,
            'created_at': self.created_at.strftime('%Y-%m-%d %H:%M:%S') if self.created_at else None
        }


class CommLog(db.Model):
    """通讯记录模型"""
    __tablename__ = 'comm_logs'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    direction = db.Column(db.Enum('receive', 'forward'), nullable=False, comment='方向：receive接收，forward转发')
    source_type = db.Column(db.Enum('indoor', 'outdoor'), nullable=False, comment='来源设备类型')
    source_imei = db.Column(db.String(20), nullable=False, comment='来源设备IMEI')
    target_type = db.Column(db.Enum('indoor', 'outdoor'), nullable=True, comment='目标设备类型')
    target_imei = db.Column(db.String(20), nullable=True, comment='目标设备IMEI')
    topic = db.Column(db.String(100), nullable=False, comment='MQTT主题')
    payload = db.Column(db.Text, nullable=False, comment='原始数据')
    station_id = db.Column(db.Integer, db.ForeignKey('stations.id'), nullable=True, comment='加油站ID')
    created_at = db.Column(db.DateTime, default=datetime.now, comment='创建时间')
    
    # 关联加油站
    station = db.relationship('Station', backref='comm_logs')
    
    def to_dict(self):
        """转换为字典"""
        return {
            'id': self.id,
            'direction': self.direction,
            'source_type': self.source_type,
            'source_imei': self.source_imei,
            'target_type': self.target_type,
            'target_imei': self.target_imei,
            'topic': self.topic,
            'payload': self.payload,
            'station_id': self.station_id,
            'station_name': self.station.name if self.station else None,
            'created_at': self.created_at.strftime('%Y-%m-%d %H:%M:%S') if self.created_at else None
        }
