<template>
  <div class="page">
    <div class="page-header">
      <div>
        <div class="section-label">后台任务</div>
        <h1 class="page-title">任务中心</h1>
        <p class="page-subtitle">翻译与知识抽取在后台分批执行。任务持久化保存，失败可重新发起，人工译文不会被自动覆盖。</p>
      </div>
      <div class="header-actions">
        <v-chip size="small" :color="tasks.connected ? 'success' : 'warning'" variant="tonal">
          {{ tasks.connected ? '实时连接' : '轮询模式' }}
        </v-chip>
        <v-btn variant="tonal" color="primary" prepend-icon="mdi-refresh" :loading="loading" @click="refresh">刷新</v-btn>
      </div>
    </div>

    <div class="task-filters">
      <v-btn-toggle v-model="statusFilter" density="compact" variant="tonal" divided mandatory>
        <v-btn value="" size="small">全部</v-btn>
        <v-btn value="running" size="small">进行中</v-btn>
        <v-btn value="completed" size="small">已完成</v-btn>
        <v-btn value="failed" size="small">失败</v-btn>
      </v-btn-toggle>
      <v-spacer />
      <span class="tiny muted">共 {{ tasks.tasks.length }} 个任务</span>
    </div>

    <v-progress-linear v-if="loading" indeterminate color="primary" rounded class="mb-4" />

    <div v-if="filtered.length" class="task-list">
      <v-card v-for="task in filtered" :key="task.id" class="task-card">
        <div class="task-main">
          <div class="task-status-icon" :class="task.status">
            <v-icon v-if="task.status === 'completed'" icon="mdi-check" />
            <v-icon v-else-if="task.status === 'failed'" icon="mdi-alert" />
            <v-icon v-else-if="task.status === 'cancelled'" icon="mdi-stop" />
            <v-progress-circular v-else indeterminate size="18" width="2" />
          </div>
          <div class="task-body">
            <div class="task-title-row">
              <span class="task-title serif">{{ task.title }}</span>
              <v-chip size="x-small" variant="tonal" :color="statusColor(task.status)">{{ statusLabel(task.status) }}</v-chip>
              <v-chip size="x-small" variant="tonal">{{ typeLabel(task.type) }}</v-chip>
            </div>
            <div class="task-meta">
              <span>{{ formatDate(task.created_at) }}</span>
              <template v-if="task.total">
                <span>·</span>
                <span>{{ task.completed }}/{{ task.total }} 完成</span>
              </template>
              <template v-if="task.failed_count">
                <span>·</span>
                <span class="error-text">{{ task.failed_count }} 失败</span>
              </template>
            </div>
            <div class="task-progress-row">
              <v-progress-linear
                :model-value="task.progress"
                :color="task.status === 'failed' ? 'error' : task.status === 'completed' ? 'success' : 'primary'"
                bg-color="surface-variant"
                height="5"
                rounded
              />
              <span class="progress-number">{{ Math.round(task.progress) }}%</span>
            </div>
            <v-alert
              v-if="task.error"
              type="error"
              variant="tonal"
              density="compact"
              class="task-error"
              :text="task.error"
            />
            <div v-if="task.status === 'partial'" class="task-warning">
              任务完成但存在失败句子。重新发起任务只会处理缺失或失败的部分。
            </div>
            <div v-if="resultRows(task).length" class="task-result">
              <span v-for="[label, value] in resultRows(task)" :key="label" class="result-item">
                {{ label }} <strong>{{ value }}</strong>
              </span>
            </div>
          </div>
          <div class="task-actions">
            <v-btn
              v-if="['queued', 'running'].includes(task.status)"
              size="small"
              variant="text"
              color="error"
              :loading="cancelling === task.id"
              @click="cancel(task.id)"
            >取消</v-btn>
            <v-btn
              v-if="task.chapter_id"
              size="small"
              variant="text"
              prepend-icon="mdi-arrow-top-right"
              @click="openTask(task)"
            >查看内容</v-btn>
            <v-btn
              v-if="['failed', 'partial'].includes(task.status) && task.chapter_id"
              size="small"
              variant="tonal"
              color="primary"
              prepend-icon="mdi-refresh"
              @click="retry(task)"
            >重试</v-btn>
          </div>
        </div>
      </v-card>
    </div>

    <EmptyState
      v-else-if="!loading"
      title="暂无任务"
      text="打开章节时若配置了 AI 模型，系统会自动创建翻译任务；知识抽取可在书籍详情页或任务接口中发起。"
      glyph="任"
    />
  </div>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import EmptyState from '@/components/EmptyState.vue'
import { translationApi } from '@/api/translation'
import { aiApi } from '@/api/ai'
import type { TaskInfo } from '@/api/types'
import { useAppStore } from '@/stores/app'
import { useTasksStore } from '@/stores/tasks'

const router = useRouter()
const app = useAppStore()
const tasks = useTasksStore()
const statusFilter = ref('')
const loading = ref(false)
const cancelling = ref('')
let interval: number | undefined

const filtered = computed(() => {
  let rows = [...tasks.tasks]
  if (statusFilter.value === 'running') {
    rows = rows.filter((task) => ['queued', 'running'].includes(task.status))
  } else if (statusFilter.value) {
    rows = rows.filter((task) => task.status === statusFilter.value)
  }
  return rows
})

