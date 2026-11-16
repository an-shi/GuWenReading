<template>
  <v-app>
    <v-banner
      v-if="showOfflineBanner"
      color="warning"
      icon="mdi-lan-disconnect"
      class="offline-banner"
      lines="one"
    >
      <v-banner-text>
        无法连接古文阅读器本地服务。请先启动后端（默认 127.0.0.1:8765）。
      </v-banner-text>
      <template #actions>
        <v-btn variant="text" @click="retryBackend">重试连接</v-btn>
      </template>
    </v-banner>

    <router-view v-slot="{ Component }">
      <transition name="fade-slide" mode="out-in">
        <component :is="Component" />
      </transition>
    </router-view>

    <v-snackbar
      v-model="app.snackbar.show"
      :color="app.snackbar.color"
      :timeout="app.snackbar.color === 'error' ? 7000 : 3200"
      location="bottom right"
      rounded="lg"
    >
      {{ app.snackbar.message }}
      <template #actions>
        <v-btn variant="text" @click="app.snackbar.show = false">关闭</v-btn>
      </template>
    </v-snackbar>
  </v-app>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, watch } from 'vue'
import { useTheme } from 'vuetify'
import { onApiError } from '@/api/client'
import { useAppStore } from '@/stores/app'
import { useAiStore } from '@/stores/ai'
import { useTasksStore } from '@/stores/tasks'

const app = useAppStore()
const ai = useAiStore()
const tasks = useTasksStore()
const theme = useTheme()
let unsubscribeError: (() => void) | null = null
let initialized = false

const showOfflineBanner = computed(() => initialized && !app.backendOnline && !app.initializing)

watch(
  () => app.theme,
  (value) => { theme.change(value) },
  { immediate: true },
)

watch(
  () => tasks.lastEvent,
  (event) => {
    if (!event) return
    if (event.type === 'task_completed' && event.task.status === 'partial') {
      app.notify(`任务完成，但有 ${event.task.failed_count} 项失败`, 'warning')
    } else if (event.type === 'task_completed') {
      app.notify('AI 任务已完成')
    } else if (event.type === 'task_failed') {
      app.notify(event.task.error || 'AI 任务失败', 'error')
    }
  },
)

async function boot() {
  await app.initialize()
  initialized = true
  if (app.backendOnline) {
    tasks.connect()
    tasks.load()
    ai.load().catch(() => undefined)
  }
}

async function retryBackend() {
  await app.loadInfo()
  if (app.backendOnline) {
    app.notify('已连接本地服务')
    tasks.connect()
    ai.load().catch(() => undefined)
  }
}

onMounted(() => {
  unsubscribeError = onApiError((error) => {
    if (error.status !== 401) app.notify(error.message, 'error')
  })
  boot()
})

onBeforeUnmount(() => {
  unsubscribeError?.()
  tasks.disconnect()
})
</script>

<style scoped>
.offline-banner {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  z-index: 3000;
}
</style>
