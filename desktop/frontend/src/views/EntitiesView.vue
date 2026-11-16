<template>
  <div class="page">
    <div class="page-header">
      <div>
        <div class="section-label">历史人物</div>
        <h1 class="page-title">人物知识库</h1>
        <p class="page-subtitle">跨书籍共享的人物、地名、职官与机构。AI 抽取结果保持待审核状态，并保留原文出处。</p>
      </div>
      <v-btn variant="tonal" color="primary" prepend-icon="mdi-robot-outline" @click="router.push('/tasks')">
        知识抽取任务
      </v-btn>
    </div>

    <div class="filter-bar">
      <v-text-field
        v-model="filters.q"
        prepend-inner-icon="mdi-magnify"
        placeholder="搜索姓名、别名、简介"
        density="comfortable"
        variant="solo"
        flat
        hide-details
        rounded="lg"
        clearable
        class="filter-search"
        @keydown.enter="loadEntities"
      />
      <v-select
        v-model="filters.kind"
        :items="kindOptions"
        item-title="title"
        item-value="value"
        placeholder="全部类型"
        density="comfortable"
        variant="solo"
        flat
        hide-details
        rounded="lg"
        clearable
        class="filter-select"
        @update:model-value="loadEntities"
      />
      <v-text-field
        v-model="filters.dynasty"
        placeholder="朝代"
        density="comfortable"
        variant="solo"
        flat
        hide-details
        rounded="lg"
        clearable
        class="filter-dynasty"
        @keydown.enter="loadEntities"
      />
      <v-select
        v-model="filters.status"
        :items="statusOptions"
        item-title="title"
        item-value="value"
        placeholder="全部状态"
        density="comfortable"
        variant="solo"
        flat
        hide-details
        rounded="lg"
        clearable
        class="filter-select"
        @update:model-value="loadEntities"
      />
      <v-btn color="primary" variant="tonal" @click="loadEntities">筛选</v-btn>
    </div>

    <div class="entity-layout">
      <v-card class="entity-list-card">
        <div class="list-head">
          <span class="section-label">人物</span>
          <span class="tiny muted">{{ total }} 条</span>
        </div>
        <v-progress-linear v-if="loading" indeterminate color="primary" />
        <div v-if="!entities.length && !loading" class="list-empty">暂无符合条件的实体</div>
        <div class="entity-list">
          <button
            v-for="entity in entities"
            :key="entity.id"
            class="entity-item"
            :class="{ active: selected?.id === entity.id }"
            @click="selectEntity(entity)"
          >
            <div class="entity-avatar serif">{{ entity.canonical_name.slice(0, 1) }}</div>
            <div class="entity-item-body">
              <div class="entity-item-top">
                <span class="entity-name serif">{{ entity.canonical_name }}</span>
                <span class="status-dot" :class="entity.status" />
              </div>
              <div class="entity-item-meta">
                {{ kindLabel(entity.kind) }}
                <template v-if="entity.dynasty"> · {{ entity.dynasty }}</template>
                <template v-if="entity.aliases.length"> · {{ entity.aliases.slice(0, 2).join('、') }}</template>
              </div>
            </div>
            <v-icon size="16" icon="mdi-chevron-right" class="item-arrow" />
          </button>
        </div>
      </v-card>

      <v-card v-if="selected" class="entity-detail-card">
        <div class="detail-head">
          <div>
            <div class="detail-labels">
              <v-chip size="x-small" variant="tonal" color="primary">{{ kindLabel(selected.kind) }}</v-chip>
              <v-chip size="x-small" variant="tonal" :color="statusColor(selected.status)">{{ statusLabel(selected.status) }}</v-chip>
              <v-chip v-if="selected.dynasty" size="x-small" variant="tonal">{{ selected.dynasty }}</v-chip>
            </div>
            <h2 class="detail-name serif">{{ selected.canonical_name }}</h2>
            <div v-if="selected.aliases.length" class="alias-line">
              别名：{{ selected.aliases.join('、') }}
            </div>
          </div>
          <v-menu>
            <template #activator="{ props }">
              <v-btn v-bind="props" icon="mdi-dots-vertical" variant="text" />
            </template>
            <v-list density="compact">
              <v-list-item prepend-icon="mdi-check-decagram" title="确认收录" :disabled="selected.status === 'confirmed'" @click="setStatus('confirmed')" />
              <v-list-item prepend-icon="mdi-clock-outline" title="标记待审" :disabled="selected.status === 'pending'" @click="setStatus('pending')" />
              <v-list-item prepend-icon="mdi-call-merge" title="合并重复条目" @click="mergeOpen = true" />
            </v-list>
          </v-menu>
        </div>

        <div class="detail-grid">
          <div class="detail-field"><span>身份</span><strong>{{ selected.identity || '未详' }}</strong></div>
          <div class="detail-field"><span>生卒</span><strong>{{ lifespan }}</strong></div>
          <div class="detail-field"><span>字 / 号</span><strong>{{ [selected.courtesy_name, selected.art_name].filter(Boolean).join(' / ') || '未详' }}</strong></div>
          <div class="detail-field"><span>职官</span><strong>{{ selected.offices.join('、') || '未详' }}</strong></div>
        </div>

        <div v-if="selected.summary" class="detail-block">
          <div class="section-label">摘要</div>
          <p class="summary-text">{{ selected.summary }}</p>
        </div>

        <div class="detail-block">
          <div class="section-label">关系 · {{ selected.relations?.length || 0 }}</div>
          <div v-if="!selected.relations?.length" class="tiny muted empty-line">暂无关系记录。可在章节中运行知识抽取，或人工添加关系。</div>
          <div v-for="relation in selected.relations" :key="relation.id" class="relation-row">
            <div class="relation-main">
              <v-chip size="x-small" variant="tonal" :color="relationStatusColor(relation.status)">{{ relationStatusLabel(relation.status) }}</v-chip>
              <span class="relation-type">{{ relation.relation_type }}</span>
              <span class="serif relation-other">{{ relation.other_entity_name }}</span>
              <span v-if="relation.label" class="tiny muted">（{{ relation.label }}）</span>
              <v-spacer />
              <v-btn
                v-if="relation.status === 'inferred' || relation.status === 'explicit'"
                size="x-small"
                variant="text"
                color="success"
                @click="reviewRelation(relation, 'confirmed')"
              >确认</v-btn>
              <v-btn
                v-if="relation.status !== 'rejected'"
                size="x-small"
                variant="text"
                @click="reviewRelation(relation, 'rejected')"
              >驳回</v-btn>
            </div>
            <div v-if="relation.description" class="relation-description">{{ relation.description }}</div>
            <div v-for="source in relation.sources || []" :key="source.id" class="evidence-card">
              <div class="evidence-quote serif">{{ source.quote }}</div>
              <div class="evidence-source">{{ source.book_title }} · {{ source.chapter_title }}</div>
            </div>
          </div>
        </div>

        <div class="detail-block">
          <div class="section-label">提及 · {{ selected.mentions?.length || 0 }}</div>
          <div v-if="!selected.mentions?.length" class="tiny muted empty-line">暂无原文提及记录。</div>
          <div
            v-for="mention in selected.mentions"
            :key="mention.id"
            class="mention-row"
            @click="openMention(mention)"
          >
            <div class="mention-quote serif">{{ mention.quote }}</div>
            <div class="mention-meta">
              <span>{{ mention.book_title }} · {{ mention.chapter_title }}</span>
              <v-chip size="x-small" variant="tonal" :color="mention.status === 'confirmed' ? 'success' : 'warning'">
                {{ mention.status === 'confirmed' ? '已确认' : '待审核' }}
              </v-chip>
              <v-icon size="14" icon="mdi-arrow-top-right" />
            </div>
          </div>
        </div>
      </v-card>

      <div v-else class="entity-placeholder">
        <div class="placeholder-glyph serif">人</div>
        <div class="placeholder-title serif">选择一个人物</div>
        <p>查看其别名、身份、人物关系与原文出处。运行章节知识抽取后，结果会出现在这里。</p>
        <v-btn color="primary" variant="tonal" @click="router.push('/graph')">打开关系图谱</v-btn>
      </div>
    </div>

    <v-dialog v-model="mergeOpen" max-width="560">
      <v-card>
        <v-card-title class="pt-6 px-6">合并重复条目</v-card-title>
        <v-card-text>
          <p class="merge-hint">将其他重复实体并入「{{ selected?.canonical_name }}」。其别名、提及、关系与事件参与记录会转移到当前人物。</p>
          <v-select
            v-model="mergeIds"
            :items="mergeOptions"
            item-title="title"
            item-value="value"
            multiple
            chips
            label="选择要合并的实体"
          />
        </v-card-text>
        <v-card-actions class="px-6 pb-5">
          <v-spacer />
          <v-btn variant="text" @click="mergeOpen = false">取消</v-btn>
          <v-btn color="primary" :disabled="!mergeIds.length" :loading="merging" @click="mergeEntities">确认合并</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { knowledgeApi } from '@/api/knowledge'
