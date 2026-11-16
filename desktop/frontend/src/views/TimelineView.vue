<template>
  <div class="page timeline-page">
    <div class="page-header">
      <div>
        <div class="section-label">历史时间线</div>
        <h1 class="page-title">历史时间线</h1>
        <p class="page-subtitle">年号、干支与公元年份并置保留。无法确定的纪年不会被强行换算，而是单独列入“时间未详”。</p>
      </div>
      <v-btn variant="tonal" color="primary" prepend-icon="mdi-refresh" @click="loadTimeline">刷新</v-btn>
    </div>

    <v-card class="timeline-filter-card">
      <div class="timeline-filters">
        <v-select
          v-model="filters.eventType"
          :items="eventTypes"
          label="事件类型"
          density="comfortable"
          variant="solo"
          flat
          hide-details
          rounded="lg"
          clearable
          class="filter-select"
          @update:model-value="loadTimeline"
        />
        <v-text-field
          v-model="filters.dynasty"
          label="朝代"
          density="comfortable"
          variant="solo"
          flat
          hide-details
          rounded="lg"
          clearable
          class="filter-input"
          @keydown.enter="loadTimeline"
        />
        <v-switch
          v-model="filters.includeExtracted"
          label="包含 AI 抽取（待审）"
          color="primary"
          density="compact"
          hide-details
          @update:model-value="loadTimeline"
        />
        <v-spacer />
        <span class="tiny muted">{{ dated.length }} 条有明确年份 · {{ undated.length }} 条时间未详</span>
      </div>
    </v-card>

    <div class="timeline-layout">
      <v-card class="chart-card">
        <div ref="chartContainer" class="timeline-chart" />
        <v-progress-linear v-if="loading" indeterminate color="primary" class="chart-loading" />
        <div v-if="!loading && !dated.length" class="chart-empty">
          <div class="chart-empty-glyph serif">时</div>
          <div class="chart-empty-title serif">暂无可定位到年的时间线</div>
          <p>运行章节知识抽取后，带有年号或公元纪年的事件会显示在这里。时间不详的事件仍会保留在下方。</p>
          <v-btn color="primary" variant="tonal" @click="router.push('/tasks')">前往任务中心</v-btn>
        </div>
      </v-card>

      <v-card class="event-side">
        <div v-if="selectedEvent" class="event-detail">
          <div class="event-detail-head">
            <v-chip size="x-small" variant="tonal" :color="statusColor(selectedEvent.status)">
              {{ statusLabel(selectedEvent.status) }}
            </v-chip>
            <v-chip size="x-small" variant="tonal">{{ selectedEvent.event_type }}</v-chip>
            <v-spacer />
            <v-btn icon="mdi-close" size="small" variant="text" @click="selectedEvent = null" />
          </div>
          <h2 class="event-title serif">{{ selectedEvent.name }}</h2>
          <div class="event-time">
            {{ selectedEvent.time_raw || '时间未详' }}
            <span v-if="selectedEvent.time_start_year !== null"> · {{ formatYear(selectedEvent.time_start_year) }}</span>
          </div>
          <div class="event-meta-line">
            {{ selectedEvent.dynasty || '朝代未详' }} · 精度 {{ precisionLabel(selectedEvent.time_precision) }}
          </div>
          <div v-if="selectedEvent.time_note" class="event-note">{{ selectedEvent.time_note }}</div>

          <p v-if="selectedEvent.description" class="event-description">{{ selectedEvent.description }}</p>

          <div v-if="selectedEvent.participants?.length" class="event-section">
            <div class="section-label">参与者</div>
            <div class="participant-chips">
              <v-chip
                v-for="participant in selectedEvent.participants"
                :key="participant.entity_id"
                size="small"
                variant="tonal"
                color="primary"
                @click="router.push(`/entities?entity=${participant.entity_id}`)"
              >
                {{ participant.name }}
              </v-chip>
            </div>
          </div>

          <div class="event-section">
            <div class="section-label">史料出处</div>
            <div v-if="!selectedEvent.sources?.length" class="tiny muted">暂无史料来源。</div>
            <div v-for="source in selectedEvent.sources" :key="source.id" class="event-source">
              <div class="serif event-quote">{{ source.quote }}</div>
              <div class="tiny muted">{{ source.book_title }} · {{ source.chapter_title }}</div>
            </div>
          </div>

          <div class="event-actions">
            <v-btn
              v-if="selectedEvent.status !== 'confirmed'"
              size="small"
              color="success"
              variant="tonal"
              @click="review(selectedEvent, 'confirmed')"
            >确认史实</v-btn>
            <v-btn
              v-if="selectedEvent.status !== 'rejected'"
              size="small"
              variant="text"
              @click="review(selectedEvent, 'rejected')"
            >驳回</v-btn>
          </div>
        </div>

        <div v-else class="event-side-empty">
          <div class="side-glyph serif">史</div>
          <div class="side-title serif">选择一个事件</div>
          <p>查看原始纪年、标准化年份、参与者与史料出处。不同史书的冲突记载会分别保留。</p>
        </div>
      </v-card>
    </div>

    <div v-if="undated.length" class="undated-section">
      <div class="section-label">时间待考</div>
      <div class="undated-grid">
        <v-card
          v-for="event in undated"
          :key="event.id"
          class="undated-card"
          @click="selectEvent(event)"
        >
          <div class="undated-meta">
            <v-chip size="x-small" variant="tonal" :color="statusColor(event.status)">{{ statusLabel(event.status) }}</v-chip>
            <span>{{ event.event_type }}</span>
          </div>
          <div class="undated-title serif">{{ event.name }}</div>
          <div class="undated-time">{{ event.time_raw || '原文未给出可换算时间' }}</div>
          <div class="tiny muted">{{ event.time_note }}</div>
        </v-card>
      </div>
    </div>

    <v-alert v-if="error" type="error" variant="tonal" class="mt-5" :text="error" />
  </div>
