import { http } from './client'
import type { TaskInfo, TranslationRecord } from './types'

export interface TranslationDetail {
  sentence: {
    id: string
    original_text: string
    translation_state: string
    translation_error: string | null
    book_id: string
    chapter_id: string
    paragraph_id: string
  }
  book_title: string | null
  chapter_title: string | null
  translation: TranslationRecord | null
  versions: Array<{
    id: string
    text: string
    origin: string
    model_name: string | null
    prompt_version: number | null
    note: string | null
    created_at: string
  }>
  reviews: Array<{
    id: string
    candidate_text: string
    previous_text: string
    status: string
    model_name: string | null
    created_at: string
  }>
}

export const translationApi = {
  chapter(chapterId: string, options: { retranslate?: boolean; only_failed?: boolean; model_id?: string } = {}) {
    return http.post<TaskInfo>(`/translations/chapter/${chapterId}`, options)
  },
  paragraph(paragraphId: string, options: { retranslate?: boolean; model_id?: string } = {}) {
    return http.post<TaskInfo>(`/translations/paragraph/${paragraphId}`, options)
  },
  sentence(sentenceId: string, options: { retranslate?: boolean; model_id?: string } = {}) {
    return http.post<TaskInfo>(`/translations/sentence/${sentenceId}`, options)
  },
  retranslate(translationId: string) {
    return http.post<TaskInfo>(`/translations/retranslate/${translationId}`, {})
  },
  detail(sentenceId: string) {
    return http.get<TranslationDetail>(`/translations/sentence/${sentenceId}`)
  },
  detailById(translationId: string) {
    return http.get<{ translation: TranslationRecord; sentence: { id: string; original_text: string } | null }>(
      `/translations/${translationId}`,
    )
  },
  edit(translationId: string, text: string, note?: string) {
    return http.put<TranslationRecord>(`/translations/${translationId}`, { text, note })
  },
  createManual(sentenceId: string, text: string) {
    return http.post<TranslationRecord>(`/translations/sentence/${sentenceId}/manual`, { text })
  },
  versions(translationId: string) {
    return http.get<TranslationDetail['versions']>(`/translations/${translationId}/versions`)
  },
  reviews(status = 'pending') {
    return http.get<Array<Record<string, unknown>>>('/translations/reviews', { params: { status } })
  },
  resolveReview(reviewId: string, action: 'accept' | 'reject', text?: string) {
    return http.post<Record<string, unknown>>(`/translations/reviews/${reviewId}/resolve`, { action, text })
  },
  resolveByTranslation(translationId: string, action: 'accept' | 'reject', text?: string) {
    return http.post<Record<string, unknown>>(`/translations/${translationId}/review`, { action, text })
  },
}
