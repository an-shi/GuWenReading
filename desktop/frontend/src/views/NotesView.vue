<template>
  <div class="page">
    <div class="page-header">
      <div>
        <div class="section-label">批注札记</div>
        <h1 class="page-title">批注与书签</h1>
        <p class="page-subtitle">阅读时留下的疑问、考据与位置。批注与阅读进度按设备分别保存。</p>
      </div>
    </div>

    <div class="filter-row">
      <v-select
        v-model="bookFilter"
        :items="bookOptions"
        item-title="title"
        item-value="value"
        placeholder="全部书籍"
        density="comfortable"
        variant="solo"
        flat
        hide-details
        rounded="lg"
        clearable
        class="book-filter"
        @update:model-value="loadAll"
      />
      <v-spacer />
      <v-btn-toggle v-model="tab" density="compact" variant="tonal" divided mandatory>
        <v-btn value="annotations" size="small" prepend-icon="mdi-comment-text-outline">批注 {{ annotations.length }}</v-btn>
        <v-btn value="bookmarks" size="small" prepend-icon="mdi-bookmark-outline">书签 {{ bookmarks.length }}</v-btn>
      </v-btn-toggle>
    </div>

    <v-progress-linear v-if="loading" indeterminate color="primary" rounded class="mb-5" />

    <template v-if="tab === 'annotations'">
      <div v-if="annotations.length" class="annotation-grid">
        <v-card v-for="annotation in annotations" :key="annotation.id" class="annotation-card">
          <div class="annotation-head">
            <div>
              <span class="serif annotation-book">{{ bookTitle(annotation.book_id) }}</span>
              <span class="tiny muted"> · {{ chapterTitle(annotation.chapter_id) }}</span>
            </div>
            <v-menu>
              <template #activator="{ props }">
                <v-btn v-bind="props" icon="mdi-dots-horizontal" size="x-small" variant="text" />
              </template>
              <v-list density="compact">
                <v-list-item prepend-icon="mdi-arrow-top-right" title="回到原文" @click="openAnnotation(annotation)" />
                <v-list-item prepend-icon="mdi-pencil-outline" title="编辑批注" @click="openEdit(annotation)" />
                <v-list-item prepend-icon="mdi-delete-outline" title="删除" base-color="error" @click="removeAnnotation(annotation.id)" />
              </v-list>
            </v-menu>
          </div>
          <div v-if="annotation.quote" class="annotation-quote serif" @click="openAnnotation(annotation)">
            {{ annotation.quote }}
          </div>
          <div class="annotation-body">{{ annotation.content }}</div>
          <div class="annotation-foot">
            <span>{{ formatDate(annotation.created_at) }}</span>
            <div class="tag-row">
              <v-chip v-for="tag in annotation.tags" :key="tag" size="x-small" variant="tonal">{{ tag }}</v-chip>
            </div>
          </div>
        </v-card>
      </div>
      <EmptyState
        v-else-if="!loading"
        title="还没有批注"
        text="在阅读器中选中句子或添加批注，内容会出现在这里，并可随时回到原文位置。"
        glyph="注"
      />
    </template>

    <template v-else>
      <div v-if="bookmarks.length" class="bookmark-list">
        <v-card v-for="bookmark in bookmarks" :key="bookmark.id" class="bookmark-card" @click="openBookmark(bookmark)">
          <div class="bookmark-ribbon"><v-icon icon="mdi-bookmark" size="18" /></div>
          <div class="bookmark-body">
            <div class="bookmark-title serif">{{ bookmark.label || '未命名书签' }}</div>
            <div class="bookmark-meta">
              {{ bookTitle(bookmark.book_id) }} · {{ chapterTitle(bookmark.chapter_id) }}
            </div>
            <div class="tiny muted">{{ formatDate(bookmark.created_at) }}</div>
          </div>
          <v-btn
            icon="mdi-delete-outline"
            size="small"
            variant="text"
            @click.stop="removeBookmark(bookmark.id)"
          />
        </v-card>
      </div>
      <EmptyState
        v-else-if="!loading"
        title="还没有书签"
        text="阅读时点击书签按钮，即可保存当前章节与段落位置。"
        glyph="签"
      />
    </template>

    <v-dialog v-model="editOpen" max-width="620">
      <v-card>
        <v-card-title class="pt-6 px-6">编辑批注</v-card-title>
        <v-card-text>
          <div v-if="editTarget?.quote" class="edit-quote serif">{{ editTarget.quote }}</div>
          <v-textarea v-model="editContent" rows="5" label="批注内容" />
        </v-card-text>
        <v-card-actions class="px-6 pb-5">
          <v-spacer />
          <v-btn variant="text" @click="editOpen = false">取消</v-btn>
          <v-btn color="primary" :loading="saving" @click="saveEdit">保存</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import EmptyState from '@/components/EmptyState.vue'
import { booksApi } from '@/api/books'
import { readerApi } from '@/api/reader'
import type { Annotation, Book, Bookmark, ChapterSummary } from '@/api/types'
import { useAppStore } from '@/stores/app'

const router = useRouter()
const app = useAppStore()
const tab = ref<'annotations' | 'bookmarks'>('annotations')
const annotations = ref<Annotation[]>([])
const bookmarks = ref<Bookmark[]>([])
const books = ref<Book[]>([])
const chaptersByBook = ref<Record<string, ChapterSummary[]>>({})
const bookFilter = ref<string | null>(null)
const loading = ref(false)
const editOpen = ref(false)
const editTarget = ref<Annotation | null>(null)
const editContent = ref('')
const saving = ref(false)

