import { http } from './client'
import type {
  Annotation, Bookmark, ChapterContent, ReadingProgress, TranslationStatus,
} from './types'

export const readerApi = {
  content(chapterId: string) {
    return http.get<ChapterContent>(`/chapters/${chapterId}/content`)
  },
  status(chapterId: string) {
    return http.get<TranslationStatus>(`/chapters/${chapterId}/translation-status`)
  },
  chapter(chapterId: string) {
    return http.get<Record<string, unknown>>(`/chapters/${chapterId}`)
  },
  getProgress(bookId: string, deviceId: string) {
    return http.get<{ progress: ReadingProgress | null }>(`/reading-progress/${bookId}`, {
      params: { device_id: deviceId },
    })
  },
  saveProgress(payload: {
    book_id: string
    device_id: string
    chapter_id?: string | null
    paragraph_id?: string | null
    sentence_id?: string | null
    position_ratio: number
  }) {
    return http.put<ReadingProgress>('/reading-progress', payload)
  },
  annotations(bookId?: string, chapterId?: string) {
    return http.get<{ items: Annotation[]; total: number }>('/annotations', {
      params: { book_id: bookId, chapter_id: chapterId, page_size: 500 },
    })
  },
  createAnnotation(payload: {
    book_id: string
    chapter_id?: string | null
    paragraph_id?: string | null
    sentence_id?: string | null
    quote?: string | null
    content: string
    color?: string
    tags?: string[]
    device_id?: string
  }) {
    return http.post<Annotation>('/annotations', payload)
  },
  updateAnnotation(annotationId: string, payload: { content?: string; color?: string; tags?: string[] }) {
    return http.put<Annotation>(`/annotations/${annotationId}`, payload)
  },
  deleteAnnotation(annotationId: string) {
    return http.delete<{ removed: boolean }>(`/annotations/${annotationId}`)
  },
  bookmarks(bookId?: string) {
    return http.get<Bookmark[]>('/bookmarks', { params: { book_id: bookId } })
  },
  createBookmark(payload: {
    book_id: string
    chapter_id: string
    paragraph_id?: string | null
    sentence_id?: string | null
    label?: string | null
    position_ratio?: number
    device_id?: string
  }) {
    return http.post<Bookmark>('/bookmarks', payload)
  },
  deleteBookmark(bookmarkId: string) {
    return http.delete<{ removed: boolean }>(`/bookmarks/${bookmarkId}`)
  },
}
