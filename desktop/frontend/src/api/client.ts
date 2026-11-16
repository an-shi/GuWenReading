import axios, { type AxiosRequestConfig } from 'axios'

const API_BASE_KEY = 'guwen:apiBase'
const TOKEN_KEY = 'guwen:token'

export const DEFAULT_API_BASE =
  (import.meta.env.VITE_API_BASE_URL as string | undefined) || 'http://127.0.0.1:8765/api/v1'

export class ApiError extends Error {
  code: string
  details: unknown
  status: number

  constructor(message: string, code = 'UNKNOWN', status = 0, details: unknown = null) {
    super(message)
    this.name = 'ApiError'
    this.code = code
    this.status = status
    this.details = details
  }
}

type ErrorListener = (error: ApiError) => void
const errorListeners = new Set<ErrorListener>()

export function onApiError(listener: ErrorListener): () => void {
  errorListeners.add(listener)
  return () => errorListeners.delete(listener)
}

export function apiBase(): string {
  return (localStorage.getItem(API_BASE_KEY) || DEFAULT_API_BASE).replace(/\/$/, '')
}

export function setApiBase(value: string): void {
  if (!value) {
    localStorage.removeItem(API_BASE_KEY)
  } else {
    localStorage.setItem(API_BASE_KEY, value.replace(/\/$/, ''))
  }
  instance.defaults.baseURL = apiBase()
}

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}

export function setToken(value: string | null): void {
  if (value) localStorage.setItem(TOKEN_KEY, value)
  else localStorage.removeItem(TOKEN_KEY)
}

export function wsUrl(): string {
  const base = new URL(apiBase())
  const protocol = base.protocol === 'https:' ? 'wss:' : 'ws:'
  return `${protocol}//${base.host}/ws/tasks`
}

export function assetUrl(path: string | null | undefined): string {
  if (!path) return ''
  if (/^https?:\/\//.test(path)) return path
  const base = new URL(apiBase())
  return `${base.origin}${path}`
}

const instance = axios.create({
  baseURL: apiBase(),
  timeout: 120_000,
  headers: { 'Content-Type': 'application/json' },
})

instance.interceptors.request.use((config) => {
  const token = getToken()
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

instance.interceptors.response.use(
  (response) => {
    const body = response.data
    if (body && typeof body === 'object' && 'success' in body) {
      if (body.success === false) {
        throw new ApiError(
          body.error?.message || body.message || '请求失败',
          body.error?.code || 'UNKNOWN',
          response.status,
          body.error?.details,
        )
      }
      return body.data
    }
    return body
  },
  (error) => {
    if (error instanceof ApiError) {
      errorListeners.forEach((listener) => listener(error))
      return Promise.reject(error)
    }
    const status = error.response?.status || 0
    const body = error.response?.data
    const message =
      body?.error?.message ||
      body?.message ||
      (status === 0
        ? '无法连接古文阅读器后端，请确认本地服务已启动'
        : `请求失败（HTTP ${status}）`)
    const apiError = new ApiError(
      message,
      body?.error?.code || 'NETWORK_ERROR',
      status,
      body?.error?.details,
    )
    errorListeners.forEach((listener) => listener(apiError))
    return Promise.reject(apiError)
  },
)

function get<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
  return instance.get(url, config) as unknown as Promise<T>
}

function post<T>(url: string, data?: unknown, config?: AxiosRequestConfig): Promise<T> {
  return instance.post(url, data, config) as unknown as Promise<T>
}

function put<T>(url: string, data?: unknown, config?: AxiosRequestConfig): Promise<T> {
  return instance.put(url, data, config) as unknown as Promise<T>
}

function del<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
  return instance.delete(url, config) as unknown as Promise<T>
}

export const http = { get, post, put, delete: del }
export { instance as axiosInstance }
