import { axiosInstance, http } from './client'
import type { SystemInfo, TaskInfo, Paginated } from './types'

export interface AuthResponse {
  token: string
  token_type: string
  user: { id: string; username: string; display_name: string | null; created_at: string }
}

export const systemApi = {
  health() {
    return http.get<{ status: string; database: boolean; version: string }>('/system/health')
  },
  info() {
    return http.get<SystemInfo>('/system/info')
  },
  login(username: string, password: string) {
    return http.post<AuthResponse>('/auth/login', { username, password })
  },
  register(username: string, password: string, displayName?: string) {
    return http.post<AuthResponse>('/auth/register', {
      username, password, display_name: displayName || username,
    })
  },
  me() {
    return http.get<{ authenticated: boolean; user?: AuthResponse['user']; local_mode?: boolean }>('/auth/me')
  },
  registerDevice(payload: {
    name: string
    platform: 'windows' | 'android' | 'ios' | 'web' | 'other'
    fingerprint?: string
    app_version?: string
  }) {
    return http.post<{ id: string; name: string; platform: string; last_seen_at: string }>('/devices/register', payload)
  },
  devices() {
    return http.get<Array<{ id: string; name: string; platform: string; last_seen_at: string }>>('/devices')
  },
  createBackup() {
    return http.post<{ filename: string; size: number; created_at: string; download_url: string }>('/system/backup')
  },
  backups() {
    return http.get<Array<{ filename: string; size: number; created_at: string; download_url: string }>>('/system/backups')
  },
  async downloadBackup(filename: string): Promise<Blob> {
    const blob = await axiosInstance.get(`/system/backups/${filename}`, { responseType: 'blob' })
    return blob as unknown as Blob
  },
}

export const tasksApi = {
  list(params: { status?: string; type?: string; book_id?: string; page?: number; page_size?: number } = {}) {
    return http.get<Paginated<TaskInfo>>('/tasks', { params })
  },
  get(taskId: string) {
    return http.get<TaskInfo>(`/tasks/${taskId}`)
  },
  cancel(taskId: string) {
    return http.post<TaskInfo>(`/tasks/${taskId}/cancel`, {})
  },
  progress(taskId: string) {
    return http.get<Record<string, unknown>>(`/tasks/${taskId}/progress`)
  },
}

export const syncApi = {
  status(deviceId: string) {
    return http.get<{
      enabled: boolean
      device_id: string
      last_pulled_seq: number
      latest_seq: number
      pending_conflicts: number
      supported_entity_types: string[]
    }>('/sync/status', { params: { device_id: deviceId } })
  },
  pull(deviceId: string, after = 0) {
    return http.get<{ operations: Array<Record<string, unknown>>; next_cursor: number; has_more: boolean }>(
      '/sync/pull', { params: { device_id: deviceId, after } },
    )
  },
  push(deviceId: string, operations: Array<Record<string, unknown>>) {
    return http.post<{ results: Array<Record<string, unknown>>; conflicts: number }>('/sync/push', {
      device_id: deviceId, operations,
    })
  },
  conflicts() {
    return http.get<Array<Record<string, unknown>>>('/sync/conflicts')
  },
}
