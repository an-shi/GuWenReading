<template>
  <div class="page settings-page">
    <div class="page-header">
      <div>
        <div class="section-label">偏好设置</div>
        <h1 class="page-title">设置</h1>
        <p class="page-subtitle">模型、提示词、阅读偏好与本地服务。密钥只写入加密存储，不会在接口或日志中明文返回。</p>
      </div>
      <v-chip size="small" variant="tonal" :color="app.backendOnline ? 'success' : 'error'">
        {{ app.backendOnline ? '后端已连接' : '后端未连接' }}
      </v-chip>
    </div>

    <v-tabs v-model="tab" class="settings-tabs" color="primary" density="comfortable">
      <v-tab value="ai" prepend-icon="mdi-robot-outline">AI 服务</v-tab>
      <v-tab value="prompts" prepend-icon="mdi-code-braces">提示词</v-tab>
      <v-tab value="reading" prepend-icon="mdi-book-open-variant">阅读</v-tab>
      <v-tab value="service" prepend-icon="mdi-server-network">服务与同步</v-tab>
    </v-tabs>

    <div v-if="tab === 'ai'" class="tab-content">
      <div class="section-head">
        <div>
          <div class="section-title serif">模型服务商</div>
          <div class="section-desc">兼容 OpenAI 接口的服务或 Ollama。密钥在 Windows 上优先使用系统 DPAPI 加密。</div>
        </div>
        <v-btn color="primary" prepend-icon="mdi-plus" @click="openProviderDialog()">添加服务商</v-btn>
      </div>

      <div v-if="ai.providers.length" class="provider-list">
        <v-card v-for="provider in ai.providers" :key="provider.id" class="provider-card">
          <div class="provider-main">
            <div class="provider-icon"><v-icon icon="mdi-api" size="20" /></div>
            <div class="provider-body">
              <div class="provider-name-row">
                <span class="provider-name">{{ provider.name }}</span>
                <v-chip size="x-small" variant="tonal">{{ providerKindLabel(provider.kind) }}</v-chip>
                <v-chip v-if="provider.has_api_key" size="x-small" variant="tonal" color="success">
                  密钥 {{ provider.api_key_hint }}
                </v-chip>
                <v-chip v-else size="x-small" variant="tonal" color="warning">未配置密钥</v-chip>
              </div>
              <div class="provider-url">{{ provider.base_url }}</div>
            </div>
            <v-switch
              :model-value="provider.enabled"
              color="primary"
              density="compact"
              hide-details
              @update:model-value="toggleProvider(provider, Boolean($event))"
            />
            <v-btn
              size="small"
              variant="tonal"
              color="primary"
              :loading="testingProvider === provider.id"
              @click="testProvider(provider)"
            >测试连接</v-btn>
            <v-btn icon="mdi-pencil-outline" size="small" variant="text" @click="openProviderDialog(provider)" />
            <v-btn icon="mdi-delete-outline" size="small" variant="text" @click="deleteProvider(provider)" />
          </div>
        </v-card>
      </div>
      <v-alert v-else type="info" variant="tonal" class="mt-2">
        尚未添加服务商。可填写 OpenAI、DeepSeek、Moonshot、智谱兼容接口，或本地 Ollama 地址。
      </v-alert>

      <div class="section-head models-head">
        <div>
          <div class="section-title serif">模型</div>
          <div class="section-desc">为翻译与问答分别指定默认模型。上下文长度会用于动态控制翻译批次。</div>
        </div>
        <v-btn variant="tonal" color="primary" prepend-icon="mdi-plus" :disabled="!ai.providers.length" @click="openModelDialog()">
          添加模型
        </v-btn>
      </div>

      <div v-if="ai.models.length" class="model-list">
        <v-card v-for="model in ai.models" :key="model.id" class="model-card">
          <div class="model-main">
            <div class="model-body">
              <div class="model-title-row">
                <span class="model-name serif">{{ model.display_name }}</span>
                <v-chip size="x-small" variant="tonal" color="primary">{{ model.name }}</v-chip>
                <v-chip size="x-small" variant="tonal">{{ ai.providerName(model.provider_id) }}</v-chip>
                <v-chip v-if="model.is_default_translation" size="x-small" color="success" variant="tonal">默认翻译</v-chip>
                <v-chip v-if="model.is_default_chat" size="x-small" color="info" variant="tonal">默认问答</v-chip>
              </div>
              <div class="model-meta">
                上下文 {{ model.context_window.toLocaleString() }} 词元 ·
                最大输出 {{ model.max_output_tokens.toLocaleString() }} ·
                超时 {{ model.timeout_seconds }} 秒 ·
                {{ model.supports_json ? '结构化模式' : '文本模式' }}
              </div>
              <div class="model-capabilities">
                <v-chip v-for="capability in model.capabilities" :key="capability" size="x-small" variant="tonal">
                  {{ capability === 'translation' ? '翻译' : capability === 'chat' ? '问答' : capability }}
                </v-chip>
              </div>
            </div>
            <v-switch
              :model-value="model.enabled"
              color="primary"
              density="compact"
              hide-details
              @update:model-value="toggleModel(model, 'enabled', Boolean($event))"
            />
            <v-btn icon="mdi-pencil-outline" size="small" variant="text" @click="openModelDialog(model)" />
            <v-btn icon="mdi-delete-outline" size="small" variant="text" @click="deleteModel(model)" />
          </div>
        </v-card>
      </div>
      <v-alert v-else type="info" variant="tonal" class="mt-2">
        添加模型后，翻译、知识抽取和 AI 助手才能工作。没有配置时，软件仍可完整阅读原文并使用人工译文。
      </v-alert>
    </div>

    <div v-else-if="tab === 'prompts'" class="tab-content">
      <div class="section-head">
        <div>
          <div class="section-title serif">提示词版本管理</div>
          <div class="section-desc">所有 AI 指令独立存储并保留版本。每条译文记录使用的提示词版本。</div>
        </div>
      </div>
      <div class="prompt-layout">
        <v-card class="prompt-list-card">
          <button
            v-for="prompt in promptGroups"
            :key="prompt.key"
            class="prompt-item"
            :class="{ active: promptKey === prompt.key }"
            @click="loadPrompt(prompt.key)"
          >
            <div class="prompt-item-icon"><v-icon icon="mdi-code-braces" size="16" /></div>
            <div class="prompt-item-body">
              <div class="prompt-item-title">{{ promptDisplayName(prompt.name) }}</div>
              <div class="prompt-item-key">版本 v{{ prompt.version }}</div>
            </div>
          </button>
        </v-card>
        <v-card class="prompt-detail-card">
          <template v-if="promptDetail">
            <div class="prompt-detail-head">
              <div>
                <div class="section-label">提示词模板</div>
                <div class="prompt-detail-title serif">{{ promptDisplayName(promptDetail.active.name) }}</div>
                <div class="tiny muted">当前生效版本 v{{ promptDetail.active.version }}</div>
              </div>
              <v-btn color="primary" variant="tonal" prepend-icon="mdi-plus" @click="openPromptDialog">创建新版本</v-btn>
            </div>
            <pre class="prompt-template">{{ promptDetail.active.template }}</pre>
            <div class="prompt-versions">
              <div class="section-label">历史版本</div>
              <div v-for="version in promptDetail.versions" :key="version.id" class="version-row">
                <div>
                  <span class="version-name">v{{ version.version }} · {{ version.name }}</span>
                  <span v-if="version.is_active" class="active-label">当前</span>
                  <div class="tiny muted">{{ formatDate(version.created_at) }}</div>
                </div>
                <v-btn
                  v-if="!version.is_active"
                  size="small"
                  variant="text"
                  color="primary"
                  @click="activatePrompt(version.version)"
                >启用此版本</v-btn>
              </div>
            </div>
          </template>
          <div v-else class="prompt-empty">选择左侧提示词查看当前模板与历史版本。</div>
        </v-card>
      </div>
    </div>

    <div v-else-if="tab === 'reading'" class="tab-content">
      <div class="section-head">
        <div>
          <div class="section-title serif">阅读外观</div>
          <div class="section-desc">设置会保存在本机，并即时应用于阅读器。</div>
        </div>
      </div>
      <div class="reading-grid">
        <v-card class="settings-card">
          <div class="section-label">阅读主题</div>
          <div class="theme-options">
            <button
              v-for="theme in themeOptions"
              :key="theme.value"
              class="theme-option"
              :class="[theme.value, { active: app.theme === theme.value }]"
              @click="app.setTheme(theme.value)"
            >
              <span class="theme-preview"><span class="theme-line" /><span class="theme-line short" /><span class="theme-line" /></span>
              <span>{{ theme.title }}</span>
            </button>
          </div>
          <div class="section-label mt-6">排版</div>
          <div class="setting-line">
            <span>正文字号</span>
            <div class="setting-control">
              <v-slider :model-value="app.fontSize" :min="14" :max="30" :step="1" hide-details density="compact" color="primary" @update:model-value="app.setFontSize(Number($event))" />
              <span class="value">{{ app.fontSize }} 像素</span>
            </div>
          </div>
          <div class="setting-line">
            <span>行距</span>
            <div class="setting-control">
              <v-slider :model-value="app.lineHeight" :min="1.4" :max="2.6" :step="0.1" hide-details density="compact" color="primary" @update:model-value="app.setLineHeight(Number($event))" />
              <span class="value">{{ app.lineHeight.toFixed(1) }}</span>
            </div>
          </div>
          <div class="setting-line">
            <span>打开章节自动翻译</span>
            <v-switch :model-value="app.autoTranslate" color="primary" density="compact" hide-details @update:model-value="app.setAutoTranslate(Boolean($event))" />
          </div>
          <p class="setting-hint">自动翻译只会在已配置翻译模型且章节存在未译句子时触发。人工修订译文永远不会被覆盖。</p>
        </v-card>

        <v-card class="settings-card preview-card">
          <div class="section-label">效果预览</div>
          <div
            class="preview-text serif"
            :style="{ fontSize: `${app.fontSize}px`, lineHeight: app.lineHeight }"
          >
            黄帝者，少典之子，姓公孙，名曰轩辕。生而神灵，弱而能言，幼而徇齐，长而敦敏，成而聪明。
          </div>
          <div class="preview-translation" :style="{ fontSize: `${Math.round(app.fontSize * 0.92)}px` }">
            黄帝，是少典的儿子，姓公孙，名叫轩辕。他生下来就十分神奇灵异，很小的时候就会说话……
          </div>
        </v-card>
      </div>
    </div>

    <div v-else class="tab-content">
      <div class="section-head">
        <div>
          <div class="section-title serif">本地服务与同步</div>
          <div class="section-desc">内嵌模式默认只监听 127.0.0.1；服务端模式需要登录并用于多设备共享。同步是可选能力。</div>
        </div>
      </div>

      <div class="service-grid">
        <v-card class="settings-card">
          <div class="section-label">服务模式</div>
          <div class="kv-row"><span>状态</span><strong :class="app.backendOnline ? 'ok' : 'bad'">{{ app.backendOnline ? '在线' : '离线' }}</strong></div>
          <div class="kv-row"><span>模式</span><strong>{{ backendModeLabel(app.info?.mode) }}</strong></div>
          <div class="kv-row"><span>版本</span><strong>{{ app.info?.version || '—' }}</strong></div>
          <div class="kv-row"><span>认证</span><strong>{{ app.info?.auth_required ? '必须登录' : '本地免登录' }}</strong></div>
          <div class="kv-row data-dir-row">
            <span>数据目录</span>
            <div class="data-dir">
              <code>{{ app.info?.data_dir || '服务器模式不公开本地路径' }}</code>
              <v-btn v-if="app.info?.data_dir" icon="mdi-content-copy" size="x-small" variant="text" @click="copyDataDir" />
            </div>
          </div>

          <div class="section-label mt-6">接口地址</div>
          <v-text-field v-model="apiBaseForm" density="compact" variant="outlined" hide-details class="mt-2" />
          <div class="action-line">
            <span class="tiny muted">例如 http://127.0.0.1:8765/api/v1</span>
            <v-btn size="small" color="primary" variant="tonal" :loading="reconnecting" @click="saveApiBase">保存并重连</v-btn>
          </div>
        </v-card>

        <v-card class="settings-card">
          <div class="section-label">账户</div>
          <template v-if="app.info?.auth_required && !app.authenticated">
            <p class="setting-hint">当前为服务端模式，需要登录后才能读取书架与知识库。首个账户可直接注册。</p>
            <v-text-field v-model="authForm.username" label="用户名" density="compact" />
            <v-text-field v-model="authForm.password" label="密码（至少 8 位）" type="password" density="compact" />
            <v-text-field v-if="authMode === 'register'" v-model="authForm.displayName" label="显示名称" density="compact" />
            <v-alert v-if="authError" type="error" variant="tonal" density="compact" :text="authError" />
            <div class="action-line">
              <v-btn variant="text" size="small" @click="authMode = authMode === 'login' ? 'register' : 'login'">
                {{ authMode === 'login' ? '注册首个账户' : '已有账户？登录' }}
              </v-btn>
              <v-btn color="primary" size="small" :loading="authLoading" @click="submitAuth">
                {{ authMode === 'login' ? '登录' : '注册' }}
              </v-btn>
            </div>
          </template>
          <template v-else-if="app.authenticated">
            <div class="account-badge">
              <div class="account-avatar serif">{{ (app.username || '本').slice(0, 1) }}</div>
              <div>
                <div class="account-name">{{ app.username }}</div>
                <div class="tiny muted">已认证 · 同步身份分层</div>
              </div>
            </div>
            <v-btn variant="text" color="error" class="mt-4" @click="logout">退出登录</v-btn>
          </template>
          <template v-else>
            <div class="account-badge">
              <div class="account-avatar serif">本</div>
              <div>
                <div class="account-name">本地模式</div>
                <div class="tiny muted">无需账户，数据保存在本机</div>
              </div>
            </div>
          </template>

          <div class="section-label mt-6">设备</div>
          <div class="kv-row"><span>设备编号</span><code class="device-id">{{ app.deviceId }}</code></div>
          <div v-if="devices.length" class="device-list">
            <div v-for="device in devices" :key="device.id" class="device-row">
              <v-icon :icon="device.platform === 'windows' ? 'mdi-monitor' : 'mdi-cellphone'" size="16" />
              <span>{{ device.name }}</span>
              <span class="tiny muted">{{ formatDate(device.last_seen_at) }}</span>
            </div>
          </div>
        </v-card>

        <v-card class="settings-card">
          <div class="section-label">同步</div>
          <template v-if="app.info?.capabilities.sync">
            <p class="setting-hint">同步为可选能力。此桌面端直接访问当前后端；手机端可通过同一服务端增量拉取译文、批注、书签与知识数据。</p>
            <div v-if="syncStatus" class="kv-row"><span>最新操作序号</span><strong>{{ syncStatus.latest_seq }}</strong></div>
            <div v-if="syncStatus" class="kv-row"><span>待处理冲突</span><strong :class="syncStatus.pending_conflicts ? 'warn' : 'ok'">{{ syncStatus.pending_conflicts }}</strong></div>
            <div v-if="syncStatus" class="kv-row"><span>本设备游标</span><strong>{{ syncStatus.last_pulled_seq }}</strong></div>
            <v-btn variant="tonal" size="small" class="mt-3" @click="loadSyncStatus">刷新同步状态</v-btn>
          </template>
          <template v-else>
            <p class="setting-hint">当前为本地模式，同步未启用。启用服务端模式后，可在服务端统一管理多设备数据。</p>
            <v-btn variant="tonal" size="small" :to="'/tasks'">查看本地任务</v-btn>
          </template>
        </v-card>

        <v-card class="settings-card">
          <div class="section-label">功能支持</div>
          <div class="cap-grid">
            <div v-for="(value, key) in app.info?.capabilities || {}" :key="key" class="cap-row">
              <span>{{ capabilityLabel(String(key)) }}</span>
              <v-icon :icon="value ? 'mdi-check-circle' : 'mdi-minus-circle-outline'" :color="value ? 'success' : 'warning'" size="16" />
            </div>
          </div>
          <div class="tiny muted mt-3">扫描版 PDF 的文字识别尚未实现；这类文件会被明确拒绝，而不是静默生成错误文本。</div>
        </v-card>

        <v-card class="settings-card">
          <div class="section-label">备份</div>
          <p class="setting-hint">创建完整的本机数据备份（数据库、原始书籍、提取文本和封面）。恢复时请先停止后端，再运行 scripts/restore_backup.py。</p>
          <div class="action-line">
            <span class="tiny muted">本地数据库模式可用</span>
            <v-btn
              size="small"
              color="primary"
              variant="tonal"
              prepend-icon="mdi-database-export-outline"
              :loading="creatingBackup"
              :disabled="!app.info?.capabilities.backup"
              @click="createBackup"
            >
              创建备份
            </v-btn>
          </div>
          <div v-if="backups.length" class="backup-list">
            <div v-for="backup in backups.slice(0, 5)" :key="backup.filename" class="backup-row">
              <v-icon icon="mdi-zip-box-outline" size="16" />
              <div class="backup-main">
                <div class="backup-name">{{ backup.filename }}</div>
                <div class="tiny muted">{{ formatSize(backup.size) }}</div>
              </div>
              <v-btn
                icon="mdi-download"
                size="x-small"
                variant="text"
                @click="downloadBackup(backup.filename)"
              />
            </div>
          </div>
        </v-card>
      </div>
    </div>

    <v-dialog v-model="providerDialog" max-width="620" persistent>
      <v-card>
        <v-card-title class="pt-6 px-6">{{ editingProvider ? '编辑服务商' : '添加服务商' }}</v-card-title>
        <v-card-text>
          <v-text-field v-model="providerForm.name" label="名称" placeholder="例如 DeepSeek" />
          <v-select
            v-model="providerForm.kind"
            :items="providerKinds"
            item-title="title"
            item-value="value"
            label="类型"
          />
          <v-text-field v-model="providerForm.base_url" label="接口基础地址" placeholder="https://api.deepseek.com/v1" />
          <v-text-field
            v-model="providerForm.api_key"
            label="接口密钥"
            type="password"
            :placeholder="editingProvider?.has_api_key ? '留空则保持原密钥不变' : 'sk-...'"
            autocomplete="off"
          />
          <v-checkbox v-if="editingProvider" v-model="providerForm.clear_api_key" label="清除已保存的密钥" color="warning" />
          <v-textarea v-model="providerForm.notes" label="备注（可选）" rows="2" />
          <v-switch v-model="providerForm.enabled" label="启用该服务商" color="primary" density="compact" />
        </v-card-text>
        <v-card-actions class="px-6 pb-5">
          <v-spacer />
          <v-btn variant="text" @click="providerDialog = false">取消</v-btn>
          <v-btn color="primary" :loading="savingProvider" @click="saveProvider">保存</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="modelDialog" max-width="700" persistent>
      <v-card>
        <v-card-title class="pt-6 px-6">{{ editingModel ? '编辑模型' : '添加模型' }}</v-card-title>
        <v-card-text>
          <v-select
            v-model="modelForm.provider_id"
            :items="ai.providers"
            item-title="name"
            item-value="id"
            label="服务商"
            :disabled="Boolean(editingModel)"
          />
          <v-row dense>
            <v-col cols="12" sm="6"><v-text-field v-model="modelForm.name" label="模型标识" placeholder="deepseek-chat" /></v-col>
            <v-col cols="12" sm="6"><v-text-field v-model="modelForm.display_name" label="显示名称" placeholder="DeepSeek Chat" /></v-col>
            <v-col cols="12" sm="6"><v-text-field v-model.number="modelForm.context_window" label="上下文长度（词元）" type="number" /></v-col>
            <v-col cols="12" sm="6"><v-text-field v-model.number="modelForm.max_output_tokens" label="最大输出（词元）" type="number" /></v-col>
            <v-col cols="12" sm="6"><v-text-field v-model.number="modelForm.timeout_seconds" label="超时（秒）" type="number" /></v-col>
            <v-col cols="12" sm="6">
              <v-select
                v-model="modelForm.capabilities"
                :items="capabilityOptions"
                item-title="title"
                item-value="value"
                label="能力"
                multiple
                chips
              />
            </v-col>
          </v-row>
          <v-switch v-model="modelForm.supports_json" label="支持结构化输出" color="primary" density="compact" />
          <v-switch v-model="modelForm.is_default_translation" label="设为默认翻译模型" color="primary" density="compact" />
          <v-switch v-model="modelForm.is_default_chat" label="设为默认问答模型" color="primary" density="compact" />
          <v-switch v-model="modelForm.enabled" label="启用该模型" color="primary" density="compact" />
        </v-card-text>
        <v-card-actions class="px-6 pb-5">
          <v-spacer />
          <v-btn variant="text" @click="modelDialog = false">取消</v-btn>
          <v-btn color="primary" :loading="savingModel" @click="saveModel">保存</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="promptDialog" max-width="760" persistent>
      <v-card>
        <v-card-title class="pt-6 px-6">创建提示词新版本</v-card-title>
        <v-card-text>
          <v-text-field v-model="promptForm.name" label="版本名称" />
          <v-text-field v-model="promptForm.description" label="说明" />
          <v-text-field v-model="promptForm.variables" label="变量（逗号分隔）" />
          <v-textarea v-model="promptForm.template" label="模板内容" rows="14" class="prompt-editor" />
        </v-card-text>
        <v-card-actions class="px-6 pb-5">
          <v-spacer />
          <v-btn variant="text" @click="promptDialog = false">取消</v-btn>
          <v-btn color="primary" :loading="savingPrompt" @click="savePrompt">创建并启用</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="confirmDialog.open" max-width="460">
      <v-card>
        <v-card-title class="pt-6 px-6">{{ confirmDialog.title }}</v-card-title>
        <v-card-text>{{ confirmDialog.text }}</v-card-text>
        <v-card-actions class="px-6 pb-5">
          <v-spacer />
          <v-btn variant="text" @click="confirmDialog.open = false">取消</v-btn>
          <v-btn color="error" :loading="confirmDialog.loading" @click="runConfirm">确认</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import type { AIModel, AIProvider, PromptDetail, PromptSummary } from '@/api/types'
