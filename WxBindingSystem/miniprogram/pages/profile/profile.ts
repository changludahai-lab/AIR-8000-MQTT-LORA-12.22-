// 个人中心页
const app = getApp<IAppOption>()

Page({
  data: {
    userInfo: null as any
  },

  onLoad() {
    this.checkLogin()
  },

  onShow() {
    this.loadUserInfo()
  },

  checkLogin() {
    if (!app.checkLogin()) {
      wx.redirectTo({ url: '/pages/login/login' })
    }
  },

  loadUserInfo() {
    const userInfo = wx.getStorageSync('userInfo')
    this.setData({ userInfo })
  },

  // 退出登录
  onLogout() {
    wx.showModal({
      title: '确认退出',
      content: '确定要退出登录吗？',
      success: (res) => {
        if (res.confirm) {
          app.clearLoginInfo()
          wx.reLaunch({ url: '/pages/login/login' })
        }
      }
    })
  }
})