import type { EntityMention, EntityRelation, HistoricalEntity } from '@/api/types'
import { useAppStore } from '@/stores/app'

const route = useRoute()
const router = useRouter()
const app = useAppStore()
const entities = ref<HistoricalEntity[]>([])
const selected = ref<HistoricalEntity | null>(null)
const total = ref(0)
const loading = ref(false)
const merging = ref(false)
const mergeOpen = ref(false)
const mergeIds = ref<string[]>([])
const filters = reactive({ q: '', kind: '', dynasty: '', status: '' })

const kindOptions = [
  { title: '人物', value: 'person' },
  { title: '地点', value: 'place' },
  { title: '朝代/政权', value: 'dynasty' },
  { title: '职官', value: 'office' },
  { title: '机构', value: 'institution' },
  { title: '典籍', value: 'work' },
  { title: '其他', value: 'other' },
]
const statusOptions = [
  { title: '已确认', value: 'confirmed' },
  { title: '待审核', value: 'pending' },
  { title: '已驳回', value: 'rejected' },
]
const lifespan = computed(() => {
  if (!selected.value) return '未详'
  const birth = selected.value.birth_raw || selected.value.birth_year
  const death = selected.value.death_raw || selected.value.death_year
  if (!birth && !death) return '未详'
  return `${birth ?? '未详'} — ${death ?? '未详'}`
})
const mergeOptions = computed(() => entities.value
  .filter((entity) => entity.id !== selected.value?.id)
  .map((entity) => ({
    title: `${entity.canonical_name}${entity.dynasty ? `（${entity.dynasty}）` : ''}`,
    value: entity.id,
  })))

