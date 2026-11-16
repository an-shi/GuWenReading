<template>
  <div class="reader-shell paper-texture">
    <div class="reader-toolbar">
      <v-btn icon="mdi-arrow-left" variant="text" size="small" title="返回书籍" @click="goBook" />
      <div class="toolbar-book">
        <div class="toolbar-title serif">{{ content?.book.title || bookTitleFallback }}</div>
        <div class="toolbar-chapter">{{ content?.chapter.title || '正在载入…' }}</div>
      </div>

      <v-select
        v-model="selectedChapterId"
        :items="chapterOptions"
        item-title="title"
        item-value="value"
        density="compact"
        variant="solo"
        flat
        hide-details
        rounded="lg"
        class="chapter-select"
        :disabled="!chapters.length || loading"
        @update:model-value="changeChapter"
      />

      <div class="chapter-nav">
        <v-btn
          icon="mdi-chevron-left"
          variant="text"
          size="small"
          :disabled="!content?.previous_chapter_id"
          title="上一章"
          @click="navigateChapter(content?.previous_chapter_id)"
        />
        <v-btn
          icon="mdi-chevron-right"
          variant="text"
          size="small"
          :disabled="!content?.next_chapter_id"
          title="下一章"
          @click="navigateChapter(content?.next_chapter_id)"
        />
      </div>

      <v-spacer />

      <v-chip
        v-if="content"
        size="small"
        :color="translationPercent >= 100 ? 'success' : 'default'"
        variant="tonal"
        class="status-chip"
        @click="router.push('/tasks')"
      >
        <v-progress-circular
          v-if="activeTranslationTask"
          indeterminate
          size="12"
          width="2"
          color="info"
          class="mr-2"
        />
        {{ content.translation_status.translated }}/{{ content.translation_status.total }} 句
        · {{ Math.round(translationPercent) }}%
      </v-chip>

      <v-menu :close-on-content-click="false" location="bottom end">
        <template #activator="{ props }">
          <v-btn
            v-bind="props"
            variant="tonal"
            color="primary"
            size="small"
            prepend-icon="mdi-translate"
            :loading="translating"
          >
            翻译
          </v-btn>
        </template>
        <v-list density="compact" class="py-1">
          <v-list-item
            prepend-icon="mdi-play"
            title="翻译未完成部分"
            :disabled="Boolean(activeTranslationTask) || !ai.configured"
            @click="triggerTranslation(false)"
          />
          <v-list-item
            prepend-icon="mdi-refresh"
            title="重新翻译本章"
            subtitle="人工译文不会被覆盖，只会生成待审候选"
            :disabled="Boolean(activeTranslationTask) || !ai.configured"
            @click="triggerTranslation(true)"
          />
          <v-divider class="my-1" />
          <v-list-item
            v-if="activeTranslationTask"
            prepend-icon="mdi-stop-circle-outline"
            title="取消当前翻译任务"
            base-color="error"
            @click="cancelTranslation"
          />
          <v-list-item
            v-else
            prepend-icon="mdi-cog-outline"
            title="配置翻译模型"
            @click="router.push('/settings')"
          />
        </v-list>
      </v-menu>

      <v-btn icon="mdi-robot-outline" variant="text" size="small" title="AI 助手" @click="assistantOpen = true" />
      <v-btn icon="mdi-bookmark-plus-outline" variant="text" size="small" title="添加书签" @click="addBookmark" />

      <v-menu :close-on-content-click="false" location="bottom end">
        <template #activator="{ props }">
          <v-btn v-bind="props" icon="mdi-format-font" variant="text" size="small" title="阅读设置" />
        </template>
        <v-card class="reader-settings" width="330">
          <div class="settings-head">
            <div class="section-label">阅读</div>
            <div class="settings-title serif">阅读偏好</div>
          </div>
          <div class="settings-body">
            <div class="setting-row">
              <span>显示模式</span>
              <v-btn-toggle v-model="viewMode" density="compact" variant="tonal" divided mandatory>
                <v-btn value="both" size="small">对照</v-btn>
                <v-btn value="original" size="small">原文</v-btn>
                <v-btn value="translation" size="small">译文</v-btn>
              </v-btn-toggle>
            </div>
            <div class="setting-row">
              <span>字号</span>
              <div class="slider-with-value">
                <v-slider
                  :model-value="app.fontSize"
                  :min="14" :max="30" :step="1"
                  hide-details density="compact" color="primary"
                  @update:model-value="app.setFontSize(Number($event))"
                />
                <span class="setting-value">{{ app.fontSize }} 像素</span>
              </div>
            </div>
            <div class="setting-row">
              <span>行距</span>
              <div class="slider-with-value">
                <v-slider
                  :model-value="app.lineHeight"
                  :min="1.4" :max="2.6" :step="0.1"
                  hide-details density="compact" color="primary"
                  @update:model-value="app.setLineHeight(Number($event))"
                />
                <span class="setting-value">{{ app.lineHeight.toFixed(1) }}</span>
              </div>
            </div>
            <div class="setting-row">
              <span>阅读主题</span>
              <v-btn-toggle :model-value="app.theme" density="compact" variant="tonal" divided mandatory>
                <v-btn value="paper" size="small" icon="mdi-book-open-variant" title="纸张" @click="app.setTheme('paper')" />
                <v-btn value="light" size="small" icon="mdi-white-balance-sunny" title="浅色" @click="app.setTheme('light')" />
                <v-btn value="dark" size="small" icon="mdi-weather-night" title="深色" @click="app.setTheme('dark')" />
              </v-btn-toggle>
            </div>
            <div class="setting-row">
              <span>打开章节时自动翻译</span>
              <v-switch
                :model-value="app.autoTranslate"
                density="compact"
                color="primary"
                hide-details
                @update:model-value="app.setAutoTranslate(Boolean($event))"
              />
            </div>
          </div>
        </v-card>
      </v-menu>
    </div>

    <v-progress-linear
      :model-value="readingRatio * 100"
      height="2"
      color="primary"
      bg-color="transparent"
      absolute
      style="top: 57px; z-index: 4"
    />

    <div ref="scrollContainer" class="reader-body" @scroll.passive="onScroll">
      <div
        class="reader-page"
        :style="{ '--reader-font-size': `${app.fontSize}px`, '--reader-line-height': app.lineHeight }"
      >
        <v-progress-linear v-if="loading" indeterminate color="primary" rounded class="mb-6" />

        <template v-if="content && !loading">
          <div class="chapter-masthead">
            <div class="masthead-book serif">{{ content.book.title }}</div>
            <h1 class="reader-chapter-title">{{ content.chapter.title }}</h1>
            <div class="masthead-meta">
              <span>{{ content.chapter.paragraph_count }} 段</span>
              <span>·</span>
              <span>{{ content.chapter.sentence_count }} 句</span>
              <span>·</span>
              <span>已译 {{ content.translation_status.translated }} 句</span>
              <span v-if="content.translation_status.manual">· 人工 {{ content.translation_status.manual }} 句</span>
            </div>
          </div>

          <v-alert
            v-if="!ai.configured && translationPercent < 100"
            type="info"
            variant="tonal"
            density="compact"
            class="reader-alert"
            icon="mdi-robot-outline"
          >
            尚未配置 AI 翻译模型，当前仅显示原文。可以在设置中接入任意 OpenAI 兼容服务或 Ollama。
            <template #append>
              <v-btn size="small" variant="text" @click="router.push('/settings')">配置模型</v-btn>
            </template>
          </v-alert>

          <v-alert
            v-if="content.translation_status.states.failed"
            type="warning"
            variant="tonal"
            density="compact"
            class="reader-alert"
            icon="mdi-alert-outline"
          >
            有 {{ content.translation_status.states.failed }} 句翻译失败。
            <template #append>
              <v-btn size="small" variant="text" :disabled="Boolean(activeTranslationTask)" @click="triggerTranslation(false)">重试失败句</v-btn>
            </template>
          </v-alert>

          <div v-if="!content.paragraphs.length" class="empty-reader">
            <div class="serif">本章没有可显示的正文。</div>
          </div>

          <div
            v-else
            class="reader-columns"
            :class="{ 'single-column': viewMode !== 'both', 'only-translation': viewMode === 'translation' }"
          >
            <div v-if="showOriginal" class="column-head">
              <span class="column-title serif">原文</span>
              <span class="column-note">保留原始文本与标点</span>
            </div>
            <div v-if="showTranslation" class="column-head translation">
              <span class="column-title serif">译文</span>
              <span class="column-note">双栏均衡 · 逐句对应</span>
            </div>

            <template v-for="paragraph in content.paragraphs" :key="paragraph.id">
              <div
                v-if="showOriginal"
                class="paragraph-cell original"
                :class="{ active: activeParagraphId === paragraph.id }"
                :data-paragraph-id="showOriginal ? paragraph.id : undefined"
                :id="`para-${paragraph.id}`"
                @click="selectParagraph(paragraph)"
              >
                <span class="paragraph-number">{{ paragraph.ordinal + 1 }}</span>
                <div class="reader-text">
                  <span
                    v-for="sentence in paragraph.sentences"
                    :key="sentence.id"
                    class="sentence"
                    :class="sentenceClass(sentence)"
                    :id="`sent-${sentence.id}`"
                    @click.stop="selectSentence(sentence, paragraph)"
                  >{{ sentence.original_text }}</span>
                </div>
              </div>

              <div
                v-if="showTranslation"
                class="paragraph-cell translation"
                :class="{ active: activeParagraphId === paragraph.id }"
                :data-paragraph-id="!showOriginal ? paragraph.id : undefined"
                @click="selectParagraph(paragraph)"
              >
                <span class="paragraph-number">{{ paragraph.ordinal + 1 }}</span>
                <div v-if="paragraph.sentences.some((sentence) => sentence.translation)" class="reader-text translation">
                  <span
                    v-for="sentence in paragraph.sentences"
                    :key="sentence.id"
                    class="sentence"
                    :class="sentenceClass(sentence)"
                    @click.stop="selectSentence(sentence, paragraph)"
                  >
                    <template v-if="sentence.translation">
                      {{ sentence.translation.text }}
                      <span v-if="sentence.translation.origin === 'manual'" class="manual-mark">人</span>
                      <span v-if="sentence.pending_review" class="review-mark" title="有新的候选译文待审核">审</span>
                    </template>
                    <span v-else class="sentence-placeholder">{{ shortState(sentence) }}</span>
                  </span>
                </div>
                <div v-else class="reader-text translation empty-translation">
                  <span class="sentence-placeholder">{{ paragraphPlaceholder(paragraph) }}</span>
                </div>
              </div>
            </template>
          </div>

          <div class="chapter-end">
            <v-btn v-if="content.previous_chapter_id" variant="text" prepend-icon="mdi-chevron-left" @click="navigateChapter(content.previous_chapter_id)">
              上一章
            </v-btn>
            <v-spacer />
            <span class="end-mark serif">终</span>
            <v-spacer />
            <v-btn v-if="content.next_chapter_id" variant="text" append-icon="mdi-chevron-right" @click="navigateChapter(content.next_chapter_id)">
              下一章
            </v-btn>
          </div>
        </template>

        <v-alert
          v-if="loadError && !loading"
          type="error"
          variant="tonal"
          class="mt-8"
          :text="loadError"
        >
          <template #append>
            <v-btn size="small" variant="text" @click="loadChapter">重试</v-btn>
          </template>
        </v-alert>
      </div>
    </div>

    <SentencePanel
      v-model="sentencePanelOpen"
      :book-id="bookId"
      :chapter-id="chapterId"
      :sentence="selectedSentence"
      :paragraph="selectedParagraph"
      :device-id="app.deviceId"
      @updated="refreshContent"
      @assistant="assistantOpen = true"
    />

    <AssistantDrawer
      v-model="assistantOpen"
      :book-id="bookId"
      :chapter-id="chapterId"
      :paragraph-id="selectedParagraph?.id || null"
      :sentence-id="selectedSentence?.id || null"
      :context-label="assistantContext"
    />
  </div>
