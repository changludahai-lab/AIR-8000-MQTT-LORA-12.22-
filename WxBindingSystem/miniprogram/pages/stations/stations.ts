// 加油站列表页
import { getStations, Station } from '../../utils/api'

const app = getApp<IAppOption>()

Page({
  data: {
    stations: [] as Station[],
    loading: false,
    refreshing: false
  },

  onLoad() {
    this.checkLogin()
  },

  onShow() {
    if (app.checkLogin()) {
      this.loadStations()
    }
  },

  // 检查登录状态
  checkLogin() {
    if (!app.checkLogin()) {
      wx.redirectTo({ url: '/pages/login/login' })
    }
  },

  // 加载加油站列表
  async loadStations() {
    this.setData({ loading: true })

    try {
      const res = await getStations({ per_page: 100 })
      if (res.code === 200) {
        this.setData({ stations: res.data.items })
      }
    } catch (err) {
      console.error('加载加油站失败:', err)
    } finally {
      this.setData({ loading: false, refreshing: false })
    }
  },

  // 下拉刷新
  onPullDownRefresh() {
    this.setData({ refreshing: true })
    this.loadStations().then(() => {
      wx.stopPullDownRefresh()
    })
  },

  // 新建加油站
  onAddStation() {
    wx.navigateTo({ url: '/pages/stations/add/add' })
  },

  // 进入加油站详情
  onStationTap(e: any) {
    const id = e.currentTarget.dataset.id
    wx.navigateTo({ url: `/pages/stations/detail/detail?id=${id}` })
  }
})