function kindLabel(kind: string): string {
  return kindOptions.find((option) => option.value === kind)?.title || kind
}

function statusLabel(status: string): string {
  return ({ confirmed: '已确认', pending: '待审核', rejected: '已驳回' } as Record<string, string>)[status] || status
}
function statusColor(status: string): string {
  return ({ confirmed: 'success', pending: 'warning', rejected: 'error' } as Record<string, string>)[status] || 'default'
}
function relationStatusLabel(status: string): string {
  return ({
    confirmed: '已确认', explicit: '原文明确', inferred: 'AI 推断', rejected: '已驳回',
  } as Record<string, string>)[status] || status
}
function relationStatusColor(status: string): string {
  return ({
    confirmed: 'success', explicit: 'info', inferred: 'warning', rejected: 'error',
  } as Record<string, string>)[status] || 'default'
}

async function loadEntities() {
  loading.value = true
  try {
    const data = await knowledgeApi.entities({
      q: filters.q || undefined,
      kind: filters.kind || undefined,
      dynasty: filters.dynasty || undefined,
      status: filters.status || undefined,
      page_size: 100,
    })
    entities.value = data.items
    total.value = data.total
    const queryEntity = typeof route.query.entity === 'string' ? route.query.entity : ''
    const target = queryEntity
      ? data.items.find((entity) => entity.id === queryEntity)
      : selected.value && data.items.find((entity) => entity.id === selected.value?.id)
    if (target) await selectEntity(target)
    else if (data.items.length) await selectEntity(data.items[0])
    else selected.value = null
  } finally {
    loading.value = false
  }
}