</template>

<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import AssistantDrawer from '@/components/AssistantDrawer.vue'
import SentencePanel from '@/components/SentencePanel.vue'
import { booksApi } from '@/api/books'
import { readerApi } from '@/api/reader'
import { translationApi } from '@/api/translation'
import type { ChapterContent, ChapterSummary, Paragraph, Sentence } from '@/api/types'
import { useAiStore } from '@/stores/ai'
import { useAppStore } from '@/stores/app'
import { useTasksStore } from '@/stores/tasks'

const route = useRoute()
const router = useRouter()
const app = useAppStore()
const ai = useAiStore()
const tasks = useTasksStore()

const content = ref<ChapterContent | null>(null)
const chapters = ref<ChapterSummary[]>([])
const loading = ref(true)
const loadError = ref('')
const scrollContainer = ref<HTMLElement | null>(null)
const selectedChapterId = ref(String(route.params.chapterId))
const selectedSentenceId = ref<string | null>(null)
const selectedParagraphId = ref<string | null>(null)
const sentencePanelOpen = ref(false)
const assistantOpen = ref(false)
const readingRatio = ref(0)
const activeParagraphId = ref<string | null>(null)
const translating = ref(false)
const storedReaderMode = localStorage.getItem('guwen:readerMode') || 'both'
const viewMode = ref<'both' | 'original' | 'translation'>(
  (['both', 'original', 'translation'].includes(storedReaderMode)
    ? storedReaderMode : 'both') as 'both' | 'original' | 'translation',
)
watch(viewMode, (value) => localStorage.setItem('guwen:readerMode', value))