import { aiApi } from '@/api/ai'
import { setToken, getToken } from '@/api/client'
import { systemApi, syncApi } from '@/api/system'
import { useAiStore } from '@/stores/ai'
import { useAppStore } from '@/stores/app'

const app = useAppStore()
const ai = useAiStore()
const tab = ref('ai')

const providerKinds = [
  { title: 'OpenAI 兼容', value: 'openai_compatible' },
  { title: 'OpenAI', value: 'openai' },
  { title: 'Ollama', value: 'ollama' },
]
const capabilityOptions = [
  { title: '翻译', value: 'translation' },
  { title: '问答与抽取', value: 'chat' },
]
const themeOptions = [
  { title: '纸张', value: 'paper' as const },
  { title: '浅色', value: 'light' as const },
  { title: '深色', value: 'dark' as const },
]

const providerDialog = ref(false)
const editingProvider = ref<AIProvider | null>(null)
const savingProvider = ref(false)
const testingProvider = ref('')
const providerForm = reactive({
  name: '',
  kind: 'openai_compatible' as 'openai_compatible' | 'openai' | 'ollama',
  base_url: '',
  api_key: '',
  clear_api_key: false,
  notes: '',
  enabled: true,
})

const modelDialog = ref(false)
const editingModel = ref<AIModel | null>(null)
const savingModel = ref(false)
const modelForm = reactive({
  provider_id: '',
  name: '',
  display_name: '',
  context_window: 8192,
  max_output_tokens: 2048,
  timeout_seconds: 120,
  capabilities: ['translation', 'chat'] as string[],
  supports_json: true,
  is_default_translation: false,
  is_default_chat: false,
  enabled: true,
})

