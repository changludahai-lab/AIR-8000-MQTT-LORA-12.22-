/**
 * 请求封装模块
 * 功能：
 * - 统一添加 Authorization 请求头
 * - 统一处理响应错误
 * - 401 错误自动跳转登录页
 * - 支持请求超时配置
 */
import { config } from './config'

// 请求配置选项
interface RequestOptions {
  url: string
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE'
  data?: any
  header?: Record<string, string>
  showError?: boolean  // 是否显示错误提示，默认true
  showLoading?: boolean  // 是否显示加载中，默认false
}

// API 响应结构
export interface ApiResponse<T = any> {
  code: number
  message: string
  data: T
}

// 错误码映射
const ERROR_MESSAGES: Record<number, string> = {
  400: '请求参数错误',
  401: '请重新登录',
  403: '没有权限',
  404: '资源不存在',
  500: '服务器繁忙',
  502: '网关错误',
  503: '服务不可用'
}

// 是否正在跳转登录页（防止重复跳转）
let isRedirectingToLogin = false

/**
 * 处理401未授权错误
 * 清除本地存储并跳转到登录页
 */
function handleUnauthorized(): void {
  if (isRedirectingToLogin) return
  
  isRedirectingToLogin = true
  wx.removeStorageSync('token')
  wx.removeStorageSync('userInfo')
  
  wx.showToast({
    title: '请重新登录',
    icon: 'none',
    duration: 1500
  })
  
  setTimeout(() => {
    wx.reLaunch({
      url: '/pages/login/login',
      complete: () => {
        isRedirectingToLogin = false
      }
    })
  }, 1500)
}

/**
 * 获取错误提示信息
 */
function getErrorMessage(statusCode: number, responseMessage?: string): string {
  return responseMessage || ERROR_MESSAGES[statusCode] || '请求失败'
}

/**
 * 发起HTTP请求
 * @param options 请求配置
 * @returns Promise<ApiResponse<T>>
 */
export function request<T = any>(options: RequestOptions): Promise<ApiResponse<T>> {
  const { 
    url, 
    method = 'GET', 
    data, 
    header = {}, 
    showError = true,
    showLoading = false 
  } = options

  return new Promise((resolve, reject) => {
    // 显示加载中
    if (showLoading) {
      wx.showLoading({
        title: '加载中...',
        mask: true
      })
    }

    // 获取本地存储的token
    const token = wx.getStorageSync('token')
    
    wx.request({
      url: config.baseUrl + url,
      method,
      data,
      timeout: config.timeout,
      header: {
        'Content-Type': 'application/json',
        ...(token ? { 'Authorization': `Bearer ${token}` } : {}),
        ...header
      },
      success: (res: WechatMiniprogram.RequestSuccessCallbackResult) => {
        if (showLoading) {
          wx.hideLoading()
        }

        const statusCode = res.statusCode
        const responseData = res.data as ApiResponse<T>
        
        // 请求成功 (2xx)
        if (statusCode >= 200 && statusCode < 300) {
          resolve(responseData)
          return
        }
        
        // 401 未授权 - 跳转登录页
        if (statusCode === 401) {
          handleUnauthorized()
          reject(new Error('未登录或登录已过期'))
          return
        }
        
        // 其他错误
        const errorMessage = getErrorMessage(statusCode, responseData && responseData.message)
        if (showError) {
          wx.showToast({
            title: errorMessage,
            icon: 'none',
            duration: 2000
          })
        }
        reject(new Error(errorMessage))
      },
      fail: (_err: WechatMiniprogram.GeneralCallbackResult) => {
        if (showLoading) {
          wx.hideLoading()
        }
        
        const errorMessage = '网络连接失败，请检查网络'
        if (showError) {
          wx.showToast({
            title: errorMessage,
            icon: 'none',
            duration: 2000
          })
        }
        reject(new Error(errorMessage))
      }
    })
  })
}

/**
 * GET 请求
 * @param url 请求路径
 * @param data 查询参数
 * @param options 额外配置
 */
export function get<T = any>(
  url: string, 
  data?: any, 
  options?: Omit<RequestOptions, 'url' | 'method' | 'data'>
): Promise<ApiResponse<T>> {
  return request<T>({ url, method: 'GET', data, ...options })
}

/**
 * POST 请求
 * @param url 请求路径
 * @param data 请求体数据
 * @param options 额外配置
 */
export function post<T = any>(
  url: string, 
  data?: any, 
  options?: Omit<RequestOptions, 'url' | 'method' | 'data'>
): Promise<ApiResponse<T>> {
  return request<T>({ url, method: 'POST', data, ...options })
}

/**
 * PUT 请求
 * @param url 请求路径
 * @param data 请求体数据
 * @param options 额外配置
 */
export function put<T = any>(
  url: string, 
  data?: any, 
  options?: Omit<RequestOptions, 'url' | 'method' | 'data'>
): Promise<ApiResponse<T>> {
  return request<T>({ url, method: 'PUT', data, ...options })
}

/**
 * DELETE 请求
 * @param url 请求路径
 * @param data 请求体数据
 * @param options 额外配置
 */
export function del<T = any>(
  url: string, 
  data?: any, 
  options?: Omit<RequestOptions, 'url' | 'method' | 'data'>
): Promise<ApiResponse<T>> {
  return request<T>({ url, method: 'DELETE', data, ...options })
}
