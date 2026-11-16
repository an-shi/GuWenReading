<template>
  <div class="page">
    <div class="back-row">
      <v-btn variant="text" prepend-icon="mdi-arrow-left" @click="router.push('/')">返回书架</v-btn>
    </div>

    <v-progress-linear v-if="loading" indeterminate color="primary" rounded class="mb-6" />

    <template v-if="book">
      <div class="book-hero">
        <div class="hero-cover">
          <img v-if="book.cover_url" :src="booksApi.coverUrl(book)" :alt="book.title" />
          <div v-else class="cover-fallback">
            <span class="cover-glyph">{{ book.title.slice(0, 16) }}</span>
          </div>
        </div>
        <div class="hero-main">
          <div class="hero-labels">
            <v-chip v-if="book.category" size="small" color="secondary" variant="tonal">{{ book.category }}</v-chip>
            <v-chip size="small" color="primary" variant="tonal">{{ book.source_format.toUpperCase() }}</v-chip>
            <v-chip v-if="book.dynasty" size="small" variant="tonal">{{ book.dynasty }}</v-chip>
          </div>
          <h1 class="hero-title serif">{{ book.title }}</h1>
          <div class="hero-author serif">{{ book.author || '作者未详' }}</div>
          <p v-if="book.description" class="hero-description">{{ book.description }}</p>

          <div class="hero-stats">
            <div><span class="stat-number">{{ book.chapter_count }}</span><span class="stat-label">章</span></div>
            <div><span class="stat-number">{{ book.sentence_count.toLocaleString() }}</span><span class="stat-label">句</span></div>
            <div><span class="stat-number">{{ Math.round(book.translation_percent) }}</span><span class="stat-label">% 已译</span></div>
          </div>

          <div class="hero-actions">
            <v-btn color="primary" size="large" prepend-icon="mdi-book-open-page-variant" :disabled="!chapters.length" @click="continueReading">
              {{ progress ? '继续阅读' : '开始阅读' }}
            </v-btn>
            <v-btn variant="tonal" prepend-icon="mdi-pencil-outline" @click="openEdit">编辑信息</v-btn>
            <v-menu>
              <template #activator="{ props }">
                <v-btn v-bind="props" icon="mdi-dots-horizontal" variant="text" />
              </template>
              <v-list density="compact">
                <v-list-item prepend-icon="mdi-download" title="下载原始文件" :href="originalUrl" target="_blank" />
                <v-list-item prepend-icon="mdi-refresh" title="重新解析章节" @click="reparseOpen = true" />
                <v-divider />
                <v-list-item prepend-icon="mdi-delete-outline" title="移出书架" base-color="error" @click="deleteOpen = true" />
              </v-list>
            </v-menu>
          </div>
        </div>
      </div>

      <v-alert
        v-if="warnings.length"
        type="info"
        variant="tonal"
        density="compact"
        class="mb-5"
        :text="warnings.join('；')"
      />

      <div class="content-grid">
        <v-card class="chapter-card">
          <div class="card-head">
            <div>
              <div class="section-label">目录</div>
              <div class="card-title serif">章节目录</div>
            </div>
            <v-text-field
              v-model="chapterQuery"
              prepend-inner-icon="mdi-magnify"
              placeholder="筛选章节"
              density="compact"
              variant="solo"
              flat
              hide-details
              rounded="lg"
              class="chapter-search"
              clearable
            />
          </div>

          <div v-if="!filteredChapters.length" class="empty-chapters">没有匹配的章节</div>
          <div v-else class="chapter-list">
            <div
              v-for="chapter in visibleChapters"
              :key="chapter.id"
              class="chapter-row"
              :class="{ current: progress?.chapter_id === chapter.id }"
              @click="openChapter(chapter)"
            >
              <div class="chapter-ordinal">{{ String(chapter.ordinal + 1).padStart(2, '0') }}</div>
              <div class="chapter-info">
                <div class="chapter-title serif">{{ chapter.title }}</div>
                <div class="chapter-meta">
                  {{ chapter.paragraph_count }} 段 · {{ chapter.sentence_count }} 句 ·
                  {{ Math.round(chapter.translation_percent) }}% 已译
                  <span v-if="progress?.chapter_id === chapter.id" class="current-mark">上次读到</span>
                </div>
                <v-progress-linear
                  :model-value="chapter.translation_percent"
                  height="3"
                  rounded
                  color="primary"
                  bg-color="surface-variant"
                  class="chapter-progress"
                />
              </div>
              <div class="chapter-actions">
                <v-tooltip text="翻译本章" location="top">
                  <template #activator="{ props }">
                    <v-btn
                      v-bind="props"
                      icon="mdi-translate"
                      size="small"
                      variant="text"
                      :loading="translatingChapter === chapter.id"
                      @click.stop="translateChapter(chapter)"
                    />
                  </template>
                </v-tooltip>
                <v-tooltip text="抽取人物与事件" location="top">
                  <template #activator="{ props }">
                    <v-btn
                      v-bind="props"
                      icon="mdi-account-search-outline"
                      size="small"
                      variant="text"
                      :loading="extractingChapter === chapter.id"
                      @click.stop="extractChapter(chapter)"
                    />
                  </template>
                </v-tooltip>
              </div>
            </div>
          </div>
          <div v-if="filteredChapters.length > visibleChapters.length" class="load-more">
            <v-btn variant="text" @click="visibleCount += 80">加载更多章节</v-btn>
          </div>
        </v-card>

        <div class="side-column">
          <v-card class="side-card">
            <div class="section-label">阅读进度</div>
            <div class="side-title serif">阅读与进度</div>
            <div class="side-stat-row">
              <span>上次阅读</span>
              <strong>{{ book.last_read_at ? formatDate(book.last_read_at) : '尚未开始' }}</strong>
            </div>
            <div class="side-stat-row">
              <span>当前设备</span>
              <strong>{{ progress ? `第 ${progressChapterTitle}` : '无记录' }}</strong>
            </div>
            <div class="side-stat-row">
              <span>书籍文件</span>
              <strong>{{ formatSize(book.file_size) }}</strong>
            </div>
            <v-progress-linear
              v-if="progress"
              :model-value="progress.position_ratio * 100"
              height="5"
              rounded
              color="primary"
              class="mt-4"
            />
            <v-btn
              v-if="progress"
              variant="tonal"
              color="primary"
              block
              class="mt-4"
              prepend-icon="mdi-book-open-variant"
              @click="continueReading"
            >
              跳到上次位置
            </v-btn>
          </v-card>

          <v-card class="side-card">
            <div class="section-label">AI 分析</div>
            <div class="side-title serif">知识抽取</div>
            <p class="side-text">
              从章节中抽取人物、人物关系与历史事件。所有 AI 结果都保留原文证据，并标记为待审核。
            </p>
            <v-btn
              variant="tonal"
              color="secondary"
              block
              prepend-icon="mdi-graph-outline"
              @click="router.push('/tasks')"
            >
              查看抽取任务
            </v-btn>
          </v-card>
        </div>
      </div>
    </template>

    <v-dialog v-model="editOpen" max-width="660">
      <v-card>
        <v-card-title class="pt-6 px-6">编辑书籍信息</v-card-title>
        <v-card-text>
          <v-text-field v-model="editForm.title" label="书名" />
          <v-row dense>
            <v-col cols="12" sm="6"><v-text-field v-model="editForm.author" label="作者" /></v-col>
            <v-col cols="12" sm="6"><v-text-field v-model="editForm.dynasty" label="朝代" /></v-col>
            <v-col cols="12" sm="6"><v-text-field v-model="editForm.category" label="分类" /></v-col>
            <v-col cols="12" sm="6"><v-text-field v-model="editForm.tags" label="标签（逗号分隔）" /></v-col>
          </v-row>
          <v-textarea v-model="editForm.description" label="简介" rows="4" />
        </v-card-text>
        <v-card-actions class="px-6 pb-5">
          <v-spacer />
          <v-btn variant="text" @click="editOpen = false">取消</v-btn>
          <v-btn color="primary" :loading="saving" @click="saveEdit">保存</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="reparseOpen" max-width="520">
      <v-card>
        <v-card-title class="pt-6 px-6">重新解析书籍</v-card-title>
        <v-card-text>
          重新解析会按当前文件重建章节与句子。若已有译文，为避免丢失，操作将被拒绝；需要先在勾选强制的情况下归档并重建。
          <v-checkbox v-model="forceReparse" label="强制重新解析（归档并移除现有译文）" color="warning" class="mt-3" />
        </v-card-text>
        <v-card-actions class="px-6 pb-5">
          <v-spacer />
          <v-btn variant="text" @click="reparseOpen = false">取消</v-btn>
          <v-btn color="warning" :loading="reparsing" @click="reparse">开始解析</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="deleteOpen" max-width="480">
      <v-card>
        <v-card-title class="pt-6 px-6">移出书架？</v-card-title>
        <v-card-text>默认仅从书架隐藏，原始文件与数据仍保留。永久删除会同时移除托管文件、译文、批注与知识记录。</v-card-text>
        <v-card-actions class="px-6 pb-5">
          <v-btn variant="text" @click="deleteOpen = false">取消</v-btn>
          <v-spacer />
          <v-btn variant="text" color="error" @click="removeBook(false)">仅移出书架</v-btn>
          <v-btn color="error" @click="removeBook(true)">永久删除</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { assetUrl } from '@/api/client'