</template>

<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import * as echarts from 'echarts'
import { knowledgeApi } from '@/api/knowledge'
import type { HistoricalEvent } from '@/api/types'
import { useAppStore } from '@/stores/app'

const route = useRoute()
const router = useRouter()
const app = useAppStore()
const chartContainer = ref<HTMLElement | null>(null)
const dated = ref<HistoricalEvent[]>([])
const undated = ref<HistoricalEvent[]>([])
const selectedEvent = ref<HistoricalEvent | null>(null)
const loading = ref(false)
const error = ref('')
let chart: echarts.ECharts | null = null
let resizeObserver: ResizeObserver | null = null

const filters = reactive({
  eventType: null as string | null,
  dynasty: '',
  includeExtracted: true,
})

const eventTypes = ['政治', '战争', '外交', '经济', '文化', '社会', '自然灾害', '其他']
const typeColors: Record<string, string> = {
  政治: '#8a5a44', 战争: '#a53b35', 外交: '#3b6475', 经济: '#9a6a34',
  文化: '#7b5675', 社会: '#5f6b4f', 自然灾害: '#b3543f', 其他: '#77756d',
}
const eventMap = computed(() => {
  const map = new Map<string, HistoricalEvent>()
  dated.value.forEach((event) => map.set(event.id, event))
  undated.value.forEach((event) => map.set(event.id, event))
  return map
})

function formatYear(year: number): string {
  return year < 0 ? `公元前 ${Math.abs(year)} 年` : `公元 ${year} 年`
}

function precisionLabel(precision: string): string {
  return ({
    exact: '精确日期', day: '日', month: '月', year: '年', range: '时间区间', circa: '约略', unknown: '未知',
  } as Record<string, string>)[precision] || precision
}

function statusLabel(status: string): string {
  return ({ confirmed: '已确认', extracted: '待审核', rejected: '已驳回' } as Record<string, string>)[status] || status
}
function statusColor(status: string): string {
  return ({ confirmed: 'success', extracted: 'warning', rejected: 'error' } as Record<string, string>)[status] || 'default'
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  } as Record<string, string>)[char])
}

async function loadTimeline() {
  loading.value = true
  error.value = ''
  try {
    const data = await knowledgeApi.timeline({
      event_type: filters.eventType || undefined,
      dynasty: filters.dynasty || undefined,
      include_extracted: filters.includeExtracted,
    })
    dated.value = data.events
    undated.value = data.undated
    const queryId = typeof route.query.event === 'string' ? route.query.event : ''
    const target = queryId ? eventMap.value.get(queryId) : null
    if (target) selectedEvent.value = await knowledgeApi.event(target.id)
    else if (selectedEvent.value) {
      const refreshed = eventMap.value.get(selectedEvent.value.id)
      selectedEvent.value = refreshed ? await knowledgeApi.event(refreshed.id) : null
    } else if (data.events.length) {
      selectedEvent.value = await knowledgeApi.event(data.events[0].id)
    }
    await nextTick()
    renderChart()
  } catch (err) {
    error.value = err instanceof Error ? err.message : '时间线加载失败'
  } finally {
    loading.value = false
  }
}