const promptKey = ref('translation')
const promptDetail = ref<PromptDetail | null>(null)
const promptDialog = ref(false)
const savingPrompt = ref(false)
const promptForm = reactive({ name: '', description: '', variables: '', template: '' })

const apiBaseForm = ref(app.baseUrl)
const reconnecting = ref(false)
const devices = ref<Array<{ id: string; name: string; platform: string; last_seen_at: string }>>([])
const backups = ref<Array<{ filename: string; size: number; created_at: string; download_url: string }>>([])
const creatingBackup = ref(false)
const syncStatus = ref<{
  enabled: boolean
  latest_seq: number
  pending_conflicts: number
  last_pulled_seq: number
} | null>(null)
const authMode = ref<'login' | 'register'>('login')
const authForm = reactive({ username: '', password: '', displayName: '' })
const authError = ref('')
const authLoading = ref(false)

const confirmDialog = reactive({
  open: false,
  title: '',
  text: '',
  loading: false,
  action: async () => undefined as void,
})

const promptGroups = computed<PromptSummary[]>(() => {
  const map = new Map<string, PromptSummary>()
  for (const prompt of ai.prompts) {
    const current = map.get(prompt.key)
    const shouldReplace =
      !current
      || (prompt.is_active && !current.is_active)
      || (!current.is_active && !prompt.is_active && prompt.version > current.version)
    if (shouldReplace) map.set(prompt.key, prompt)
  }
  return [...map.values()].sort((a, b) => a.key.localeCompare(b.key))
})