async function selectEntity(entity: HistoricalEntity) {
  selected.value = await knowledgeApi.entity(entity.id)
  if (route.query.entity !== entity.id) {
    router.replace({ query: { ...route.query, entity: entity.id } })
  }
}

async function setStatus(status: string) {
  if (!selected.value) return
  selected.value = await knowledgeApi.updateEntity(selected.value.id, { status })
  app.notify(status === 'confirmed' ? '已确认该实体' : '已更新审核状态')
  await loadEntities()
}

async function reviewRelation(relation: EntityRelation, status: string) {
  await knowledgeApi.reviewRelation(relation.id, status)
  if (selected.value) selected.value = await knowledgeApi.entity(selected.value.id)
}

function openMention(mention: EntityMention) {
  router.push(`/read/${mention.book_id}/${mention.chapter_id}?highlight=${mention.sentence_id}`)
}

async function mergeEntities() {
  if (!selected.value || !mergeIds.value.length) return
  merging.value = true
  try {
    selected.value = await knowledgeApi.mergeEntities(selected.value.id, mergeIds.value)
    mergeOpen.value = false
    mergeIds.value = []
    app.notify('实体已合并')
    await loadEntities()
  } finally {
    merging.value = false
  }
}

watch(
  () => route.query.entity,
  (value) => {
    if (typeof value === 'string' && entities.value.length) {
      const entity = entities.value.find((item) => item.id === value)
      if (entity && entity.id !== selected.value?.id) selectEntity(entity)
    }
  },
)

onMounted(loadEntities)
</script>

