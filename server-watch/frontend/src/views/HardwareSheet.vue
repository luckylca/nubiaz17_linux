<script setup lang="ts">
import { computed } from 'vue'
import { useMonitorStore } from '../stores/monitor'
import { formatBytes, formatKB } from '../composables/format'
import GlassSheet from '../components/GlassSheet.vue'

defineProps<{ open: boolean }>()
defineEmits<{ close: [] }>()

const store = useMonitorStore()
const mem = computed(() => store.snap?.memory)
</script>

<template>
  <GlassSheet :open="open" title="Hardware" wide @close="$emit('close')">
    <h3 class="section">Memory</h3>
    <div class="fact-grid">
      <div class="fact"><div class="fact-value">{{ mem ? formatKB(mem.total_kb) : '—' }}</div><div class="t-label">Total</div></div>
      <div class="fact"><div class="fact-value">{{ mem ? formatKB(mem.used_kb) : '—' }}</div><div class="t-label">Used</div></div>
      <div class="fact"><div class="fact-value">{{ mem ? formatKB(mem.avail_kb) : '—' }}</div><div class="t-label">Available</div></div>
      <div class="fact"><div class="fact-value">{{ mem ? formatKB(mem.cached_kb) : '—' }}</div><div class="t-label">Cached</div></div>
      <div class="fact"><div class="fact-value">{{ mem ? formatKB(mem.swap_total_kb) : '—' }}</div><div class="t-label">Swap</div></div>
      <div class="fact"><div class="fact-value">{{ mem ? formatKB(mem.swap_used_kb) : '—' }}</div><div class="t-label">Swap Used</div></div>
    </div>

    <h3 class="section">Storage</h3>
    <div v-for="s in store.snap?.storage ?? []" :key="s.mount" class="disk-row">
      <div class="disk-head">
        <span class="disk-mount">{{ s.mount }}</span>
        <span class="disk-dev t-tertiary">{{ s.device }}</span>
        <span class="disk-pct">{{ s.used_pct.toFixed(0) }}%</span>
      </div>
      <div class="meter"><div class="meter-fill" :style="{ width: s.used_pct + '%' }"></div></div>
      <div class="disk-sub t-tertiary">
        {{ formatBytes(s.used_b) }} used · {{ formatBytes(s.avail_b) }} free of {{ formatBytes(s.total_b) }}
      </div>
    </div>

    <template v-if="store.snap?.thermal?.length">
      <h3 class="section">Thermals</h3>
      <div class="fact-grid">
        <div v-for="z in store.snap.thermal" :key="z.name" class="fact">
          <div class="fact-value">{{ z.temp_c.toFixed(1) }}°C</div>
          <div class="t-label">{{ z.name }}</div>
        </div>
      </div>
    </template>
  </GlassSheet>
</template>

<style scoped>
.section {
  font-size: 0.78rem;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--text-tertiary);
  font-weight: 500;
  margin: 16px 0 8px;
  text-align: center;
}
.fact-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px 10px;
}
.fact { text-align: center; }
.fact-value { font-size: 1.05rem; font-weight: 500; padding-bottom: 3px; }
.disk-row { padding: 8px 4px; }
.disk-head { display: flex; align-items: baseline; gap: 12px; }
.disk-mount { font-weight: 500; }
.disk-dev { font-size: 0.75rem; flex: 1; }
.disk-pct { font-size: 0.9rem; color: var(--text-secondary); }
.meter {
  height: 5px;
  border-radius: 3px;
  background: rgba(255, 255, 255, 0.08);
  margin-top: 8px;
  overflow: hidden;
}
.meter-fill {
  height: 100%;
  border-radius: 3px;
  background: var(--accent);
}
.disk-sub { font-size: 0.75rem; padding-top: 6px; }
</style>
