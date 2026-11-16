<template>
  <v-navigation-drawer
    :model-value="modelValue"
    location="right"
    temporary
    width="450"
    class="sentence-drawer"
    @update:model-value="$emit('update:modelValue', $event)"
  >
    <div v-if="sentence" class="panel-shell">
      <div class="panel-head">
        <div>
          <div class="section-label">句子</div>
          <div class="panel-title serif">句子详情</div>
        </div>
        <v-spacer />
        <v-btn icon="mdi-close" variant="text" size="small" @click="$emit('update:modelValue', false)" />
      </div>

      <div class="panel-body">
        <div class="original-box serif">{{ sentence.original_text }}</div>
        <div class="status-row">
          <v-chip size="x-small" :color="stateColor" variant="tonal">{{ stateLabel }}</v-chip>
          <span v-if="sentence.needs_review" class="tiny muted">断句待复核</span>
          <v-spacer />
          <v-btn icon="mdi-content-copy" size="x-small" variant="text" title="复制原文" @click="copy(sentence.original_text)" />
        </div>

        <v-alert
          v-if="sentence.translation_error"
          type="error"
          variant="tonal"
          density="compact"
          class="mt-3"
          :text="sentence.translation_error"
        />

        <v-progress-linear v-if="working" indeterminate color="primary" rounded class="mt-4" />

        <div class="section-block">
          <div class="section-block-head">
            <span class="section-label">译文</span>
            <span v-if="detail?.translation" class="tiny muted">
              {{ detail.translation.origin === 'manual' ? '人工修订' : detail.translation.model_name || 'AI 译文' }}
              <template v-if="detail.translation.prompt_version"> · 提示词 v{{ detail.translation.prompt_version }}</template>
            </span>
          </div>

          <div v-if="!editing && detail?.translation" class="translation-text">
            {{ detail.translation.text }}
          </div>

          <div v-if="!editing && !detail?.translation" class="no-translation">
            尚未翻译。已经在阅读器中保留原文位置，可创建人工译文或让 AI 翻译。
          </div>

          <v-textarea
            v-if="editing || !detail?.translation"
            v-model="draft"
            label="译文"
            rows="4"
            auto-grow
            class="mt-2"
            :disabled="working"
          />

          <div class="action-row">
            <template v-if="!editing && detail?.translation">
              <v-btn size="small" variant="tonal" prepend-icon="mdi-pencil" @click="startEdit">修改译文</v-btn>
              <v-btn size="small" variant="text" prepend-icon="mdi-translate" :disabled="working" @click="retranslate">
                重新翻译
              </v-btn>
            </template>
            <template v-else>
              <v-btn size="small" color="primary" :loading="working" @click="saveTranslation">
                {{ detail?.translation ? '保存人工修订' : '保存人工译文' }}
              </v-btn>
              <v-btn v-if="detail?.translation" size="small" variant="text" @click="cancelEdit">取消</v-btn>
            </template>
            <v-spacer />
            <v-btn
              icon="mdi-sparkles"
              size="small"
              variant="text"
              title="AI 解释"
              :disabled="!ai.configured"
              @click="explain"
            />
          </div>
        </div>

        <div v-if="detail?.reviews?.filter((review) => review.status === 'pending').length" class="section-block review-block">
          <div class="section-label">待审核候选</div>
          <div class="review-title">AI 重新翻译产生了候选译文</div>
          <div class="review-original">{{ detail.reviews.find((review) => review.status === 'pending')?.previous_text }}</div>
          <div class="review-candidate">{{ detail.reviews.find((review) => review.status === 'pending')?.candidate_text }}</div>
          <div class="action-row">
            <v-btn size="small" color="success" variant="tonal" :loading="working" @click="resolveReview('accept')">采用候选</v-btn>
            <v-btn size="small" variant="text" :loading="working" @click="resolveReview('reject')">保留现译文</v-btn>
          </div>
        </div>

        <div v-if="explanation" class="section-block explain-block">
          <div class="section-block-head">
            <span class="section-label">AI 解释</span>
            <v-btn icon="mdi-close" size="x-small" variant="text" @click="explanation = ''" />
          </div>
          <div class="assistant-prose">{{ explanation }}</div>
          <div v-if="explanationCitations.length" class="explanation-citations">
            <div v-for="(citation, index) in explanationCitations" :key="index" class="citation-card">
              <div class="citation-head serif">{{ citation.book }} · {{ citation.chapter }}</div>
              <div class="citation-quote serif">{{ citation.quote }}</div>
            </div>
          </div>
        </div>

        <div class="section-block">
          <div class="section-block-head">
            <span class="section-label">批注</span>
            <v-btn size="x-small" variant="text" prepend-icon="mdi-plus" @click="annotationOpen = !annotationOpen">
              添加批注
            </v-btn>
          </div>
          <div v-if="annotationOpen" class="annotation-form">
            <v-textarea v-model="annotationDraft" placeholder="记录你的理解、疑问或考据…" rows="3" auto-grow hide-details />
            <div class="action-row">
              <v-spacer />
              <v-btn size="small" color="primary" :disabled="!annotationDraft.trim()" :loading="working" @click="createAnnotation">保存批注</v-btn>
            </div>
          </div>
          <div v-if="!annotations.length" class="tiny muted annotation-empty">本句暂无批注。</div>
          <div v-for="annotation in annotations" :key="annotation.id" class="annotation-row">
            <div class="annotation-content">{{ annotation.content }}</div>
            <div class="annotation-meta">
              <span>{{ formatTime(annotation.created_at) }}</span>
              <v-btn icon="mdi-delete-outline" size="x-small" variant="text" @click="deleteAnnotation(annotation.id)" />
            </div>
          </div>
        </div>

        <div v-if="detail?.versions?.length" class="section-block">
          <div class="section-block-head">
            <span class="section-label">版本历史</span>
            <v-btn size="x-small" variant="text" @click="showVersions = !showVersions">
              {{ showVersions ? '收起' : `${detail.versions.length} 个历史版本` }}
            </v-btn>
          </div>
          <div v-if="showVersions" class="version-list">
            <div v-for="version in detail.versions" :key="version.id" class="version-row">
              <div class="version-meta">
                <v-chip size="x-small" variant="tonal" :color="version.origin === 'manual' ? 'secondary' : 'primary'">
                  {{ version.origin === 'manual' ? '人工' : 'AI' }}
                </v-chip>
                <span>{{ version.model_name || '' }}</span>
                <span>{{ formatTime(version.created_at) }}</span>
              </div>
              <div class="version-text">{{ version.text }}</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </v-navigation-drawer>
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { aiApi } from '@/api/ai'
import { readerApi } from '@/api/reader'
import { tasksApi } from '@/api/system'
import { translationApi, type TranslationDetail } from '@/api/translation'
import type { Annotation, AssistantAnswer, Paragraph, Sentence } from '@/api/types'
import { useAiStore } from '@/stores/ai'
import { useAppStore } from '@/stores/app'

