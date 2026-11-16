import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import { apiBase, setApiBase } from '@/api/client'
import { systemApi } from '@/api/system'
import type { SystemInfo } from '@/api/types'

export type ThemeName = 'paper' | 'light' | 'dark'

const THEME_KEY = 'guwen:theme'
const FONT_KEY = 'guwen:fontSize'
const LINE_KEY = 'guwen:lineHeight'
const AUTO_KEY = 'guwen:autoTranslate'
const DEVICE_KEY = 'guwen:deviceId'

function loadNumber(key: string, fallback: number): number {
  const value = Number(localStorage.getItem(key))
  return Number.isFinite(value) && value > 0 ? value : fallback
}

export const useAppStore = defineStore('app', () => {
  const theme = ref<ThemeName>((localStorage.getItem(THEME_KEY) as ThemeName) || 'paper')
  const fontSize = ref(loadNumber(FONT_KEY, 19))
  const lineHeight = ref(loadNumber(LINE_KEY, 1.9))
  const autoTranslate = ref(localStorage.getItem(AUTO_KEY) !== 'false')
  const deviceId = ref(localStorage.getItem(DEVICE_KEY) || '')
  const info = ref<SystemInfo | null>(null)
  const backendOnline = ref(false)
  const baseUrl = ref(apiBase())
  const initializing = ref(true)
  const snackbar = ref<{ show: boolean; message: string; color: string }>({
    show: false, message: '', color: 'success',
  })

  const authenticated = ref(false)
  const username = ref('')

  const modelConfigured = computed(() => (info.value?.counts.models || 0) > 0)
  const backendMode = computed(() => info.value?.mode || 'embedded')

  function notify(message: string, color = 'success') {
    snackbar.value = { show: true, message, color }
  }

  function setTheme(value: ThemeName) {
    theme.value = value
    localStorage.setItem(THEME_KEY, value)
  }

  function setFontSize(value: number) {
    fontSize.value = Math.min(30, Math.max(14, value))
    localStorage.setItem(FONT_KEY, String(fontSize.value))
  }

  function setLineHeight(value: number) {
    lineHeight.value = Math.min(2.6, Math.max(1.4, value))
    localStorage.setItem(LINE_KEY, String(lineHeight.value))
  }

  function setAutoTranslate(value: boolean) {
    autoTranslate.value = value
    localStorage.setItem(AUTO_KEY, String(value))
  }

  function updateApiBase(value: string) {
    setApiBase(value)
    baseUrl.value = apiBase()
  }

  async function initialize() {
    initializing.value = true
    await loadInfo()
    if (!deviceId.value) {
      deviceId.value = `desktop-${crypto.randomUUID()}`
      localStorage.setItem(DEVICE_KEY, deviceId.value)
    }
    try {
      await systemApi.registerDevice({
        name: 'Windows 桌面端',
        platform: 'windows',
        fingerprint: deviceId.value,
        app_version: info.value?.version || '0.1.0',
      })
      const me = await systemApi.me()
      authenticated.value = Boolean(me.authenticated)
      username.value = me.user?.username || ''
    } catch {
      // Device registration is optional in embedded mode.
    }
    initializing.value = false
  }

  async function loadInfo() {
    try {
      info.value = await systemApi.info()
      backendOnline.value = true
    } catch {
      backendOnline.value = false
    }
  }

  return {
    theme, fontSize, lineHeight, autoTranslate, deviceId, info, backendOnline, baseUrl,
    initializing, snackbar, authenticated, username, modelConfigured, backendMode,
    notify, setTheme, setFontSize, setLineHeight, setAutoTranslate, updateApiBase,
    initialize, loadInfo,
  }
})
