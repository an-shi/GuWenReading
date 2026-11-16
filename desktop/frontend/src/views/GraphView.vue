<template>
  <div class="page graph-page">
    <div class="page-header">
      <div>
        <div class="section-label">人物关系图</div>
        <h1 class="page-title">人物关系图谱</h1>
        <p class="page-subtitle">关系来自原文证据或人工确认。虚线为 AI 推断，必须经过审核才可视为确定关系。</p>
      </div>
      <v-btn variant="tonal" color="primary" prepend-icon="mdi-refresh" @click="loadGraph">刷新图谱</v-btn>
    </div>

    <v-card class="graph-filter-card">
      <div class="graph-filters">
        <v-autocomplete
          v-model="filters.centerId"
          :items="entityOptions"
          item-title="title"
          item-value="value"
          label="以人物为中心"
          density="comfortable"
          variant="solo"
          flat
          hide-details
          rounded="lg"
          clearable
          :loading="searchingEntity"
          class="center-autocomplete"
          @update:search="searchEntityOptions"
          @update:model-value="loadGraph"
        />
        <v-select
          v-model="filters.dynasty"
          :items="dynastyOptions"
          label="朝代"
          density="comfortable"
          variant="solo"
          flat
          hide-details
          rounded="lg"
          clearable
          class="graph-select"
          @update:model-value="loadGraph"
        />
        <v-select
          v-model="filters.relationType"
          :items="relationTypes"
          label="关系类型"
          density="comfortable"
          variant="solo"
          flat
          hide-details
          rounded="lg"
          clearable
          class="graph-select"
          @update:model-value="loadGraph"
        />
        <div class="depth-control">
          <span class="tiny muted">层级 {{ filters.depth }}</span>
          <v-slider
            v-model="filters.depth"
            :min="1"
            :max="3"
            :step="1"
            hide-details
            density="compact"
            color="primary"
            @update:model-value="loadGraph"
          />
        </div>
        <v-switch
          v-model="filters.includePending"
          label="包含待审关系"
          color="primary"
          density="compact"
          hide-details
          @update:model-value="loadGraph"
        />
      </div>
    </v-card>

    <div class="graph-layout">
      <v-card class="graph-card">
        <div class="graph-toolbar">
          <div class="graph-legend">
            <span><i class="legend-dot person" />人物</span>
            <span><i class="legend-line inferred" />AI 推断</span>
            <span><i class="legend-line confirmed" />已确认</span>
          </div>
          <v-spacer />
          <v-btn size="small" variant="text" prepend-icon="mdi-fit-to-page-outline" @click="fitGraph">适应画布</v-btn>
          <v-btn size="small" variant="text" prepend-icon="mdi-image-filter-center-focus" @click="centerGraph">居中</v-btn>
        </div>
        <div ref="graphContainer" class="graph-container" />
        <div v-if="!graphLoading && !graphData.nodes.length" class="graph-empty">
          <div class="graph-empty-glyph serif">谱</div>
          <div class="graph-empty-title serif">关系图谱尚未建立</div>
          <p>在书籍章节中运行知识抽取，或从人物知识库人工添加关系。AI 推断的关系会以待审状态显示。</p>
          <v-btn color="primary" variant="tonal" @click="router.push('/tasks')">前往任务中心</v-btn>
        </div>
        <v-progress-linear v-if="graphLoading" indeterminate color="primary" class="graph-loading" />
      </v-card>

      <v-card class="graph-side">
        <div v-if="selectedEntity" class="entity-panel">
          <div class="entity-panel-head">
            <div class="entity-seal serif">{{ selectedEntity.canonical_name.slice(0, 1) }}</div>
            <div>
              <div class="entity-panel-name serif">{{ selectedEntity.canonical_name }}</div>
              <div class="entity-panel-meta">
                {{ selectedEntity.dynasty || '朝代未详' }} · {{ selectedEntity.identity || entityKindLabel(selectedEntity.kind) }}
              </div>
            </div>
          </div>
          <div class="entity-panel-stats">
            <div><strong>{{ selectedEntity.mentions?.length || 0 }}</strong><span>原文提及</span></div>
            <div><strong>{{ selectedEntity.relations?.length || 0 }}</strong><span>人物关系</span></div>
          </div>
          <p v-if="selectedEntity.summary" class="entity-panel-summary">{{ selectedEntity.summary }}</p>
          <div v-if="selectedEntity.aliases.length" class="entity-alias">别名：{{ selectedEntity.aliases.join('、') }}</div>

          <div class="panel-actions">
            <v-btn size="small" variant="tonal" color="primary" @click="router.push(`/entities?entity=${selectedEntity.id}`)">
              完整资料
            </v-btn>
            <v-btn size="small" variant="text" @click="setCenter(selectedEntity.id)">以此人为中心</v-btn>
          </div>

          <div class="panel-section">
            <div class="section-label">关系</div>
            <div v-if="!selectedEntity.relations?.length" class="tiny muted">暂无关系记录。</div>
            <div v-for="relation in selectedEntity.relations" :key="relation.id" class="panel-relation">
              <div class="panel-relation-head">
                <v-chip size="x-small" variant="tonal" :color="relationColor(relation.status)">{{ relationStatusLabel(relation.status) }}</v-chip>
                <span>{{ relation.relation_type }}</span>
                <strong class="serif">{{ relation.other_entity_name }}</strong>
              </div>
              <div v-if="relation.sources?.length" class="panel-evidence serif">
                {{ relation.sources[0].quote }}
              </div>
            </div>
          </div>

          <div class="panel-section">
            <div class="section-label">提及</div>
            <div
              v-if="selectedEntity.mentions?.length"
              class="mention-jump"
              @click="openMention(selectedEntity.mentions[0])"
            >
              <div class="serif">{{ selectedEntity.mentions[0].quote }}</div>
              <div class="tiny muted">{{ selectedEntity.mentions[0].book_title }} · {{ selectedEntity.mentions[0].chapter_title }}</div>
            </div>
            <div v-else class="tiny muted">暂无原文提及。</div>
          </div>
        </div>
        <div v-else class="graph-side-empty">
          <div class="side-glyph serif">点</div>
          <p>点击图谱中的人物，查看资料、关系类型与原文证据。</p>
        </div>
      </v-card>
    </div>

    <v-alert v-if="error" type="error" variant="tonal" class="mt-4" :text="error" />
  </div>