const props = defineProps<{
  modelValue: boolean
  bookId: string
  chapterId: string
  sentence: Sentence | null
  paragraph: Paragraph | null
  deviceId: string
}>()
const emit = defineEmits<{
  'update:modelValue': [value: boolean]
  updated: []
  assistant: []
}>()

const ai = useAiStore()
const app = useAppStore()
const detail = ref<TranslationDetail | null>(null)
const annotations = ref<Annotation[]>([])
const working = ref(false)
const editing = ref(false)
const draft = ref('')
const annotationOpen = ref(false)
const annotationDraft = ref('')
const explanation = ref('')
const explanationCitations = ref<AssistantAnswer['citations']>([])
const showVersions = ref(false)

const stateLabels: Record<string, string> = {
  pending: '未翻译',
  queued: '排队中',
  translating: '翻译中',
  completed: '已翻译',
  failed: '翻译失败',
}
const stateLabel = computed(() => stateLabels[props.sentence?.translation_state || 'pending'] || '未知')
const stateColor = computed(() => {
  const state = props.sentence?.translation_state
  return ({
    pending: 'default', queued: 'info', translating: 'info', completed: 'success', failed: 'error',
  } as Record<string, string>)[state || 'pending'] || 'default'
})

watch(
  () => [props.modelValue, props.sentence?.id, props.sentence?.translation?.version],
  () => {
    if (props.modelValue && props.sentence) load()
  },
  { immediate: true },
)