const bookId = computed(() => String(route.params.bookId))
const chapterId = computed(() => String(route.params.chapterId))
const bookTitleFallback = computed(() => content.value?.book.title || '阅读')
const showOriginal = computed(() => viewMode.value !== 'translation')
const showTranslation = computed(() => viewMode.value !== 'original')
const chapterOptions = computed(() => chapters.value.map((chapter) => ({
  title: `${String(chapter.ordinal + 1).padStart(2, '0')} · ${chapter.title}`,
  value: chapter.id,
})))
const selectedSentence = computed<Sentence | null>(() => {
  if (!content.value || !selectedSentenceId.value) return null
  for (const paragraph of content.value.paragraphs) {
    const found = paragraph.sentences.find((sentence) => sentence.id === selectedSentenceId.value)
    if (found) return found
  }
  return null
})
const selectedParagraph = computed<Paragraph | null>(() => {
  if (!content.value || !selectedParagraphId.value) return null
  return content.value.paragraphs.find((paragraph) => paragraph.id === selectedParagraphId.value) || null
})
const translationPercent = computed(() => content.value?.translation_status.percent || 0)
const activeTranslationTask = computed(() => tasks.tasks.find((task) =>
  task.type === 'translation'
  && task.chapter_id === chapterId.value
  && ['queued', 'running'].includes(task.status),
))
const assistantContext = computed(() => {
  if (!content.value) return ''
  const sentenceText = selectedSentence.value ? ` · 选中：${selectedSentence.value.original_text.slice(0, 28)}…` : ''
  return `${content.value.book.title} · ${content.value.chapter.title}${sentenceText}`
})