</template>

<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { Graph } from '@antv/g6'
import { knowledgeApi } from '@/api/knowledge'
import type { EntityMention, GraphData, HistoricalEntity } from '@/api/types'
import { useAppStore } from '@/stores/app'

const router = useRouter()
const app = useAppStore()
const graphContainer = ref<HTMLElement | null>(null)
const graphData = ref<GraphData>({ nodes: [], edges: [], truncated: false, center_id: null })
const selectedEntity = ref<HistoricalEntity | null>(null)
const graphLoading = ref(false)
const searchingEntity = ref(false)
const error = ref('')
const entityOptions = ref<Array<{ title: string; value: string }>>([])
let graph: Graph | null = null
let resizeObserver: ResizeObserver | null = null

const filters = reactive({
  centerId: null as string | null,
  dynasty: null as string | null,
  relationType: null as string | null,
  depth: 2,
  includePending: true,
})

const dynastyOptions = ['上古', '夏', '商', '周', '秦', '汉', '三国', '晋', '南北朝', '隋', '唐', '五代', '宋', '辽', '金', '元', '明', '清']
const relationTypes = ['父子', '母子', '兄弟', '夫妻', '君臣', '主从', '同盟', '敌对', '师生', '任职', '其他']

function themeColors() {
  const dark = app.theme === 'dark'
  return {
    label: dark ? '#e7e2d6' : '#2d2a24',
    edge: dark ? 'rgba(160, 190, 180, 0.35)' : 'rgba(28, 90, 76, 0.28)',
    edgeLabel: dark ? 'rgba(231, 226, 214, 0.6)' : 'rgba(45, 42, 36, 0.55)',
    labelBg: dark ? 'rgba(17,24,21,0.8)' : 'rgba(251,247,239,0.86)',
    stroke: dark ? '#18211d' : '#fbf7ef',
  }
}

function nodeColor(kind: string): string {
  return ({
    person: '#1c5a4c', place: '#3b6475', office: '#9a6a34', dynasty: '#8a5a44',
    institution: '#5f6b4f', work: '#7b5675', other: '#6f746c',
  } as Record<string, string>)[kind] || '#6f746c'
}

