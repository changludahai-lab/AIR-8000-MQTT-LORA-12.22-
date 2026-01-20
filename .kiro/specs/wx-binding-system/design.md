# 微信小程序设备绑定系统 - 设计文档

## 1. 系统架构

```
┌─────────────────┐     HTTPS      ┌─────────────────┐
│   微信小程序     │ ◄────────────► │   Flask 后端    │
│  WxBindingSystem │               │   (已有服务)     │
└─────────────────┘               └─────────────────┘
                                          │
                                          ▼
                                  ┌─────────────────┐
                                  │     MySQL       │
                                  │   (已有数据库)   │
                                  └─────────────────┘
```

## 2. 小程序页面设计

### 2.1 页面列表

| 页面路径 | 页面名称 | 说明 |
|---------|---------|------|
| pages/login/login | 登录页 | 账号密码登录 |
| pages/stations/stations | 加油站列表 | Tab页，显示所有加油站 |
| pages/stations/add/add | 新建加油站 | 录入加油站信息 |
| pages/stations/detail/detail | 加油站详情 | 编辑信息、绑定/解绑设备 |
| pages/devices/devices | 设备列表 | Tab页，显示所有设备 |
| pages/devices/add/add | 添加设备 | 手动输入IMEI添加 |
| pages/profile/profile | 个人中心 | Tab页，账户信息、退出登录 |

### 2.2 TabBar 配置

```json
{
  "tabBar": {
    "list": [
      { "pagePath": "pages/stations/stations", "text": "加油站" },
      { "pagePath": "pages/devices/devices", "text": "设备" },
      { "pagePath": "pages/profile/profile", "text": "我的" }
    ]
  }
}
```

## 3. 数据模型

### 3.1 本地存储

| Key | 类型 | 说明 |
|-----|------|------|
| token | string | JWT认证令牌 |
| userInfo | object | 用户信息 {id, username, role} |

### 3.2 接口数据结构

**加油站 Station**
```typescript
interface Station {
  id: number
  name: string
  code: string
  address: string
  contact: string
  phone: string
  status: number
  created_at: string
  indoor_device?: Device    // 绑定的室内机
  outdoor_devices?: Device[] // 绑定的室外机列表
}
```

**设备 Device**
```typescript
interface Device {
  id: number
  imei: string
  type: 'indoor' | 'outdoor'
  name: string
  station_id: number | null
  station_name: string | null
  last_seen: string | null
  online: boolean
  vbat: number | null  // 室外机电压
}
```

## 4. API 接口设计

### 4.1 复用现有接口

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | /api/auth/login | 登录 |
| GET | /api/auth/me | 获取当前用户 |
| GET | /api/stations | 获取加油站列表 |
| POST | /api/stations | 创建加油站 |
| PUT | /api/stations/:id | 更新加油站 |
| DELETE | /api/stations/:id | 删除加油站 |
| GET | /api/devices | 获取设备列表 |
| POST | /api/devices | 创建设备 |
| POST | /api/devices/:imei/bind | 绑定设备 |
| POST | /api/devices/:imei/unbind | 解绑设备 |

### 4.2 需新增接口

**GET /api/stations/:id**

获取单个加油站详情，包含已绑定设备列表。

响应示例：
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 1,
    "name": "测试加油站",
    "code": "GS001",
    "address": "xxx",
    "contact": "张三",
    "phone": "13800138000",
    "indoor_device": {
      "imei": "123456789",
      "online": true,
      "last_seen": "2026-01-10 12:00:00"
    },
    "outdoor_devices": [
      {
        "imei": "987654321",
        "online": false,
        "last_seen": "2026-01-09 10:00:00",
        "vbat": 3.8
      }
    ]
  }
}
```

## 5. 小程序工具模块

### 5.1 请求封装 (utils/request.ts)

- 统一添加 Authorization 请求头
- 统一处理响应错误
- 401 错误自动跳转登录页

### 5.2 API 模块 (utils/api.ts)

- 封装所有后端接口调用
- 提供类型定义

## 6. 页面交互流程

### 6.1 登录流程
```
登录页 → 输入账号密码 → 调用登录API → 保存token → 跳转加油站列表
```

### 6.2 扫码绑定流程
```
加油站详情 → 点击扫码绑定 → 调用wx.scanCode → 获取IMEI 
→ 调用绑定API（设备不存在则自动创建） → 刷新设备列表
```

### 6.3 解绑流程
```
加油站详情 → 点击解绑 → 确认弹窗 → 调用解绑API → 刷新设备列表
```

## 7. 错误处理

| 错误码 | 说明 | 处理方式 |
|--------|------|----------|
| 401 | 未登录/token过期 | 跳转登录页 |
| 400 | 请求参数错误 | 显示错误提示 |
| 404 | 资源不存在 | 显示错误提示 |
| 500 | 服务器错误 | 显示"服务器繁忙" |