function formatDate(value: string): string {
  return new Date(value).toLocaleString('zh-CN', {
    month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
  })
}

function capabilityLabel(key: string): string {
  return ({
    epub: 'EPUB 解析', pdf_text: '文本型 PDF', pdf_ocr: '扫描版文字识别',
    docx: 'DOCX 解析', txt: 'TXT 解析', fts5: '全文检索',
    sync: '多设备同步', ai: 'AI 服务', backup: '数据备份',
  } as Record<string, string>)[key] || key
}

function providerKindLabel(kind: string): string {
  return ({
    openai_compatible: 'OpenAI 兼容',
    openai: 'OpenAI',
    ollama: 'Ollama',
  } as Record<string, string>)[kind] || kind
}

function backendModeLabel(mode?: string): string {
  if (!mode) return '未知'
  return ({ embedded: '内嵌', server: '服务端' } as Record<string, string>)[mode] || mode
}

function promptDisplayName(name: string): string {
  return name.replace(/（Balanced）/g, '（均衡）')
}

function openProviderDialog(provider?: AIProvider) {
  editingProvider.value = provider || null
  providerForm.name = provider?.name || ''
  providerForm.kind = provider?.kind || 'openai_compatible'
  providerForm.base_url = provider?.base_url || ''
  providerForm.api_key = ''
  providerForm.clear_api_key = false
  providerForm.notes = provider?.notes || ''
  providerForm.enabled = provider?.enabled ?? true
  providerDialog.value = true
}

