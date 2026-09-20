<script setup lang="ts">
defineProps<{
  text: string
  level: 'normal' | 'warning' | 'critical'
}>()
</script>

<template>
  <button class="status-pill pressable">
    <span class="dot" :class="level"></span>
    <span class="pill-text">{{ text }}</span>
  </button>
</template>

<style scoped>
/* Sizes are real device pixels inside the fixed 1920x1080 design space. */
.status-pill {
  display: inline-flex;
  align-items: center;
  gap: 14px;
  padding: 18px 34px;
  border: 1px solid rgba(255, 255, 255, 0.09);
  border-radius: var(--radius-pill);
  background: #0c0c0e;
  color: var(--text-secondary);
  font-family: inherit;
  font-size: 23px;
  font-weight: 550;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  white-space: nowrap;
}
.status-pill:active { background: #1a1a1c; }
.dot {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: var(--status-normal);
}
.dot.warning {
  background: var(--status-warning);
}
.dot.critical {
  background: var(--status-critical);
}
.status-pill.warning { color: var(--status-warning); }
.status-pill.critical { color: var(--status-critical); }
</style>
