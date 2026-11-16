<template>
  <v-card class="book-card" @click="$emit('open', book)">
    <div class="card-cover">
      <img v-if="book.cover_url" :src="booksApi.coverUrl(book)" :alt="book.title" />
      <div v-else class="cover-fallback">
        <span class="cover-glyph">{{ book.title.slice(0, 12) }}</span>
      </div>
    </div>
    <div class="card-body">
      <div class="book-title serif">{{ book.title }}</div>
      <div class="book-author">
        {{ book.author || '作者未详' }}
        <span v-if="book.dynasty"> · {{ book.dynasty }}</span>
      </div>
      <div class="book-meta">
        <span>{{ book.chapter_count }} 章</span>
        <span>·</span>
        <span>{{ book.translated_sentence_count }}/{{ book.sentence_count }} 句</span>
      </div>
      <div class="progress-row">
        <v-progress-linear
          :model-value="book.translation_percent"
          color="primary"
          bg-color="surface-variant"
          height="4"
          rounded
        />
        <span class="percent">{{ Math.round(book.translation_percent) }}%</span>
      </div>
      <div class="last-read">
        {{ book.last_read_at ? `上次阅读 ${formatRelative(book.last_read_at)}` : '尚未开始阅读' }}
      </div>
    </div>
  </v-card>
</template>

<script setup lang="ts">
import { booksApi } from '@/api/books'
import type { Book } from '@/api/types'

defineProps<{ book: Book }>()
defineEmits<{ open: [book: Book] }>()

function formatRelative(value: string): string {
  const date = new Date(value)
  const diff = Date.now() - date.getTime()
  const minutes = Math.floor(diff / 60000)
  if (minutes < 60) return `${Math.max(minutes, 1)} 分钟前`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours} 小时前`
  const days = Math.floor(hours / 24)
  if (days < 30) return `${days} 天前`
  return date.toLocaleDateString('zh-CN')
}
</script>

<style scoped>
.card-cover {
  height: 184px;
  overflow: hidden;
}
.card-cover img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.card-body {
  padding: 16px 17px 15px;
}
.book-title {
  font-size: 1.06rem;
  font-weight: 650;
  line-height: 1.35;
  letter-spacing: 0.01em;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  min-height: 2.8em;
}
.book-author {
  font-size: 0.76rem;
  color: rgba(var(--v-theme-on-surface), 0.56);
  margin-top: 5px;
}
.book-meta {
  display: flex;
  gap: 6px;
  font-size: 0.7rem;
  color: rgba(var(--v-theme-on-surface), 0.46);
  margin-top: 11px;
}
.progress-row {
  display: flex;
  align-items: center;
  gap: 9px;
  margin-top: 10px;
}
.percent {
  font-size: 0.66rem;
  color: rgba(var(--v-theme-on-surface), 0.46);
  font-variant-numeric: tabular-nums;
  min-width: 30px;
  text-align: right;
}
.last-read {
  font-size: 0.67rem;
  color: rgba(var(--v-theme-on-surface), 0.36);
  margin-top: 9px;
}
</style>
