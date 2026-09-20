<script setup lang="ts">
defineProps<{
  primary: string
  secondary?: string
  label: string
  severity?: 'normal' | 'warning' | 'critical'
}>()
</script>

<template>
  <button class="complication glass pressable" :class="severity ?? 'normal'">
    <div class="comp-primary">{{ primary }}</div>
    <div v-if="secondary" class="comp-secondary">{{ secondary }}</div>
    <div class="comp-label">{{ label }}</div>
  </button>
</template>

<style scoped>
.complication {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  justify-content: center;
  gap: 1px;
  min-width: 148px;
  min-height: 76px;
  padding: 12px 20px;
  border-radius: var(--radius-medium);
  color: var(--text-primary);
  font-family: inherit;
  text-align: left;
}
.complication {
  background: transparent;
  border: 0;
  box-shadow: none;
}
.complication:active {
  background: #1c1c1e;
}
.comp-primary {
  font-size: 1.42rem;
  font-weight: 400;
  letter-spacing: 0.01em;
}
.comp-secondary {
  font-size: 0.82rem;
  color: var(--text-secondary);
  font-weight: 400;
}
.comp-label {
  font-size: 0.62rem;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: var(--text-tertiary);
  margin-top: 3px;
}

/* severity only shifts the primary value color — quiet by design */
.complication.warning .comp-primary { color: var(--status-warning); }
.complication.critical .comp-primary { color: var(--status-critical); }
.complication.warning,
.complication.critical {
  border-color: color-mix(in srgb, currentColor 30%, transparent);
}
</style>