function renderChart() {
  if (!chartContainer.value) return
  if (!chart) {
    chart = echarts.init(chartContainer.value)
    chart.on('click', (params: any) => {
      const eventId = params?.data?.[2]
      if (eventId) {
        const event = eventMap.value.get(eventId)
        if (event) openEvent(event)
      }
    })
  }
  const presentTypes = [...new Set(dated.value.map((event) => event.event_type))]
  const categories = presentTypes.length ? presentTypes : eventTypes
  const years = dated.value.flatMap((event) => [event.time_start_year, event.time_end_year])
    .filter((value): value is number => value !== null)
  const minYear = years.length ? Math.min(...years) - 20 : -500
  const maxYear = years.length ? Math.max(...years) + 20 : 2000
  const series = categories.map((type) => {
    const items = dated.value.filter((event) => event.event_type === type)
    if (!items.length) return null
    return {
      name: type,
      type: 'scatter',
      symbolSize: (value: unknown[]) => {
        const event = eventMap.value.get(String(value?.[2] || ''))
        return event?.status === 'confirmed' ? 15 : 11
      },
      itemStyle: {
        color: typeColors[type] || '#77756d',
        borderColor: 'rgba(251,247,239,0.9)',
        borderWidth: 1.5,
        shadowBlur: 6,
        shadowColor: 'rgba(20,30,25,0.14)',
      },
      emphasis: { scale: 1.5 },
      data: dated.value
        .filter((event) => event.event_type === type)
        .map((event) => [
          event.time_start_year,
          categories.indexOf(type),
          event.id,
          event.name,
        ]),
    }
  }).filter(Boolean)

  chart.setOption({
    backgroundColor: 'transparent',
    animation: false,
    grid: { left: 78, right: 30, top: 36, bottom: 82 },
    tooltip: {
      trigger: 'item',
      borderWidth: 0,
      padding: 12,
      backgroundColor: app.theme === 'dark' ? 'rgba(24,33,29,0.96)' : 'rgba(251,247,239,0.98)',
      textStyle: { color: app.theme === 'dark' ? '#e7e2d6' : '#2d2a24', fontSize: 12 },
      extraCssText: 'border-radius:10px;box-shadow:0 10px 30px rgba(0,0,0,.16);',
      formatter: (params: any) => {
        const event = eventMap.value.get(params.data[2])
        if (!event) return ''
        const participants = (event.participants || []).map((item) => escapeHtml(item.name)).join('、')
        return `<div style="font-weight:600;margin-bottom:4px">${escapeHtml(event.name)}</div>
          <div style="opacity:.66">${escapeHtml(event.time_raw || '时间未详')} · ${escapeHtml(event.event_type)}</div>
          ${participants ? `<div style="margin-top:5px;font-size:11px;opacity:.6">参与者：${participants}</div>` : ''}
          <div style="margin-top:6px;font-size:11px;opacity:.5">${escapeHtml(statusLabel(event.status))} · 点击查看史料</div>`
      },
    },
    xAxis: {
      type: 'value',
      min: minYear,
      max: maxYear,
      axisLabel: {
        color: app.theme === 'dark' ? 'rgba(231,226,214,.48)' : 'rgba(45,42,36,.48)',
        fontSize: 10,
        formatter: (value: number) => value < 0 ? `前${Math.abs(value)}` : `${value}`,
      },
      axisLine: { lineStyle: { color: 'rgba(128,128,120,.25)' } },
      splitLine: { show: true, lineStyle: { color: 'rgba(128,128,120,.08)' } },
    },
    yAxis: {
      type: 'category',
      data: categories,
      axisLabel: {
        color: app.theme === 'dark' ? 'rgba(231,226,214,.6)' : 'rgba(45,42,36,.6)',
        fontSize: 11,
      },
      axisLine: { show: false },
      axisTick: { show: false },
      splitLine: { show: true, lineStyle: { color: 'rgba(128,128,120,.07)' } },
    },
    dataZoom: [
      { type: 'inside', xAxisIndex: 0, filterMode: 'none' },
      {
        type: 'slider',
        xAxisIndex: 0,
        height: 20,
        bottom: 20,
        borderColor: 'transparent',
        backgroundColor: 'rgba(128,128,120,.06)',
        fillerColor: 'rgba(28,90,76,.12)',
        handleStyle: { color: 'rgba(28,90,76,.4)' },
        textStyle: { color: 'rgba(128,128,120,.6)', fontSize: 9 },
      },
    ],
    series,
  }, true)
}

async function openEvent(event: HistoricalEvent) {
  selectedEvent.value = await knowledgeApi.event(event.id)
  if (route.query.event !== event.id) {
    router.replace({ query: { ...route.query, event: event.id } })
  }
}

function selectEvent(event: HistoricalEvent) {
  openEvent(event)
}

async function review(event: HistoricalEvent, status: string) {
  await knowledgeApi.reviewEvent(event.id, status)
  selectedEvent.value = await knowledgeApi.event(event.id)
  await loadTimeline()
}

function handleResize() {
  chart?.resize()
}

onMounted(async () => {
  await loadTimeline()
  resizeObserver = new ResizeObserver(handleResize)
  if (chartContainer.value) resizeObserver.observe(chartContainer.value)
})

onBeforeUnmount(() => {
  resizeObserver?.disconnect()
  chart?.dispose()
  chart = null
})
</script>

