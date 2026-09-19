<script setup lang="ts">
defineProps<{
  text: string
  level: 'normal' | 'warning' | 'critical'
}>()
</script>

<template>
  <button class="status-pill glass pressable">
    <span class="dot" :class="level"></span>
    <span class="pill-text">{{ text }}</span>
  </button>
</template>

<style scoped>
.status-pill {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  padding: 12px 26px;
  border-radius: var(--radius-pill);
  color: var(--text-secondary);
  font-family: inherit;
  font-size: 0.78rem;
  font-weight: 500;
  letter-spacing: 0.18em;
  text-transform: uppercase;
}
.dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--status-normal);
  box-shadow: 0 0 10px color-mix(in srgb, var(--status-normal) 60%, transparent);
}
.dot.warning {
  background: var(--status-warning);
  box-shadow: 0 0 10px color-mix(in srgb, var(--status-warning) 60%, transparent);
}
.dot.critical {
  background: var(--status-critical);
  box-shadow: 0 0 12px color-mix(in srgb, var(--status-critical) 70%, transparent);
}
.status-pill.warning { color: var(--status-warning); }
.status-pill.critical { color: var(--status-critical); }
</style>
