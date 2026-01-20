/**
 * API 接口封装模块
 * 封装所有后端接口调用，提供类型定义
 */
import { get, post, put, del, ApiResponse } from './request'

// ========== 类型定义 ==========

/**
 * 用户信息
 */
export interface UserInfo {
  id: number
  username: string
  role: 'admin' | 'user'
  status: number
}

/**
 * 登录响应
 */
export interface LoginResponse {
  token: string
  user: UserInfo
}

/**
 * 设备信息
 */
export interface Device {
  id: number
  imei: string
  type: 'indoor' | 'outdoor'
  name: string
  station_id: number | null
  station_name: string | null
  last_seen: string | null
  online: boolean
  vbat: number | null  // 室外机电压
}

/**
 * 加油站信息
 */
export interface Station {
  id: number
  name: string
  code: string
  address: string
  contact: string
  phone: string
  status: number
  created_at: string
  indoor_count?: number       // 室内机数量
  outdoor_count?: number      // 室外机数量
  device_count?: number       // 设备总数
  indoor_device?: Device      // 绑定的室内机
  outdoor_devices?: Device[]  // 绑定的室外机列表
}

/**
 * 分页数据结构
 */
export interface PageData<T> {
  items: T[]
  total: number
  page: number
  per_page: number
  pages: number
}

/**
 * 创建加油站参数
 */
export interface CreateStationParams {
  name: string
  code: string
  address?: string
  contact?: string
  phone?: string
}

/**
 * 更新加油站参数
 */
export interface UpdateStationParams {
  name?: string
  code?: string
  address?: string
  contact?: string
  phone?: string
}

/**
 * 创建设备参数
 */
export interface CreateDeviceParams {
  imei: string
  type: 'indoor' | 'outdoor'
  name?: string
}

/**
 * 加油站查询参数
 */
export interface StationQueryParams {
  page?: number
  per_page?: number
  search?: string
}

/**
 * 设备查询参数
 */
export interface DeviceQueryParams {
  page?: number
  per_page?: number
  type?: 'indoor' | 'outdoor'
  station_id?: number
  search?: string
}

// ========== 认证接口 ==========

/**
 * 用户登录
 * @param username 用户名
 * @param password 密码
 */
export function login(username: string, password: string): Promise<ApiResponse<LoginResponse>> {
  return post<LoginResponse>('/api/auth/login', { username, password }, { showError: false })
}

/**
 * 获取当前登录用户信息
 */
export function getCurrentUser(): Promise<ApiResponse<UserInfo>> {
  return get<UserInfo>('/api/auth/me')
}

// ========== 加油站接口 ==========

/**
 * 获取加油站列表
 * @param params 查询参数
 */
export function getStations(params?: StationQueryParams): Promise<ApiResponse<PageData<Station>>> {
  return get<PageData<Station>>('/api/stations', params)
}

/**
 * 获取加油站详情（包含已绑定设备列表）
 * @param id 加油站ID
 */
export function getStation(id: number): Promise<ApiResponse<Station>> {
  return get<Station>(`/api/stations/${id}`)
}

/**
 * 创建加油站
 * @param data 加油站信息
 */
export function createStation(data: CreateStationParams): Promise<ApiResponse<Station>> {
  return post<Station>('/api/stations', data)
}

/**
 * 更新加油站
 * @param id 加油站ID
 * @param data 更新的信息
 */
export function updateStation(id: number, data: UpdateStationParams): Promise<ApiResponse<Station>> {
  return put<Station>(`/api/stations/${id}`, data)
}

/**
 * 删除加油站
 * @param id 加油站ID
 */
export function deleteStation(id: number): Promise<ApiResponse<null>> {
  return del<null>(`/api/stations/${id}`)
}

// ========== 设备接口 ==========

/**
 * 获取设备列表
 * @param params 查询参数
 */
export function getDevices(params?: DeviceQueryParams): Promise<ApiResponse<PageData<Device>>> {
  return get<PageData<Device>>('/api/devices', params)
}

/**
 * 创建设备
 * @param data 设备信息
 */
export function createDevice(data: CreateDeviceParams): Promise<ApiResponse<Device>> {
  return post<Device>('/api/devices', data)
}

/**
 * 绑定设备到加油站
 * @param imei 设备IMEI
 * @param stationId 加油站ID
 */
export function bindDevice(imei: string, stationId: number): Promise<ApiResponse<Device>> {
  return post<Device>(`/api/devices/${imei}/bind`, { station_id: stationId })
}

/**
 * 解绑设备
 * @param imei 设备IMEI
 */
export function unbindDevice(imei: string): Promise<ApiResponse<Device>> {
  return post<Device>(`/api/devices/${imei}/unbind`)
}

/**
 * 扫码绑定设备（设备不存在时自动创建）
 * 这是一个组合操作：先尝试绑定，如果设备不存在则创建后再绑定
 * @param imei 设备IMEI
 * @param type 设备类型
 * @param stationId 加油站ID
 */
export async function scanAndBindDevice(
  imei: string, 
  type: 'indoor' | 'outdoor', 
  stationId: number
): Promise<ApiResponse<Device>> {
  try {
    // 直接尝试绑定（后端会自动创建不存在的设备）
    return await bindDevice(imei, stationId)
  } catch (error) {
    // 如果绑定失败，尝试先创建设备再绑定
    try {
      await createDevice({ imei, type })
      return await bindDevice(imei, stationId)
    } catch (createError) {
      throw createError
    }
  }
}