<style scoped>
.filter-bar {
  display: flex;
  gap: 10px;
  margin-bottom: 20px;
  flex-wrap: wrap;
}
.filter-search {
  max-width: 330px;
  background: rgba(var(--v-theme-surface), 0.65);
}
.filter-select {
  max-width: 150px;
  background: rgba(var(--v-theme-surface), 0.65);
}
.filter-dynasty {
  max-width: 130px;
  background: rgba(var(--v-theme-surface), 0.65);
}
.entity-layout {
  display: grid;
  grid-template-columns: 330px minmax(0, 1fr);
  gap: 20px;
  align-items: start;
}
.entity-list-card {
  background: rgba(var(--v-theme-surface), 0.68);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.07);
  padding: 10px 6px 8px;
  max-height: calc(100dvh - 280px);
  display: flex;
  flex-direction: column;
}
.list-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 8px 12px 10px;
}
.entity-list {
  overflow-y: auto;
  min-height: 100px;
}
.list-empty {
  padding: 40px 16px;
  text-align: center;
  font-size: 0.8rem;
  color: rgba(var(--v-theme-on-surface), 0.4);
}
.entity-item {
  display: flex;
  align-items: center;
  gap: 11px;
  width: 100%;
  text-align: left;
  background: transparent;
  border: 0;
  border-radius: 11px;
  padding: 10px 11px;
  cursor: pointer;
  color: inherit;
  transition: background 150ms ease;
}
.entity-item:hover {
  background: rgba(var(--v-theme-primary), 0.05);
}
.entity-item.active {
  background: rgba(var(--v-theme-primary), 0.085);
}
.entity-avatar {
  width: 37px;
  height: 37px;
  border-radius: 11px;
  background: rgba(var(--v-theme-secondary), 0.1);
  color: rgb(var(--v-theme-secondary));
  display: grid;
  place-items: center;
  font-size: 1rem;
  flex-shrink: 0;
}
.entity-item-body {
  flex: 1;
  min-width: 0;
}
.entity-item-top {
  display: flex;
  align-items: center;
  gap: 7px;
}
.entity-name {
  font-size: 0.91rem;
  font-weight: 650;
}
.entity-item-meta {
  font-size: 0.64rem;
  color: rgba(var(--v-theme-on-surface), 0.44);
  margin-top: 3px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.item-arrow {
  color: rgba(var(--v-theme-on-surface), 0.22);
}
.status-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: rgb(var(--v-theme-warning));
}
.status-dot.confirmed { background: rgb(var(--v-theme-success)); }
.status-dot.rejected { background: rgb(var(--v-theme-error)); }
.entity-detail-card {
  padding: 24px 26px;
  background: rgba(var(--v-theme-surface), 0.68);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.07);
}
.detail-head {
  display: flex;
  justify-content: space-between;
  gap: 20px;
}
.detail-labels {
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
}
.detail-name {
  font-size: clamp(1.7rem, 2.6vw, 2.3rem);
  font-weight: 650;
  letter-spacing: 0.03em;
  margin: 12px 0 4px;
}
.alias-line {
  font-size: 0.76rem;
  color: rgba(var(--v-theme-on-surface), 0.46);
}
.detail-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 10px;
  margin-top: 20px;
}
.detail-field {
  padding: 10px 12px;
  border-radius: 10px;
  background: rgba(var(--v-theme-primary), 0.035);
  display: flex;
  flex-direction: column;
  gap: 3px;
  font-size: 0.72rem;
  color: rgba(var(--v-theme-on-surface), 0.45);
}
.detail-field strong {
  color: rgba(var(--v-theme-on-surface), 0.76);
  font-weight: 500;
  font-size: 0.82rem;
}
.detail-block {
  margin-top: 24px;
  padding-top: 18px;
  border-top: 1px dashed rgba(var(--v-theme-on-surface), 0.11);
}
.summary-text {
  font-size: 0.87rem;
  line-height: 1.85;
  color: rgba(var(--v-theme-on-surface), 0.7);
  margin: 8px 0 0;
}
.empty-line {
  padding: 8px 0;
}
.relation-row {
  padding: 11px 0;
  border-bottom: 1px dashed rgba(var(--v-theme-on-surface), 0.08);
}
.relation-main {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}
.relation-type {
  font-size: 0.76rem;
  color: rgba(var(--v-theme-on-surface), 0.46);
}
.relation-other {
  font-size: 0.92rem;
  font-weight: 600;
}
.relation-description {
  font-size: 0.76rem;
  color: rgba(var(--v-theme-on-surface), 0.5);
  margin-top: 5px;
}
.evidence-card {
  margin-top: 7px;
  padding: 8px 11px;
  border-left: 2px solid rgba(var(--v-theme-secondary), 0.5);
  background: rgba(var(--v-theme-secondary), 0.05);
}
.evidence-quote {
  font-size: 0.8rem;
  line-height: 1.7;
}
.evidence-source {
  font-size: 0.64rem;
  color: rgba(var(--v-theme-on-surface), 0.4);
  margin-top: 3px;
}
.mention-row {
  padding: 10px 8px;
  border-radius: 8px;
  cursor: pointer;
}
.mention-row:hover {
  background: rgba(var(--v-theme-primary), 0.04);
}
.mention-quote {
  font-size: 0.84rem;
  line-height: 1.7;
}
.mention-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 0.64rem;
  color: rgba(var(--v-theme-on-surface), 0.4);
  margin-top: 4px;
  flex-wrap: wrap;
}
.entity-placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  min-height: 430px;
  color: rgba(var(--v-theme-on-surface), 0.5);
  padding: 30px;
}
.placeholder-glyph {
  width: 64px;
  height: 64px;
  border-radius: 18px;
  display: grid;
  place-items: center;
  font-size: 1.6rem;
  background: rgba(var(--v-theme-primary), 0.06);
  color: rgba(var(--v-theme-primary), 0.6);
  margin-bottom: 16px;
}
.placeholder-title {
  font-size: 1.1rem;
  font-weight: 650;
}
.entity-placeholder p {
  max-width: 360px;
  font-size: 0.8rem;
  line-height: 1.75;
}
.merge-hint {
  font-size: 0.8rem;
  line-height: 1.7;
  color: rgba(var(--v-theme-on-surface), 0.55);
}
@media (max-width: 980px) {
  .entity-layout {
    grid-template-columns: 1fr;
  }
  .entity-list-card {
    max-height: 320px;
  }
  .filter-search {
    max-width: none;
    flex: 1;
  }
}
</style>
