/// Local SQLite schema for the standalone desktop/mobile application.
///
/// Every client owns its database. There is no server-side database, session
/// or network dependency. FTS5 is created opportunistically; search falls back
/// to LIKE when the platform SQLite build does not include FTS5.
const List<String> schemaStatements = [
  '''
  CREATE TABLE IF NOT EXISTS books (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    author TEXT,
    dynasty TEXT,
    category TEXT,
    description TEXT,
    tags TEXT NOT NULL DEFAULT '[]',
    source_format TEXT NOT NULL,
    source_filename TEXT,
    source_hash TEXT,
    original_path TEXT,
    cover_path TEXT,
    file_size INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'ready',
    chapter_count INTEGER NOT NULL DEFAULT 0,
    paragraph_count INTEGER NOT NULL DEFAULT 0,
    sentence_count INTEGER NOT NULL DEFAULT 0,
    translated_sentence_count INTEGER NOT NULL DEFAULT 0,
    last_read_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
  )
  ''',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_books_hash ON books(source_hash) WHERE source_hash IS NOT NULL',
  'CREATE INDEX IF NOT EXISTS idx_books_updated ON books(updated_at DESC)',
  '''
  CREATE TABLE IF NOT EXISTS chapters (
    id TEXT PRIMARY KEY,
    book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    ordinal INTEGER NOT NULL,
    title TEXT NOT NULL,
    paragraph_count INTEGER NOT NULL DEFAULT 0,
    sentence_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_chapters_book ON chapters(book_id, ordinal)',
  '''
  CREATE TABLE IF NOT EXISTS paragraphs (
    id TEXT PRIMARY KEY,
    book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    chapter_id TEXT NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
    ordinal INTEGER NOT NULL,
    original_text TEXT NOT NULL,
    start_offset INTEGER NOT NULL DEFAULT 0,
    end_offset INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_paragraphs_chapter ON paragraphs(chapter_id, ordinal)',
  '''
  CREATE TABLE IF NOT EXISTS sentences (
    id TEXT PRIMARY KEY,
    book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    chapter_id TEXT NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
    paragraph_id TEXT NOT NULL REFERENCES paragraphs(id) ON DELETE CASCADE,
    ordinal INTEGER NOT NULL,
    original_text TEXT NOT NULL,
    start_offset INTEGER NOT NULL DEFAULT 0,
    end_offset INTEGER NOT NULL DEFAULT 0,
    translation_state TEXT NOT NULL DEFAULT 'pending',
    translation_error TEXT,
    needs_review INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_sentences_paragraph ON sentences(paragraph_id, ordinal)',
  'CREATE INDEX IF NOT EXISTS idx_sentences_chapter ON sentences(chapter_id)',
  'CREATE INDEX IF NOT EXISTS idx_sentences_state ON sentences(chapter_id, translation_state)',
  '''
  CREATE TABLE IF NOT EXISTS translations (
    id TEXT PRIMARY KEY,
    sentence_id TEXT NOT NULL UNIQUE REFERENCES sentences(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    origin TEXT NOT NULL DEFAULT 'ai',
    status TEXT NOT NULL DEFAULT 'completed',
    model_name TEXT,
    prompt_version INTEGER,
    version INTEGER NOT NULL DEFAULT 1,
    edited_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS translation_versions (
    id TEXT PRIMARY KEY,
    sentence_id TEXT NOT NULL REFERENCES sentences(id) ON DELETE CASCADE,
    translation_id TEXT,
    text TEXT NOT NULL,
    origin TEXT NOT NULL,
    model_name TEXT,
    prompt_version INTEGER,
    created_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_translation_versions_sentence ON translation_versions(sentence_id, created_at DESC)',
  '''
  CREATE TABLE IF NOT EXISTS translation_reviews (
    id TEXT PRIMARY KEY,
    sentence_id TEXT NOT NULL REFERENCES sentences(id) ON DELETE CASCADE,
    previous_text TEXT NOT NULL,
    candidate_text TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TEXT NOT NULL,
    resolved_at TEXT
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_reviews_status ON translation_reviews(status, created_at DESC)',
  '''
  CREATE TABLE IF NOT EXISTS translation_cache (
    cache_key TEXT PRIMARY KEY,
    text TEXT NOT NULL,
    created_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS annotations (
    id TEXT PRIMARY KEY,
    book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    chapter_id TEXT,
    paragraph_id TEXT,
    sentence_id TEXT,
    quote TEXT,
    content TEXT NOT NULL,
    color TEXT,
    tags TEXT NOT NULL DEFAULT '[]',
    created_at TEXT,
    updated_at TEXT
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_annotations_book ON annotations(book_id, chapter_id)',
  '''
  CREATE TABLE IF NOT EXISTS bookmarks (
    id TEXT PRIMARY KEY,
    book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    chapter_id TEXT NOT NULL,
    paragraph_id TEXT,
    sentence_id TEXT,
    label TEXT,
    position_ratio REAL NOT NULL DEFAULT 0,
    created_at TEXT,
    updated_at TEXT
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_bookmarks_book ON bookmarks(book_id, chapter_id)',
  '''
  CREATE TABLE IF NOT EXISTS reading_progress (
    book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
    chapter_id TEXT,
    paragraph_id TEXT,
    paragraph_index INTEGER NOT NULL DEFAULT 0,
    sentence_id TEXT,
    position_ratio REAL NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS entities (
    id TEXT PRIMARY KEY,
    canonical_name TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'person',
    aliases TEXT NOT NULL DEFAULT '[]',
    dynasty TEXT,
    identity TEXT,
    summary TEXT,
    description TEXT,
    birth_raw TEXT,
    death_raw TEXT,
    birth_year INTEGER,
    death_year INTEGER,
    courtesy_name TEXT,
    art_name TEXT,
    offices TEXT NOT NULL DEFAULT '[]',
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_entities_name ON entities(canonical_name)',
  'CREATE INDEX IF NOT EXISTS idx_entities_kind ON entities(kind, status)',
  '''
  CREATE TABLE IF NOT EXISTS entity_mentions (
    id TEXT PRIMARY KEY,
    entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    book_id TEXT,
    chapter_id TEXT,
    sentence_id TEXT,
    quote TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_mentions_entity ON entity_mentions(entity_id)',
  '''
  CREATE TABLE IF NOT EXISTS entity_relations (
    id TEXT PRIMARY KEY,
    from_entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    to_entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    relation_type TEXT NOT NULL,
    label TEXT,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'inferred',
    confidence REAL NOT NULL DEFAULT 0.5,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_relations_from ON entity_relations(from_entity_id)',
  'CREATE INDEX IF NOT EXISTS idx_relations_to ON entity_relations(to_entity_id)',
  '''
  CREATE TABLE IF NOT EXISTS relation_sources (
    id TEXT PRIMARY KEY,
    relation_id TEXT NOT NULL REFERENCES entity_relations(id) ON DELETE CASCADE,
    sentence_id TEXT,
    book_id TEXT,
    chapter_id TEXT,
    quote TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS historical_events (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    event_type TEXT NOT NULL DEFAULT '其他',
    description TEXT,
    dynasty TEXT,
    time_raw TEXT,
    time_start_year INTEGER,
    time_end_year INTEGER,
    time_precision TEXT NOT NULL DEFAULT 'unknown',
    time_note TEXT,
    status TEXT NOT NULL DEFAULT 'extracted',
    fingerprint TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_events_year ON historical_events(time_start_year)',
  'CREATE INDEX IF NOT EXISTS idx_events_type ON historical_events(event_type, status)',
  '''
  CREATE TABLE IF NOT EXISTS event_participants (
    id TEXT PRIMARY KEY,
    event_id TEXT NOT NULL REFERENCES historical_events(id) ON DELETE CASCADE,
    entity_id TEXT,
    name TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS event_sources (
    id TEXT PRIMARY KEY,
    event_id TEXT NOT NULL REFERENCES historical_events(id) ON DELETE CASCADE,
    sentence_id TEXT,
    book_id TEXT,
    chapter_id TEXT,
    quote TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'queued',
    title TEXT NOT NULL,
    book_id TEXT,
    chapter_id TEXT,
    progress REAL NOT NULL DEFAULT 0,
    total INTEGER NOT NULL DEFAULT 0,
    completed INTEGER NOT NULL DEFAULT 0,
    failed_count INTEGER NOT NULL DEFAULT 0,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    cache_read_tokens INTEGER NOT NULL DEFAULT 0,
    cache_write_tokens INTEGER NOT NULL DEFAULT 0,
    cost REAL NOT NULL DEFAULT 0,
    requests INTEGER NOT NULL DEFAULT 0,
    estimated_usage INTEGER NOT NULL DEFAULT 0,
    error TEXT,
    result TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_tasks_created ON tasks(created_at DESC)',
  '''
  CREATE TABLE IF NOT EXISTS ai_providers (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'openai_compatible',
    base_url TEXT NOT NULL,
    notes TEXT,
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS ai_models (
    id TEXT PRIMARY KEY,
    provider_id TEXT NOT NULL REFERENCES ai_providers(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    display_name TEXT NOT NULL,
    context_window INTEGER NOT NULL DEFAULT 8192,
    max_output_tokens INTEGER NOT NULL DEFAULT 2048,
    timeout_seconds INTEGER NOT NULL DEFAULT 120,
    capabilities TEXT NOT NULL DEFAULT '["translation","chat"]',
    supports_json INTEGER NOT NULL DEFAULT 1,
    is_default_translation INTEGER NOT NULL DEFAULT 0,
    is_default_chat INTEGER NOT NULL DEFAULT 0,
    is_default_extraction INTEGER NOT NULL DEFAULT 0,
    input_price REAL NOT NULL DEFAULT 0,
    output_price REAL NOT NULL DEFAULT 0,
    cache_read_price REAL NOT NULL DEFAULT 0,
    cache_write_price REAL NOT NULL DEFAULT 0,
    tokenizer TEXT,
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS prompt_templates (
    id TEXT PRIMARY KEY,
    key TEXT NOT NULL,
    version INTEGER NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    template TEXT NOT NULL,
    variables TEXT NOT NULL DEFAULT '[]',
    is_active INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    UNIQUE(key, version)
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_prompts_key ON prompt_templates(key, version DESC)',
  '''
  CREATE TABLE IF NOT EXISTS assistant_sessions (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    book_id TEXT,
    chapter_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS assistant_messages (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES assistant_sessions(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    citations TEXT NOT NULL DEFAULT '[]',
    claims TEXT NOT NULL DEFAULT '[]',
    created_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_messages_session ON assistant_messages(session_id, created_at)',
  '''
  CREATE TABLE IF NOT EXISTS app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS ai_usage (
    id TEXT PRIMARY KEY,
    task_id TEXT,
    task_type TEXT NOT NULL,
    provider_id TEXT,
    provider_name TEXT,
    model_id TEXT,
    model_name TEXT,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    cache_read_tokens INTEGER NOT NULL DEFAULT 0,
    cache_write_tokens INTEGER NOT NULL DEFAULT 0,
    total_tokens INTEGER NOT NULL DEFAULT 0,
    cost REAL NOT NULL DEFAULT 0,
    duration_ms INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'success',
    retry_count INTEGER NOT NULL DEFAULT 0,
    is_estimated INTEGER NOT NULL DEFAULT 0,
    token_source TEXT NOT NULL DEFAULT 'provider_actual',
    error TEXT,
    created_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_ai_usage_created ON ai_usage(created_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_ai_usage_task ON ai_usage(task_id)',
  'CREATE INDEX IF NOT EXISTS idx_ai_usage_type ON ai_usage(task_type, created_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_ai_usage_model ON ai_usage(model_id, created_at DESC)',
  '''
  CREATE TABLE IF NOT EXISTS translation_sentence_cache (
    cache_key TEXT PRIMARY KEY,
    source_hash TEXT NOT NULL,
    context_hash TEXT NOT NULL,
    model_label TEXT NOT NULL,
    prompt_version INTEGER NOT NULL,
    translated_text TEXT NOT NULL,
    created_at TEXT NOT NULL,
    last_used_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_translation_sentence_model ON translation_sentence_cache(model_label, prompt_version)',
  '''
  CREATE TABLE IF NOT EXISTS knowledge_chunk_cache (
    chapter_id TEXT NOT NULL,
    chunk_index INTEGER NOT NULL,
    content_hash TEXT NOT NULL,
    model_label TEXT NOT NULL,
    prompt_version INTEGER NOT NULL,
    schema_version INTEGER NOT NULL,
    result_json TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'completed',
    updated_at TEXT NOT NULL,
    PRIMARY KEY (chapter_id, chunk_index, content_hash, model_label, prompt_version, schema_version)
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS knowledge_extraction_state (
    chapter_id TEXT PRIMARY KEY,
    content_hash TEXT NOT NULL,
    model_label TEXT NOT NULL,
    prompt_version INTEGER NOT NULL,
    schema_version INTEGER NOT NULL,
    status TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
];
