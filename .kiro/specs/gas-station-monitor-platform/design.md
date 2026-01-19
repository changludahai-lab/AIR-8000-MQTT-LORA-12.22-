# 设计文档

## 概述

本设计文档描述加油站液位监控 WEB 管理平台的技术架构和实现方案。平台采用 Flask 后端 + Vue3 前端的架构，使用 MySQL 数据库存储数据，通过 MQTT 实现设备间消息转发。

## 系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                         用户浏览器                               │
│                    Vue3 + Element Plus                          │
└─────────────────────────────┬───────────────────────────────────┘
                              │ HTTP/JSON API
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Flask 后端                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │  API 路由   │  │  JWT 认证   │  │  静态文件服务(Vue dist) │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ SQLAlchemy  │  │ MQTT 客户端 │  │     业务逻辑层          │  │
│  │   ORM       │  │  (paho)     │  │                         │  │
│  └──────┬──────┘  └──────┬──────┘  └─────────────────────────┘  │
└─────────┼────────────────┼──────────────────────────────────────┘
          │                │
          ▼                ▼
┌─────────────────┐  ┌─────────────────┐
│  MySQL 数据库   │  │  MQTT Broker    │
│                 │  │ 47.104.166.179  │
└─────────────────┘  └────────┬────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
         ┌─────────┐    ┌─────────┐    ┌─────────┐
         │ 室内机  │    │ 室外机1 │    │ 室外机N │
         │AIR8000  │    │AIR780EPM│    │AIR780EPM│
         └─────────┘    └─────────┘    └─────────┘
```

## 组件和接口

### 后端组件

#### 1. Flask 应用主体 (app.py)

负责初始化应用、注册蓝图、配置数据库和启动 MQTT 服务。

```python
# 伪代码
app = Flask(__name__)
app.config.from_object(Config)
db.init_app(app)
jwt.init_app(app)

# 注册 API 蓝图
app.register_blueprint(auth_bp, url_prefix='/api/auth')
app.register_blueprint(user_bp, url_prefix='/api/users')
app.register_blueprint(station_bp, url_prefix='/api/stations')
app.register_blueprint(device_bp, url_prefix='/api/devices')
app.register_blueprint(alarm_bp, url_prefix='/api/alarms')

# 托管前端静态文件
@app.route('/')
def index():
    return send_from_directory('static', 'index.html')
