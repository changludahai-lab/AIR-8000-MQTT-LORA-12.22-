// 新建加油站页
// 关联需求: REQ-3 - 加油站管理 - 新建加油站
import { createStation } from '../../../utils/api'

interface FormErrors {
  name?: string
  code?: string
  phone?: string
}

Page({
  data: {
    // 表单数据
    name: '',
    code: '',
    address: '',
    contact: '',
    phone: '',
    // 状态
    loading: false,
    // 表单验证错误
    errors: {} as FormErrors
  },

  /**
   * 处理输入事件
   */
  onInput(e: WechatMiniprogram.Input) {
    const field = e.currentTarget.dataset.field as string
    const value = e.detail.value
    
    // 更新字段值并清除该字段的错误
    const errors = { ...this.data.errors }
    delete errors[field as keyof FormErrors]
    
    this.setData({ 
      [field]: value,
      errors 
    })
  },

  /**
   * 验证表单
   * @returns 是否验证通过
   */
  validateForm(): boolean {
    const { name, code, phone } = this.data
    const errors: FormErrors = {}
    
    // 验证名称（必填）
    if (!name.trim()) {
      errors.name = '请输入加油站名称'
    } else if (name.trim().length > 50) {
      errors.name = '名称不能超过50个字符'
    }
    
    // 验证编号（必填）
    if (!code.trim()) {
      errors.code = '请输入加油站编号'
    } else if (code.trim().length > 20) {
      errors.code = '编号不能超过20个字符'
    }
    
    // 验证电话（可选，但如果填写需要格式正确）
    if (phone.trim()) {
      const phoneRegex = /^1[3-9]\d{9}$|^0\d{2,3}-?\d{7,8}$/
      if (!phoneRegex.test(phone.trim())) {
        errors.phone = '请输入正确的电话号码'
      }
    }
    
    this.setData({ errors })
    
    // 如果有错误，显示第一个错误提示
    const errorKeys = Object.keys(errors) as (keyof FormErrors)[]
    if (errorKeys.length > 0) {
      wx.showToast({ 
        title: errors[errorKeys[0]] || '请检查表单', 
        icon: 'none' 
      })
      return false
    }
    
    return true
  },

  /**
   * 提交创建加油站
   */
  async onSubmit() {
    // 表单验证
    if (!this.validateForm()) {
      return
    }

    const { name, code, address, contact, phone } = this.data

    this.setData({ loading: true })

    try {
      const res = await createStation({ 
        name: name.trim(), 
        code: code.trim(), 
        address: address.trim(), 
        contact: contact.trim(), 
        phone: phone.trim() 
      })
      
      if (res.code === 200 || res.code === 201) {
        wx.showToast({ title: '创建成功', icon: 'success' })
        // 返回列表页并刷新
        setTimeout(() => {
          wx.navigateBack()
        }, 1500)
      } else {
        wx.showToast({ 
          title: res.message || '创建失败', 
          icon: 'none' 
        })
      }
    } catch (err: any) {
      console.error('创建加油站失败:', err)
      wx.showToast({ 
        title: err.message || '创建失败，请重试', 
        icon: 'none' 
      })
    } finally {
      this.setData({ loading: false })
    }
  },

  /**
   * 取消创建，返回上一页
   */
  onCancel() {
    wx.navigateBack()
  }
})
