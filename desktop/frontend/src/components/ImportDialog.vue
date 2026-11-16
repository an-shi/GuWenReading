<template>
  <v-dialog v-model="model" max-width="620" persistent>
    <v-card class="import-card">
      <div class="import-head">
        <div>
          <div class="section-label">导入新书</div>
          <div class="import-title serif">导入古籍</div>
        </div>
        <v-btn icon="mdi-close" variant="text" :disabled="library.importing" @click="close" />
      </div>

      <v-card-text class="pt-2">
        <v-file-input
          v-model="file"
          label="选择文件"
          accept=".txt,.epub,.docx,.pdf"
          prepend-icon="mdi-book-plus-outline"
          show-size
          :disabled="library.importing"
          hint="支持 TXT、EPUB、DOCX、文本型 PDF，原始文件会完整保留"
          persistent-hint
        />

        <v-row class="mt-4" dense>
          <v-col cols="12" sm="7">
            <v-text-field v-model="form.title" label="书名（可选）" :disabled="library.importing" />
          </v-col>
          <v-col cols="12" sm="5">
            <v-text-field v-model="form.author" label="作者（可选）" :disabled="library.importing" />
          </v-col>
          <v-col cols="12" sm="5">
            <v-text-field v-model="form.dynasty" label="朝代（可选）" :disabled="library.importing" />
          </v-col>
          <v-col cols="12" sm="7">
            <v-text-field v-model="form.category" label="分类（可选）" placeholder="史书 / 经部 / 集部" :disabled="library.importing" />
          </v-col>
          <v-col cols="12">
            <v-text-field
              v-model="form.tags"
              label="标签（逗号分隔）"
              placeholder="正史, 纪传体"
              :disabled="library.importing"
            />
          </v-col>
        </v-row>

        <v-alert
          v-if="errorMessage"
          type="error"
          variant="tonal"
          density="compact"
          class="mt-2"
          :text="errorMessage"
        />

        <v-progress-linear v-if="library.importing" indeterminate color="primary" rounded class="mt-4" />
        <div v-if="library.importing" class="importing-hint">正在提取文本、识别章节并切分句子…</div>
      </v-card-text>

      <v-card-actions class="px-6 pb-5">
        <v-spacer />
        <v-btn variant="text" :disabled="library.importing" @click="close">取消</v-btn>
        <v-btn color="primary" :loading="library.importing" :disabled="!file" @click="submit">
          导入书籍
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useLibraryStore } from '@/stores/library'
import type { Book } from '@/api/types'

const model = defineModel<boolean>({ default: false })
const emit = defineEmits<{ imported: [book: Book] }>()
const library = useLibraryStore()

const file = ref<File | File[] | null>(null)
const errorMessage = ref('')
const form = reactive({ title: '', author: '', dynasty: '', category: '', tags: '' })

function close() {
  if (library.importing) return
  model.value = false
  errorMessage.value = ''
  file.value = null
  form.title = ''
  form.author = ''
  form.dynasty = ''
  form.category = ''
  form.tags = ''
}

async function submit() {
  const selected = Array.isArray(file.value) ? file.value[0] : file.value
  if (!selected) return
  errorMessage.value = ''
  try {
    const book = await library.importBook({
      file: selected,
      title: form.title || undefined,
      author: form.author || undefined,
      dynasty: form.dynasty || undefined,
      category: form.category || undefined,
      tags: form.tags || undefined,
    })
    model.value = false
    file.value = null
    emit('imported', book)
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : '导入失败'
  }
}
</script>

<style scoped>
.import-card {
  background: rgb(var(--v-theme-surface));
}
.import-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  padding: 24px 26px 8px;
}
.import-title {
  font-size: 1.55rem;
  font-weight: 650;
  margin-top: 4px;
}
.importing-hint {
  margin-top: 8px;
  font-size: 0.78rem;
  color: rgba(var(--v-theme-on-surface), 0.52);
}
</style>