import { aiApi } from '@/api/ai'
import { booksApi } from '@/api/books'
import { readerApi } from '@/api/reader'
import { translationApi } from '@/api/translation'
import type { Book, ChapterSummary, ReadingProgress } from '@/api/types'
import { useAiStore } from '@/stores/ai'
import { useAppStore } from '@/stores/app'
import { useLibraryStore } from '@/stores/library'
import { useTasksStore } from '@/stores/tasks'

const route = useRoute()
const router = useRouter()
const app = useAppStore()
const ai = useAiStore()
const library = useLibraryStore()
const tasks = useTasksStore()

const book = ref<Book | null>(null)
const chapters = ref<ChapterSummary[]>([])
const progress = ref<ReadingProgress | null>(null)
const loading = ref(true)
const chapterQuery = ref('')
const visibleCount = ref(80)
const translatingChapter = ref('')
const extractingChapter = ref('')
const editOpen = ref(false)
const reparseOpen = ref(false)
const deleteOpen = ref(false)
const forceReparse = ref(false)
const reparsing = ref(false)
const saving = ref(false)
const editForm = reactive({ title: '', author: '', dynasty: '', category: '', description: '', tags: '' })

const bookId = computed(() => String(route.params.bookId))
const filteredChapters = computed(() => {
  const query = chapterQuery.value.trim()
  if (!query) return chapters.value
  return chapters.value.filter((chapter) => chapter.title.includes(query))
})
const visibleChapters = computed(() => filteredChapters.value.slice(0, visibleCount.value))
const warnings = computed(() => {
  const value = book.value?.metadata?.warnings
  return Array.isArray(value) ? value.map(String) : []
})
const originalUrl = computed(() => assetUrl(`/api/v1/books/${bookId.value}/original`))
const progressChapterTitle = computed(() =>
  chapters.value.find((chapter) => chapter.id === progress.value?.chapter_id)?.title || '未知章节',
)