async function saveProvider() {
  savingProvider.value = true
  try {
    if (editingProvider.value) {
      await aiApi.updateProvider(editingProvider.value.id, {
        name: providerForm.name,
        kind: providerForm.kind,
        base_url: providerForm.base_url,
        api_key: providerForm.api_key || undefined,
        clear_api_key: providerForm.clear_api_key,
        notes: providerForm.notes,
        enabled: providerForm.enabled,
      })
    } else {
      await aiApi.createProvider({
        name: providerForm.name,
        kind: providerForm.kind,
        base_url: providerForm.base_url,
        api_key: providerForm.api_key || undefined,
        notes: providerForm.notes,
        enabled: providerForm.enabled,
      })
    }
    providerDialog.value = false
    app.notify('服务商配置已保存')
    await refreshAi()
  } finally {
    savingProvider.value = false
  }
}

async function toggleProvider(provider: AIProvider, enabled: boolean) {
  await aiApi.updateProvider(provider.id, { enabled })
  await refreshAi()
}

async function testProvider(provider: AIProvider) {
  testingProvider.value = provider.id
  try {
    const result = await aiApi.testProvider(provider.id)
    app.notify(`连接成功：${result.model} · ${result.latency_ms} 毫秒`)
  } finally {
    testingProvider.value = ''
  }
}