const autoTriggered = new Set<string>()
let saveTimer: number | undefined
let refreshTimer: number | undefined
let pollTimer: number | undefined
let restoreTimer: number | undefined
let restoring = false

watch(
  () => chapterId.value,
  () => { loadChapter() },
)

watch(
  () => tasks.lastEvent,
  (event) => {
    if (!event || event.task.chapter_id !== chapterId.value) return
    if (event.task.type !== 'translation') return
    if (['task_completed', 'task_failed', 'task_cancelled'].includes(event.type)) {
      refreshContent()
      maybeStartPolling()
    } else {
      scheduleRefresh()
      maybeStartPolling()
    }
  },
)

watch(
  () => activeTranslationTask.value?.id,
  () => { maybeStartPolling() },
)

watch(
  () => ai.configured,
  (configured) => { if (configured) maybeAutoTranslate() },
)

async function loadChapter() {
  loading.value = true
  loadError.value = ''
  selectedSentenceId.value = null
  selectedParagraphId.value = null
  sentencePanelOpen.value = false
  readingRatio.value = 0
  restoring = true
  window.clearTimeout(restoreTimer)
  selectedChapterId.value = chapterId.value
  try {
    const [chapterRows, data] = await Promise.all([
      chapters.value.length ? Promise.resolve(chapters.value) : booksApi.chapters(bookId.value),
      readerApi.content(chapterId.value),
    ])
    chapters.value = chapterRows
    content.value = data
    await nextTick()
    await restoreProgress()
    await applyQueryHighlight()
    updateActiveParagraph()
    maybeStartPolling()
    maybeAutoTranslate()
  } catch (error) {
    content.value = null
    loadError.value = error instanceof Error ? error.message : '章节加载失败'
  } finally {
    loading.value = false
    restoreTimer = window.setTimeout(() => { restoring = false }, 800)
  }
}