```

#### 2. 数据模型 (models.py)

使用 SQLAlchemy ORM 定义数据模型。

#### 3. API 蓝图

| 蓝图 | 路径前缀 | 功能 |
|------|---------|------|
| auth_bp | /api/auth | 登录、登出、获取当前用户 |
| user_bp | /api/users | 用户增删改查 |
| station_bp | /api/stations | 加油站增删改查 |
| device_bp | /api/devices | 设备查询、绑定、解绑 |
| alarm_bp | /api/alarms | 报警日志查询 |

#### 4. MQTT 转发服务 (mqtt_service.py)

后台线程运行，负责订阅设备消息并根据绑定关系转发。

### 前端组件

#### 1. 页面结构

| 页面 | 路由 | 功能 |
|------|------|------|
| 登录页 | /login | 用户登录 |
| 首页/仪表盘 | / | 概览信息 |
| 用户管理 | /users | 用户增删改查（仅超级管理员可见） |
| 加油站管理 | /stations | 加油站增删改查 |
| 设备管理 | /devices | 设备列表、绑定、解绑 |
| 设备监控 | /monitor | 设备在线状态实时监控 |
| 报警日志 | /alarms | 报警历史记录查询 |

#### 2. 组件结构

```
src/
├── views/           # 页面组件
│   ├── Login.vue
│   ├── Dashboard.vue
│   ├── Users.vue
│   ├── Stations.vue
│   ├── Devices.vue
│   ├── Monitor.vue
│   └── Alarms.vue
├── components/      # 通用组件
│   ├── Sidebar.vue
│   └── Header.vue
├── api/             # API 调用封装
│   └── index.js
├── router/          # 路由配置
│   └── index.js
├── store/           # 状态管理
│   └── index.js
└── App.vue
```

### API 接口设计

#### 认证接口

| 方法 | 路径 | 功能 | 请求体 | 响应 |
|------|------|------|--------|------|
| POST | /api/auth/login | 登录 | {username, password} | {token, user} |
| POST | /api/auth/logout | 登出 | - | {message} |
| GET | /api/auth/me | 获取当前用户 | - | {user} |

#### 用户接口

| 方法 | 路径 | 功能 | 权限 |
|------|------|------|------|
| GET | /api/users | 获取用户列表 | 超级管理员 |
| POST | /api/users | 创建用户 | 超级管理员 |
| PUT | /api/users/{id} | 更新用户 | 超级管理员 |
| DELETE | /api/users/{id} | 删除用户 | 超级管理员 |

#### 加油站接口

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | /api/stations | 获取加油站列表（支持分页、搜索） |
| POST | /api/stations | 创建加油站 |
| GET | /api/stations/{id} | 获取加油站详情（含设备列表） |
| PUT | /api/stations/{id} | 更新加油站 |
| DELETE | /api/stations/{id} | 删除加油站 |

#### 设备接口

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | /api/devices | 获取设备列表（支持筛选、搜索） |
| GET | /api/devices/{imei} | 获取设备详情 |
| POST | /api/devices/{imei}/bind | 绑定设备到加油站 |
| POST | /api/devices/{imei}/unbind | 解绑设备 |

#### 报警日志接口

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | /api/alarms | 获取报警日志（支持筛选、搜索、分页） |

## 数据模型

### 用户表 (users)

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT | 主键，自增 |
| username | VARCHAR(50) | 用户名，唯一 |
| password_hash | VARCHAR(255) | 密码哈希 |
| role | ENUM('admin', 'user') | 角色 |
| status | TINYINT | 状态：1启用，0禁用 |
| created_at | DATETIME | 创建时间 |
| updated_at | DATETIME | 更新时间 |

### 加油站表 (stations)

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT | 主键，自增 |
| name | VARCHAR(100) | 加油站名称 |
| code | VARCHAR(50) | 加油站编号，唯一 |
| address | VARCHAR(255) | 地址 |
| contact | VARCHAR(50) | 联系人 |
| phone | VARCHAR(20) | 联系电话 |
| status | TINYINT | 状态：1启用，0禁用 |
| created_at | DATETIME | 创建时间 |
| updated_at | DATETIME | 更新时间 |

### 设备表 (devices)

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT | 主键，自增 |
| imei | VARCHAR(20) | IMEI，唯一 |
| type | ENUM('indoor', 'outdoor') | 设备类型 |
| name | VARCHAR(100) | 设备名称/备注 |
| station_id | INT | 绑定的加油站ID，可为空 |
| online | TINYINT | 在线状态：1在线，0离线 |
| last_seen | DATETIME | 最后在线时间 |
| vbat | INT | 电池电压（mV），室外机专用 |
| created_at | DATETIME | 创建时间 |
| updated_at | DATETIME | 更新时间 |

### 报警日志表 (alarm_logs)

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT | 主键，自增 |
| station_id | INT | 加油站ID |
| indoor_imei | VARCHAR(20) | 室内机IMEI |
| alarm_type | ENUM('alarm', 'cancel') | 报警类型 |
| outdoor_imeis | TEXT | 转发的室外机IMEI列表（JSON数组） |
| forward_status | TINYINT | 转发状态：1成功，0失败 |
| created_at | DATETIME | 创建时间 |

### 用户-加油站关联表 (user_stations)

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT | 主键，自增 |
| user_id | INT | 用户ID |
| station_id | INT | 加油站ID |

## MQTT 转发逻辑

### 消息流程

```
室内机发送报警:
/AIR8000/PUB/{室内机IMEI} → {"bj": 1}
    │
    ▼
MQTT转发服务接收
    │
    ▼
查询室内机绑定的加油站
    │
    ▼
查询该加油站所有室外机
    │
    ▼
转发到每个室外机:
/780EHV/SUB/{室外机IMEI} → {"bj": 1}
    │
    ▼
记录报警日志
```

### 转发服务伪代码

```python
def on_message(client, userdata, msg):
    topic = msg.topic
    payload = msg.payload.decode('utf-8')
    
    if topic.startswith('/AIR8000/PUB/'):
        # 室内机消息
        imei = topic.split('/')[-1]
        handle_indoor_message(imei, payload)
    elif topic.startswith('/780EHV/PUB/'):
        # 室外机消息
        imei = topic.split('/')[-1]
        handle_outdoor_message(imei, payload)

def handle_indoor_message(imei, payload):
    # 更新设备在线状态
    update_device_status(imei, 'indoor')
    
    # 解析消息
    data = json.loads(payload)
    
    # 查询绑定关系
    device = Device.query.filter_by(imei=imei).first()
    if not device or not device.station_id:
        return
    
    # 获取同站室外机
    outdoor_devices = Device.query.filter_by(
        station_id=device.station_id,
        type='outdoor'
    ).all()
    
    # 转发消息
    for outdoor in outdoor_devices:
        target_topic = f'/780EHV/SUB/{outdoor.imei}'
        client.publish(target_topic, payload)
    
    # 记录报警日志（如果是报警消息）
    if 'bj' in data:
        log_alarm(device.station_id, imei, data['bj'], outdoor_devices)
