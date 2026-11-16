<template>
  <div class="page">
    <div class="library-hero">
      <div>
        <div class="section-label">古籍书架</div>
        <h1 class="page-title">藏书阁</h1>
        <p class="page-subtitle">原文完整保留，译文逐句对应。把注意力留给文本本身。</p>
      </div>
      <v-btn color="primary" size="large" prepend-icon="mdi-plus" @click="importOpen = true">
        导入古籍
      </v-btn>
    </div>

    <div class="stat-strip">
      <div class="stat-item">
        <div class="stat-number">{{ library.total }}</div>
        <div class="stat-label">在架书籍</div>
      </div>
      <div class="stat-divider" />
      <div class="stat-item">
        <div class="stat-number">{{ totalSentences.toLocaleString() }}</div>
        <div class="stat-label">可读句子</div>
      </div>
      <div class="stat-divider" />
      <div class="stat-item">
        <div class="stat-number">{{ Math.round(translationPercent) }}<span class="unit">%</span></div>
        <div class="stat-label">整体翻译进度</div>
      </div>
      <div class="stat-divider" />
      <div class="stat-item">
        <div class="stat-number">{{ ai.enabledModels.length }}</div>
        <div class="stat-label">可用 AI 模型</div>
      </div>
    </div>

    <v-card v-if="continueBook" class="continue-card" @click="openBook(continueBook)">
      <div class="continue-cover">
        <img v-if="continueBook.cover_url" :src="booksApi.coverUrl(continueBook)" alt="" />
        <div v-else class="cover-fallback"><span class="serif">{{ continueBook.title.slice(0, 1) }}</span></div>
      </div>
      <div class="continue-body">
        <div class="section-label">继续阅读</div>
        <div class="continue-title serif">{{ continueBook.title }}</div>
        <div class="continue-meta">
          {{ continueBook.author || '作者未详' }}
          <span>·</span>
          {{ continueBook.last_read_at ? formatRelative(continueBook.last_read_at) : '' }}
          <span>·</span>
          已译 {{ Math.round(continueBook.translation_percent) }}%
        </div>
      </div>
      <div class="continue-action">
        <v-btn color="primary" append-icon="mdi-arrow-right">继续阅读</v-btn>
      </div>
    </v-card>

    <div class="toolbar-row">
      <v-text-field
        v-model="library.query"
        prepend-inner-icon="mdi-magnify"
        placeholder="搜索书名、作者或简介"
        density="comfortable"
        variant="solo"
        flat
        hide-details
        rounded="lg"
        class="search-field"
        clearable
      />
      <v-select
        v-model="library.sort"
        :items="sortOptions"
        item-title="title"
        item-value="value"
        density="comfortable"
        variant="solo"
        flat
        hide-details
        rounded="lg"
        class="sort-field"
        prepend-inner-icon="mdi-sort"
      />
    </div>

    <div v-if="library.categories.length" class="category-row">
      <v-chip
        :variant="!library.category ? 'flat' : 'tonal'"
        color="primary"
        size="small"
        @click="library.category = null"
      >
        全部
      </v-chip>
      <v-chip
        v-for="category in library.categories"
        :key="category"
        :variant="library.category === category ? 'flat' : 'tonal'"
        color="primary"
        size="small"
        @click="library.category = library.category === category ? null : category"
      >
        {{ category }}
      </v-chip>
    </div>

    <v-progress-linear v-if="library.loading" indeterminate color="primary" class="mt-8" rounded />

    <div v-else-if="library.books.length" class="book-grid">
      <BookCard v-for="book in library.books" :key="book.id" :book="book" @open="openBook" />
    </div>

    <EmptyState
      v-else-if="!library.query"
      title="书架还是空的"
      text="导入 TXT、EPUB、DOCX 或文本型 PDF，古文阅读器会识别章节、切分句子并保留原文位置。"
      glyph="藏"
    >
      <v-btn color="primary" class="mt-6" prepend-icon="mdi-plus" @click="importOpen = true">导入第一本书</v-btn>
    </EmptyState>

    <EmptyState
      v-else
      title="没有找到匹配的书籍"
      text="尝试更换关键词或清除分类筛选。"
      glyph="寻"
    />

    <ImportDialog v-model="importOpen" @imported="onImported" />
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import BookCard from '@/components/BookCard.vue'
import EmptyState from '@/components/EmptyState.vue'
import ImportDialog from '@/components/ImportDialog.vue'
import { booksApi } from '@/api/books'
import type { Book } from '@/api/types'
import { useAiStore } from '@/stores/ai'
import { useLibraryStore } from '@/stores/library'

const library = useLibraryStore()
const ai = useAiStore()
const router = useRouter()
const importOpen = ref(false)

