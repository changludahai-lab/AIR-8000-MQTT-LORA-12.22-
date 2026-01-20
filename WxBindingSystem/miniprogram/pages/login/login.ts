/**
 * 登录页
 * 关联需求: REQ-1 用户登录
 * 
 * 功能:
 * - 用户名、密码输入
 * - 调用 /api/auth/login 接口进行认证
 * - 登录成功保存token到本地存储
 * - 登录失败显示错误提示
 * - 登录成功跳转到加油站列表
 */
import { login } from '../../utils/api'

const app = getApp<IAppOption>()

Page({
  data: {
    username: '',
    password: '',
    loading: false
  },

  /**
   * 页面加载时检查是否已登录
   */
  onLoad() {
    // 如果已登录，直接跳转到首页
    if (app.checkLogin()) {
      wx.switchTab({ url: '/pages/stations/stations' })
    }
  },

  /**
   * 输入用户名
   */
  onUsernameInput(e: WechatMiniprogram.Input) {
    this.setData({ username: e.detail.value })
  },

  /**
   * 输入密码
   */
  onPasswordInput(e: WechatMiniprogram.Input) {
    this.setData({ password: e.detail.value })
  },

  /**
   * 执行登录
   * - 验证输入
   * - 调用登录API
   * - 处理成功/失败响应
   */
  async onLogin() {
    const { username, password } = this.data

    // 表单验证
    if (!username.trim()) {
      wx.showToast({ title: '请输入用户名', icon: 'none' })
      return
    }

    if (!password) {
      wx.showToast({ title: '请输入密码', icon: 'none' })
      return
    }

    this.setData({ loading: true })

    try {
      const res = await login(username, password)
      
      // 登录成功 (code === 0 或 200 表示成功)
      if (res.code === 0 || res.code === 200) {
        // 保存登录信息到本地存储
        app.setLoginInfo(res.data.token, res.data.user)
        
        wx.showToast({ title: '登录成功', icon: 'success' })
        
        // 跳转到加油站列表页
        setTimeout(() => {
          wx.switchTab({ url: '/pages/stations/stations' })
        }, 1000)
      } else {
        // 登录失败，显示服务器返回的错误信息
        this.showLoginError(res.message || '登录失败')
      }
    } catch (err: any) {
      console.error('登录失败:', err)
      // 显示错误提示
      this.showLoginError(err.message || '登录失败，请检查网络')
    } finally {
      this.setData({ loading: false })
    }
  },

  /**
   * 显示登录错误提示
   * 根据错误类型显示不同的提示信息
   */
  showLoginError(message: string) {
    // 常见错误信息映射
    let displayMessage = message
    
    if (message.includes('用户名或密码') || message.includes('password') || message.includes('username')) {
      displayMessage = '用户名或密码错误'
    } else if (message.includes('禁用') || message.includes('disabled') || message.includes('locked')) {
      displayMessage = '账号已被禁用'
    } else if (message.includes('网络') || message.includes('network')) {
      displayMessage = '网络连接失败，请检查网络'
    }
    
    wx.showToast({
      title: displayMessage,
      icon: 'none',
      duration: 2500
    })
  }
})
