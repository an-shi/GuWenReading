import { http } from './client'
import type { AIModel, AIProvider, AssistantAnswer, PromptDetail, PromptSummary, TaskInfo } from './types'

export interface ProviderInput {
  name: string
  kind: 'openai_compatible' | 'openai' | 'ollama'
  base_url: string
  api_key?: string
  headers?: Record<string, string>
  enabled?: boolean
  notes?: string
}

export interface ModelInput {
  provider_id: string
  name: string
  display_name: string
  context_window?: number
  max_output_tokens?: number
  timeout_seconds?: number
  max_concurrency?: number
  supports_streaming?: boolean
  supports_json?: boolean
  capabilities?: string[]
  params?: Record<string, unknown>
  enabled?: boolean
  is_default_translation?: boolean
  is_default_chat?: boolean
}

export const aiApi = {
  providers() {
    return http.get<AIProvider[]>('/ai/providers')
  },
  createProvider(payload: ProviderInput) {
    return http.post<AIProvider>('/ai/providers', payload)
  },
  updateProvider(providerId: string, payload: Partial<ProviderInput> & { clear_api_key?: boolean }) {
    return http.put<AIProvider>(`/ai/providers/${providerId}`, payload)
  },
  deleteProvider(providerId: string) {
    return http.delete<{ removed: boolean }>(`/ai/providers/${providerId}`)
  },
  testProvider(providerId: string, modelName?: string) {
    return http.post<{
      ok: boolean
      latency_ms: number
      model: string
      reply: string
      provider_name: string
    }>(`/ai/providers/${providerId}/test`, { model_name: modelName || null })
  },
  models(providerId?: string, capability?: string) {
    return http.get<AIModel[]>('/ai/models', { params: { provider_id: providerId, capability } })
  },
  createModel(payload: ModelInput) {
    return http.post<AIModel>('/ai/models', payload)
  },
  updateModel(modelId: string, payload: Partial<ModelInput>) {
    return http.put<AIModel>(`/ai/models/${modelId}`, payload)
  },
  deleteModel(modelId: string) {
    return http.delete<{ removed: boolean }>(`/ai/models/${modelId}`)
  },
  prompts() {
    return http.get<PromptSummary[]>('/ai/prompts')
  },
  prompt(key: string) {
    return http.get<PromptDetail>(`/ai/prompts/${key}`)
  },
  createPromptVersion(key: string, payload: { name: string; template: string; variables: string[]; description?: string }) {
    return http.post<PromptSummary>(`/ai/prompts/${key}/versions`, payload)
  },
  activatePrompt(key: string, version: number) {
    return http.post<{ active_version: number }>(`/ai/prompts/${key}/activate/${version}`)
  },
  chat(payload: {
    question: string
    book_id?: string | null
    chapter_id?: string | null
    paragraph_id?: string | null
    sentence_id?: string | null
    session_id?: string | null
    model_id?: string | null
  }) {
    return http.post<AssistantAnswer>('/assistant/chat', payload)
  },
  sessions(bookId?: string) {
    return http.get<Array<{
      id: string
      title: string
      book_id: string | null
      chapter_id: string | null
      updated_at: string
    }>>('/assistant/sessions', { params: { book_id: bookId } })
  },
  session(sessionId: string) {
    return http.get<{
      session: { id: string; title: string; book_id: string | null; chapter_id: string | null; created_at: string }
      messages: Array<{
        id: string
        role: 'user' | 'assistant'
        content: string
        citations: AssistantAnswer['citations']
        model_name: string | null
        created_at: string
      }>
    }>(`/assistant/sessions/${sessionId}`)
  },
  extractKnowledge(chapterId: string, options: { extract_entities?: boolean; extract_relations?: boolean; extract_events?: boolean } = {}) {
    return http.post<TaskInfo>('/knowledge/extract', { chapter_id: chapterId, ...options })
  },
}
