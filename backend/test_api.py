"""
后端 API 基础功能测试脚本
用于检查点 6 - 验证后端 API 基础功能
"""
import sys
import os

# 添加当前目录到路径
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app import create_app, db
from app.models import User, Station, Device, AlarmLog


def test_database_connection():
    """测试数据库连接"""
    print("=" * 50)
    print("测试 1: 数据库连接")
    print("=" * 50)
    
    app = create_app('development')
    with app.app_context():
        try:
            # 尝试执行简单查询
            result = db.session.execute(db.text('SELECT 1')).fetchone()
            print(f"✓ 数据库连接成功: {result}")
            return True
        except Exception as e:
            print(f"✗ 数据库连接失败: {e}")
            return False


def test_tables_exist():
    """测试数据库表是否存在"""
    print("\n" + "=" * 50)
    print("测试 2: 数据库表结构")
    print("=" * 50)
    
    app = create_app('development')
    with app.app_context():
        try:
            # 检查各表是否存在
            tables = ['users', 'stations', 'devices', 'alarm_logs', 'user_stations']
            for table in tables:
                result = db.session.execute(
                    db.text(f"SHOW TABLES LIKE '{table}'")
                ).fetchone()
                if result:
                    print(f"✓ 表 {table} 存在")
                else:
                    print(f"✗ 表 {table} 不存在")
                    return False
            return True
        except Exception as e:
            print(f"✗ 检查表结构失败: {e}")
            return False


def test_default_admin():
    """测试默认管理员是否创建"""
    print("\n" + "=" * 50)
    print("测试 3: 默认管理员账号")
    print("=" * 50)
    
    app = create_app('development')
    with app.app_context():
        try:
            admin = User.query.filter_by(username='admin').first()
            if admin:
                print(f"✓ 默认管理员存在: {admin.username}, 角色: {admin.role}")
                # 验证密码
                if admin.check_password('admin123'):
                    print("✓ 默认密码验证成功")
                    return True
                else:
                    print("✗ 默认密码验证失败")
                    return False
            else:
                print("✗ 默认管理员不存在")
                return False
        except Exception as e:
            print(f"✗ 检查默认管理员失败: {e}")
            return False


def test_auth_api():
    """测试认证 API"""
    print("\n" + "=" * 50)
    print("测试 4: 认证 API")
    print("=" * 50)
    
    app = create_app('development')
    with app.test_client() as client:
        # 测试登录 - 正确凭证
        response = client.post('/api/auth/login', json={
            'username': 'admin',
            'password': 'admin123'
        })
        data = response.get_json()
        
        if response.status_code == 200 and data.get('code') == 200:
            print("✓ 登录成功")
            token = data['data']['token']
            
            # 测试获取当前用户
            response = client.get('/api/auth/me', headers={
                'Authorization': f'Bearer {token}'
            })
            data = response.get_json()
            
            if response.status_code == 200 and data.get('code') == 200:
                print(f"✓ 获取当前用户成功: {data['data']['username']}")
            else:
                print(f"✗ 获取当前用户失败: {data}")
                return False
            
            # 测试登出
            response = client.post('/api/auth/logout', headers={
                'Authorization': f'Bearer {token}'
            })
            data = response.get_json()
            
            if response.status_code == 200 and data.get('code') == 200:
                print("✓ 登出成功")
            else:
                print(f"✗ 登出失败: {data}")
                return False
            
            return True
        else:
            print(f"✗ 登录失败: {data}")
            return False


def test_auth_api_invalid():
    """测试认证 API - 无效凭证"""
    print("\n" + "=" * 50)
    print("测试 5: 认证 API - 无效凭证")
    print("=" * 50)
    
    app = create_app('development')
    with app.test_client() as client:
        # 测试登录 - 错误密码
        response = client.post('/api/auth/login', json={
            'username': 'admin',
            'password': 'wrongpassword'
        })
        data = response.get_json()
        
        if response.status_code == 401 and data.get('code') == 401:
            print("✓ 错误密码正确返回 401")
        else:
            print(f"✗ 错误密码应返回 401: {data}")
            return False
        
        # 测试登录 - 不存在的用户
        response = client.post('/api/auth/login', json={
            'username': 'nonexistent',
            'password': 'password'
        })
        data = response.get_json()
        
        if response.status_code == 401 and data.get('code') == 401:
            print("✓ 不存在用户正确返回 401")
            return True
        else:
            print(f"✗ 不存在用户应返回 401: {data}")
            return False


