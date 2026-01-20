// app.ts

// 不需要登录验证的页面白名单
const WHITE_LIST = [
  'pages/login/login'
]

App<IAppOption>({
  globalData: {
    userInfo: null,
    token: ''
  },
  
  onLaunch() {
    // 检查登录状态
    const token = wx.getStorageSync('token')
    const userInfo = wx.getStorageSync('userInfo')
    
    if (token && userInfo) {
      this.globalData.token = token
      this.globalData.userInfo = userInfo
    }
    
    // 监听页面切换，进行登录检查
    this.setupPageInterceptor()
  },
  
  // 设置页面拦截器
  setupPageInterceptor() {
    const app = this
    
    // 重写 wx.switchTab
    const originalSwitchTab = wx.switchTab
    Object.defineProperty(wx, 'switchTab', {
      configurable: true,
      enumerable: true,
      writable: true,
      value(options: WechatMiniprogram.SwitchTabOption) {
        if (!app.checkLogin()) {
          app.goLogin()
          return
        }
        return originalSwitchTab.call(this, options)
      }
    })
  },
  
  // 检查是否已登录
  checkLogin(): boolean {
    return !!this.globalData.token
  },
  
  // 检查页面是否需要登录
  checkPageAuth(pagePath: string): boolean {
    // 白名单页面不需要登录
    if (WHITE_LIST.some(path => pagePath.includes(path))) {
      return true
    }
    
    // 其他页面需要登录
    if (!this.checkLogin()) {
      this.goLogin()
      return false
    }
    
    return true
  },
  
  // 跳转到登录页
  goLogin() {
    wx.reLaunch({
      url: '/pages/login/login'
    })
  },
  
  // 设置登录信息
  setLoginInfo(token: string, userInfo: IUserInfo) {
    this.globalData.token = token
    this.globalData.userInfo = userInfo
    wx.setStorageSync('token', token)
    wx.setStorageSync('userInfo', userInfo)
  },
  
  // 清除登录信息
  clearLoginInfo() {
    this.globalData.token = ''
    this.globalData.userInfo = null
    wx.removeStorageSync('token')
    wx.removeStorageSync('userInfo')
  },
  
  // 获取用户信息
  getUserInfo(): IUserInfo | null {
    return this.globalData.userInfo
  },
  
  // 获取 token
  getToken(): string {
    return this.globalData.token
  }
})