function deleteProvider(provider: AIProvider) {
  confirmDialog.title = '删除服务商？'
  confirmDialog.text = `将停用「${provider.name}」及其下的模型。已有译文与知识数据不会删除。`
  confirmDialog.action = async () => {
    await aiApi.deleteProvider(provider.id)
    app.notify('服务商已停用')
    await refreshAi()
  }
  confirmDialog.open = true
}

function openModelDialog(model?: AIModel) {
  editingModel.value = model || null
  modelForm.provider_id = model?.provider_id || ai.providers[0]?.id || ''
  modelForm.name = model?.name || ''
  modelForm.display_name = model?.display_name || ''
  modelForm.context_window = model?.context_window || 8192
  modelForm.max_output_tokens = model?.max_output_tokens || 2048
  modelForm.timeout_seconds = model?.timeout_seconds || 120
  modelForm.capabilities = [...(model?.capabilities || ['translation', 'chat'])]
  modelForm.supports_json = model?.supports_json ?? true
  modelForm.is_default_translation = model?.is_default_translation ?? false
  modelForm.is_default_chat = model?.is_default_chat ?? false
  modelForm.enabled = model?.enabled ?? true
  modelDialog.value = true
}

async function saveModel() {
  savingModel.value = true
  try {
    if (editingModel.value) {
      await aiApi.updateModel(editingModel.value.id, {
        name: modelForm.name,
        display_name: modelForm.display_name,
        context_window: modelForm.context_window,
        max_output_tokens: modelForm.max_output_tokens,
        timeout_seconds: modelForm.timeout_seconds,
        capabilities: modelForm.capabilities,
        supports_json: modelForm.supports_json,
        is_default_translation: modelForm.is_default_translation,
        is_default_chat: modelForm.is_default_chat,
        enabled: modelForm.enabled,
      })
    } else {
      await aiApi.createModel({
        provider_id: modelForm.provider_id,
        name: modelForm.name,
        display_name: modelForm.display_name,
        context_window: modelForm.context_window,
        max_output_tokens: modelForm.max_output_tokens,
        timeout_seconds: modelForm.timeout_seconds,
        capabilities: modelForm.capabilities,
        supports_json: modelForm.supports_json,
        is_default_translation: modelForm.is_default_translation,
        is_default_chat: modelForm.is_default_chat,
        enabled: modelForm.enabled,
      })
    }
    modelDialog.value = false
    app.notify('模型配置已保存')
    await refreshAi()
  } finally {
    savingModel.value = false
  }
}

async function toggleModel(model: AIModel, field: 'enabled', value: boolean) {
  await aiApi.updateModel(model.id, { [field]: value })
  await refreshAi()
}

function deleteModel(model: AIModel) {
  confirmDialog.title = '删除模型？'
  confirmDialog.text = `将停用「${model.display_name}」。已经生成的译文不会受影响。`
  confirmDialog.action = async () => {
    await aiApi.deleteModel(model.id)
    app.notify('模型已停用')
    await refreshAi()
  }
  confirmDialog.open = true
}

async function refreshAi() {
  await ai.load()
  await app.loadInfo()
}

async function loadPrompt(key: string) {
  promptKey.value = key
  promptDetail.value = await aiApi.prompt(key)
}

function openPromptDialog() {
  promptForm.name = `${promptDetail.value?.active.name || promptKey.value} 修订版`
  promptForm.description = ''
  promptForm.variables = ''
  promptForm.template = promptDetail.value?.active.template || ''
  promptDialog.value = true
}

async function savePrompt() {
  savingPrompt.value = true
  try {
    const variables = promptForm.variables
      .split(/[,，]/).map((item) => item.trim()).filter(Boolean)
    await aiApi.createPromptVersion(promptKey.value, {
      name: promptForm.name,
      description: promptForm.description || undefined,
      variables,
      template: promptForm.template,
    })
    promptDialog.value = false
    app.notify('提示词新版本已创建并启用')
    await loadPrompt(promptKey.value)
    await ai.load()
  } finally {
    savingPrompt.value = false
  }
}

async function activatePrompt(version: number) {
  await aiApi.activatePrompt(promptKey.value, version)
  app.notify(`已启用提示词 v${version}`)
  await loadPrompt(promptKey.value)
  await ai.load()
}

async function saveApiBase() {
  reconnecting.value = true
  try {
    app.updateApiBase(apiBaseForm.value.trim())
    await app.initialize()
    await refreshAi()
    if (app.backendOnline) app.notify('已重新连接后端')
  } finally {
    reconnecting.value = false
  }
}

async function copyDataDir() {
  if (!app.info?.data_dir) return
  await navigator.clipboard.writeText(app.info.data_dir)
  app.notify('数据目录已复制')
}

async function submitAuth() {
  authLoading.value = true
  authError.value = ''
  try {
    const result = authMode.value === 'login'
      ? await systemApi.login(authForm.username, authForm.password)
      : await systemApi.register(authForm.username, authForm.password, authForm.displayName)
    setToken(result.token)
    app.authenticated = true
    app.username = result.user.username
    app.notify('登录成功')
    await app.initialize()
    await loadDevices()
    await loadSyncStatus()
  } catch (error) {
    authError.value = error instanceof Error ? error.message : '登录失败'
  } finally {
    authLoading.value = false
  }
}

function logout() {
  setToken(null)
  app.authenticated = false
  app.username = ''
  app.notify('已退出登录')
}

async function loadDevices() {
  try {
    devices.value = await systemApi.devices()
  } catch {
    devices.value = []
  }
}