watch(chapterQuery, () => { visibleCount.value = 80 })

async function load() {
  loading.value = true
  try {
    book.value = await booksApi.get(bookId.value)
    chapters.value = await booksApi.chapters(bookId.value)
    try {
      progress.value = (await readerApi.getProgress(bookId.value, app.deviceId)).progress
    } catch {
      progress.value = null
    }
  } finally {
    loading.value = false
  }
}

function openChapter(chapter: ChapterSummary) {
  router.push(`/read/${bookId.value}/${chapter.id}`)
}

async function continueReading() {
  const target =
    chapters.value.find((chapter) => chapter.id === progress.value?.chapter_id)
    || chapters.value.find((chapter) => chapter.sentence_count > 0)
    || chapters.value[0]
  if (target) openChapter(target)
}

function openEdit() {
  if (!book.value) return
  editForm.title = book.value.title
  editForm.author = book.value.author || ''
  editForm.dynasty = book.value.dynasty || ''
  editForm.category = book.value.category || ''
  editForm.description = book.value.description || ''
  editForm.tags = book.value.tags.join(', ')
  editOpen.value = true
}

async function saveEdit() {
  if (!book.value) return
  saving.value = true
  try {
    book.value = await booksApi.update(book.value.id, {
      title: editForm.title,
      author: editForm.author || null,
      dynasty: editForm.dynasty || null,
      category: editForm.category || null,
      description: editForm.description || null,
      tags: editForm.tags.split(/[,，]/).map((tag) => tag.trim()).filter(Boolean),
    })
    editOpen.value = false
    app.notify('书籍信息已更新')
    await library.load()
  } finally {
    saving.value = false
  }
}

