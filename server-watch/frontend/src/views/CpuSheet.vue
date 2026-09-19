<script setup lang="ts">
import { computed } from 'vue'
import { useMonitorStore } from '../stores/monitor'
import GlassSheet from '../components/GlassSheet.vue'
import Sparkline from '../components/Sparkline.vue'

defineProps<{ open: boolean }>()
defineEmits<{ close: [] }>()

const store = useMonitorStore()
const cpu = computed(() => store.snap?.cpu)
const temp = computed(() => store.snap?.soc_temp)
const history = computed(() => store.snap?.history?.cpu ?? [])
</script>

<template>
  <GlassSheet :open="open" title="CPU" @close="$emit('close')">
    <div class="cpu-hero">
      <div class="hero-value">{{ cpu ? Math.round(cpu.total) : 0 }}<span class="unit">%</span></div>
      <div v-if="temp != null" class="hero-temp">{{ Math.round(temp) }}°C</div>
    </div>

    <div class="spark-wrap">
      <Sparkline :data="history" :max="100" :height="64" />
      <div class="spark-label t-label">Last 60 seconds</div>
    </div>

    <div v-if="cpu?.per_core?.length" class="cores">
      <div v-for="(v, i) in cpu.per_core" :key="i" class="core-row">
        <span class="core-name">Core {{ i }}</span>
        <div class="core-bar">
          <div class="core-fill" :style="{ width: Math.min(v, 100) + '%' }"></div>
        </div>
        <span class="core-pct">{{ Math.round(v) }}%</span>
      </div>
    </div>

    <div class="fact-grid">
      <div v-if="cpu?.freq_mhz?.length" class="fact">
        <div class="fact-value">{{ Math.round(cpu.freq_mhz.reduce((a, b) => a + b, 0) / cpu.freq_mhz.length) }} MHz</div>
        <div class="t-label">Avg Frequency</div>
      </div>
      <div class="fact">
        <div class="fact-value">{{ cpu?.load1?.toFixed(2) ?? '—' }}</div>
        <div class="t-label">Load 1m</div>
      </div>
      <div class="fact">
        <div class="fact-value">{{ cpu?.load5?.toFixed(2) ?? '—' }}</div>
        <div class="t-label">Load 5m</div>
      </div>
      <div v-if="cpu?.governor" class="fact">
        <div class="fact-value">{{ cpu.governor }}</div>
        <div class="t-label">Governor</div>
      </div>
      <div class="fact">
        <div class="fact-value">{{ cpu?.threads ?? '—' }}</div>
        <div class="t-label">Threads</div>
      </div>
      <div class="fact">
        <div class="fact-value">{{ cpu?.cores ?? '—' }}</div>
        <div class="t-label">Cores</div>
      </div>
    </div>
  </GlassSheet>
</template>

<style scoped>
.cpu-hero {
  display: flex;
  align-items: baseline;
  justify-content: center;
  gap: 18px;
  padding: 4px 0 10px;
}
.hero-value { font-size: 3.4rem; font-weight: 300; }
.unit { font-size: 1.5rem; color: var(--text-secondary); margin-left: 2px; }
.hero-temp { font-size: 1.4rem; color: var(--text-secondary); font-weight: 400; }
.spark-wrap { padding: 6px 0 16px; }
.spark-label { text-align: center; padding-top: 6px; }
.cores { padding-bottom: 14px; }
.core-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 5px 0;
  min-height: 30px;
}
.core-name { width: 64px; font-size: 0.82rem; color: var(--text-secondary); }
.core-bar {
  flex: 1;
  height: 5px;
  border-radius: 3px;
  background: rgba(255, 255, 255, 0.08);
  overflow: hidden;
}
.core-fill {
  height: 100%;
  border-radius: 3px;
  background: linear-gradient(90deg, rgba(138, 180, 248, 0.5), rgba(138, 180, 248, 0.9));
  transition: width 600ms var(--ease-out);
}
.core-pct { width: 44px; text-align: right; font-size: 0.82rem; color: var(--text-secondary); }
.fact-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 14px 10px;
  padding: 8px 0 4px;
}
.fact { text-align: center; }
.fact-value { font-size: 1.05rem; font-weight: 500; padding-bottom: 3px; }
</style>
