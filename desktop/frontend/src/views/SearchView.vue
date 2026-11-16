<template>
  <div class="page">
    <div class="page-header">
      <div>
        <div class="section-label">知识检索</div>
        <h1 class="page-title">知识检索</h1>
        <p class="page-subtitle">在原文、译文、人物与历史事件中检索，并回到具体史料位置。</p>
      </div>
    </div>

    <v-card class="search-panel">
      <div class="search-row">
        <v-text-field
          v-model="query"
          prepend-inner-icon="mdi-magnify"
          placeholder="搜索原文、译文、人物或事件，例如：轩辕、贞观、淝水之战"
          variant="solo"
          flat
          hide-details
          rounded="lg"
          class="search-input"
          autofocus
          clearable
          @keydown.enter="runSearch"
        />
        <v-btn color="primary" size="large" :loading="loading" @click="runSearch">检索</v-btn>
      </div>
      <div class="search-filters">
        <v-btn-toggle v-model="scope" density="compact" variant="tonal" divided mandatory @update:model-value="runSearch">
          <v-btn value="all" size="small">全部</v-btn>
          <v-btn value="original" size="small">原文</v-btn>
          <v-btn value="translation" size="small">译文</v-btn>
        </v-btn-toggle>
        <v-select
          v-model="bookId"
          :items="bookOptions"
          item-title="title"
          item-value="value"
          placeholder="全部书籍"
          density="compact"
          variant="solo"
          flat
          hide-details
          rounded="lg"
          clearable
          class="book-filter"
          @update:model-value="runSearch"
        />
        <v-spacer />
        <span v-if="results" class="tiny muted">共 {{ results.total }} 条结果</span>
      </div>
    </v-card>

    <div v-if="!results && !loading" class="search-intro">
      <div class="intro-mark serif">寻</div>
      <div class="intro-title serif">从只言片语，回到史料本身</div>
      <p>检索结果会标明书籍、章节与句子位置。知识库中的 AI 推断内容不会作为确定事实呈现。</p>
      <div class="quick-searches">
        <v-chip v-for="item in quickSearches" :key="item" variant="tonal" color="primary" size="small" @click="quickSearch(item)">
          {{ item }}
        </v-chip>
      </div>
    </div>

    <v-progress-linear v-if="loading" indeterminate color="primary" rounded class="mt-6" />

    <template v-else-if="results">
      <section v-if="results.sentences.length" class="result-section">
        <div class="result-heading">
          <span class="section-label">原文匹配</span>
          <span class="result-count">{{ results.sentences.length }}</span>
        </div>
        <div class="sentence-results">
          <v-card
            v-for="hit in results.sentences"
            :key="`${hit.sentence_id}-${hit.doc_type}`"
            class="sentence-result"
            @click="openSentence(hit)"
          >
            <div class="result-meta">
              <span class="serif result-book">{{ hit.book_title }}</span>
              <span>{{ hit.chapter_title }}</span>
              <v-chip size="x-small" variant="tonal" :color="hit.doc_type === 'translation' ? 'secondary' : 'primary'">
                {{ hit.doc_type === 'translation' ? '译文' : '原文' }}
              </v-chip>
            </div>
            <div class="result-snippet serif">
              <template v-for="(part, index) in highlightParts(hit.snippet)" :key="index">
                <mark v-if="part.mark">{{ part.text }}</mark>
                <span v-else>{{ part.text }}</span>
              </template>
            </div>
            <div v-if="hit.doc_type === 'translation' && hit.original_text" class="result-original">
              原文：{{ hit.original_text }}
            </div>
          </v-card>
        </div>
      </section>

      <section v-if="results.entities.length" class="result-section">
        <div class="result-heading">
          <span class="section-label">人物</span>
          <span class="result-count">{{ results.entities.length }}</span>
        </div>
        <div class="mini-grid">
          <v-card
            v-for="entity in results.entities"
            :key="entity.id"
            class="mini-card"
            @click="router.push(`/entities?entity=${entity.id}`)"
          >
            <div class="mini-title serif">{{ entity.canonical_name }}</div>
            <div class="mini-meta">{{ entityKindLabel(entity.kind) }} · {{ entity.dynasty || '朝代未详' }}</div>
            <div class="mini-text">{{ entity.summary || entity.identity || '暂无简介' }}</div>
            <v-chip size="x-small" variant="tonal" :color="entity.status === 'confirmed' ? 'success' : 'warning'">
              {{ entity.status === 'confirmed' ? '已确认' : '待审核' }}
            </v-chip>
          </v-card>
        </div>
      </section>

      <section v-if="results.events.length" class="result-section">
        <div class="result-heading">
          <span class="section-label">历史事件</span>
          <span class="result-count">{{ results.events.length }}</span>
        </div>
        <div class="mini-grid">
          <v-card
            v-for="event in results.events"
            :key="event.id"
            class="mini-card"
            @click="router.push(`/timeline?event=${event.id}`)"
          >
            <div class="mini-title serif">{{ event.name }}</div>
            <div class="mini-meta">{{ event.event_type }} · {{ event.time_raw || '时间待考' }}</div>
            <div class="mini-text">
              {{ event.time_start_year !== null ? formatYear(event.time_start_year) : '未换算为公元年份' }}
            </div>
            <v-chip size="x-small" variant="tonal" :color="event.status === 'confirmed' ? 'success' : 'warning'">
              {{ event.status === 'confirmed' ? '已确认' : '待审核' }}
            </v-chip>
          </v-card>
        </div>
      </section>

      <EmptyState
        v-if="!results.sentences.length && !results.entities.length && !results.events.length"
        title="没有找到相关内容"
        text="尝试更短的关键词、切换检索范围，或先为书籍配置 AI 翻译与知识抽取。"
        glyph="无"
      />
    </template>

    <v-alert v-if="error" type="error" variant="tonal" class="mt-6" :text="error" />
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import EmptyState from '@/components/EmptyState.vue'
import { booksApi } from '@/api/books'
import { knowledgeApi } from '@/api/knowledge'
import type { Book, SearchResults } from '@/api/types'
import { useAppStore } from '@/stores/app'