async function refreshContent() {
  if (!content.value) return
  const container = scrollContainer.value
  const top = container?.scrollTop || 0
  try {
    content.value = await readerApi.content(chapterId.value)
    await nextTick()
    if (container) container.scrollTop = top
    updateActiveParagraph()
  } catch {
    // Leave the currently displayed text in place if the refresh fails.
  }
}

function scheduleRefresh() {
  if (refreshTimer) return
  refreshTimer = window.setTimeout(async () => {
    refreshTimer = undefined
    await refreshContent()
  }, 700)
}

async function restoreProgress() {
  try {
    const result = await readerApi.getProgress(bookId.value, app.deviceId)
    const progress = result.progress
    if (!progress || progress.chapter_id !== chapterId.value) {
      if (scrollContainer.value) scrollContainer.value.scrollTop = 0
      return
    }
    const container = scrollContainer.value
    if (!container) return
    if (progress.paragraph_id) {
      const element = document.getElementById(`para-${progress.paragraph_id}`)
      if (element) {
        const elementTop = element.getBoundingClientRect().top
        const containerTop = container.getBoundingClientRect().top
        container.scrollTop += elementTop - containerTop - 90
        activeParagraphId.value = progress.paragraph_id
      }
    } else if (progress.position_ratio > 0) {
      container.scrollTop = container.scrollHeight * progress.position_ratio
    }
  } catch {
    // Start from the top if progress cannot be loaded.
  }
}

function selectSentence(sentence: Sentence, paragraph: Paragraph) {
  selectedSentenceId.value = sentence.id
  selectedParagraphId.value = paragraph.id
  activeParagraphId.value = paragraph.id
  sentencePanelOpen.value = true
}

function selectParagraph(paragraph: Paragraph) {
  selectedParagraphId.value = paragraph.id
  activeParagraphId.value = paragraph.id
  scheduleSave()
}

async function applyQueryHighlight() {
  const highlight = route.query.highlight
  if (typeof highlight !== 'string' || !content.value) return
  for (const paragraph of content.value.paragraphs) {
    const sentence = paragraph.sentences.find((item) => item.id === highlight)
    if (sentence) {
      selectedSentenceId.value = sentence.id
      selectedParagraphId.value = paragraph.id
      activeParagraphId.value = paragraph.id
      await nextTick()
      const element = document.getElementById(`sent-${sentence.id}`)
      const container = scrollContainer.value
      if (element && container) {
        const top = element.getBoundingClientRect().top - container.getBoundingClientRect().top
        container.scrollTop += top - container.clientHeight / 2.6
      }
      return
    }
  }
}

function sentenceClass(sentence: Sentence) {
  return [
    `state-${sentence.translation_state}`,
    { selected: selectedSentenceId.value === sentence.id, 'needs-review': sentence.needs_review },
  ]
}

function shortState(sentence: Sentence): string {
  return ({
    pending: '〔待译〕',
    queued: '〔排队中〕',
    translating: '〔翻译中〕',
    failed: '〔翻译失败〕',
  } as Record<string, string>)[sentence.translation_state] || '〔待译〕'
}

function paragraphPlaceholder(paragraph: Paragraph): string {
  const states = paragraph.sentences.map((sentence) => sentence.translation_state)
  if (states.includes('translating')) return '正在翻译本段…'
  if (states.includes('queued')) return '本段译文排队中…'
  if (states.includes('failed')) return '本段翻译失败，可点击重试'
  return '本段尚未翻译'
}

function onScroll() {
  const container = scrollContainer.value
  if (!container || restoring) return
  const max = container.scrollHeight - container.clientHeight
  readingRatio.value = max > 0 ? Math.min(1, Math.max(0, container.scrollTop / max)) : 0
  updateActiveParagraph()
  scheduleSave()
}

function updateActiveParagraph() {
  const container = scrollContainer.value
  if (!container) return
  const cells = [...container.querySelectorAll<HTMLElement>('[data-paragraph-id]')]
  if (!cells.length) return
  const threshold = container.getBoundingClientRect().top + 140
  let current = cells[0]
  for (const cell of cells) {
    if (cell.getBoundingClientRect().top <= threshold) current = cell
    else break
  }
  activeParagraphId.value = current.dataset.paragraphId || null
}

