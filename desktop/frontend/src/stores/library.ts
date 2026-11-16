import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import { booksApi, type BookImportPayload, type BookListParams } from '@/api/books'
import type { Book } from '@/api/types'
import { useAppStore } from './app'

export const useLibraryStore = defineStore('library', () => {
  const app = useAppStore()
  const books = ref<Book[]>([])
  const total = ref(0)
  const loading = ref(false)
  const importing = ref(false)
  const query = ref('')
  const sort = ref<BookListParams['sort']>('recent')
  const category = ref<string | null>(null)
  const error = ref<string | null>(null)

  const categories = computed(() => {
    const values = new Set<string>()
    books.value.forEach((book) => { if (book.category) values.add(book.category) })
    return [...values].sort()
  })

  async function load() {
    loading.value = true
    error.value = null
    try {
      const data = await booksApi.list({
        q: query.value || undefined,
        sort: sort.value,
        category: category.value || undefined,
        page: 1,
        page_size: 100,
      })
      books.value = data.items
      total.value = data.total
    } catch (err) {
      error.value = err instanceof Error ? err.message : '加载书架失败'
      books.value = []
    } finally {
      loading.value = false
    }
  }

  async function importBook(payload: BookImportPayload) {
    importing.value = true
    try {
      const book = await booksApi.import(payload)
      app.notify(`已导入《${book.title}》`)
      await load()
      await app.loadInfo()
      return book
    } finally {
      importing.value = false
    }
  }

  async function remove(bookId: string, permanent = false) {
    await booksApi.remove(bookId, permanent)
    app.notify(permanent ? '书籍已永久删除' : '书籍已移出书架')
    await load()
    await app.loadInfo()
  }

  async function refreshOne(bookId: string) {
    const book = await booksApi.get(bookId)
    const index = books.value.findIndex((item) => item.id === bookId)
    if (index >= 0) books.value[index] = book
    return book
  }

  return {
    books, total, loading, importing, query, sort, category, categories, error,
    load, importBook, remove, refreshOne,
  }
})
