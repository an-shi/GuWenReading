<template>
  <div class="empty-state">
    <div class="empty-glyph serif">{{ glyph }}</div>
    <div class="empty-title">{{ title }}</div>
    <div class="empty-text">{{ text }}</div>
    <slot />
  </div>
</template>

<script setup lang="ts">
withDefaults(defineProps<{
  title: string
  text?: string
  glyph?: string
}>(), {
  glyph: '卷',
  text: '',
})
</script>

<style scoped>
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  padding: 76px 24px;
  color: rgba(var(--v-theme-on-surface), 0.52);
}
.empty-glyph {
  width: 74px;
  height: 74px;
  border-radius: 22px;
  display: grid;
  place-items: center;
  font-size: 1.9rem;
  color: rgba(var(--v-theme-primary), 0.72);
  background: rgba(var(--v-theme-primary), 0.07);
  border: 1px solid rgba(var(--v-theme-primary), 0.12);
  margin-bottom: 20px;
}
.empty-title {
  font-family: "Noto Serif SC", "Songti SC", "SimSun", serif;
  font-size: 1.2rem;
  font-weight: 650;
  color: rgba(var(--v-theme-on-surface), 0.8);
}
.empty-text {
  max-width: 400px;
  margin-top: 8px;
  font-size: 0.86rem;
  line-height: 1.7;
}
</style>
