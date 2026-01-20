// 设备列表页
import { getDevices, Device } from '../../utils/api'

const app = getApp<IAppOption>()

Page({
  data: {
    devices: [] as Device[],
    loading: false,
    filterType: '' // 筛选类型: '', 'indoor', 'outdoor'
  },

  onLoad() {
    this.checkLogin()
  },

  onShow() {
    if (app.checkLogin()) {
      this.loadDevices()
    }
  },

  checkLogin() {
    if (!app.checkLogin()) {
      wx.redirectTo({ url: '/pages/login/login' })
    }
  },

  async loadDevices() {
    this.setData({ loading: true })

    try {
      const params: any = { per_page: 200 }
      if (this.data.filterType) {
        params.type = this.data.filterType
      }

      const res = await getDevices(params)
      if (res.code === 200) {
        this.setData({ devices: res.data.items })
      }
    } catch (err) {
      console.error('加载设备失败:', err)
    } finally {
      this.setData({ loading: false })
    }
  },

  onPullDownRefresh() {
    this.loadDevices().then(() => {
      wx.stopPullDownRefresh()
    })
  },

  // 筛选类型
  onFilterChange(e: any) {
    const type = e.currentTarget.dataset.type
    this.setData({ filterType: type === this.data.filterType ? '' : type })
    this.loadDevices()
  },

  // 添加设备
  onAddDevice() {
    wx.navigateTo({ url: '/pages/devices/add/add' })
  }
})