async function translateChapter(chapter: ChapterSummary) {
  if (!ai.configured) {
    app.notify('请先在设置中配置翻译模型', 'warning')
    router.push('/settings')
    return
  }
  translatingChapter.value = chapter.id
  try {
    const task = await translationApi.chapter(chapter.id)
    tasks.upsert(task)
    app.notify('已创建章节翻译任务，可继续阅读')
  } finally {
    translatingChapter.value = ''
  }
}

async function extractChapter(chapter: ChapterSummary) {
  if (!ai.configured) {
    app.notify('请先在设置中配置 AI 模型', 'warning')
    router.push('/settings')
    return
  }
  extractingChapter.value = chapter.id
  try {
    const task = await aiApi.extractKnowledge(chapter.id)
    tasks.upsert(task)
    app.notify('已创建人物与事件抽取任务')
  } finally {
    extractingChapter.value = ''
  }
}

async function reparse() {
  reparsing.value = true
  try {
    book.value = await booksApi.reparse(bookId.value, forceReparse.value)
    chapters.value = await booksApi.chapters(bookId.value)
    reparseOpen.value = false
    forceReparse.value = false
    app.notify('书籍已重新解析')
  } finally {
    reparsing.value = false
  }
}

async function removeBook(permanent: boolean) {
  await library.remove(bookId.value, permanent)
  deleteOpen.value = false
  router.push('/')
}