const bookOptions = computed(() => books.value.map((book) => ({ title: book.title, value: book.id })))
const bookMap = computed(() => new Map(books.value.map((book) => [book.id, book])))
const chapterMap = computed(() => {
  const map = new Map<string, string>()
  Object.values(chaptersByBook.value).forEach((chapters) => {
    chapters.forEach((chapter) => map.set(chapter.id, chapter.title))
  })
  return map
})

function bookTitle(id: string): string {
  return bookMap.value.get(id)?.title || '未知书籍'
}
function chapterTitle(id: string | null): string {
  return (id && chapterMap.value.get(id)) || '未知章节'
}
function formatDate(value: string): string {
  return new Date(value).toLocaleString('zh-CN', {
    year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
  })
}

async function loadAll() {
  loading.value = true
  try {
    const [annotationData, bookmarkData, bookData] = await Promise.all([
      readerApi.annotations(bookFilter.value || undefined),
      readerApi.bookmarks(bookFilter.value || undefined),
      booksApi.list({ page: 1, page_size: 100 }),
    ])
    annotations.value = annotationData.items
    bookmarks.value = bookmarkData
    books.value = bookData.items
    const missing = new Set<string>()
    annotations.value.forEach((item) => {
      if (!chaptersByBook.value[item.book_id] && !missing.has(item.book_id)) missing.add(item.book_id)
    })
    bookmarks.value.forEach((item) => {
      if (!chaptersByBook.value[item.book_id] && !missing.has(item.book_id)) missing.add(item.book_id)
    })
    await Promise.all([...missing].map(async (bookId) => {
      try {
        chaptersByBook.value[bookId] = await booksApi.chapters(bookId)
      } catch {
        chaptersByBook.value[bookId] = []
      }
    }))
    if (bookFilter.value) {
      annotations.value = annotations.value.filter((item) => item.book_id === bookFilter.value)
      bookmarks.value = bookmarks.value.filter((item) => item.book_id === bookFilter.value)
    }
  } finally {
    loading.value = false
  }
}

function openAnnotation(annotation: Annotation) {
  if (!annotation.chapter_id) return
  const highlight = annotation.sentence_id ? `?highlight=${annotation.sentence_id}` : ''
  router.push(`/read/${annotation.book_id}/${annotation.chapter_id}${highlight}`)
}

function openBookmark(bookmark: Bookmark) {
  router.push(`/read/${bookmark.book_id}/${bookmark.chapter_id}`)
}

function openEdit(annotation: Annotation) {
  editTarget.value = annotation
  editContent.value = annotation.content
  editOpen.value = true
}

async function saveEdit() {
  if (!editTarget.value || !editContent.value.trim()) return
  saving.value = true
  try {
    const updated = await readerApi.updateAnnotation(editTarget.value.id, { content: editContent.value.trim() })
    const index = annotations.value.findIndex((item) => item.id === updated.id)
    if (index >= 0) annotations.value[index] = updated
    editOpen.value = false
    app.notify('批注已更新')
  } finally {
    saving.value = false
  }
}

async function removeAnnotation(id: string) {
  await readerApi.deleteAnnotation(id)
  annotations.value = annotations.value.filter((item) => item.id !== id)
  app.notify('批注已删除')
}

async function removeBookmark(id: string) {
  await readerApi.deleteBookmark(id)
  bookmarks.value = bookmarks.value.filter((item) => item.id !== id)
  app.notify('书签已删除')
}

onMounted(loadAll)
</script>

<style scoped>
.filter-row {
  display: flex;
  align-items: center;
  gap: 14px;
  margin-bottom: 20px;
  flex-wrap: wrap;
}
.book-filter {
  max-width: 220px;
  background: rgba(var(--v-theme-surface), 0.65);
}
.annotation-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
  gap: 14px;
}
.annotation-card {
  padding: 17px 18px;
  background: rgba(var(--v-theme-surface), 0.68);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.07);
}
.annotation-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 10px;
  font-size: 0.7rem;
}
.annotation-book {
  font-weight: 650;
  font-size: 0.8rem;
}
.annotation-quote {
  font-size: 0.86rem;
  line-height: 1.75;
  color: rgba(var(--v-theme-on-surface), 0.55);
  padding: 9px 11px;
  margin-top: 10px;
  border-left: 2px solid rgba(var(--v-theme-secondary), 0.45);
  background: rgba(var(--v-theme-secondary), 0.045);
  cursor: pointer;
}
.annotation-body {
  font-size: 0.86rem;
  line-height: 1.78;
  margin-top: 11px;
  white-space: pre-wrap;
}
.annotation-foot {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  margin-top: 13px;
  font-size: 0.64rem;
  color: rgba(var(--v-theme-on-surface), 0.38);
}
.tag-row {
  display: flex;
  gap: 4px;
}
.bookmark-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.bookmark-card {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 13px 16px;
  cursor: pointer;
  background: rgba(var(--v-theme-surface), 0.66);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.065);
}
.bookmark-ribbon {
  width: 34px;
  height: 34px;
  border-radius: 10px;
  display: grid;
  place-items: center;
  background: rgba(var(--v-theme-secondary), 0.09);
  color: rgb(var(--v-theme-secondary));
}
.bookmark-body {
  flex: 1;
  min-width: 0;
}
.bookmark-title {
  font-size: 0.95rem;
  font-weight: 600;
}
.bookmark-meta {
  font-size: 0.68rem;
  color: rgba(var(--v-theme-on-surface), 0.45);
  margin: 3px 0;
}
.edit-quote {
  font-size: 0.9rem;
  line-height: 1.75;
  padding: 10px 12px;
  border-left: 2px solid rgba(var(--v-theme-secondary), 0.45);
  background: rgba(var(--v-theme-secondary), 0.05);
  margin-bottom: 14px;
}
</style>