const router = useRouter()
const app = useAppStore()
const query = ref('')
const scope = ref<'all' | 'original' | 'translation'>('all')
const bookId = ref<string | null>(null)
const results = ref<SearchResults | null>(null)
const loading = ref(false)
const error = ref('')
const books = ref<Book[]>([])
const quickSearches = ['轩辕', '贞观', '诸侯', '战争', '司马迁']

const bookOptions = ref<Array<{ title: string; value: string }>>([])

function entityKindLabel(kind: string): string {
  return ({
    person: '人物', place: '地点', dynasty: '朝代/政权', office: '职官',
    institution: '机构', work: '典籍', other: '其他',
  } as Record<string, string>)[kind] || kind
}

function highlightParts(text: string): Array<{ text: string; mark: boolean }> {
  if (!text) return []
  const parts: Array<{ text: string; mark: boolean }> = []
  const regex = /\[\[(.*?)\]\]/g
  let last = 0
  let match: RegExpExecArray | null
  while ((match = regex.exec(text)) !== null) {
    if (match.index > last) parts.push({ text: text.slice(last, match.index), mark: false })
    parts.push({ text: match[1], mark: true })
    last = match.index + match[0].length
  }
  if (last < text.length) parts.push({ text: text.slice(last), mark: false })
  return parts
}

async function runSearch() {
  const value = query.value.trim()
  if (!value) {
    results.value = null
    return
  }
  loading.value = true
  error.value = ''
  try {
    results.value = await knowledgeApi.search(value, scope.value, bookId.value || undefined)
  } catch (err) {
    error.value = err instanceof Error ? err.message : '检索失败'
    results.value = null
  } finally {
    loading.value = false
  }
}

function quickSearch(value: string) {
  query.value = value
  runSearch()
}

function openSentence(hit: SearchResults['sentences'][number]) {
  router.push(`/read/${hit.book_id}/${hit.chapter_id}?highlight=${hit.sentence_id}`)
}

function formatYear(year: number): string {
  return year < 0 ? `公元前 ${Math.abs(year)} 年` : `公元 ${year} 年`
}

