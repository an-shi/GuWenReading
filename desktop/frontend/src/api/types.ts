export interface Paginated<T> {
  items: T[]
  total: number
  page: number
  page_size: number
}

export interface Book {
  id: string
  title: string
  author: string | null
  dynasty: string | null
  category: string | null
  description: string | null
  tags: string[]
  source_format: string
  source_filename: string
  file_size: number
  status: string
  cover_url: string | null
  chapter_count: number
  paragraph_count: number
  sentence_count: number
  translated_sentence_count: number
  translation_percent: number
  last_read_at: string | null
  created_at: string
  updated_at: string
  metadata: Record<string, unknown>
  version: number
}

export interface ChapterSummary {
  id: string
  book_id: string
  ordinal: number
  title: string
  paragraph_count: number
  sentence_count: number
  translated_count: number
  translation_percent: number
}

export interface TranslationRecord {
  id: string
  sentence_id: string
  paragraph_id: string
  chapter_id: string
  book_id: string
  text: string
  origin: 'ai' | 'manual'
  status: string
  model_name: string | null
  provider_name?: string | null
  prompt_version: number | null
  edited_at: string | null
  version: number
}

export interface PendingReview {
  id: string
  candidate_text: string
}

export interface Sentence {
  id: string
  ordinal: number
  original_text: string
  start_offset: number
  end_offset: number
  needs_review: boolean
  split_confidence: number
  translation_state: 'pending' | 'queued' | 'translating' | 'completed' | 'failed'
  translation_error: string | null
  translation: TranslationRecord | null
  pending_review: PendingReview | null
}

export interface Paragraph {
  id: string
  ordinal: number
  original_text: string
  start_offset: number
  end_offset: number
  sentence_count: number
  sentences: Sentence[]
  translation_text: string | null
  translation_complete: boolean
}

export interface TranslationStatus {
  chapter_id: string
  total: number
  translated: number
  manual: number
  pending_reviews: number
  states: Record<string, number>
  percent: number
  updated_at: string | null
}

export interface ChapterContent {
  book: { id: string; title: string; author: string | null; source_format: string; category: string | null }
  chapter: {
    id: string
    book_id: string
    ordinal: number
    title: string
    start_offset: number
    end_offset: number
    paragraph_count: number
    sentence_count: number
    translated_count: number
  }
  previous_chapter_id: string | null
  next_chapter_id: string | null
  translation_status: TranslationStatus
  paragraphs: Paragraph[]
}

export interface TaskInfo {
  id: string
  type: string
  status: 'queued' | 'running' | 'completed' | 'partial' | 'failed' | 'cancelled'
  title: string
  progress: number
  total: number
  completed: number
  failed_count: number
  payload: Record<string, unknown>
  result: Record<string, unknown>
  error: string | null
  cancel_requested: boolean
  book_id: string | null
  chapter_id: string | null
  created_at: string
  started_at: string | null
  finished_at: string | null
  updated_at: string
}

export interface AIProvider {
  id: string
  name: string
  kind: 'openai_compatible' | 'openai' | 'ollama'
  base_url: string
  api_key_hint: string | null
  has_api_key: boolean
  headers: Record<string, string>
  enabled: boolean
  notes: string | null
  created_at: string
  updated_at: string
}

export interface AIModel {
  id: string
  provider_id: string
  name: string
  display_name: string
  context_window: number
  max_output_tokens: number
  timeout_seconds: number
  max_concurrency: number
  supports_streaming: boolean
  supports_json: boolean
  capabilities: string[]
  params: Record<string, unknown>
  enabled: boolean
  is_default_translation: boolean
  is_default_chat: boolean
}

export interface PromptSummary {
  id: string
  key: string
  version: number
  name: string
  description: string | null
  variables: string[]
  is_active: boolean
  created_at: string
}

export interface PromptDetail {
  key: string
  active: { version: number; name: string; template: string }
  versions: PromptSummary[]
}

export interface HistoricalEntity {
  id: string
  canonical_name: string
  kind: string
  dynasty: string | null
  courtesy_name: string | null
  art_name: string | null
  posthumous_name: string | null
  temple_name: string | null
  aliases: string[]
  birth_raw: string | null
  death_raw: string | null
  birth_year: number | null
  death_year: number | null
  identity: string | null
  offices: string[]
  summary: string | null
  status: string
  confidence: number | null
  mentions?: EntityMention[]
  relations?: EntityRelation[]
  mention_count?: number
}