function scheduleSave() {
  window.clearTimeout(saveTimer)
  saveTimer = window.setTimeout(() => { saveProgress() }, 1400)
}

function saveProgress() {
  if (!content.value) return
  readerApi.saveProgress({
    book_id: bookId.value,
    device_id: app.deviceId,
    chapter_id: chapterId.value,
    paragraph_id: activeParagraphId.value,
    sentence_id: selectedSentenceId.value,
    position_ratio: readingRatio.value,
  }).catch(() => undefined)
}

function changeChapter(value: string | null) {
  if (!value || value === chapterId.value) return
  saveProgress()
  router.replace(`/read/${bookId.value}/${value}`)
}

function navigateChapter(value: string | null | undefined) {
  if (value) changeChapter(value)
}

function goBook() {
  saveProgress()
  router.push(`/books/${bookId.value}`)
}

async function triggerTranslation(retranslate: boolean) {
  if (!ai.configured) {
    app.notify('请先在设置中配置翻译模型', 'warning')
    router.push('/settings')
    return
  }
  if (activeTranslationTask.value) return
  translating.value = true
  try {
    const task = await translationApi.chapter(chapterId.value, { retranslate })
    tasks.upsert(task)
    app.notify(retranslate ? '已创建重新翻译任务' : '已创建本章翻译任务')
    maybeStartPolling()
  } finally {
    translating.value = false
  }
}

async function cancelTranslation() {
  if (!activeTranslationTask.value) return
  const task = await tasks.cancel(activeTranslationTask.value.id)
  app.notify(task.status === 'cancelled' ? '翻译任务已取消' : '已请求取消翻译任务', 'warning')
}

function maybeAutoTranslate() {
  if (!content.value || !app.autoTranslate || !ai.configured) return
  if (translationPercent.value >= 100) return
  if (activeTranslationTask.value) return
  const states = content.value.translation_status.states
  if (states.queued || states.translating) return
  if (autoTriggered.has(chapterId.value)) return
  autoTriggered.add(chapterId.value)
  triggerTranslation(false).catch(() => undefined)
}

function maybeStartPolling() {
  if (!content.value) return
  const states = content.value.translation_status.states
  const active = Boolean(activeTranslationTask.value) || Boolean(states.queued) || Boolean(states.translating)
  if (!active) {
    if (pollTimer) {
      window.clearInterval(pollTimer)
      pollTimer = undefined
    }
    return
  }
  if (pollTimer) return
  pollTimer = window.setInterval(async () => {
    if (!content.value) return
    try {
      const status = await readerApi.status(chapterId.value)
      const previous = content.value.translation_status.translated
      content.value.translation_status = status
      if (status.translated !== previous) {
        await refreshContent()
      }
      const live = status.states.queued || status.states.translating || Boolean(activeTranslationTask.value)
      if (!live) {
        window.clearInterval(pollTimer)
        pollTimer = undefined
      }
    } catch {
      // Polling is a fallback for dropped WebSocket connections.
    }
  }, 3000)
}

async function addBookmark() {
  if (!content.value) return
  const paragraph = content.value.paragraphs.find((item) => item.id === activeParagraphId.value)
    || content.value.paragraphs[0]
  try {
    await readerApi.createBookmark({
      book_id: bookId.value,
      chapter_id: chapterId.value,
      paragraph_id: paragraph?.id || null,
      sentence_id: selectedSentenceId.value,
      label: `${content.value.chapter.title}${paragraph ? ` · 第 ${paragraph.ordinal + 1} 段` : ''}`,
      position_ratio: readingRatio.value,
      device_id: app.deviceId,
    })
    app.notify('书签已添加')
  } catch {
    // Interceptor already surfaced the error.
  }
}

onMounted(async () => {
  await loadChapter()
  if (!ai.loaded) ai.load().catch(() => undefined)
})

onBeforeUnmount(() => {
  saveProgress()
  window.clearTimeout(saveTimer)
  window.clearTimeout(refreshTimer)
  window.clearTimeout(restoreTimer)
  if (pollTimer) window.clearInterval(pollTimer)
})
</script>

