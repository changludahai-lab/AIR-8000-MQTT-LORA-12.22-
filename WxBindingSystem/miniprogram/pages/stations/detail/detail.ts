// 加油站详情页
// REQ-4: 编辑加油站信息（名称、编号、地址、联系人、电话）
// REQ-5: 删除加油站（需二次确认，检查绑定设备）
// REQ-6: 扫码绑定室内机（每站限1台）
// REQ-7: 扫码绑定室外机（可多台）
// REQ-8: 设备解绑（需二次确认）
import { getStation, updateStation, deleteStation, bindDevice, unbindDevice, createDevice, Station } from '../../../utils/api'

Page({
  data: {
    id: 0,
    station: null as Station | null,
    loading: false,
    editing: false,
    saving: false,
    // 编辑表单
    form: {
      name: '',
      code: '',
      address: '',
      contact: '',
      phone: ''
    }
  },

  onLoad(options: any) {
    if (options.id) {
      this.setData({ id: parseInt(options.id) })
    } else {
      wx.showToast({ title: '参数错误', icon: 'none' })
      setTimeout(() => wx.navigateBack(), 1500)
    }
  },

  onShow() {
    if (this.data.id) {
      this.loadStation()
    }
  },

  // 加载加油站详情
  async loadStation() {
    this.setData({ loading: true })

    try {
      const res = await getStation(this.data.id)
      if (res.code === 200) {
        this.setData({ 
          station: res.data,
          form: {
            name: res.data.name || '',
            code: res.data.code || '',
            address: res.data.address || '',
            contact: res.data.contact || '',
            phone: res.data.phone || ''
          }
        })
      }
    } catch (err) {
      console.error('加载失败:', err)
      wx.showToast({ title: '加载失败', icon: 'none' })
    } finally {
      this.setData({ loading: false })
    }
  },

  // 切换编辑模式
  toggleEdit() {
    const { editing, station } = this.data
    if (editing) {
      // 取消编辑时恢复原始数据
      this.setData({ 
        editing: false,
        form: {
          name: (station && station.name) || '',
          code: (station && station.code) || '',
          address: (station && station.address) || '',
          contact: (station && station.contact) || '',
          phone: (station && station.phone) || ''
        }
      })
    } else {
      this.setData({ editing: true })
    }
  },

  // 表单输入
  onInput(e: any) {
    const field = e.currentTarget.dataset.field
    this.setData({ [`form.${field}`]: e.detail.value })
  },

  // 保存修改 (REQ-4)
  async onSave() {
    const { form, id, saving } = this.data

    if (saving) return

    // 表单验证 - 名称和编号为必填
    if (!form.name.trim()) {
      wx.showToast({ title: '请输入加油站名称', icon: 'none' })
      return
    }

    if (!form.code.trim()) {
      wx.showToast({ title: '请输入加油站编号', icon: 'none' })
      return
    }

    this.setData({ saving: true })

    try {
      const res = await updateStation(id, {
        name: form.name.trim(),
        code: form.code.trim(),
        address: form.address.trim(),
        contact: form.contact.trim(),
        phone: form.phone.trim()
      })
      if (res.code === 200) {
        wx.showToast({ title: '保存成功', icon: 'success' })
        this.setData({ editing: false })
        this.loadStation()
      }
    } catch (err) {
      console.error('保存失败:', err)
    } finally {
      this.setData({ saving: false })
    }
  },

  // 扫码绑定室内机 (REQ-6)
  async onBindIndoor() {
    const { station } = this.data
    
    // 每个加油站只能绑定1台室内机
    if (station && station.indoor_device) {
      wx.showModal({
        title: '提示',
        content: '该加油站已绑定室内机，请先解绑后再绑定新设备',
        showCancel: false,
        confirmText: '知道了'
      })
      return
    }

    this.scanAndBind('indoor')
  },

  // 扫码绑定室外机 (REQ-7)
  onBindOutdoor() {
    // 每个加油站可绑定多台室外机
    this.scanAndBind('outdoor')
  },

  // 扫码并绑定
  async scanAndBind(type: 'indoor' | 'outdoor') {
    const typeName = type === 'indoor' ? '室内机' : '室外机'
    
    try {
      // 调用微信扫码API
      const scanRes = await wx.scanCode({ 
        scanType: ['qrCode', 'barCode'],
        onlyFromCamera: false
      })
      
      // 扫描结果直接作为IMEI（无需格式处理）
      const imei = scanRes && scanRes.result && scanRes.result.trim();
      

      if (!imei) {
        wx.showToast({ title: '扫码失败，请重试', icon: 'none' })
        return
      }

      wx.showLoading({ title: '绑定中...', mask: true })

      // 设备未开机也支持绑定（设备不存在时自动创建）
      try {
        await createDevice({ imei, type })
      } catch (e) {
        // 设备可能已存在，忽略错误继续绑定
        console.log('设备可能已存在:', e)
      }

      // 绑定设备到加油站
      const res = await bindDevice(imei, this.data.id, type)
      
      wx.hideLoading()
      
      if (res.code === 200) {
        wx.showToast({ title: `${typeName}绑定成功`, icon: 'success' })
        // 刷新设备列表
        this.loadStation()
      }
    } catch (err: any) {
      wx.hideLoading()
      
      // 用户取消扫码
      if (err && err.errMsg && err.errMsg.includes('cancel')) {
        return
      }
      
      // 显示错误弹窗（使用 showModal 避免被 hideLoading 影响）
      const errorMsg = (err && err.message) || '绑定失败'
      wx.showModal({
        title: '绑定失败',
        content: errorMsg,
        showCancel: false,
        confirmText: '知道了'
      })
      console.error('绑定失败:', err)
    }
  },

  // 解绑设备 (REQ-8)
  onUnbind(e: any) {
    const imei = e.currentTarget.dataset.imei
    const type = e.currentTarget.dataset.type
    const typeName = type === 'indoor' ? '室内机' : '室外机'

    // 解绑前需二次确认
    wx.showModal({
      title: '确认解绑',
      content: `确定要解绑${typeName} ${imei} 吗？解绑后设备将变为未绑定状态。`,
      confirmColor: '#ff4d4f',
      success: async (res) => {
        if (res.confirm) {
          wx.showLoading({ title: '解绑中...', mask: true })
          
          try {
            const result = await unbindDevice(imei)
            wx.hideLoading()
            
            if (result.code === 200) {
              wx.showToast({ title: '解绑成功', icon: 'success' })
              // 刷新设备列表
              this.loadStation()
            }
          } catch (err) {
            wx.hideLoading()
            console.error('解绑失败:', err)
            wx.showToast({ title: '解绑失败', icon: 'none' })
          }
        }
      }
    })
  },

  // 删除加油站 (REQ-5)
  onDelete() {
    const { station } = this.data
    
    // 如果加油站下有绑定设备，提示需先解绑设备
    const hasIndoor = !!(station && station.indoor_device);
    const hasOutdoor = (station && station.outdoor_devices) && station.outdoor_devices.length > 0
    
    if (hasIndoor || hasOutdoor) {
      const deviceInfo = []
      if (hasIndoor) deviceInfo.push('1台室内机')
      if (hasOutdoor) deviceInfo.push(`${station!.outdoor_devices!.length}台室外机`)
      
      wx.showModal({
        title: '无法删除',
        content: `该加油站还有${deviceInfo.join('和')}绑定，请先解绑所有设备后再删除。`,
        showCancel: false,
        confirmText: '知道了'
      })
      return
    }

    // 删除前需二次确认
    wx.showModal({
      title: '确认删除',
      content: `确定要删除加油站"${(station && station.name)}"吗？此操作不可恢复。`,
      confirmColor: '#ff4d4f',
      confirmText: '删除',
      success: async (res) => {
        if (res.confirm) {
          wx.showLoading({ title: '删除中...', mask: true })
          
          try {
            const result = await deleteStation(this.data.id)
            wx.hideLoading()
            
            if (result.code === 200) {
              wx.showToast({ title: '删除成功', icon: 'success' })
              // 删除成功后刷新列表并返回
              setTimeout(() => {
                wx.navigateBack()
              }, 1500)
            }
          } catch (err) {
            wx.hideLoading()
            console.error('删除失败:', err)
            wx.showToast({ title: '删除失败', icon: 'none' })
          }
        }
      }
    })
  }
})
