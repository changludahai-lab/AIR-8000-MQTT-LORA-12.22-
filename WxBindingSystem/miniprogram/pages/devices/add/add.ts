// 添加设备页
// 关联需求: REQ-10 - 设备管理 - 手动添加设备
import { createDevice } from '../../../utils/api'

interface FormErrors {
  imei?: string
}

Page({
  data: {
    // 表单数据
    imei: '',
    type: 'indoor' as 'indoor' | 'outdoor',
    // 状态
    loading: false,
    // 表单验证错误
    errors: {} as FormErrors
  },

  /**
   * IMEI输入事件
   */
  onImeiInput(e: WechatMiniprogram.Input) {
    const value = e.detail.value
    // 更新字段值并清除错误
    const errors = { ...this.data.errors }
    delete errors.imei
    
    this.setData({ 
      imei: value,
      errors 
    })
  },

  /**
   * 设备类型选择事件
   */
  onTypeChange(e: WechatMiniprogram.RadioGroupChange) {
    this.setData({ type: e.detail.value as 'indoor' | 'outdoor' })
  },

  /**
   * 扫码获取IMEI
   */
  async onScan() {
    try {
      const res = await wx.scanCode({ scanType: ['qrCode', 'barCode'] })
      if (res.result) {
        // 清除错误并设置IMEI
        this.setData({ 
          imei: res.result,
          errors: {}
        })
        wx.showToast({ title: '扫码成功', icon: 'success' })
      }
    } catch (err: any) {
      // 用户取消扫码不提示错误
      if (!err || !err.errMsg || !err.errMsg.includes('cancel')) {
        wx.showToast({ title: '扫码失败', icon: 'none' })
      }
    }
  },

  /**
   * 验证表单
   * @returns 是否验证通过
   */
  validateForm(): boolean {
    const { imei } = this.data
    const errors: FormErrors = {}
    
    // 验证IMEI（必填）
    if (!imei.trim()) {
      errors.imei = '请输入设备IMEI'
    } else if (imei.trim().length < 10) {
      errors.imei = 'IMEI长度不能少于10位'
    } else if (imei.trim().length > 20) {
      errors.imei = 'IMEI长度不能超过20位'
    } else if (!/^[A-Za-z0-9]+$/.test(imei.trim())) {
      errors.imei = 'IMEI只能包含字母和数字'
    }
    
    this.setData({ errors })
    
    // 如果有错误，显示提示
    if (Object.keys(errors).length > 0) {
      wx.showToast({ 
        title: errors.imei || '请检查表单', 
        icon: 'none' 
      })
      return false
    }
    
    return true
  },

  /**
   * 提交添加设备
   */
  async onSubmit() {
    // 表单验证
    if (!this.validateForm()) {
      return
    }

    const { imei, type } = this.data

    this.setData({ loading: true })

    try {
      const res = await createDevice({ 
        imei: imei.trim(), 
        type 
      })
      
      if (res.code === 200 || res.code === 201) {
        wx.showToast({ title: '添加成功', icon: 'success' })
        // 返回设备列表页并刷新
        setTimeout(() => {
          wx.navigateBack()
        }, 1500)
      } else {
        // 处理错误响应
        this.handleApiError(res)
      }
    } catch (err: any) {
      console.error('添加设备失败:', err)
      this.handleApiError(err)
    } finally {
      this.setData({ loading: false })
    }
  },

  /**
   * 处理API错误
   */
  handleApiError(err: any) {
    let errorMessage = '添加失败，请重试'
    
    // 检查是否是IMEI已存在的错误
    if (err.message) {
      const msg = err.message.toLowerCase()
      if (msg.includes('exist') || msg.includes('已存在') || msg.includes('duplicate')) {
        errorMessage = '该IMEI设备已存在'
        this.setData({ 
          errors: { imei: '该IMEI设备已存在' } 
        })
      } else {
        errorMessage = err.message
      }
    } else if (err.code === 400) {
      errorMessage = '请求参数错误'
    } else if (err.code === 409) {
      errorMessage = '该IMEI设备已存在'
      this.setData({ 
        errors: { imei: '该IMEI设备已存在' } 
      })
    }
    
    wx.showToast({ 
      title: errorMessage, 
      icon: 'none',
      duration: 2000
    })
  },

  /**
   * 取消添加，返回上一页
   */
  onCancel() {
    wx.navigateBack()
  }
})