<style scoped>
.timeline-page {
  max-width: 1500px;
}
.timeline-filter-card {
  padding: 14px 18px;
  margin-bottom: 14px;
  background: rgba(var(--v-theme-surface), 0.68);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.07);
}
.timeline-filters {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}
.filter-select {
  max-width: 155px;
  background: rgba(var(--v-theme-surface), 0.55);
}
.filter-input {
  max-width: 135px;
  background: rgba(var(--v-theme-surface), 0.55);
}
.timeline-layout {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 340px;
  gap: 14px;
  align-items: stretch;
}
.chart-card {
  position: relative;
  overflow: hidden;
  min-height: 540px;
  background: rgba(var(--v-theme-surface), 0.66);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.07);
}
.timeline-chart {
  width: 100%;
  height: 540px;
}
.chart-loading {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
}
.chart-empty {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 38px;
  color: rgba(var(--v-theme-on-surface), 0.5);
  pointer-events: none;
}
.chart-empty-glyph {
  width: 64px;
  height: 64px;
  border-radius: 18px;
  display: grid;
  place-items: center;
  font-size: 1.6rem;
  background: rgba(var(--v-theme-primary), 0.06);
  color: rgba(var(--v-theme-primary), 0.55);
  margin-bottom: 14px;
}
.chart-empty-title {
  font-size: 1.1rem;
  font-weight: 650;
}
.chart-empty p {
  max-width: 420px;
  font-size: 0.8rem;
  line-height: 1.75;
}
.chart-empty .v-btn {
  pointer-events: auto;
}
.event-side {
  padding: 20px;
  background: rgba(var(--v-theme-surface), 0.68);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.07);
  max-height: 640px;
  overflow-y: auto;
}
.event-detail-head {
  display: flex;
  align-items: center;
  gap: 6px;
}
.event-title {
  font-size: 1.45rem;
  font-weight: 650;
  line-height: 1.35;
  margin: 12px 0 6px;
}
.event-time {
  font-size: 0.78rem;
  color: rgb(var(--v-theme-primary));
}
.event-meta-line {
  font-size: 0.67rem;
  color: rgba(var(--v-theme-on-surface), 0.42);
  margin-top: 4px;
}
.event-note {
  margin-top: 9px;
  padding: 8px 10px;
  border-radius: 8px;
  background: rgba(var(--v-theme-warning), 0.07);
  font-size: 0.7rem;
  line-height: 1.6;
  color: rgba(var(--v-theme-on-surface), 0.56);
}
.event-description {
  font-size: 0.82rem;
  line-height: 1.8;
  color: rgba(var(--v-theme-on-surface), 0.66);
  margin-top: 14px;
}
.event-section {
  margin-top: 18px;
  padding-top: 13px;
  border-top: 1px dashed rgba(var(--v-theme-on-surface), 0.1);
}
.participant-chips {
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
  margin-top: 8px;
}
.event-source {
  margin-top: 8px;
  padding-left: 9px;
  border-left: 2px solid rgba(var(--v-theme-secondary), 0.5);
}
.event-quote {
  font-size: 0.78rem;
  line-height: 1.7;
  color: rgba(var(--v-theme-on-surface), 0.68);
}
.event-actions {
  display: flex;
  gap: 7px;
  margin-top: 18px;
}
.event-side-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  min-height: 360px;
  color: rgba(var(--v-theme-on-surface), 0.45);
  padding: 20px;
}
.side-glyph {
  width: 56px;
  height: 56px;
  border-radius: 16px;
  display: grid;
  place-items: center;
  background: rgba(var(--v-theme-primary), 0.055);
  color: rgba(var(--v-theme-primary), 0.55);
  font-size: 1.4rem;
  margin-bottom: 12px;
}
.side-title {
  font-size: 1.05rem;
  font-weight: 650;
}
.event-side-empty p {
  font-size: 0.78rem;
  line-height: 1.75;
}
.undated-section {
  margin-top: 28px;
}
.undated-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
  gap: 11px;
  margin-top: 10px;
}
.undated-card {
  padding: 15px;
  cursor: pointer;
  background: rgba(var(--v-theme-surface), 0.64);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.065);
}
.undated-meta {
  display: flex;
  align-items: center;
  gap: 7px;
  font-size: 0.66rem;
  color: rgba(var(--v-theme-on-surface), 0.44);
}
.undated-title {
  font-size: 1.02rem;
  font-weight: 650;
  margin-top: 7px;
}
.undated-time {
  font-size: 0.72rem;
  color: rgba(var(--v-theme-secondary), 0.9);
  margin: 4px 0 3px;
}
@media (max-width: 1100px) {
  .timeline-layout {
    grid-template-columns: 1fr;
  }
  .event-side {
    max-height: none;
  }
}
</style>
