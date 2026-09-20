<script setup lang="ts">
defineProps<{ time: string }>()
</script>

<template>
  <div class="digit-clock" aria-label="current time">{{ time }}</div>
</template>

<style scoped>
.digit-clock {
  display: flex;
  justify-content: center;
  align-items: baseline;
  font-weight: 300;
  line-height: 1;
  letter-spacing: 0.015em;
  color: var(--text-primary);
  font-variant-numeric: tabular-nums;
}
</style>