def test_user_api():
    """测试用户管理 API"""
    print("\n" + "=" * 50)
    print("测试 6: 用户管理 API")
    print("=" * 50)
    
    app = create_app('development')
    with app.test_client() as client:
        # 先登录获取 token
        response = client.post('/api/auth/login', json={
            'username': 'admin',
            'password': 'admin123'
        })
        token = response.get_json()['data']['token']
        headers = {'Authorization': f'Bearer {token}'}
        
        # 获取用户列表
        response = client.get('/api/users', headers=headers)
        data = response.get_json()
        
        if response.status_code == 200 and data.get('code') == 200:
            print(f"✓ 获取用户列表成功，共 {len(data['data'])} 个用户")
        else:
            print(f"✗ 获取用户列表失败: {data}")
            return False
        
        # 创建测试用户
        response = client.post('/api/users', headers=headers, json={
            'username': 'test_user_checkpoint',
            'password': 'test123',
            'role': 'user'
        })
        data = response.get_json()
        
        if response.status_code == 200 and data.get('code') == 200:
            test_user_id = data['data']['id']
            print(f"✓ 创建用户成功: ID={test_user_id}")
        elif data.get('code') == 409:
            # 用户已存在，查找其 ID
            response = client.get('/api/users', headers=headers)
            users = response.get_json()['data']
            test_user = next((u for u in users if u['username'] == 'test_user_checkpoint'), None)
            if test_user:
                test_user_id = test_user['id']
                print(f"✓ 测试用户已存在: ID={test_user_id}")
            else:
                print("✗ 无法找到测试用户")
                return False
        else:
            print(f"✗ 创建用户失败: {data}")
            return False
        
        # 更新用户
        response = client.put(f'/api/users/{test_user_id}', headers=headers, json={
            'role': 'admin'
        })
        data = response.get_json()
        
        if response.status_code == 200 and data.get('code') == 200:
            print(f"✓ 更新用户成功: 角色已改为 {data['data']['role']}")
        else:
            print(f"✗ 更新用户失败: {data}")
            return False
        
        # 删除测试用户
        response = client.delete(f'/api/users/{test_user_id}', headers=headers)
        data = response.get_json()
        
        if response.status_code == 200 and data.get('code') == 200:
            print("✓ 删除用户成功")
            return True
        else:
            print(f"✗ 删除用户失败: {data}")
            return False


def test_station_api():
    """测试加油站管理 API"""
    print("\n" + "=" * 50)
    print("测试 7: 加油站管理 API")
    print("=" * 50)
    
    app = create_app('development')
    with app.test_client() as client:
        # 先登录获取 token
        response = client.post('/api/auth/login', json={
            'username': 'admin',
            'password': 'admin123'
        })
        token = response.get_json()['data']['token']
        headers = {'Authorization': f'Bearer {token}'}
        
        # 获取加油站列表
        response = client.get('/api/stations', headers=headers)
        data = response.get_json()
        
        if response.status_code == 200 and data.get('code') == 200:
            print(f"✓ 获取加油站列表成功，共 {data['data']['total']} 个加油站")
        else:
            print(f"✗ 获取加油站列表失败: {data}")
            return False
        
        # 创建测试加油站
        response = client.post('/api/stations', headers=headers, json={
            'name': '测试加油站_检查点',
            'code': 'TEST_CHECKPOINT_001',
            'address': '测试地址',
            'contact': '测试联系人',
            'phone': '13800138000'
        })
        data = response.get_json()
        
        if response.status_code == 200 and data.get('code') == 200:
            test_station_id = data['data']['id']
            print(f"✓ 创建加油站成功: ID={test_station_id}")
        elif data.get('code') == 409:
            # 加油站已存在，查找其 ID
            response = client.get('/api/stations?search=TEST_CHECKPOINT_001', headers=headers)
            stations = response.get_json()['data']['items']
            if stations:
                test_station_id = stations[0]['id']
                print(f"✓ 测试加油站已存在: ID={test_station_id}")
            else:
                print("✗ 无法找到测试加油站")
                return False
        else:
            print(f"✗ 创建加油站失败: {data}")
            return False
        
        # 获取加油站详情
        response = client.get(f'/api/stations/{test_station_id}', headers=headers)
        data = response.get_json()
        
        if response.status_code == 200 and data.get('code') == 200:
            print(f"✓ 获取加油站详情成功: {data['data']['name']}")
        else:
            print(f"✗ 获取加油站详情失败: {data}")
            return False
        
        # 更新加油站
        response = client.put(f'/api/stations/{test_station_id}', headers=headers, json={
            'address': '更新后的地址'
        })
        data = response.get_json()
        
        if response.status_code == 200 and data.get('code') == 200:
            print(f"✓ 更新加油站成功: 地址已改为 {data['data']['address']}")
        else:
            print(f"✗ 更新加油站失败: {data}")
            return False
        
        # 删除测试加油站
        response = client.delete(f'/api/stations/{test_station_id}', headers=headers)
        data = response.get_json()
        
        if response.status_code == 200 and data.get('code') == 200:
            print("✓ 删除加油站成功")
            return True
        else:
            print(f"✗ 删除加油站失败: {data}")
            return False