async function loadSyncStatus() {
  try {
    syncStatus.value = await syncApi.status(app.deviceId)
  } catch {
    syncStatus.value = null
  }
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`
}

async function loadBackups() {
  try {
    backups.value = await systemApi.backups()
  } catch {
    backups.value = []
  }
}

async function createBackup() {
  creatingBackup.value = true
  try {
    const backup = await systemApi.createBackup()
    app.notify(`备份已创建：${backup.filename}`)
    await loadBackups()
  } finally {
    creatingBackup.value = false
  }
}

async function downloadBackup(filename: string) {
  try {
    const blob = await systemApi.downloadBackup(filename)
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = filename
    anchor.click()
    URL.revokeObjectURL(url)
  } catch (error) {
    app.notify(error instanceof Error ? error.message : '备份下载失败', 'error')
  }
}

async function runConfirm() {
  confirmDialog.loading = true
  try {
    await confirmDialog.action()
    confirmDialog.open = false
  } finally {
    confirmDialog.loading = false
  }
}

watch(tab, async (value) => {
  if (value === 'prompts' && !promptDetail.value) {
    const first = promptGroups.value[0]
    if (first) await loadPrompt(first.key)
  }
  if (value === 'service') {
    await loadDevices()
    await loadBackups()
    if (app.info?.capabilities.sync) await loadSyncStatus()
  }
})

onMounted(async () => {
  apiBaseForm.value = app.baseUrl
  if (!ai.loaded) await ai.load()
  if (!app.info) await app.loadInfo()
  if (promptGroups.value.length) await loadPrompt(promptGroups.value[0].key)
  if (getToken()) {
    try {
      const me = await systemApi.me()
      app.authenticated = Boolean(me.authenticated)
      app.username = me.user?.username || ''
    } catch {
      app.authenticated = false
    }
  }
})
</script>

<style scoped>
.settings-page {
  max-width: 1280px;
}
.settings-tabs {
  border-bottom: 1px solid rgba(var(--v-theme-on-surface), 0.09);
  margin-bottom: 26px;
}
.tab-content {
  max-width: 1100px;
}
.section-head {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 20px;
  margin-bottom: 14px;
  flex-wrap: wrap;
}
.models-head {
  margin-top: 36px;
}
.section-title {
  font-size: 1.3rem;
  font-weight: 650;
}
.section-desc {
  font-size: 0.78rem;
  color: rgba(var(--v-theme-on-surface), 0.5);
  margin-top: 4px;
  line-height: 1.6;
  max-width: 680px;
}
.provider-list,
.model-list {
  display: flex;
  flex-direction: column;
  gap: 9px;
}
.provider-card,
.model-card {
  padding: 13px 16px;
  background: rgba(var(--v-theme-surface), 0.68);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.065);
}
.provider-main,
.model-main {
  display: flex;
  align-items: center;
  gap: 12px;
}
.provider-icon {
  width: 38px;
  height: 38px;
  border-radius: 11px;
  display: grid;
  place-items: center;
  background: rgba(var(--v-theme-primary), 0.08);
  color: rgb(var(--v-theme-primary));
  flex-shrink: 0;
}
.provider-body,
.model-body {
  flex: 1;
  min-width: 0;
}
.provider-name-row,
.model-title-row {
  display: flex;
  align-items: center;
  gap: 7px;
  flex-wrap: wrap;
}
.provider-name,
.model-name {
  font-size: 0.96rem;
  font-weight: 650;
}
.provider-url {
  font-size: 0.68rem;
  color: rgba(var(--v-theme-on-surface), 0.46);
  margin-top: 3px;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.model-meta {
  font-size: 0.67rem;
  color: rgba(var(--v-theme-on-surface), 0.42);
  margin-top: 4px;
}
.model-capabilities {
  display: flex;
  gap: 4px;
  margin-top: 6px;
}
.prompt-layout {
  display: grid;
  grid-template-columns: 270px minmax(0, 1fr);
  gap: 14px;
  align-items: start;
}
.prompt-list-card {
  padding: 8px;
  background: rgba(var(--v-theme-surface), 0.68);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.065);
}
.prompt-item {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 9px 10px;
  border: 0;
  border-radius: 9px;
  background: transparent;
  color: inherit;
  text-align: left;
  cursor: pointer;
}
.prompt-item:hover {
  background: rgba(var(--v-theme-primary), 0.045);
}
.prompt-item.active {
  background: rgba(var(--v-theme-primary), 0.08);
}
.prompt-item-icon {
  width: 27px;
  height: 27px;
  border-radius: 8px;
  background: rgba(var(--v-theme-secondary), 0.08);
  color: rgb(var(--v-theme-secondary));
  display: grid;
  place-items: center;
}
.prompt-item-title {
  font-size: 0.8rem;
  font-weight: 600;
}
.prompt-item-key {
  font-size: 0.63rem;
  color: rgba(var(--v-theme-on-surface), 0.4);
  margin-top: 2px;
  font-family: ui-monospace, monospace;
}
.prompt-detail-card {
  padding: 20px;
  background: rgba(var(--v-theme-surface), 0.68);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.065);
}
.prompt-detail-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 20px;
}
.prompt-detail-title {
  font-size: 1.25rem;
  font-weight: 650;
  margin-top: 3px;
}
.prompt-template {
  margin-top: 15px;
  padding: 16px;
  background: rgba(var(--v-theme-on-surface), 0.035);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.07);
  border-radius: 10px;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 0.73rem;
  line-height: 1.75;
  white-space: pre-wrap;
  color: rgba(var(--v-theme-on-surface), 0.7);
  max-height: 420px;
  overflow-y: auto;
}
.prompt-versions {
  margin-top: 22px;
  padding-top: 16px;
  border-top: 1px dashed rgba(var(--v-theme-on-surface), 0.1);
}
.version-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 8px 0;
  border-bottom: 1px dashed rgba(var(--v-theme-on-surface), 0.06);
}
.version-name {
  font-size: 0.78rem;
  font-weight: 550;
}
.active-label {
  font-size: 0.62rem;
  color: rgb(var(--v-theme-success));
  margin-left: 7px;
}
.prompt-empty {
  padding: 80px 20px;
  text-align: center;
  color: rgba(var(--v-theme-on-surface), 0.4);
  font-size: 0.82rem;
}
.reading-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 14px;
  align-items: start;
}
.settings-card {
  padding: 20px;
  background: rgba(var(--v-theme-surface), 0.68);
  border: 1px solid rgba(var(--v-theme-on-surface), 0.065);
}
.theme-options {
  display: flex;
  gap: 9px;
  margin-top: 10px;
  flex-wrap: wrap;
}
.theme-option {
  border: 1px solid rgba(var(--v-theme-on-surface), 0.12);
  border-radius: 11px;
  padding: 8px;
  background: transparent;
  color: inherit;
  cursor: pointer;
  font-size: 0.7rem;
  display: flex;
  flex-direction: column;
  gap: 5px;
  align-items: center;
  min-width: 88px;
}
.theme-option.active {
  border-color: rgba(var(--v-theme-primary), 0.55);
  box-shadow: 0 0 0 2px rgba(var(--v-theme-primary), 0.12);
}
.theme-preview {
  width: 64px;
  height: 42px;
  border-radius: 6px;
  padding: 8px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.theme-option.paper .theme-preview { background: #f3ecdf; }
.theme-option.light .theme-preview { background: #ffffff; border: 1px solid #e4e4e0; }
.theme-option.dark .theme-preview { background: #18211d; }
.theme-line {
  height: 2px;
  border-radius: 2px;
  background: rgba(50, 45, 38, 0.35);
}
.theme-option.dark .theme-line { background: rgba(230, 225, 210, 0.35); }
.theme-line.short { width: 65%; }
.setting-line {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 11px 0;
  border-bottom: 1px dashed rgba(var(--v-theme-on-surface), 0.08);
  font-size: 0.78rem;
}
.setting-control {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 200px;
}
.value {
  width: 38px;
  text-align: right;
  font-size: 0.68rem;
  color: rgba(var(--v-theme-on-surface), 0.46);
}
.setting-hint {
  font-size: 0.72rem;
  line-height: 1.72;
  color: rgba(var(--v-theme-on-surface), 0.46);
  margin-top: 14px;
}
.preview-card {
  background:
    radial-gradient(at 80% 20%, rgba(154, 106, 52, 0.05), transparent 50%),
    rgba(var(--v-theme-surface), 0.68);
}
.preview-text {
  margin-top: 18px;
  color: rgba(var(--v-theme-on-surface), 0.78);
}
.preview-translation {
  margin-top: 16px;
  line-height: 1.9;
  color: rgba(var(--v-theme-on-surface), 0.52);
}
.service-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 14px;
  align-items: start;
}
.kv-row {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 14px;
  padding: 8px 0;
  border-bottom: 1px dashed rgba(var(--v-theme-on-surface), 0.07);
  font-size: 0.76rem;
  color: rgba(var(--v-theme-on-surface), 0.48);
}
.kv-row strong {
  font-weight: 500;
  color: rgba(var(--v-theme-on-surface), 0.74);
  text-align: right;
}
.kv-row strong.ok { color: rgb(var(--v-theme-success)); }
.kv-row strong.bad { color: rgb(var(--v-theme-error)); }
.kv-row strong.warn { color: rgb(var(--v-theme-warning)); }
.data-dir-row {
  align-items: center;
}
.data-dir {
  display: flex;
  align-items: center;
  gap: 4px;
  max-width: 65%;
}
.data-dir code,
.device-id {
  font-family: ui-monospace, monospace;
  font-size: 0.64rem;
  color: rgba(var(--v-theme-on-surface), 0.55);
  overflow: hidden;
  text-overflow: ellipsis;
  word-break: break-all;
}
.action-line {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  margin-top: 12px;
  flex-wrap: wrap;
}
.account-badge {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-top: 10px;
}
.account-avatar {
  width: 40px;
  height: 40px;
  border-radius: 12px;
  display: grid;
  place-items: center;
  background: rgba(var(--v-theme-primary), 0.09);
  color: rgb(var(--v-theme-primary));
  font-weight: 650;
}
.account-name {
  font-size: 0.9rem;
  font-weight: 600;
}
.device-list {
  margin-top: 10px;
}
.device-row {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 7px 0;
  font-size: 0.74rem;
  border-bottom: 1px dashed rgba(var(--v-theme-on-surface), 0.06);
}
.device-row .tiny {
  margin-left: auto;
}
.cap-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 5px 20px;
  margin-top: 10px;
}
.cap-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 5px 0;
  font-size: 0.73rem;
  color: rgba(var(--v-theme-on-surface), 0.6);
}
.backup-list {
  margin-top: 12px;
  border-top: 1px dashed rgba(var(--v-theme-on-surface), 0.08);
}
.backup-row {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 0;
  border-bottom: 1px dashed rgba(var(--v-theme-on-surface), 0.06);
}
.backup-main {
  flex: 1;
  min-width: 0;
}
.backup-name {
  font-size: 0.7rem;
  font-family: ui-monospace, monospace;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.prompt-editor :deep(textarea) {
  font-family: ui-monospace, monospace;
  font-size: 0.76rem;
}
@media (max-width: 900px) {
  .reading-grid,
  .service-grid,
  .prompt-layout {
    grid-template-columns: 1fr;
  }
  .provider-main,
  .model-main {
    flex-wrap: wrap;
  }
}
</style>
