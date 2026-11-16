<template>
  <v-layout class="layout-root">
    <v-navigation-drawer
      v-model="drawer"
      :permanent="!mobile"
      :temporary="mobile"
      width="256"
      class="nav-drawer"
    >
      <div class="nav-watermark serif">古</div>
      <div class="brand" @click="go('/')">
        <div class="brand-seal serif">古</div>
        <div>
          <div class="brand-name serif">古文阅读器</div>
          <div class="brand-sub">古籍阅读与研究</div>
        </div>
      </div>

      <div class="nav-group">
        <div class="nav-label">阅读</div>
        <v-list nav density="comfortable" class="nav-list">
          <v-list-item
            v-for="item in primaryNav"
            :key="item.to"
            :to="item.to"
            :prepend-icon="item.icon"
            :title="item.title"
            :active="isActive(item.to)"
            rounded="lg"
            class="nav-item"
            @click="closeOnMobile"
          >
            <template v-if="item.to === '/tasks' && tasks.active.length" #append>
              <v-chip size="x-small" color="secondary" variant="flat">{{ tasks.active.length }}</v-chip>
            </template>
          </v-list-item>
        </v-list>
      </div>

      <div class="nav-group">
        <div class="nav-label">知识</div>
        <v-list nav density="comfortable" class="nav-list">
          <v-list-item
            v-for="item in knowledgeNav"
            :key="item.to"
            :to="item.to"
            :prepend-icon="item.icon"
            :title="item.title"
            :active="isActive(item.to)"
            rounded="lg"
            class="nav-item"
            @click="closeOnMobile"
          />
        </v-list>
      </div>

      <template #append>
        <div class="nav-footer">
          <button class="ai-status" @click="go('/settings')">
            <span class="dot" :class="{ ready: ai.configured }" />
            <span>{{ ai.configured ? 'AI 服务已就绪' : '尚未配置 AI 模型' }}</span>
            <v-icon size="15" icon="mdi-chevron-right" />
          </button>
          <div class="footer-meta">
            <span>v{{ app.info?.version || '0.1.0' }}</span>
            <span>{{ app.backendMode === 'server' ? '服务端' : '本地模式' }}</span>
            <span :class="['status-dot', { online: app.backendOnline }]" />
          </div>
        </div>
      </template>
    </v-navigation-drawer>

    <v-app-bar v-if="mobile" flat class="mobile-bar" height="62">
      <v-app-bar-nav-icon @click="drawer = true" />
      <div class="mobile-brand serif">古文阅读器</div>
      <v-spacer />
      <v-btn icon="mdi-magnify" to="/search" />
    </v-app-bar>

    <v-main class="main-scroll" :style="mobile ? 'padding-top:62px' : ''">
      <router-view />
    </v-main>
  </v-layout>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue'
import { useDisplay } from 'vuetify'
import { useRoute, useRouter } from 'vue-router'
import { useAppStore } from '@/stores/app'
import { useAiStore } from '@/stores/ai'
import { useTasksStore } from '@/stores/tasks'

const app = useAppStore()
const ai = useAiStore()
const tasks = useTasksStore()
const route = useRoute()
const router = useRouter()
const { mobile } = useDisplay()
const drawer = ref(!mobile.value)

watch(mobile, (value) => { drawer.value = !value })

const primaryNav = [
  { to: '/', title: '书架', icon: 'mdi-bookshelf' },
  { to: '/search', title: '知识检索', icon: 'mdi-text-search' },
  { to: '/notes', title: '批注与书签', icon: 'mdi-bookmark-outline' },
  { to: '/tasks', title: '任务中心', icon: 'mdi-progress-clock' },
]

const knowledgeNav = [
  { to: '/entities', title: '人物知识库', icon: 'mdi-account-group-outline' },
  { to: '/graph', title: '关系图谱', icon: 'mdi-graph-outline' },
  { to: '/timeline', title: '历史时间线', icon: 'mdi-timeline-clock-outline' },
]

function isActive(path: string) {
  return path === '/' ? route.path === '/' : route.path.startsWith(path)
}

function go(path: string) {
  router.push(path)
  closeOnMobile()
}

function closeOnMobile() {
  if (mobile.value) drawer.value = false
}
</script>