def test_device_api():
    """测试设备管理 API"""
    print("\n" + "=" * 50)
    print("测试 8: 设备管理 API")
    print("=" * 50)
    
    app = create_app('development')
    with app.test_client() as client:
        # 先登录获取 token
        response = client.post('/api/auth/login', json={
            'username': 'admin',
            'password': 'admin123'
        })
        token = response.get_json()['data']['token']
        headers = {'Authorization': f'Bearer {token}'}
        
        # 获取设备列表
        response = client.get('/api/devices', headers=headers)
        data = response.get_json()
        
        if response.status_code == 200 and data.get('code') == 200:
            print(f"✓ 获取设备列表成功，共 {data['data']['total']} 个设备")
            return True
        else:
            print(f"✗ 获取设备列表失败: {data}")
            return False


def test_alarm_api():
    """测试报警日志 API"""
    print("\n" + "=" * 50)
    print("测试 9: 报警日志 API")
    print("=" * 50)
    
    app = create_app('development')
    with app.test_client() as client:
        # 先登录获取 token
        response = client.post('/api/auth/login', json={
            'username': 'admin',
            'password': 'admin123'
        })
        token = response.get_json()['data']['token']
        headers = {'Authorization': f'Bearer {token}'}
        
        # 获取报警日志列表
        response = client.get('/api/alarms', headers=headers)
        data = response.get_json()
        
        if response.status_code == 200 and data.get('code') == 200:
            print(f"✓ 获取报警日志列表成功，共 {data['data']['total']} 条记录")
            return True
        else:
            print(f"✗ 获取报警日志列表失败: {data}")
            return False


def test_permission_control():
    """测试权限控制"""
    print("\n" + "=" * 50)
    print("测试 10: 权限控制")
    print("=" * 50)
    
    app = create_app('development')
    with app.test_client() as client:
        # 先用管理员创建一个普通用户
        response = client.post('/api/auth/login', json={
            'username': 'admin',
            'password': 'admin123'
        })
        admin_token = response.get_json()['data']['token']
        admin_headers = {'Authorization': f'Bearer {admin_token}'}
        
        # 创建普通用户
        response = client.post('/api/users', headers=admin_headers, json={
            'username': 'test_normal_user',
            'password': 'test123',
            'role': 'user'
        })
        data = response.get_json()
        
        if data.get('code') == 200:
            test_user_id = data['data']['id']
            print("✓ 创建普通用户成功")
        elif data.get('code') == 409:
            print("✓ 普通用户已存在")
            # 查找用户 ID
            response = client.get('/api/users', headers=admin_headers)
            users = response.get_json()['data']
            test_user = next((u for u in users if u['username'] == 'test_normal_user'), None)
            test_user_id = test_user['id'] if test_user else None
        else:
            print(f"✗ 创建普通用户失败: {data}")
            return False
        
        # 用普通用户登录
        response = client.post('/api/auth/login', json={
            'username': 'test_normal_user',
            'password': 'test123'
        })
        
        if response.status_code != 200:
            print("✗ 普通用户登录失败")
            return False
        
        user_token = response.get_json()['data']['token']
        user_headers = {'Authorization': f'Bearer {user_token}'}
        
        # 普通用户尝试访问用户管理 API
        response = client.get('/api/users', headers=user_headers)
        data = response.get_json()
        
        if response.status_code == 403 and data.get('code') == 403:
            print("✓ 普通用户访问用户管理 API 正确返回 403")
        else:
            print(f"✗ 普通用户访问用户管理 API 应返回 403: {data}")
            # 清理测试用户
            if test_user_id:
                client.delete(f'/api/users/{test_user_id}', headers=admin_headers)
            return False
        
        # 清理测试用户
        if test_user_id:
            response = client.delete(f'/api/users/{test_user_id}', headers=admin_headers)
            if response.get_json().get('code') == 200:
                print("✓ 清理测试用户成功")
        
        return True


def main():
    """运行所有测试"""
    print("\n" + "=" * 60)
    print("  加油站液位监控平台 - 后端 API 基础功能检查点")
    print("=" * 60)
    
    results = []
    
    # 运行所有测试
    results.append(("数据库连接", test_database_connection()))
    results.append(("数据库表结构", test_tables_exist()))
    results.append(("默认管理员账号", test_default_admin()))
    results.append(("认证 API", test_auth_api()))
    results.append(("认证 API - 无效凭证", test_auth_api_invalid()))
    results.append(("用户管理 API", test_user_api()))
    results.append(("加油站管理 API", test_station_api()))
    results.append(("设备管理 API", test_device_api()))
    results.append(("报警日志 API", test_alarm_api()))
    results.append(("权限控制", test_permission_control()))
    
    # 输出总结
    print("\n" + "=" * 60)
    print("  测试结果总结")
    print("=" * 60)
    
    passed = 0
    failed = 0
    
    for name, result in results:
        status = "✓ 通过" if result else "✗ 失败"
        print(f"  {name}: {status}")
        if result:
            passed += 1
        else:
            failed += 1
    
    print("\n" + "-" * 60)
    print(f"  总计: {passed} 通过, {failed} 失败")
    print("=" * 60)
    
    return failed == 0


if __name__ == '__main__':
    success = main()
    sys.exit(0 if success else 1)
