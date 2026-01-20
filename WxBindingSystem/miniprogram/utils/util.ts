/**
 * 通用工具函数模块
 */

/**
 * 格式化日期时间
 * @param date Date对象或时间字符串
 * @param format 格式化模板，默认 'YYYY/MM/DD HH:mm:ss'
 * @returns 格式化后的字符串
 */
export function formatTime(date: Date | string | number, format: string = 'YYYY/MM/DD HH:mm:ss'): string {
  const d = typeof date === 'string' || typeof date === 'number' ? new Date(date) : date
  
  if (isNaN(d.getTime())) {
    return '-'
  }

  const year = d.getFullYear()
  const month = d.getMonth() + 1
  const day = d.getDate()
  const hour = d.getHours()
  const minute = d.getMinutes()
  const second = d.getSeconds()

  const formatMap: Record<string, string> = {
    'YYYY': String(year),
    'MM': formatNumber(month),
    'DD': formatNumber(day),
    'HH': formatNumber(hour),
    'mm': formatNumber(minute),
    'ss': formatNumber(second),
    'M': String(month),
    'D': String(day),
    'H': String(hour),
    'm': String(minute),
    's': String(second)
  }

  let result = format
  for (const key in formatMap) {
    result = result.replace(key, formatMap[key])
  }
  return result
}

/**
 * 数字补零
 * @param n 数字
 * @returns 补零后的字符串
 */
export function formatNumber(n: number): string {
  const s = n.toString()
  return s.length === 1 ? '0' + s : s
}

/**
 * 格式化相对时间（如：刚刚、5分钟前、1小时前）
 * @param date 日期
 * @returns 相对时间字符串
 */
export function formatRelativeTime(date: Date | string | number): string {
  const d = typeof date === 'string' || typeof date === 'number' ? new Date(date) : date
  
  if (isNaN(d.getTime())) {
    return '-'
  }

  const now = new Date()
  const diff = now.getTime() - d.getTime()
  const seconds = Math.floor(diff / 1000)
  const minutes = Math.floor(seconds / 60)
  const hours = Math.floor(minutes / 60)
  const days = Math.floor(hours / 24)

  if (seconds < 60) {
    return '刚刚'
  } else if (minutes < 60) {
    return `${minutes}分钟前`
  } else if (hours < 24) {
    return `${hours}小时前`
  } else if (days < 30) {
    return `${days}天前`
  } else {
    return formatTime(d, 'YYYY/MM/DD')
  }
}

/**
 * 检查是否已登录
 * @returns 是否已登录
 */
export function isLoggedIn(): boolean {
  const token = wx.getStorageSync('token')
  return !!token
}

/**
 * 获取本地存储的用户信息
 * @returns 用户信息或null
 */
export function getUserInfo(): { id: number; username: string; role: string } | null {
  try {
    const userInfo = wx.getStorageSync('userInfo')
    return userInfo || null
  } catch {
    return null
  }
}

/**
 * 保存登录信息到本地存储
 * @param token JWT令牌
 * @param userInfo 用户信息
 */
export function saveLoginInfo(token: string, userInfo: { id: number; username: string; role: string }): void {
  wx.setStorageSync('token', token)
  wx.setStorageSync('userInfo', userInfo)
}

/**
 * 清除登录信息
 */
export function clearLoginInfo(): void {
  wx.removeStorageSync('token')
  wx.removeStorageSync('userInfo')
}

/**
 * 显示确认对话框
 * @param options 配置选项
 * @returns Promise<boolean> 用户是否确认
 */
export function showConfirm(options: {
  title?: string
  content: string
  confirmText?: string
  cancelText?: string
}): Promise<boolean> {
  return new Promise((resolve) => {
    wx.showModal({
      title: options.title || '提示',
      content: options.content,
      confirmText: options.confirmText || '确定',
      cancelText: options.cancelText || '取消',
      success: (res) => {
        resolve(res.confirm)
      },
      fail: () => {
        resolve(false)
      }
    })
  })
}

/**
 * 显示成功提示
 * @param title 提示文字
 * @param duration 显示时长（毫秒）
 */
export function showSuccess(title: string, duration: number = 1500): void {
  wx.showToast({
    title,
    icon: 'success',
    duration
  })
}

/**
 * 显示错误提示
 * @param title 提示文字
 * @param duration 显示时长（毫秒）
 */
export function showError(title: string, duration: number = 2000): void {
  wx.showToast({
    title,
    icon: 'none',
    duration
  })
}

/**
 * 显示加载中
 * @param title 提示文字
 */
export function showLoading(title: string = '加载中...'): void {
  wx.showLoading({
    title,
    mask: true
  })
}

/**
 * 隐藏加载中
 */
export function hideLoading(): void {
  wx.hideLoading()
}

/**
 * 防抖函数
 * @param fn 要执行的函数
 * @param delay 延迟时间（毫秒）
 * @returns 防抖后的函数
 */
export function debounce<T extends (...args: any[]) => any>(
  fn: T, 
  delay: number = 300
): (...args: Parameters<T>) => void {
  let timer: number | null = null
  return function(this: any, ...args: Parameters<T>) {
    if (timer) {
      clearTimeout(timer)
    }
    timer = setTimeout(() => {
      fn.apply(this, args)
      timer = null
    }, delay) as unknown as number
  }
}

/**
 * 节流函数
 * @param fn 要执行的函数
 * @param interval 间隔时间（毫秒）
 * @returns 节流后的函数
 */
export function throttle<T extends (...args: any[]) => any>(
  fn: T, 
  interval: number = 300
): (...args: Parameters<T>) => void {
  let lastTime = 0
  return function(this: any, ...args: Parameters<T>) {
    const now = Date.now()
    if (now - lastTime >= interval) {
      fn.apply(this, args)
      lastTime = now
    }
  }
}

/**
 * 验证手机号格式
 * @param phone 手机号
 * @returns 是否有效
 */
export function isValidPhone(phone: string): boolean {
  return /^1[3-9]\d{9}$/.test(phone)
}

/**
 * 验证IMEI格式（15位数字）
 * @param imei IMEI号
 * @returns 是否有效
 */
export function isValidIMEI(imei: string): boolean {
  return /^\d{15}$/.test(imei)
}

/**
 * 获取设备类型显示名称
 * @param type 设备类型
 * @returns 显示名称
 */
export function getDeviceTypeName(type: 'indoor' | 'outdoor'): string {
  return type === 'indoor' ? '室内机' : '室外机'
}

/**
 * 获取在线状态显示
 * @param online 是否在线
 * @returns 状态文字
 */
export function getOnlineStatusText(online: boolean): string {
  return online ? '在线' : '离线'
}

/**
 * 获取用户角色显示名称
 * @param role 角色
 * @returns 显示名称
 */
export function getRoleName(role: 'admin' | 'user' | string): string {
  return role === 'admin' ? '管理员' : '普通用户'
}