function formatDate(value: string): string {
  return new Date(value).toLocaleString('zh-CN', {
    month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
  })
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`
}

onMounted(async () => {
  await load()
  if (!ai.loaded) ai.load().catch(() => undefined)
})
</script>

<style scoped>
.back-row {
  margin-bottom: 10px;
  margin-left: -12px;
}
.book-hero {
  display: grid;
  grid-template-columns: 190px minmax(0, 1fr);
  gap: 32px;
  margin-bottom: 32px;
}
.hero-cover {
  height: 272px;
  border-radius: 16px;
  overflow: hidden;
  box-shadow: 0 20px 40px rgba(25, 35, 29, 0.15);
}
.hero-cover img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.hero-cover .cover-fallback {
  width: 100%;
  height: 100%;
}
.hero-labels {
  display: flex;
  gap: 7px;
  flex-wrap: wrap;
}
.hero-title {
  font-size: clamp(2rem, 3.4vw, 3rem);
  line-height: 1.16;
  font-weight: 650;
  letter-spacing: 0.02em;
  margin: 14px 0 6px;
}
.hero-author {
  font-size: 1rem;
  color: rgba(var(--v-theme-on-surface), 0.55);
  letter-spacing: 0.04em;
}
.hero-description {
  max-width: 720px;
  margin-top: 16px;
  font-size: 0.88rem;
  line-height: 1.75;
  color: rgba(var(--v-theme-on-surface), 0.64);
}
.hero-stats {
  display: flex;
  gap: 34px;
  margin-top: 22px;
}
.hero-stats > div {
  display: flex;
  align-items: baseline;
  gap: 4px;
}
.hero-stats .stat-number {
  font-size: 1.55rem;
}
.hero-stats .stat-label {
  font-size: 0.7rem;
  color: rgba(var(--v-theme-on-surface), 0.46);
}
.hero-actions {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-top: 24px;
  flex-wrap: wrap;
}
.content-grid {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 300px;
  gap: 22px;
  align-items: start;
}
.chapter-card {
  padding: 6px 8px 10px;
  background: rgba(var(--v-theme-surface), 0.7);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.07);
}
.card-head {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 20px;
  padding: 18px 18px 14px;
  flex-wrap: wrap;
}
.card-title {
  font-size: 1.3rem;
  font-weight: 650;
  margin-top: 3px;
}
.chapter-search {
  max-width: 230px;
  background: rgba(var(--v-theme-surface), 0.6);
}
.chapter-list {
  padding: 0 6px;
}
.chapter-row {
  display: flex;
  align-items: center;
  gap: 15px;
  padding: 13px 12px;
  border-radius: 12px;
  cursor: pointer;
  transition: background 150ms ease;
}
.chapter-row:hover {
  background: rgba(var(--v-theme-primary), 0.05);
}
.chapter-row.current {
  background: rgba(var(--v-theme-primary), 0.07);
}
.chapter-ordinal {
  font-size: 0.68rem;
  color: rgba(var(--v-theme-on-surface), 0.32);
  font-variant-numeric: tabular-nums;
  width: 22px;
  flex-shrink: 0;
}
.chapter-info {
  flex: 1;
  min-width: 0;
}
.chapter-title {
  font-size: 0.98rem;
  font-weight: 600;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.chapter-meta {
  font-size: 0.68rem;
  color: rgba(var(--v-theme-on-surface), 0.45);
  margin-top: 4px;
}
.current-mark {
  color: rgb(var(--v-theme-primary));
  margin-left: 6px;
}
.chapter-progress {
  max-width: 260px;
  margin-top: 6px;
}
.chapter-actions {
  display: flex;
  gap: 2px;
  opacity: 0.5;
  transition: opacity 150ms ease;
}
.chapter-row:hover .chapter-actions {
  opacity: 1;
}
.empty-chapters {
  padding: 36px;
  text-align: center;
  color: rgba(var(--v-theme-on-surface), 0.42);
  font-size: 0.85rem;
}
.load-more {
  display: flex;
  justify-content: center;
  padding: 10px;
}
.side-column {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.side-card {
  padding: 20px;
  background: rgba(var(--v-theme-surface), 0.7);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.07);
}
.side-title {
  font-size: 1.12rem;
  font-weight: 650;
  margin: 4px 0 16px;
}
.side-stat-row {
  display: flex;
  justify-content: space-between;
  gap: 14px;
  padding: 8px 0;
  border-bottom: 1px dashed rgba(var(--v-theme-on-surface), 0.09);
  font-size: 0.76rem;
  color: rgba(var(--v-theme-on-surface), 0.5);
}
.side-stat-row strong {
  color: rgba(var(--v-theme-on-surface), 0.75);
  font-weight: 500;
  text-align: right;
}
.side-text {
  font-size: 0.8rem;
  line-height: 1.7;
  color: rgba(var(--v-theme-on-surface), 0.55);
  margin: 0 0 16px;
}
@media (max-width: 1100px) {
  .content-grid {
    grid-template-columns: 1fr;
  }
  .side-column {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  }
}
@media (max-width: 720px) {
  .book-hero {
    grid-template-columns: 110px minmax(0, 1fr);
    gap: 18px;
  }
  .hero-cover {
    height: 164px;
  }
  .hero-stats {
    gap: 18px;
  }
  .hero-description {
    display: none;
  }
}
</style>
