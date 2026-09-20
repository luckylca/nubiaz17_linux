<script setup lang="ts">
defineProps<{
  label: string
  value: string
  detail?: string
  foot?: string
  severity?: 'normal' | 'warning' | 'critical'
}>()

defineEmits<{ click: [] }>()
</script>

<template>
  <button class="metric-block pressable" :class="severity ?? 'normal'" @click="$emit('click')">
    <div class="metric-label">{{ label }}</div>
    <div class="metric-value">{{ value }}</div>
    <div v-if="detail" class="metric-detail">{{ detail }}</div>
    <div v-if="foot" class="metric-foot">{{ foot }}</div>
  </button>
</template>

<style scoped>
/* Sizes are real device pixels inside the fixed 1920x1080 design space. */
.metric-block {
  width: 100%;
  min-width: 0;
  min-height: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: 22px 28px;
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 30px;
  background: #0c0c0e;
  color: var(--text-primary);
  font-family: inherit;
  text-align: left;
  overflow: hidden;
}
.metric-block:active { background: #1a1a1c; }
.metric-label {
  margin-bottom: 12px;
  color: var(--text-tertiary);
  font-size: 21px;
  font-weight: 600;
  letter-spacing: 0.16em;
  text-transform: uppercase;
}
.metric-value {
  overflow: hidden;
  color: var(--text-primary);
  font-size: 74px;
  font-weight: 400;
  line-height: 1.04;
  letter-spacing: -0.02em;
  font-variant-numeric: tabular-nums;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.metric-detail {
  margin-top: 12px;
  overflow: hidden;
  color: var(--text-secondary);
  font-size: 27px;
  font-weight: 500;
  line-height: 1.2;
  font-variant-numeric: tabular-nums;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.metric-foot {
  margin-top: 7px;
  overflow: hidden;
  color: var(--text-tertiary);
  font-size: 22px;
  line-height: 1.2;
  letter-spacing: 0.02em;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.metric-block.warning .metric-value { color: var(--status-warning); }
.metric-block.critical .metric-value { color: var(--status-critical); }
</style>
