import { assetUrl, http } from './client'
import type { Book, ChapterSummary, Paginated } from './types'

export interface BookListParams {
  q?: string
  category?: string
  tag?: string
  sort?: 'recent' | 'imported' | 'title' | 'author'
  page?: number
  page_size?: number
}

export interface BookImportPayload {
  file: File
  title?: string
  author?: string
  dynasty?: string
  category?: string
  description?: string
  tags?: string
}

export const booksApi = {
  list(params: BookListParams = {}) {
    return http.get<Paginated<Book>>('/books', { params })
  },
  get(bookId: string) {
    return http.get<Book>(`/books/${bookId}`)
  },
  async import(payload: BookImportPayload) {
    const form = new FormData()
    form.append('file', payload.file)
    for (const key of ['title', 'author', 'dynasty', 'category', 'description', 'tags'] as const) {
      if (payload[key]) form.append(key, payload[key]!)
    }
    return http.post<Book>('/books/import', form, { timeout: 0 })
  },
  update(bookId: string, data: Partial<Pick<Book, 'title' | 'author' | 'dynasty' | 'category' | 'description' | 'tags'>>) {
    return http.put<Book>(`/books/${bookId}`, data)
  },
  remove(bookId: string, permanent = false) {
    return http.delete<{ removed: boolean }>(`/books/${bookId}`, { params: { permanent } })
  },
  reparse(bookId: string, force = false) {
    return http.post<Book>(`/books/${bookId}/reparse`, undefined, { params: { force } })
  },
  chapters(bookId: string) {
    return http.get<ChapterSummary[]>(`/books/${bookId}/chapters`)
  },
  manifest(bookId: string) {
    return http.get<Record<string, unknown>>(`/books/${bookId}/manifest`)
  },
  coverUrl(book: Book): string {
    return assetUrl(book.cover_url)
  },
}