async function load() {
  if (!props.sentence) return
  try {
    detail.value = await translationApi.detail(props.sentence.id)
    draft.value = detail.value.translation?.text || ''
    editing.value = false
    showVersions.value = false
    await loadAnnotations()
  } catch {
    detail.value = null
  }
}

async function loadAnnotations() {
  if (!props.sentence) return
  try {
    const data = await readerApi.annotations(props.bookId, props.chapterId)
    annotations.value = data.items.filter((item) => item.sentence_id === props.sentence?.id)
  } catch {
    annotations.value = []
  }
}

function startEdit() {
  draft.value = detail.value?.translation?.text || ''
  editing.value = true
}

function cancelEdit() {
  editing.value = false
  draft.value = detail.value?.translation?.text || ''
}

async function saveTranslation() {
  if (!props.sentence || !draft.value.trim()) return
  working.value = true
  try {
    if (detail.value?.translation) {
      detail.value.translation = await translationApi.edit(
        detail.value.translation.id, draft.value.trim(), '人工修订',
      )
    } else {
      await translationApi.createManual(props.sentence.id, draft.value.trim())
    }
    editing.value = false
    app.notify('译文已保存为人工修订')
    await load()
    emit('updated')
  } finally {
    working.value = false
  }
}

async function retranslate() {
  if (!detail.value?.translation || !props.sentence) return
  working.value = true
  try {
    const task = await translationApi.retranslate(detail.value.translation.id)
    await waitForTask(task.id)
    await load()
    emit('updated')
  } finally {
    working.value = false
  }
}

async function waitForTask(taskId: string) {
  for (let index = 0; index < 80; index += 1) {
    await new Promise((resolve) => setTimeout(resolve, 1500))
    const task = await tasksApi.get(taskId)
    if (['completed', 'partial', 'failed', 'cancelled'].includes(task.status)) {
      if (task.status === 'failed') app.notify(task.error || 'AI 翻译失败', 'error')
      else if (task.status === 'partial') app.notify('翻译完成，部分句子失败', 'warning')
      return task
    }
  }
  return null
}

async function resolveReview(action: 'accept' | 'reject') {
  const review = detail.value?.reviews.find((item) => item.status === 'pending')
  if (!review) return
  working.value = true
  try {
    await translationApi.resolveReview(review.id, action)
    app.notify(action === 'accept' ? '已采用候选译文' : '已保留当前译文')
    await load()
    emit('updated')
  } finally {
    working.value = false
  }
}

async function explain() {
  if (!props.sentence) return
  if (!ai.configured) {
    app.notify('请先配置 AI 问答模型', 'warning')
    return
  }
  working.value = true
  explanation.value = ''
  explanationCitations.value = []
  try {
    const answer = await aiApi.chat({
      question: '请解释这句话的难词、句式、典故与整体含义。',
      book_id: props.bookId,
      chapter_id: props.chapterId,
      paragraph_id: props.paragraph?.id || null,
      sentence_id: props.sentence.id,
    })
    explanation.value = answer.answer
    explanationCitations.value = answer.citations
  } catch (error) {
    explanation.value = `解释失败：${error instanceof Error ? error.message : '未知错误'}`
  } finally {
    working.value = false
  }
}

async function createAnnotation() {
  if (!props.sentence || !annotationDraft.value.trim()) return
  working.value = true
  try {
    await readerApi.createAnnotation({
      book_id: props.bookId,
      chapter_id: props.chapterId,
      paragraph_id: props.paragraph?.id || null,
      sentence_id: props.sentence.id,
      quote: props.sentence.original_text,
      content: annotationDraft.value.trim(),
      device_id: props.deviceId,
    })
    annotationDraft.value = ''
    annotationOpen.value = false
    app.notify('批注已保存')
    await loadAnnotations()
  } finally {
    working.value = false
  }
}

