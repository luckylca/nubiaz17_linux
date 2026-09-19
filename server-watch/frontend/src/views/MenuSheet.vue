<script setup lang="ts">
import GlassSheet from '../components/GlassSheet.vue'

defineProps<{ open: boolean }>()
const emit = defineEmits<{ close: []; open: [name: string] }>()

const items = [
  { key: 'overview', label: 'Overview', desc: 'All systems at a glance' },
  { key: 'hardware', label: 'Hardware', desc: 'Thermals · Memory · Storage' },
  { key: 'processes', label: 'Processes', desc: 'Running processes' },
  { key: 'docker', label: 'Docker', desc: 'Containers' },
  { key: 'network', label: 'Network', desc: 'Interfaces · Wi-Fi · Bluetooth' },
  { key: 'settings', label: 'Settings', desc: 'Display · Alerts · Thresholds' },
]

function pick(key: string) {
  emit('close')
  emit('open', key)
}
</script>

<template>
  <GlassSheet :open="open" @close="$emit('close')">
    <div class="menu">
      <button v-for="i in items" :key="i.key" class="menu-item pressable" @click="pick(i.key)">
        <span class="menu-label">{{ i.label }}</span>
        <span class="menu-desc">{{ i.desc }}</span>
      </button>
    </div>
  </GlassSheet>
</template>

<style scoped>
.menu { display: flex; flex-direction: column; gap: 6px; padding: 6px 0; }
.menu-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  min-height: 60px;
  padding: 10px 20px;
  border-radius: var(--radius-medium);
  background: rgba(255, 255, 255, 0.05);
  border: 0.5px solid rgba(255, 255, 255, 0.07);
  color: var(--text-primary);
  font-family: inherit;
}
.menu-label { font-size: 1.05rem; font-weight: 500; }
.menu-desc { font-size: 0.8rem; color: var(--text-tertiary); }
</style>
