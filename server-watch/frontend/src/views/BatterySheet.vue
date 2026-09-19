<script setup lang="ts">
import { computed } from 'vue'
import { useMonitorStore } from '../stores/monitor'
import GlassSheet from '../components/GlassSheet.vue'

defineProps<{ open: boolean }>()
defineEmits<{ close: [] }>()

const store = useMonitorStore()
const batt = computed(() => store.snap?.battery)

const statusText = computed(() => {
  const s = batt.value?.status
  if (!s) return ''
  return s
})
</script>

<template>
  <GlassSheet :open="open" title="Battery" @close="$emit('close')">
    <div v-if="!batt?.present" class="empty t-secondary">No battery detected</div>
    <template v-else>
      <div class="batt-hero">
        <div class="hero-value">{{ batt.capacity ?? '—' }}<span class="unit">%</span></div>
        <div class="hero-status">{{ statusText }}</div>
      </div>

      <div class="fact-grid">
        <div v-if="batt.temp_c != null" class="fact">
          <div class="fact-value">{{ batt.temp_c.toFixed(1) }}°C</div>
          <div class="t-label">Temperature</div>
        </div>
        <div v-if="batt.voltage_v != null" class="fact">
          <div class="fact-value">{{ batt.voltage_v.toFixed(2) }} V</div>
          <div class="t-label">Voltage</div>
        </div>
        <div v-if="batt.current_a != null" class="fact">
          <div class="fact-value">{{ batt.current_a.toFixed(2) }} A</div>
          <div class="t-label">Current</div>
        </div>
        <div v-if="batt.power_w != null" class="fact">
          <div class="fact-value">{{ batt.power_w.toFixed(2) }} W</div>
          <div class="t-label">Power</div>
        </div>
        <div v-if="batt.health != null" class="fact">
          <div class="fact-value">{{ batt.health.toFixed(0) }}%</div>
          <div class="t-label">Health</div>
        </div>
        <div v-if="batt.cycle_count != null" class="fact">
          <div class="fact-value">{{ batt.cycle_count }}</div>
          <div class="t-label">Cycles</div>
        </div>
        <div v-if="batt.charge_full_ah != null" class="fact">
          <div class="fact-value">{{ (batt.charge_full_ah * 1000).toFixed(0) }} mAh</div>
          <div class="t-label">Full Charge</div>
        </div>
        <div v-if="batt.charge_design_ah != null" class="fact">
          <div class="fact-value">{{ (batt.charge_design_ah * 1000).toFixed(0) }} mAh</div>
          <div class="t-label">Design</div>
        </div>
        <div v-if="batt.technology" class="fact">
          <div class="fact-value">{{ batt.technology }}</div>
          <div class="t-label">Technology</div>
        </div>
      </div>
    </template>
  </GlassSheet>
</template>

<style scoped>
.batt-hero {
  display: flex;
  align-items: baseline;
  justify-content: center;
  gap: 16px;
  padding: 6px 0 18px;
}
.hero-value { font-size: 3.4rem; font-weight: 300; }
.unit { font-size: 1.5rem; color: var(--text-secondary); margin-left: 2px; }
.hero-status { font-size: 1.1rem; color: var(--text-secondary); }
.fact-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 18px 10px;
  padding: 8px 0;
}
.fact { text-align: center; }
.fact-value { font-size: 1.05rem; font-weight: 500; padding-bottom: 3px; }
.empty { text-align: center; padding: 40px 0; }
</style>