async function deleteAnnotation(annotationId: string) {
  await readerApi.deleteAnnotation(annotationId)
  await loadAnnotations()
}

async function copy(text: string) {
  await navigator.clipboard.writeText(text)
  app.notify('已复制原文')
}

function formatTime(value: string): string {
  return new Date(value).toLocaleString('zh-CN', {
    month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
  })
}
</script>

<style scoped>
.sentence-drawer {
  background: rgb(var(--v-theme-surface)) !important;
}
.panel-shell {
  height: 100%;
  display: flex;
  flex-direction: column;
}
.panel-head {
  display: flex;
  align-items: flex-start;
  padding: 20px 20px 14px;
  border-bottom: 1px solid rgba(var(--v-theme-on-surface), 0.08);
}
.panel-title {
  font-size: 1.2rem;
  font-weight: 650;
  margin-top: 3px;
}
.panel-body {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
}
.original-box {
  font-size: 1.13rem;
  line-height: 1.9;
  padding: 15px 17px;
  border-radius: 12px;
  background: rgba(var(--v-theme-secondary), 0.065);
  border-left: 3px solid rgba(var(--v-theme-secondary), 0.55);
}
.status-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 10px;
}
.section-block {
  margin-top: 24px;
  padding-top: 18px;
  border-top: 1px dashed rgba(var(--v-theme-on-surface), 0.12);
}
.section-block-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 10px;
}
.translation-text {
  font-size: 0.92rem;
  line-height: 1.85;
  color: rgba(var(--v-theme-on-surface), 0.85);
  white-space: pre-wrap;
}
.no-translation {
  font-size: 0.8rem;
  color: rgba(var(--v-theme-on-surface), 0.46);
  line-height: 1.7;
}
.action-row {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-top: 12px;
  flex-wrap: wrap;
}
.review-block {
  background: rgba(var(--v-theme-warning), 0.055);
  border: 1px solid rgba(var(--v-theme-warning), 0.18);
  border-radius: 12px;
  padding: 15px;
}
.review-title {
  font-size: 0.84rem;
  font-weight: 600;
  margin: 5px 0 8px;
}
.review-original {
  font-size: 0.76rem;
  text-decoration: line-through;
  color: rgba(var(--v-theme-on-surface), 0.42);
  line-height: 1.7;
}
.review-candidate {
  font-size: 0.85rem;
  line-height: 1.75;
  margin-top: 6px;
}
.explain-block {
  background: rgba(var(--v-theme-primary), 0.035);
  border-radius: 12px;
  padding: 15px;
  border-top: 0;
}
.explanation-citations {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-top: 12px;
}
.citation-card {
  border-left: 3px solid rgba(var(--v-theme-secondary), 0.55);
  padding: 7px 10px;
  background: rgba(var(--v-theme-secondary), 0.06);
}
.citation-head {
  font-size: 0.72rem;
  font-weight: 600;
}
.citation-quote {
  font-size: 0.8rem;
  margin-top: 4px;
  color: rgba(var(--v-theme-on-surface), 0.65);
}
.annotation-form {
  margin-bottom: 12px;
}
.annotation-empty {
  padding: 4px 0;
}
.annotation-row {
  padding: 11px 0;
  border-bottom: 1px dashed rgba(var(--v-theme-on-surface), 0.09);
}
.annotation-content {
  font-size: 0.84rem;
  line-height: 1.7;
}
.annotation-meta {
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 0.66rem;
  color: rgba(var(--v-theme-on-surface), 0.38);
  margin-top: 4px;
}
.version-row {
  padding: 10px 0;
  border-bottom: 1px dashed rgba(var(--v-theme-on-surface), 0.08);
}
.version-meta {
  display: flex;
  align-items: center;
  gap: 7px;
  font-size: 0.66rem;
  color: rgba(var(--v-theme-on-surface), 0.4);
}
.version-text {
  font-size: 0.8rem;
  line-height: 1.7;
  margin-top: 6px;
  color: rgba(var(--v-theme-on-surface), 0.7);
}
</style>