const sortOptions = [
  { title: '最近阅读', value: 'recent' },
  { title: '最近导入', value: 'imported' },
  { title: '书名', value: 'title' },
  { title: '作者', value: 'author' },
]

const totalSentences = computed(() =>
  library.books.reduce((sum, book) => sum + book.sentence_count, 0),
)
const translationPercent = computed(() => {
  const total = library.books.reduce((sum, book) => sum + book.sentence_count, 0)
  const translated = library.books.reduce((sum, book) => sum + book.translated_sentence_count, 0)
  return total ? (translated / total) * 100 : 0
})
const continueBook = computed(() =>
  library.books.find((book) => book.last_read_at) || library.books[0] || null,
)

let timer: number | undefined
watch(
  () => [library.query, library.sort, library.category],
  () => {
    window.clearTimeout(timer)
    timer = window.setTimeout(() => library.load(), 240)
  },
)

function openBook(book: Book) {
  router.push(`/books/${book.id}`)
}

async function onImported(book: Book) {
  await router.push(`/books/${book.id}`)
}

function formatRelative(value: string): string {
  const diff = Date.now() - new Date(value).getTime()
  const minutes = Math.floor(diff / 60000)
  if (minutes < 60) return `${Math.max(minutes, 1)} 分钟前`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours} 小时前`
  return `${Math.floor(hours / 24)} 天前`
}

onMounted(async () => {
  await library.load()
  if (!ai.loaded) ai.load().catch(() => undefined)
})
</script>

<style scoped>
.library-hero {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 24px;
  flex-wrap: wrap;
  margin-bottom: 30px;
}
.stat-strip {
  display: flex;
  align-items: center;
  gap: clamp(18px, 4vw, 54px);
  padding: 18px 24px;
  border-radius: 18px;
  background: rgba(var(--v-theme-surface), 0.62);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.07);
  margin-bottom: 24px;
  flex-wrap: wrap;
}
.stat-item {
  min-width: 84px;
}
.stat-number {
  font-family: "Noto Serif SC", "Songti SC", "SimSun", serif;
  font-size: 1.7rem;
  font-weight: 650;
  font-variant-numeric: tabular-nums;
}
.stat-number .unit {
  font-size: 0.9rem;
  margin-left: 2px;
  color: rgba(var(--v-theme-on-surface), 0.45);
}
.stat-label {
  font-size: 0.71rem;
  color: rgba(var(--v-theme-on-surface), 0.5);
  margin-top: 3px;
}
.stat-divider {
  width: 1px;
  height: 34px;
  background: rgba(var(--v-theme-on-surface), 0.1);
}
.continue-card {
  display: flex;
  align-items: center;
  gap: 20px;
  padding: 16px;
  margin-bottom: 28px;
  cursor: pointer;
  background:
    linear-gradient(110deg, rgba(var(--v-theme-primary), 0.08), rgba(var(--v-theme-surface), 0.88) 45%),
    rgb(var(--v-theme-surface));
  border: 1px solid rgba(var(--v-theme-primary), 0.12);
  transition: transform 160ms ease;
}
.continue-card:hover {
  transform: translateY(-2px);
}
.continue-cover {
  width: 68px;
  height: 92px;
  border-radius: 10px;
  overflow: hidden;
  flex-shrink: 0;
}
.continue-cover img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.continue-cover .cover-fallback {
  width: 100%;
  height: 100%;
  font-size: 1.8rem;
}
.continue-body {
  flex: 1;
  min-width: 0;
}
.continue-title {
  font-size: 1.35rem;
  font-weight: 650;
  margin-top: 5px;
}
.continue-meta {
  display: flex;
  gap: 7px;
  flex-wrap: wrap;
  margin-top: 7px;
  font-size: 0.75rem;
  color: rgba(var(--v-theme-on-surface), 0.52);
}
.toolbar-row {
  display: flex;
  gap: 12px;
  margin-bottom: 15px;
}
.search-field {
  max-width: 420px;
  background: rgba(var(--v-theme-surface), 0.7);
}
.sort-field {
  max-width: 170px;
  background: rgba(var(--v-theme-surface), 0.7);
}
.category-row {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
  margin-bottom: 24px;
}
.book-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(210px, 1fr));
  gap: 22px;
}
.continue-action {
  padding-right: 8px;
}
@media (max-width: 700px) {
  .stat-divider {
    display: none;
  }
  .stat-strip {
    gap: 22px;
  }
  .continue-action {
    display: none;
  }
  .toolbar-row {
    flex-direction: column;
  }
  .search-field,
  .sort-field {
    max-width: none;
  }
}
</style>