<style scoped>
.toolbar-book {
  min-width: 120px;
  max-width: 200px;
}
.toolbar-title {
  font-size: 0.94rem;
  font-weight: 650;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.toolbar-chapter {
  font-size: 0.66rem;
  color: rgba(var(--v-theme-on-surface), 0.46);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.chapter-select {
  max-width: 240px;
  min-width: 170px;
  background: rgba(var(--v-theme-surface), 0.65);
}
.chapter-nav {
  display: flex;
  margin-left: -4px;
}
.status-chip {
  cursor: pointer;
}
.reader-settings {
  background: rgb(var(--v-theme-surface));
  border: 1px solid rgba(var(--v-theme-on-surface), 0.1);
}
.settings-head {
  padding: 18px 18px 2px;
}
.settings-title {
  font-size: 1.18rem;
  font-weight: 650;
  margin-top: 3px;
}
.settings-body {
  padding: 12px 18px 18px;
}
.setting-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  padding: 11px 0;
  border-bottom: 1px dashed rgba(var(--v-theme-on-surface), 0.08);
  font-size: 0.78rem;
}
.setting-row:last-child {
  border-bottom: 0;
}
.slider-with-value {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 175px;
}
.setting-value {
  width: 36px;
  text-align: right;
  font-size: 0.7rem;
  color: rgba(var(--v-theme-on-surface), 0.5);
  font-variant-numeric: tabular-nums;
}
.chapter-masthead {
  text-align: center;
  margin: 10px 0 26px;
}
.masthead-book {
  font-size: 0.78rem;
  letter-spacing: 0.28em;
  color: rgba(var(--v-theme-secondary), 0.9);
  text-transform: uppercase;
}
.masthead-meta {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 7px;
  margin-top: 9px;
  font-size: 0.7rem;
  color: rgba(var(--v-theme-on-surface), 0.4);
  flex-wrap: wrap;
}
.reader-alert {
  max-width: 900px;
  margin: 0 auto 18px;
}
.empty-reader {
  text-align: center;
  padding: 80px 20px;
  color: rgba(var(--v-theme-on-surface), 0.45);
}
.reader-columns .column-head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 14px;
  padding: 12px 22px;
  background: rgba(var(--v-theme-surface), 0.96);
  border-bottom: 1px solid rgba(var(--v-theme-on-surface), 0.1);
  position: sticky;
  top: 0;
  z-index: 3;
  backdrop-filter: blur(10px);
}
.reader-columns .column-head.translation {
  border-left: 1px solid rgba(var(--v-theme-on-surface), 0.08);
}
.column-title {
  font-size: 1rem;
  font-weight: 650;
  letter-spacing: 0.08em;
}
.column-note {
  font-size: 0.64rem;
  color: rgba(var(--v-theme-on-surface), 0.38);
  letter-spacing: 0.04em;
}
.reader-columns.single-column {
  grid-template-columns: 1fr;
}
.reader-columns.single-column .column-head.translation {
  border-left: 0;
}
.paragraph-cell {
  padding: 20px 26px;
  min-width: 0;
  position: relative;
  border-bottom: 1px solid rgba(var(--v-theme-on-surface), 0.075);
  transition: background 150ms ease;
}
.paragraph-cell.original {
  border-right: 1px solid rgba(var(--v-theme-on-surface), 0.075);
}
.paragraph-cell.active {
  background: rgba(var(--v-theme-primary), 0.035);
}
.paragraph-cell.translation .reader-text {
  color: rgba(var(--v-theme-on-surface), 0.82);
}
.empty-translation {
  color: rgba(var(--v-theme-on-surface), 0.4);
  font-style: normal;
}
.chapter-end {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 46px 10px 10px;
}
.end-mark {
  color: rgba(var(--v-theme-secondary), 0.5);
  font-size: 1.1rem;
  letter-spacing: 0.2em;
}
@media (max-width: 1100px) {
  .toolbar-book {
    display: none;
  }
  .chapter-select {
    min-width: 150px;
  }
}
@media (max-width: 840px) {
  .reader-toolbar {
    flex-wrap: wrap;
    padding: 8px 12px;
    gap: 8px;
  }
  .status-chip {
    display: none;
  }
  .reader-page {
    padding: 16px 12px 100px;
  }
  .reader-columns {
    grid-template-columns: 1fr;
  }
  .paragraph-cell.original {
    border-right: 0;
  }
}
</style>
