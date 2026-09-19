<script setup lang="ts">
import { computed } from 'vue'
import { useMonitorStore } from '../stores/monitor'
import { formatBytes, formatKB } from '../composables/format'
import GlassSheet from '../components/GlassSheet.vue'
import Sparkline from '../components/Sparkline.vue'

defineProps<{ open: boolean }>()
defineEmits<{ close: [] }>()

const store = useMonitorStore()
const mem = computed(() => store.snap?.memory)
const root = computed(() => store.snap?.storage?.find((s) => s.mount === '/'))
</script>

<template>
  <GlassSheet :open="open" title="Overview" wide @close="$emit('close')">
    <div class="grid">
      <div class="card glass">
        <div class="card-title t-label">CPU</div>
        <div class="card-value">{{ store.snap?.cpu ? Math.round(store.snap.cpu.total) + '%' : '—' }}</div>
        <Sparkline :data="store.snap?.history?.cpu ?? []" :max="100" :height="40" />
        <div class="card-sub t-secondary">{{ store.snap?.soc_temp != null ? Math.round(store.snap.soc_temp) + '°C' : '' }}</div>
      </div>

      <div class="card glass">
        <div class="card-title t-label">Memory</div>
        <div class="card-value">
          {{ mem ? formatKB(mem.used_kb) : '—' }}
          <span class="card-unit">/ {{ mem ? formatKB(mem.total_kb) : '' }}</span>
        </div>
        <div class="meter"><div class="meter-fill" :style="{ width: (mem?.used_percent ?? 0) + '%' }"></div></div>
        <div class="card-sub t-secondary">{{ mem ? mem.used_percent.toFixed(0) + '% used' : '' }}</div>
      </div>

      <div class="card glass">
        <div class="card-title t-label">Storage</div>
        <div class="card-value">
          {{ root ? formatBytes(root.used_b) : '—' }}
          <span class="card-unit">/ {{ root ? formatBytes(root.total_b) : '' }}</span>
        </div>
        <div class="meter"><div class="meter-fill" :style="{ width: (root?.used_pct ?? 0) + '%' }"></div></div>
        <div class="card-sub t-secondary">{{ root ? root.used_pct.toFixed(0) + '% used' : '' }}</div>
      </div>

      <div class="card glass">
        <div class="card-title t-label">Battery</div>
        <div class="card-value">{{ store.snap?.battery?.capacity ?? '—' }}<span class="card-unit">%</span></div>
        <div class="card-sub t-secondary">{{ store.snap?.battery?.status ?? '' }}</div>
      </div>

      <div class="card glass">
        <div class="card-title t-label">Network</div>
        <div class="card-value small">
          ↓ {{ formatBytes(store.snap?.network?.rx_rate ?? 0, true) }}
        </div>
        <div class="card-value small">
          ↑ {{ formatBytes(store.snap?.network?.tx_rate ?? 0, true) }}
        </div>
        <div class="card-sub t-secondary">{{ store.snap?.wifi?.ssid ?? store.snap?.network?.name ?? '' }}</div>
      </div>

      <div class="card glass">
        <div class="card-title t-label">Docker</div>
        <div class="card-value">
          {{ store.snap?.docker?.available ? `${store.snap.docker.running} / ${store.snap.docker.total}` : 'N/A' }}
        </div>
        <div class="card-sub t-secondary">
          {{ store.snap?.docker?.available ? (store.snap.docker.healthy ? 'All healthy' : 'Attention needed') : 'Unavailable' }}
        </div>
      </div>
    </div>

    <div v-if="store.snap?.thermal?.length" class="thermals">
      <div class="t-label" style="text-align:center; padding-bottom: 8px">Thermals</div>
      <div class="thermal-chips">
        <span v-for="z in store.snap.thermal" :key="z.name" class="chip">
          {{ z.name }} <b>{{ z.temp_c.toFixed(0) }}°</b>
        </span>
      </div>
    </div>
  </GlassSheet>
</template>

<style scoped>
.grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 14px;
  padding: 4px 0;
}
.card {
  padding: 16px 18px;
  border-radius: var(--radius-medium);
  min-height: 108px;
}
.card-title { padding-bottom: 8px; }
.card-value { font-size: 1.5rem; font-weight: 400; }
.card-value.small { font-size: 1rem; padding: 1px 0; }
.card-unit { font-size: 0.85rem; color: var(--text-secondary); }
.card-sub { font-size: 0.78rem; padding-top: 8px; }
.meter {
  height: 5px;
  border-radius: 3px;
  background: rgba(255, 255, 255, 0.08);
  margin-top: 10px;
  overflow: hidden;
}
.meter-fill {
  height: 100%;
  border-radius: 3px;
  background: linear-gradient(90deg, rgba(138, 180, 248, 0.5), rgba(138, 180, 248, 0.9));
  transition: width 600ms var(--ease-out);
}
.thermals { padding-top: 16px; }
.thermal-chips {
  display: flex; flex-wrap: wrap; gap: 8px; justify-content: center;
}
.chip {
  padding: 6px 14px;
  border-radius: var(--radius-pill);
  background: rgba(255, 255, 255, 0.05);
  border: 0.5px solid rgba(255, 255, 255, 0.08);
  font-size: 0.78rem;
  color: var(--text-secondary);
}
.chip b { color: var(--text-primary); font-weight: 500; }
</style>
