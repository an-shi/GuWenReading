import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import { wsUrl } from '@/api/client'
import { tasksApi } from '@/api/system'
import type { TaskInfo } from '@/api/types'

export const useTasksStore = defineStore('tasks', () => {
  const tasks = ref<TaskInfo[]>([])
  const connected = ref(false)
  const eventVersion = ref(0)
  const lastEvent = ref<{ type: string; task: TaskInfo } | null>(null)
  let socket: WebSocket | null = null
  let reconnectTimer: number | null = null
  let pollTimer: number | null = null

  const active = computed(() => tasks.value.filter((task) =>
    ['queued', 'running'].includes(task.status),
  ))

  function upsert(task: TaskInfo) {
    const index = tasks.value.findIndex((item) => item.id === task.id)
    if (index >= 0) tasks.value[index] = task
    else tasks.value.unshift(task)
    tasks.value.sort((a, b) => (a.created_at < b.created_at ? 1 : -1))
    eventVersion.value += 1
  }

  async function load() {
    try {
      const data = await tasksApi.list({ page: 1, page_size: 100 })
      tasks.value = data.items
    } catch {
      // Task panel is non-critical; keep last known state.
    }
  }

  function connect() {
    if (socket && socket.readyState <= WebSocket.OPEN) return
    try {
      socket = new WebSocket(wsUrl())
      socket.onopen = () => {
        connected.value = true
        if (reconnectTimer) window.clearTimeout(reconnectTimer)
        if (pollTimer) window.clearInterval(pollTimer)
      }
      socket.onmessage = (message) => {
        try {
          const event = JSON.parse(message.data as string) as { type: string; task?: TaskInfo }
          if (event.task && event.type !== 'heartbeat' && event.type !== 'connected') {
            upsert(event.task)
            lastEvent.value = { type: event.type, task: event.task }
          }
        } catch {
          // Ignore malformed frames.
        }
      }
      socket.onclose = () => {
        connected.value = false
        scheduleReconnect()
      }
      socket.onerror = () => socket?.close()
    } catch {
      connected.value = false
      scheduleReconnect()
    }
  }

  function scheduleReconnect() {
    if (reconnectTimer) return
    startPolling()
    reconnectTimer = window.setTimeout(() => {
      reconnectTimer = null
      connect()
    }, 4000)
  }

  function startPolling() {
    if (pollTimer) return
    pollTimer = window.setInterval(async () => {
      await load()
    }, 4000)
  }

  function disconnect() {
    socket?.close()
    socket = null
    if (reconnectTimer) window.clearTimeout(reconnectTimer)
    if (pollTimer) window.clearInterval(pollTimer)
    reconnectTimer = null
    pollTimer = null
  }

  async function cancel(taskId: string) {
    const task = await tasksApi.cancel(taskId)
    upsert(task)
    return task
  }

  async function refreshTask(taskId: string) {
    const task = await tasksApi.get(taskId)
    upsert(task)
    return task
  }

  return {
    tasks, connected, eventVersion, lastEvent, active,
    load, connect, disconnect, cancel, refreshTask, upsert,
  }
})