function statusLabel(status: string): string {
  return ({
    queued: '排队中', running: '进行中', completed: '已完成',
    partial: '部分完成', failed: '失败', cancelled: '已取消',
  } as Record<string, string>)[status] || status
}
function statusColor(status: string): string {
  return ({
    queued: 'info', running: 'info', completed: 'success',
    partial: 'warning', failed: 'error', cancelled: 'default',
  } as Record<string, string>)[status] || 'default'
}
function typeLabel(type: string): string {
  return ({ translation: 'AI 翻译', knowledge_extraction: '知识抽取' } as Record<string, string>)[type] || type
}
function formatDate(value: string): string {
  return new Date(value).toLocaleString('zh-CN', {
    month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
  })
}
function resultRows(task: TaskInfo): Array<[string, unknown]> {
  const labels: Record<string, string> = {
    completed: '完成', failed: '失败', cached: '缓存命中', entities_created: '新建人物',
    entities_matched: '匹配人物', mentions_created: '提及', relations_created: '关系',
    events_created: '事件', event_sources: '事件出处', model: '模型', prompt_version: '提示词',
  }
  return Object.entries(task.result || {})
    .filter(([key]) => key in labels)
    .map(([key, value]) => [labels[key], value] as [string, unknown])
    .filter(([, value]) => value !== null && value !== undefined && value !== '')
}

async function refresh() {
  loading.value = true
  try {
    await tasks.load()
  } finally {
    loading.value = false
  }
}

async function cancel(taskId: string) {
  cancelling.value = taskId
  try {
    const task = await tasks.cancel(taskId)
    app.notify(task.status === 'cancelled' ? '任务已取消' : '已请求取消任务', 'warning')
  } finally {
    cancelling.value = ''
  }
}

function openTask(task: TaskInfo) {
  if (!task.book_id || !task.chapter_id) return
  router.push(`/read/${task.book_id}/${task.chapter_id}`)
}

async function retry(task: TaskInfo) {
  if (!task.chapter_id) return
  const created = task.type === 'translation'
    ? await translationApi.chapter(task.chapter_id, { only_failed: false })
    : await aiApi.extractKnowledge(task.chapter_id)
  tasks.upsert(created)
  app.notify('已重新创建任务')
}

onMounted(async () => {
  await refresh()
  interval = window.setInterval(() => { tasks.load() }, 5000)
})

onBeforeUnmount(() => {
  if (interval) window.clearInterval(interval)
})
</script>

<style scoped>
.header-actions {
  display: flex;
  align-items: center;
  gap: 10px;
}
.task-filters {
  display: flex;
  align-items: center;
  gap: 14px;
  margin-bottom: 16px;
}
.task-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.task-card {
  padding: 16px 18px;
  background: rgba(var(--v-theme-surface), 0.68);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.065);
}
.task-main {
  display: flex;
  gap: 14px;
  align-items: flex-start;
}
.task-status-icon {
  width: 34px;
  height: 34px;
  border-radius: 10px;
  display: grid;
  place-items: center;
  flex-shrink: 0;
  background: rgba(var(--v-theme-info), 0.08);
  color: rgb(var(--v-theme-info));
}
.task-status-icon.completed { background: rgba(var(--v-theme-success), 0.09); color: rgb(var(--v-theme-success)); }
.task-status-icon.failed { background: rgba(var(--v-theme-error), 0.09); color: rgb(var(--v-theme-error)); }
.task-status-icon.cancelled { background: rgba(var(--v-theme-on-surface), 0.06); color: rgba(var(--v-theme-on-surface), 0.4); }
.task-body {
  flex: 1;
  min-width: 0;
}
.task-title-row {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}
.task-title {
  font-size: 0.98rem;
  font-weight: 650;
}
.task-meta {
  display: flex;
  gap: 6px;
  margin-top: 4px;
  font-size: 0.66rem;
  color: rgba(var(--v-theme-on-surface), 0.42);
  flex-wrap: wrap;
}
.error-text {
  color: rgb(var(--v-theme-error));
}
.task-progress-row {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-top: 10px;
  max-width: 640px;
}
.progress-number {
  font-size: 0.66rem;
  color: rgba(var(--v-theme-on-surface), 0.42);
  font-variant-numeric: tabular-nums;
  width: 34px;
  text-align: right;
}
.task-error {
  margin-top: 10px;
  max-width: 700px;
}
.task-warning {
  margin-top: 9px;
  font-size: 0.72rem;
  color: rgb(var(--v-theme-warning));
}
.task-result {
  display: flex;
  flex-wrap: wrap;
  gap: 13px;
  margin-top: 10px;
  font-size: 0.68rem;
  color: rgba(var(--v-theme-on-surface), 0.46);
}
.result-item strong {
  color: rgba(var(--v-theme-on-surface), 0.72);
  font-weight: 600;
}
.task-actions {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 4px;
}
@media (max-width: 800px) {
  .task-main {
    flex-wrap: wrap;
  }
  .task-actions {
    flex-direction: row;
    width: 100%;
    justify-content: flex-end;
  }
}
</style>