export interface EntityMention {
  id: string
  sentence_id: string
  surface_text: string
  quote: string
  book_id: string
  book_title: string
  chapter_id: string
  chapter_title: string
  source: string
  status: string
  confidence: number | null
}

export interface EntityRelation {
  id: string
  source_entity_id: string
  target_entity_id: string
  other_entity_id?: string
  other_entity_name?: string | null
  source_name?: string | null
  target_name?: string | null
  relation_type: string
  label: string | null
  description: string | null
  status: 'explicit' | 'inferred' | 'confirmed' | 'rejected'
  confidence: number | null
  direction?: 'incoming' | 'outgoing'
  source_count?: number
  sources?: Array<{
    id: string
    book_id?: string | null
    book_title?: string | null
    chapter_id?: string | null
    chapter_title?: string | null
    sentence_id?: string | null
    quote?: string | null
  }>
}

export interface GraphEdge {
  id: string
  source: string
  target: string
  label: string
  relation_type: string
  status: 'explicit' | 'inferred' | 'confirmed' | 'rejected'
  confidence: number | null
  description: string | null
  sources?: Array<{
    id: string
    book_id?: string | null
    book_title?: string | null
    chapter_id?: string | null
    chapter_title?: string | null
    sentence_id?: string | null
    quote?: string | null
  }>
}

export interface GraphData {
  nodes: Array<{
    id: string
    label: string
    kind: string
    dynasty: string | null
    status: string
    degree: number
  }>
  edges: GraphEdge[]
  truncated: boolean
  center_id: string | null
}

export interface HistoricalEvent {
  id: string
  name: string
  event_type: string
  description: string | null
  dynasty: string | null
  time_raw: string | null
  era_name: string | null
  reign_year: string | null
  ganzhi: string | null
  time_start_year: number | null
  time_end_year: number | null
  time_precision: string
  time_note: string | null
  confidence: number | null
  status: string
  tags: string[]
  participants?: Array<{ entity_id: string; name: string; role: string | null }>
  sources?: Array<{
    id: string
    book_id: string | null
    book_title: string | null
    chapter_id: string | null
    chapter_title: string | null
    sentence_id: string | null
    quote: string | null
  }>
  source_count?: number
  created_at: string
}

export interface TimelineData {
  events: HistoricalEvent[]
  undated: HistoricalEvent[]
  total: number
}

export interface SearchResults {
  query: string
  sentences: Array<{
    sentence_id: string
    book_id: string
    book_title: string
    chapter_id: string
    chapter_title: string | null
    doc_type: string
    original_text: string
    translation_text: string | null
    snippet: string
    score: number
  }>
  entities: Array<{
    id: string
    canonical_name: string
    kind: string
    dynasty: string | null
    identity: string | null
    summary: string | null
    status: string
  }>
  events: Array<{
    id: string
    name: string
    event_type: string
    time_raw: string | null
    time_start_year: number | null
    time_precision: string
    status: string
  }>
  total: number
}

export interface Annotation {
  id: string
  book_id: string
  chapter_id: string | null
  paragraph_id: string | null
  sentence_id: string | null
  quote: string | null
  content: string
  color: string
  tags: string[]
  device_id: string | null
  created_at: string
  updated_at: string
  version: number
}

export interface Bookmark {
  id: string
  book_id: string
  chapter_id: string
  paragraph_id: string | null
  sentence_id: string | null
  label: string | null
  position_ratio: number
  device_id: string | null
  created_at: string
}

export interface ReadingProgress {
  id: string
  book_id: string
  device_id: string
  chapter_id: string | null
  paragraph_id: string | null
  sentence_id: string | null
  position_ratio: number
  updated_at: string
}

export interface AssistantAnswer {
  session_id: string
  message_id: string
  answer: string
  citations: Array<{
    book: string
    chapter: string
    sentence_id: string | null
    quote: string
    note: string
    verified: boolean
  }>
  claims: Array<{ text: string; kind: 'explicit' | 'inference' | 'analysis' | 'unverified' }>
  local_sources: Array<Record<string, unknown>>
  model: string
  prompt_version: number
  created_at: string
}

export interface AssistantMessage {
  id: string
  role: 'user' | 'assistant'
  content: string
  citations: AssistantAnswer['citations']
  model_name: string | null
  created_at: string
}

export interface SystemInfo {
  name: string
  version: string
  mode: 'embedded' | 'server'
  auth_required: boolean
  supported_formats: string[]
  capabilities: Record<string, boolean>
  counts: { books: number; providers: number; models: number }
  data_dir: string | null
}
