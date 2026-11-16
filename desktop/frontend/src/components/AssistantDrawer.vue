<template>
  <v-navigation-drawer
    :model-value="modelValue"
    location="right"
    temporary
    width="430"
    class="assistant-drawer"
    @update:model-value="$emit('update:modelValue', $event)"
  >
    <div class="assistant-shell">
      <div class="assistant-head">
        <div class="assistant-mark serif">问</div>
        <div class="assistant-heading">
          <div class="assistant-title serif">AI 阅读助手</div>
          <div class="assistant-sub">{{ contextLabel || '基于当前章节与本地知识库' }}</div>
        </div>
        <v-spacer />
        <v-btn icon="mdi-plus" variant="text" size="small" title="新对话" @click="newSession" />
        <v-btn icon="mdi-close" variant="text" size="small" @click="$emit('update:modelValue', false)" />
      </div>

      <div v-if="!ai.configured" class="assistant-empty">
        <div class="empty-seal serif">AI</div>
        <div class="empty-heading">尚未配置问答模型</div>
        <p>配置一个 OpenAI 兼容服务或 Ollama 模型后，即可基于当前原文提问。</p>
        <v-btn color="primary" variant="tonal" @click="goSettings">前往设置</v-btn>
      </div>

      <div v-else ref="messageArea" class="assistant-messages">
        <div v-if="!messages.length" class="assistant-intro">
          <div class="intro-quote serif">“知之为知之，不知为不知。”</div>
          <p>我会优先依据当前书籍、章节和本地知识库回答，并尽量给出原文出处。我可以区分原文明示、合理推断、分析，以及证据不足的内容。</p>
          <div class="suggestions">
            <v-chip
              v-for="suggestion in suggestions"
              :key="suggestion"
              size="small"
              variant="tonal"
              color="primary"
              class="suggestion"
              @click="ask(suggestion)"
            >
              {{ suggestion }}
            </v-chip>
          </div>
        </div>

        <div v-for="(message, index) in messages" :key="index" class="message" :class="message.role">
          <div v-if="message.role === 'assistant'" class="message-avatar serif">AI</div>
          <div class="message-body">
            <div class="message-content assistant-prose">{{ message.content }}</div>
            <div v-if="message.claims?.length" class="claims">
              <v-chip
                v-for="(claim, claimIndex) in message.claims"
                :key="claimIndex"
                size="x-small"
                variant="tonal"
                :color="claimColor(claim.kind)"
                class="claim"
              >
                {{ claimLabel(claim.kind) }} · {{ claim.text }}
              </v-chip>
            </div>
            <div v-if="message.citations?.length" class="citations">
              <div class="citation-label">史料出处</div>
              <div
                v-for="(citation, citationIndex) in message.citations"
                :key="citationIndex"
                class="citation-card"
              >
                <div class="citation-head">
                  <span class="serif">{{ citation.book }}<template v-if="citation.chapter"> · {{ citation.chapter }}</template></span>
                  <v-icon
                    :icon="citation.verified ? 'mdi-check-decagram' : 'mdi-help-circle-outline'"
                    :color="citation.verified ? 'success' : 'warning'"
                    size="15"
                  />
                </div>
                <div v-if="citation.quote" class="citation-quote serif">{{ citation.quote }}</div>
                <div v-if="citation.note" class="citation-note">{{ citation.note }}</div>
              </div>
            </div>
            <div v-if="message.localSources?.length" class="local-sources">
              本地检索到 {{ message.localSources.length }} 条相关史料
            </div>
          </div>
        </div>

        <div v-if="sending" class="message assistant">
          <div class="message-avatar serif">AI</div>
          <div class="thinking"><span /><span /><span /></div>
        </div>
      </div>

      <div v-if="ai.configured" class="assistant-input">
        <v-textarea
          v-model="question"
          placeholder="询问当前句意、人物、制度或史料出处…"
          rows="2"
          auto-grow
          max-rows="5"
          variant="solo"
          flat
          hide-details
          rounded="lg"
          :disabled="sending"
          @keydown.ctrl.enter.prevent="send"
        />
        <div class="input-actions">
          <span class="tiny muted">Ctrl + 回车发送</span>
          <v-btn color="primary" icon="mdi-arrow-up" size="small" :loading="sending" :disabled="!question.trim()" @click="send" />
        </div>
      </div>
    </div>
  </v-navigation-drawer>