function relationColor(status: string): string {
  return ({ confirmed: 'success', explicit: 'info', inferred: 'warning', rejected: 'error' } as Record<string, string>)[status] || 'default'
}

function relationStatusLabel(status: string): string {
  return ({
    confirmed: '已确认', explicit: '原文明确', inferred: 'AI 推断', rejected: '已驳回',
  } as Record<string, string>)[status] || status
}

function entityKindLabel(kind: string): string {
  return ({
    person: '人物', place: '地点', dynasty: '朝代/政权', office: '职官',
    institution: '机构', work: '典籍', other: '其他',
  } as Record<string, string>)[kind] || kind
}

async function loadGraph() {
  graphLoading.value = true
  error.value = ''
  try {
    graphData.value = await knowledgeApi.graph({
      center_id: filters.centerId || undefined,
      depth: filters.depth,
      dynasty: filters.dynasty || undefined,
      relation_type: filters.relationType || undefined,
      include_pending: filters.includePending,
    })
    if (selectedEntity.value) {
      const exists = graphData.value.nodes.find((node) => node.id === selectedEntity.value?.id)
      if (!exists) selectedEntity.value = null
    }
    if (!selectedEntity.value && graphData.value.nodes.length) {
      const pick = graphData.value.center_id
        ? graphData.value.nodes.find((node) => node.id === graphData.value.center_id)
        : [...graphData.value.nodes].sort((a, b) => b.degree - a.degree)[0]
      if (pick) await openEntity(pick.id)
    }
    await nextTick()
    renderGraph()
  } catch (err) {
    error.value = err instanceof Error ? err.message : '图谱加载失败'
  } finally {
    graphLoading.value = false
  }
}

function renderGraph() {
  if (!graphContainer.value) return
  graph?.destroy()
  const colors = themeColors()
  const width = graphContainer.value.clientWidth || 800
  const height = graphContainer.value.clientHeight || 560
  const data = {
    nodes: graphData.value.nodes.map((node) => ({
      id: node.id,
      data: {
        label: node.label,
        kind: node.kind,
        dynasty: node.dynasty,
        status: node.status,
        degree: node.degree,
      },
      style: {
        size: 38 + Math.min(node.degree, 10) * 2.6,
        fill: nodeColor(node.kind),
        stroke: colors.stroke,
        lineWidth: 3,
        labelText: node.label,
        labelPlacement: 'bottom' as const,
        labelFill: colors.label,
        labelFontSize: 13,
        labelFontFamily: '"Noto Serif SC", "Songti SC", serif',
        labelBackground: true,
        labelBackgroundFill: colors.labelBg,
        labelBackgroundRadius: 4,
        labelPadding: [2, 6],
      },
    })),
    edges: graphData.value.edges.map((edge) => ({
      id: edge.id,
      source: edge.source,
      target: edge.target,
      data: {
        label: edge.label || edge.relation_type,
        status: edge.status,
      },
      style: {
        stroke: edge.status === 'confirmed'
          ? 'rgba(63,107,79,0.65)'
          : edge.status === 'inferred'
            ? 'rgba(164,118,44,0.6)'
            : colors.edge,
        lineWidth: 1.4,
        lineDash: edge.status === 'inferred' ? [5, 4] : [],
        endArrow: true,
        endArrowSize: 6,
        labelText: edge.label || edge.relation_type,
        labelFontSize: 10,
        labelFill: colors.edgeLabel,
        labelBackground: true,
        labelBackgroundFill: colors.labelBg,
        labelPadding: [2, 5],
        labelBackgroundRadius: 3,
        labelOpacity: 0.9,
      },
    })),
  }
  graph = new Graph({
    container: graphContainer.value,
    width,
    height,
    background: 'transparent',
    data,
    node: {
      style: {
        stroke: colors.stroke,
        lineWidth: 2,
        cursor: 'pointer',
      },
    },
    edge: {
      style: {
        endArrow: true,
      },
    },
    layout: graphData.value.nodes.length <= 8 ? {
      type: 'circular',
      radius: 170,
      startAngle: -Math.PI / 2,
      clockwise: true,
      sortBy: 'degree',
    } : {
      type: 'concentric',
      sortBy: 'degree',
      preventOverlap: true,
      nodeSize: 64,
      equidistant: true,
      startAngle: -Math.PI / 2,
    },
    behaviors: ['drag-canvas', 'zoom-canvas', 'drag-element'],
    autoFit: 'view',
    padding: 50,
    animation: false,
  })
  graph.on('node:click', async (event: any) => {
    const id = event?.target?.id || event?.target?.attributes?.id
    if (!id) return
    const node = graphData.value.nodes.find((item) => item.id === id)
    if (!node) return
    await openEntity(node.id)
  })
  graph.render().then(() => {
    ;(window as unknown as { __guwenGraph?: unknown }).__guwenGraph = graph
    graph?.fitView()
  }).catch((error) => {
    console.error('G6 render failed', error)
  })
  resizeObserver?.disconnect()
  resizeObserver = new ResizeObserver(() => {
    if (graph && graphContainer.value) {
      graph.resize(graphContainer.value.clientWidth, graphContainer.value.clientHeight)
    }
  })
  resizeObserver.observe(graphContainer.value)
}

