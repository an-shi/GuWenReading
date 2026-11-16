import { http } from './client'
import type {
  EntityRelation, GraphData, HistoricalEntity, HistoricalEvent, Paginated, SearchResults,
  TimelineData,
} from './types'

export const knowledgeApi = {
  entities(params: {
    q?: string
    kind?: string
    dynasty?: string
    status?: string
    page?: number
    page_size?: number
  } = {}) {
    return http.get<Paginated<HistoricalEntity>>('/entities', { params })
  },
  entity(entityId: string) {
    return http.get<HistoricalEntity>(`/entities/${entityId}`)
  },
  searchEntities(q: string) {
    return http.get<HistoricalEntity[]>('/entities/search', { params: { q } })
  },
  updateEntity(entityId: string, payload: Partial<HistoricalEntity>) {
    return http.put<HistoricalEntity>(`/entities/${entityId}`, payload)
  },
  mergeEntities(entityId: string, sourceEntityIds: string[]) {
    return http.post<HistoricalEntity>(`/entities/${entityId}/merge`, { source_entity_ids: sourceEntityIds })
  },
  relations(params: { entity_id?: string; relation_type?: string; include_pending?: boolean } = {}) {
    return http.get<EntityRelation[]>('/relations', { params })
  },
  reviewRelation(relationId: string, status: string) {
    return http.put<{ id: string; status: string }>(`/relations/${relationId}/review`, undefined, { params: { status } })
  },
  graph(params: {
    center_id?: string
    depth?: number
    dynasty?: string
    relation_type?: string
    book_id?: string
    include_pending?: boolean
  } = {}) {
    return http.get<GraphData>('/graph', { params })
  },
  events(params: {
    q?: string
    event_type?: string
    dynasty?: string
    status?: string
    page?: number
    page_size?: number
  } = {}) {
    return http.get<Paginated<HistoricalEvent>>('/events', { params })
  },
  event(eventId: string) {
    return http.get<HistoricalEvent>(`/events/${eventId}`)
  },
  reviewEvent(eventId: string, status: string) {
    return http.put<{ id: string; status: string }>(`/events/${eventId}/review`, undefined, { params: { status } })
  },
  timeline(params: {
    year_from?: number
    year_to?: number
    event_type?: string
    dynasty?: string
    include_extracted?: boolean
  } = {}) {
    return http.get<TimelineData>('/timeline', { params })
  },
  search(q: string, scope: 'all' | 'original' | 'translation' = 'all', bookId?: string) {
    return http.get<SearchResults>('/search', { params: { q, scope, book_id: bookId } })
  },
}