</template>

<script setup lang="ts">
import { nextTick, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { aiApi } from '@/api/ai'
import type { AssistantAnswer } from '@/api/types'
import { useAiStore } from '@/stores/ai'
import { useAppStore } from '@/stores/app'

interface ChatMessage {
  role: 'user' | 'assistant'
  content: string
  claims?: AssistantAnswer['claims']
  citations?: AssistantAnswer['citations']
  localSources?: unknown[]
}

const props = defineProps<{
  modelValue: boolean
  bookId?: string | null
  chapterId?: string | null
  paragraphId?: string | null
  sentenceId?: string | null
  contextLabel?: string
}>()
defineEmits<{ 'update:modelValue': [value: boolean] }>()

const ai = useAiStore()
const app = useAppStore()
const router = useRouter()
const messages = ref<ChatMessage[]>([])
const question = ref('')
const sending = ref(false)
const sessionId = ref<string | null>(null)
const messageArea = ref<HTMLElement | null>(null)

const suggestions = ['解释当前句意', '概括本章主要内容', '介绍相关人物背景', '不同史料如何记载']

watch(
  () => props.modelValue,
  (open) => { if (open) scrollToBottom() },
)

function claimLabel(kind: string): string {
  return ({
    explicit: '原文记载',
    inference: '合理推断',
    analysis: 'AI 分析',
    unverified: '证据不足',
  } as Record<string, string>)[kind] || '未标注'
}

function claimColor(kind: string): string {
  return ({
    explicit: 'success', inference: 'info', analysis: 'secondary', unverified: 'warning',
  } as Record<string, string>)[kind] || 'warning'
}

function newSession() {
  sessionId.value = null
  messages.value = []
  question.value = ''
}

function ask(text: string) {
  question.value = text
  send()
}

async function send() {
  const text = question.value.trim()
  if (!text || sending.value) return
  messages.value.push({ role: 'user', content: text })
  question.value = ''
  sending.value = true
  await scrollToBottom()
  try {
    const answer = await aiApi.chat({
      question: text,
      book_id: props.bookId || null,
      chapter_id: props.chapterId || null,
      paragraph_id: props.paragraphId || null,
      sentence_id: props.sentenceId || null,
      session_id: sessionId.value,
    })
    sessionId.value = answer.session_id
    messages.value.push({
      role: 'assistant',
      content: answer.answer,
      claims: answer.claims,
      citations: answer.citations,
      localSources: answer.local_sources,
    })
  } catch (error) {
    messages.value.push({
      role: 'assistant',
      content: `本次回答失败：${error instanceof Error ? error.message : '未知错误'}。请检查模型配置与网络连接后重试。`,
    })
  } finally {
    sending.value = false
    await scrollToBottom()
  }
}

async function scrollToBottom() {
  await nextTick()
  if (messageArea.value) {
    messageArea.value.scrollTop = messageArea.value.scrollHeight
  }
}

function goSettings() {
  router.push('/settings')
}
</script>

<style scoped>
.assistant-drawer {
  background: rgb(var(--v-theme-surface)) !important;
}
.assistant-shell {
  height: 100%;
  display: flex;
  flex-direction: column;
}
.assistant-head {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 18px 18px 14px;
  border-bottom: 1px solid rgba(var(--v-theme-on-surface), 0.08);
}
.assistant-mark {
  width: 38px;
  height: 38px;
  border-radius: 12px;
  background: rgba(var(--v-theme-primary), 0.1);
  color: rgb(var(--v-theme-primary));
  display: grid;
  place-items: center;
  font-size: 1.15rem;
  font-weight: 650;
}
.assistant-title {
  font-size: 1.02rem;
  font-weight: 650;
}
.assistant-sub {
  font-size: 0.68rem;
  color: rgba(var(--v-theme-on-surface), 0.44);
  margin-top: 2px;
}
.assistant-messages {
  flex: 1;
  overflow-y: auto;
  padding: 18px;
}
.assistant-empty {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 36px;
  gap: 10px;
}
.empty-seal {
  width: 64px;
  height: 64px;
  border-radius: 20px;
  display: grid;
  place-items: center;
  font-size: 1.5rem;
  color: rgb(var(--v-theme-secondary));
  background: rgba(var(--v-theme-secondary), 0.09);
  margin-bottom: 6px;
}
.empty-heading {
  font-family: "Noto Serif SC", "Songti SC", serif;
  font-weight: 650;
  font-size: 1.1rem;
}
.assistant-empty p {
  font-size: 0.82rem;
  line-height: 1.7;
  color: rgba(var(--v-theme-on-surface), 0.56);
  margin: 0 0 8px;
}
.assistant-intro {
  padding: 8px 2px 20px;
}
.intro-quote {
  font-size: 1.05rem;
  color: rgba(var(--v-theme-on-surface), 0.68);
  margin-bottom: 10px;
}
.assistant-intro p {
  font-size: 0.8rem;
  line-height: 1.75;
  color: rgba(var(--v-theme-on-surface), 0.5);
}
.suggestions {
  display: flex;
  gap: 7px;
  flex-wrap: wrap;
  margin-top: 14px;
}
.suggestion {
  cursor: pointer;
}
.message {
  display: flex;
  gap: 10px;
  margin-bottom: 20px;
}
.message.user {
  justify-content: flex-end;
}
.message.user .message-body {
  background: rgba(var(--v-theme-primary), 0.09);
  border-radius: 14px 14px 4px 14px;
  padding: 10px 13px;
  max-width: 88%;
  font-size: 0.88rem;
  line-height: 1.65;
}
.message-avatar {
  width: 26px;
  height: 26px;
  border-radius: 8px;
  background: rgba(var(--v-theme-primary), 0.1);
  color: rgb(var(--v-theme-primary));
  display: grid;
  place-items: center;
  font-size: 0.62rem;
  font-weight: 700;
  flex-shrink: 0;
  margin-top: 2px;
}
.message-body {
  flex: 1;
  min-width: 0;
}
.message-content {
  color: rgba(var(--v-theme-on-surface), 0.85);
}
.claims {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 5px;
  margin-top: 10px;
}
.claim {
  height: auto !important;
  padding: 4px 8px !important;
  white-space: normal;
  text-align: left;
}
.citations {
  margin-top: 13px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.citation-label {
  font-size: 0.62rem;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: rgba(var(--v-theme-on-surface), 0.38);
}
.citation-card {
  border-left: 3px solid rgba(var(--v-theme-secondary), 0.6);
  padding: 8px 11px;
  border-radius: 0 9px 9px 0;
  background: rgba(var(--v-theme-secondary), 0.06);
}
.citation-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  font-size: 0.72rem;
  font-weight: 600;
}
.citation-quote {
  font-size: 0.82rem;
  line-height: 1.7;
  margin-top: 5px;
  color: rgba(var(--v-theme-on-surface), 0.72);
}
.citation-note {
  font-size: 0.66rem;
  color: rgba(var(--v-theme-on-surface), 0.45);
  margin-top: 4px;
}
.local-sources {
  font-size: 0.66rem;
  color: rgba(var(--v-theme-on-surface), 0.4);
  margin-top: 10px;
}
.assistant-input {
  padding: 12px 16px 16px;
  border-top: 1px solid rgba(var(--v-theme-on-surface), 0.08);
  background: rgba(var(--v-theme-surface), 0.96);
}
.input-actions {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 8px;
}
.thinking {
  display: flex;
  gap: 5px;
  padding-top: 10px;
}
.thinking span {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: rgba(var(--v-theme-primary), 0.45);
  animation: pulse 1.2s infinite ease-in-out;
}
.thinking span:nth-child(2) { animation-delay: 0.15s; }
.thinking span:nth-child(3) { animation-delay: 0.3s; }
@keyframes pulse {
  0%, 80%, 100% { opacity: 0.25; transform: translateY(0); }
  40% { opacity: 1; transform: translateY(-3px); }
}
</style>