onMounted(async () => {
  try {
    const data = await booksApi.list({ page: 1, page_size: 100 })
    books.value = data.items
    bookOptions.value = data.items.map((book) => ({ title: book.title, value: book.id }))
  } catch {
    bookOptions.value = []
  }
  if (!app.backendOnline) app.notify('后端未连接，检索可能失败', 'warning')
})
</script>

<style scoped>
.search-panel {
  padding: 20px;
  background: rgba(var(--v-theme-surface), 0.72);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.07);
}
.search-row {
  display: flex;
  gap: 12px;
}
.search-input {
  background: rgba(var(--v-theme-surface), 0.7);
}
.search-input :deep(input) {
  font-family: "Noto Serif SC", "Songti SC", serif;
  font-size: 1.02rem;
}
.search-filters {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-top: 13px;
  flex-wrap: wrap;
}
.book-filter {
  max-width: 210px;
  background: rgba(var(--v-theme-surface), 0.55);
}
.search-intro {
  max-width: 680px;
  margin: 60px auto 0;
  text-align: center;
  color: rgba(var(--v-theme-on-surface), 0.55);
}
.intro-mark {
  width: 72px;
  height: 72px;
  margin: 0 auto 18px;
  border-radius: 22px;
  display: grid;
  place-items: center;
  background: rgba(var(--v-theme-secondary), 0.08);
  color: rgb(var(--v-theme-secondary));
  font-size: 1.8rem;
  border: 1px solid rgba(var(--v-theme-secondary), 0.15);
}
.intro-title {
  font-size: 1.35rem;
  font-weight: 650;
  color: rgba(var(--v-theme-on-surface), 0.76);
}
.search-intro p {
  max-width: 520px;
  margin: 10px auto 18px;
  font-size: 0.84rem;
  line-height: 1.8;
}
.quick-searches {
  display: flex;
  justify-content: center;
  gap: 8px;
  flex-wrap: wrap;
}
.result-section {
  margin-top: 30px;
}
.result-heading {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 12px;
}
.result-count {
  font-size: 0.68rem;
  color: rgba(var(--v-theme-on-surface), 0.35);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.12);
  border-radius: 999px;
  padding: 1px 7px;
}
.sentence-results {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.sentence-result {
  padding: 16px 18px;
  cursor: pointer;
  background: rgba(var(--v-theme-surface), 0.66);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.065);
  transition: border-color 150ms ease, transform 150ms ease;
}
.sentence-result:hover {
  border-color: rgba(var(--v-theme-primary), 0.24);
  transform: translateY(-1px);
}
.result-meta {
  display: flex;
  align-items: center;
  gap: 9px;
  font-size: 0.68rem;
  color: rgba(var(--v-theme-on-surface), 0.46);
  flex-wrap: wrap;
}
.result-book {
  font-weight: 650;
  color: rgba(var(--v-theme-on-surface), 0.7);
  font-size: 0.76rem;
}
.result-snippet {
  margin-top: 8px;
  font-size: 0.98rem;
  line-height: 1.8;
  color: rgba(var(--v-theme-on-surface), 0.86);
}
.result-snippet mark {
  background: rgba(var(--v-theme-secondary), 0.2);
  color: inherit;
  padding: 1px 2px;
  border-radius: 3px;
}
.result-original {
  margin-top: 7px;
  font-size: 0.72rem;
  color: rgba(var(--v-theme-on-surface), 0.4);
  line-height: 1.6;
}
.mini-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
  gap: 12px;
}
.mini-card {
  padding: 16px;
  cursor: pointer;
  background: rgba(var(--v-theme-surface), 0.66);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.065);
}
.mini-card:hover {
  border-color: rgba(var(--v-theme-primary), 0.24);
}
.mini-title {
  font-size: 1.02rem;
  font-weight: 650;
}
.mini-meta {
  font-size: 0.68rem;
  color: rgba(var(--v-theme-on-surface), 0.45);
  margin-top: 4px;
}
.mini-text {
  font-size: 0.78rem;
  line-height: 1.65;
  color: rgba(var(--v-theme-on-surface), 0.58);
  margin: 9px 0 11px;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
@media (max-width: 700px) {
  .search-row {
    flex-direction: column;
  }
  .book-filter {
    max-width: none;
    flex: 1;
  }
}
</style>