async function openEntity(id: string) {
  selectedEntity.value = await knowledgeApi.entity(id)
}

function fitGraph() {
  graph?.fitView()
}

function centerGraph() {
  graph?.fitCenter()
}

function setCenter(id: string) {
  filters.centerId = id
  loadGraph()
}

function openMention(mention: EntityMention) {
  router.push(`/read/${mention.book_id}/${mention.chapter_id}?highlight=${mention.sentence_id}`)
}

let searchTimer: number | undefined
function searchEntityOptions(query: string) {
  window.clearTimeout(searchTimer)
  if (!query.trim()) return
  searchTimer = window.setTimeout(async () => {
    searchingEntity.value = true
    try {
      const entities = await knowledgeApi.searchEntities(query)
      entityOptions.value = entities.map((entity) => ({
        title: `${entity.canonical_name}${entity.dynasty ? `（${entity.dynasty}）` : ''}`,
        value: entity.id,
      }))
    } finally {
      searchingEntity.value = false
    }
  }, 260)
}

onMounted(async () => {
  await loadGraph()
})

onBeforeUnmount(() => {
  graph?.destroy()
  graph = null
  resizeObserver?.disconnect()
  window.clearTimeout(searchTimer)
})
</script>

<style scoped>
.graph-page {
  max-width: 1500px;
}
.graph-filter-card {
  padding: 14px 18px;
  margin-bottom: 14px;
  background: rgba(var(--v-theme-surface), 0.68);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.07);
}
.graph-filters {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}
.center-autocomplete {
  max-width: 250px;
  min-width: 190px;
  background: rgba(var(--v-theme-surface), 0.55);
}
.graph-select {
  max-width: 145px;
  background: rgba(var(--v-theme-surface), 0.55);
}
.depth-control {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 170px;
}
.depth-control .v-slider {
  flex: 1;
}
.graph-layout {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 320px;
  gap: 14px;
  align-items: stretch;
}
.graph-card {
  position: relative;
  overflow: hidden;
  background:
    radial-gradient(at 20% 20%, rgba(28, 90, 76, 0.045), transparent 50%),
    radial-gradient(at 80% 80%, rgba(154, 106, 52, 0.045), transparent 46%),
    rgba(var(--v-theme-surface), 0.66);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.07);
  min-height: 620px;
}
.graph-toolbar {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  z-index: 3;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 14px;
  background: rgba(var(--v-theme-surface), 0.72);
  backdrop-filter: blur(10px);
  border-bottom: 1px solid rgba(var(--v-theme-on-surface), 0.06);
}
.graph-legend {
  display: flex;
  gap: 14px;
  font-size: 0.67rem;
  color: rgba(var(--v-theme-on-surface), 0.48);
  align-items: center;
}
.graph-legend span {
  display: flex;
  align-items: center;
  gap: 4px;
}
.legend-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #1c5a4c;
}
.legend-line {
  width: 18px;
  border-top: 2px solid rgba(45, 42, 36, 0.28);
}
.legend-line.inferred {
  border-top-style: dashed;
  border-color: rgba(164, 118, 44, 0.7);
}
.legend-line.confirmed {
  border-color: rgba(63, 107, 79, 0.7);
}
.graph-container {
  width: 100%;
  height: 620px;
}
.graph-loading {
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  z-index: 4;
}
.graph-empty {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 40px;
  color: rgba(var(--v-theme-on-surface), 0.5);
  pointer-events: none;
}
.graph-empty-glyph {
  width: 68px;
  height: 68px;
  border-radius: 20px;
  display: grid;
  place-items: center;
  font-size: 1.7rem;
  background: rgba(var(--v-theme-primary), 0.06);
  color: rgba(var(--v-theme-primary), 0.6);
  margin-bottom: 14px;
}
.graph-empty-title {
  font-size: 1.15rem;
  font-weight: 650;
}
.graph-empty p {
  max-width: 400px;
  font-size: 0.8rem;
  line-height: 1.75;
}
.graph-empty .v-btn {
  pointer-events: auto;
}
.graph-side {
  padding: 18px;
  background: rgba(var(--v-theme-surface), 0.68);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.07);
}
.entity-panel-head {
  display: flex;
  align-items: center;
  gap: 12px;
}
.entity-seal {
  width: 46px;
  height: 46px;
  border-radius: 14px;
  background: rgba(var(--v-theme-primary), 0.09);
  color: rgb(var(--v-theme-primary));
  display: grid;
  place-items: center;
  font-size: 1.25rem;
}
.entity-panel-name {
  font-size: 1.18rem;
  font-weight: 650;
}
.entity-panel-meta {
  font-size: 0.68rem;
  color: rgba(var(--v-theme-on-surface), 0.46);
  margin-top: 2px;
}
.entity-panel-stats {
  display: flex;
  gap: 30px;
  margin: 18px 0 14px;
}
.entity-panel-stats > div {
  display: flex;
  flex-direction: column;
}
.entity-panel-stats strong {
  font-family: "Noto Serif SC", "Songti SC", serif;
  font-size: 1.25rem;
  font-weight: 650;
}
.entity-panel-stats span {
  font-size: 0.65rem;
  color: rgba(var(--v-theme-on-surface), 0.42);
}
.entity-panel-summary {
  font-size: 0.78rem;
  line-height: 1.75;
  color: rgba(var(--v-theme-on-surface), 0.6);
}
.entity-alias {
  font-size: 0.68rem;
  color: rgba(var(--v-theme-on-surface), 0.44);
  margin-top: 8px;
}
.panel-actions {
  display: flex;
  gap: 6px;
  margin-top: 14px;
  flex-wrap: wrap;
}
.panel-section {
  margin-top: 20px;
  padding-top: 14px;
  border-top: 1px dashed rgba(var(--v-theme-on-surface), 0.1);
}
.panel-relation {
  padding: 8px 0;
  border-bottom: 1px dashed rgba(var(--v-theme-on-surface), 0.06);
}
.panel-relation-head {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 0.74rem;
  color: rgba(var(--v-theme-on-surface), 0.48);
}
.panel-relation-head strong {
  color: rgba(var(--v-theme-on-surface), 0.8);
  font-size: 0.84rem;
}
.panel-evidence {
  font-size: 0.74rem;
  line-height: 1.65;
  color: rgba(var(--v-theme-on-surface), 0.54);
  padding-left: 9px;
  border-left: 2px solid rgba(var(--v-theme-secondary), 0.4);
  margin-top: 5px;
}
.mention-jump {
  cursor: pointer;
  font-size: 0.8rem;
  line-height: 1.7;
  padding: 8px;
  border-radius: 8px;
  background: rgba(var(--v-theme-secondary), 0.05);
}
.mention-jump:hover {
  background: rgba(var(--v-theme-secondary), 0.09);
}
.graph-side-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  min-height: 300px;
  color: rgba(var(--v-theme-on-surface), 0.44);
  padding: 20px;
}
.side-glyph {
  width: 54px;
  height: 54px;
  border-radius: 16px;
  display: grid;
  place-items: center;
  background: rgba(var(--v-theme-primary), 0.05);
  font-size: 1.4rem;
  color: rgba(var(--v-theme-primary), 0.5);
  margin-bottom: 12px;
}
.graph-side-empty p {
  font-size: 0.78rem;
  line-height: 1.7;
}
@media (max-width: 1100px) {
  .graph-layout {
    grid-template-columns: 1fr;
  }
  .graph-side {
    min-height: 180px;
  }
  .graph-card,
  .graph-container {
    min-height: 520px;
    height: 520px;
  }
}
@media (max-width: 700px) {
  .graph-container {
    height: 430px;
  }
  .center-autocomplete {
    max-width: none;
    flex: 1;
  }
}
</style>
