/// <reference path="./types/index.d.ts" />

// 用户信息接口
interface IUserInfo {
  id: number
  username: string
  role: string
}

interface IAppOption {
  globalData: {
    userInfo: IUserInfo | null
    token: string
  }
  checkLogin(): boolean
  checkPageAuth(pagePath: string): boolean
  goLogin(): void
  setLoginInfo(token: string, userInfo: IUserInfo): void
  clearLoginInfo(): void
  getUserInfo(): IUserInfo | null
  getToken(): string
}