<style scoped>
.layout-root {
  background: rgb(var(--v-theme-background));
}
.nav-drawer {
  background: #101c18 !important;
  border-right: 0 !important;
  overflow: hidden;
}
.nav-watermark {
  position: absolute;
  right: -34px;
  top: 96px;
  font-size: 260px;
  line-height: 1;
  color: rgba(255, 255, 255, 0.025);
  pointer-events: none;
  user-select: none;
}
.brand {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 26px 22px 26px;
  cursor: pointer;
  position: relative;
  z-index: 1;
}
.brand-seal {
  width: 42px;
  height: 42px;
  border-radius: 12px;
  background: linear-gradient(145deg, #c79a5e, #9a6a34);
  color: #18231f;
  display: grid;
  place-items: center;
  font-size: 1.45rem;
  font-weight: 700;
  box-shadow: 0 8px 22px rgba(0, 0, 0, 0.3);
}
.brand-name {
  color: #f2ecdf;
  font-size: 1.22rem;
  letter-spacing: 0.045em;
  font-weight: 650;
}
.brand-sub {
  color: rgba(240, 235, 223, 0.44);
  font-size: 0.68rem;
  letter-spacing: 0.18em;
  margin-top: 3px;
}
.nav-group {
  padding: 6px 12px 14px;
  position: relative;
  z-index: 1;
}
.nav-label {
  padding: 10px 12px 8px;
  color: rgba(240, 235, 223, 0.34);
  font-size: 0.63rem;
  letter-spacing: 0.22em;
  font-weight: 700;
}
.nav-list {
  padding: 0;
}
.nav-item {
  color: rgba(243, 238, 228, 0.7) !important;
  margin-bottom: 3px;
  min-height: 42px;
}
.nav-item :deep(.v-list-item-title) {
  font-size: 0.88rem;
  letter-spacing: 0.02em;
}
.nav-item :deep(.v-icon) {
  color: rgba(243, 238, 228, 0.46) !important;
  opacity: 1;
}
.nav-item:hover {
  background: rgba(255, 255, 255, 0.055) !important;
}
.nav-item.v-list-item--active {
  background: rgba(199, 154, 94, 0.14) !important;
  color: #f3e7d3 !important;
}
.nav-item.v-list-item--active :deep(.v-icon) {
  color: #c79a5e !important;
}
.nav-item :deep(.v-list-item__overlay) {
  background: transparent;
}
.nav-footer {
  padding: 12px 16px 18px;
  border-top: 1px solid rgba(255, 255, 255, 0.07);
}
.ai-status {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 9px;
  background: rgba(255, 255, 255, 0.045);
  border: 1px solid rgba(255, 255, 255, 0.06);
  color: rgba(243, 238, 228, 0.68);
  border-radius: 10px;
  padding: 10px 12px;
  font-size: 0.75rem;
  cursor: pointer;
  transition: background 150ms ease;
}
.ai-status:hover {
  background: rgba(255, 255, 255, 0.08);
}
.ai-status .dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: #a85f52;
  box-shadow: 0 0 0 3px rgba(168, 95, 82, 0.15);
}
.ai-status .dot.ready {
  background: #7fb08e;
  box-shadow: 0 0 0 3px rgba(127, 176, 142, 0.15);
}
.ai-status v-icon {
  margin-left: auto;
}
.footer-meta {
  display: flex;
  align-items: center;
  gap: 9px;
  margin-top: 11px;
  padding: 0 4px;
  color: rgba(243, 238, 228, 0.28);
  font-size: 0.66rem;
}
.status-dot {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: #a85f52;
  margin-left: auto;
}
.status-dot.online {
  background: #7fb08e;
}
.main-scroll {
  height: 100dvh;
  overflow-y: auto;
  overflow-x: hidden;
}
.mobile-bar {
  background: rgba(var(--v-theme-surface), 0.94) !important;
  backdrop-filter: blur(14px);
  border-bottom: 1px solid rgba(var(--v-theme-on-surface), 0.08);
}
.mobile-brand {
  font-size: 1.05rem;
  font-weight: 650;
  letter-spacing: 0.05em;
}
@media (min-width: 840px) {
  .mobile-bar {
    display: none;
  }
}
</style>