```

## 错误处理

### API 错误响应格式

```json
{
    "code": 400,
    "message": "错误描述",
    "data": null
}
```

### 错误码定义

| 错误码 | 说明 |
|--------|------|
| 200 | 成功 |
| 400 | 请求参数错误 |
| 401 | 未认证 |
| 403 | 无权限 |
| 404 | 资源不存在 |
| 409 | 资源冲突（如重复绑定） |
| 500 | 服务器内部错误 |

## 正确性属性

正确性属性是系统在所有有效执行中都应保持为真的特征或行为。属性作为人类可读规范和机器可验证正确性保证之间的桥梁。

### 属性 1：认证令牌有效性

*对于任意*有效的用户凭证（用户名和密码），登录后返回的 JWT 令牌应能成功通过验证并获取用户信息。

**验证需求: 1.2**

### 属性 2：无效凭证拒绝

*对于任意*无效的用户凭证（错误的用户名或密码），登录请求应返回认证失败错误。

**验证需求: 1.3**

### 属性 3：用户数据持久化

*对于任意*用户数据，创建用户后查询应返回相同的数据；更新用户后查询应返回更新后的数据；删除用户后查询应返回空。

**验证需求: 2.2, 2.3, 2.4**

### 属性 4：角色权限控制

*对于任意*普通用户，访问用户管理 API 应返回 403 权限拒绝错误。

**验证需求: 2.5, 2.6**

### 属性 5：加油站数据持久化

*对于任意*加油站数据，创建后查询应返回相同的数据；更新后查询应返回更新后的数据。

**验证需求: 3.2, 3.3**

### 属性 6：加油站删除保护

*对于任意*有绑定设备的加油站，删除请求应返回冲突错误并保留加油站数据。

**验证需求: 3.4**

### 属性 7：加油站搜索准确性

*对于任意*搜索关键词，搜索结果中的所有加油站的名称或编号应包含该关键词。

**验证需求: 3.5**

### 属性 8：设备自动注册

*对于任意* IMEI 的首次 MQTT 消息，系统应自动创建该设备记录，且设备 IMEI 与消息来源一致。

**验证需求: 4.1**

### 属性 9：室内机绑定唯一性

*对于任意*已有室内机的加油站，再次绑定室内机应返回冲突错误。

**验证需求: 4.4**

### 属性 10：室外机绑定无限制

*对于任意*加油站，可以绑定任意数量的室外机，所有绑定请求都应成功。

**验证需求: 4.5**

### 属性 11：设备解绑有效性

*对于任意*已绑定的设备，解绑后该设备的 station_id 应为空。

**验证需求: 4.6**

### 属性 12：设备在线时间更新

*对于任意*设备的 MQTT 消息，该设备的 last_seen 时间应更新为当前时间。

**验证需求: 5.1**

### 属性 13：离线状态判定

*对于任意* last_seen 超过 13 小时的设备，其在线状态应为离线。

**验证需求: 5.2**

### 属性 14：消息转发完整性

*对于任意*已绑定加油站的室内机报警消息，该加油站所有室外机都应收到转发消息；*对于任意*已绑定加油站的室外机状态消息，该加油站的室内机应收到转发消息。

**验证需求: 6.1, 6.2**

### 属性 15：未绑定设备消息忽略

*对于任意*未绑定加油站的设备消息，不应产生任何转发。

**验证需求: 6.3**

### 属性 16：报警日志记录完整性

*对于任意*室内机的报警或取消消息，应创建包含完整信息的日志记录（时间、加油站、IMEI、类型、转发列表、状态）。

**验证需求: 7.1, 7.2, 7.3**

### 属性 17：日志时间排序

*对于任意*报警日志查询结果，日志应按创建时间倒序排列。

**验证需求: 7.4**

## 测试策略

### 单元测试

- 测试数据模型的 CRUD 操作
- 测试 API 接口的请求和响应
- 测试 JWT 认证逻辑
- 测试 MQTT 消息转发逻辑

### 属性测试

使用 Hypothesis 库进行属性测试，每个属性测试至少运行 100 次迭代：

- 属性 1-4：认证和权限相关属性
- 属性 5-7：加油站管理相关属性
- 属性 8-13：设备管理相关属性
- 属性 14-17：消息转发和日志相关属性

### 集成测试

- 测试完整的登录流程
- 测试设备绑定和消息转发流程
- 测试报警日志记录流程

