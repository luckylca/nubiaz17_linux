<script setup lang="ts">
import { watch } from 'vue'

const props = defineProps<{
  open: boolean
  title?: string
  wide?: boolean
}>()
const emit = defineEmits<{ close: [] }>()

// block touches leaking to the clock double-tap while a sheet is open
watch(
  () => props.open,
  (v) => {
    document.body.classList.toggle('sheet-open', v)
  }
)
</script>

<template>
  <Transition name="sheet">
    <div v-if="open" class="sheet-backdrop" @pointerdown.self="emit('close')">
      <div class="sheet glass glass-strong" :class="{ wide }" role="dialog">
        <div class="sheet-grabber" @pointerdown="emit('close')">
          <span class="grabber-bar"></span>
        </div>
        <header v-if="title" class="sheet-header">
          <h2>{{ title }}</h2>
        </header>
        <div class="sheet-body scroll-y">
          <slot />
        </div>
        <footer class="sheet-footer">
          <button class="close-btn pressable" @click="emit('close')">Close</button>
        </footer>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.sheet-backdrop {
  position: fixed;
  inset: 0;
  z-index: 40;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.78);
  padding: 4vh var(--safe-x);
}
.sheet {
  width: min(620px, 78vw);
  max-height: 84vh;
  display: flex;
  flex-direction: column;
  border-radius: var(--radius-large);
}
.sheet.wide {
  width: min(880px, 84vw);
}
.sheet-grabber {
  display: flex;
  justify-content: center;
  padding: 14px 0 6px;
  cursor: pointer;
  min-height: 30px;
}
.grabber-bar {
  width: 44px;
  height: 5px;
  border-radius: 3px;
  background: rgba(255, 255, 255, 0.28);
}
.sheet-header {
  padding: 2px 28px 10px;
  text-align: center;
}
.sheet-header h2 {
  margin: 0;
  font-size: 1.35rem;
  font-weight: 500;
  letter-spacing: 0.02em;
}
.sheet-body {
  flex: 1;
  padding: 6px 28px 12px;
  min-height: 0;
}
.sheet-footer {
  display: flex;
  justify-content: center;
  padding: 8px 0 18px;
}
.close-btn {
  min-width: 148px;
  min-height: 48px;
  border-radius: var(--radius-pill);
  border: 0.5px solid var(--glass-border-soft);
  background: rgba(255, 255, 255, 0.07);
  color: var(--text-secondary);
  font-family: inherit;
  font-size: 0.9rem;
  font-weight: 500;
  letter-spacing: 0.06em;
}
</style>
