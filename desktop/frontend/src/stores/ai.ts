import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import { aiApi } from '@/api/ai'
import type { AIModel, AIProvider, PromptSummary } from '@/api/types'

export const useAiStore = defineStore('ai', () => {
  const providers = ref<AIProvider[]>([])
  const models = ref<AIModel[]>([])
  const prompts = ref<PromptSummary[]>([])
  const loading = ref(false)
  const loaded = ref(false)

  const translationModel = computed(() =>
    models.value.find((model) => model.is_default_translation && model.enabled)
    || models.value.find((model) => model.enabled),
  )
  const chatModel = computed(() =>
    models.value.find((model) => model.is_default_chat && model.enabled)
    || models.value.find((model) => model.enabled),
  )
  const configured = computed(() => Boolean(translationModel.value && chatModel.value))
  const enabledModels = computed(() => models.value.filter((model) => model.enabled))

  async function load() {
    loading.value = true
    try {
      const [providerRows, modelRows, promptRows] = await Promise.all([
        aiApi.providers(), aiApi.models(), aiApi.prompts(),
      ])
      providers.value = providerRows
      models.value = modelRows
      prompts.value = promptRows
      loaded.value = true
    } finally {
      loading.value = false
    }
  }

  function providerName(providerId: string): string {
    return providers.value.find((provider) => provider.id === providerId)?.name || '未知服务商'
  }

  return {
    providers, models, prompts, loading, loaded,
    translationModel, chatModel, configured, enabledModels, providerName, load,
  }
})
