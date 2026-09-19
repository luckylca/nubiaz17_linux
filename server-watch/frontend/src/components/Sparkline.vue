<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    data: number[]
    width?: number
    height?: number
    max?: number
    color?: string
  }>(),
  { width: 260, height: 56, color: 'rgba(138, 180, 248, 0.85)' }
)

const points = computed(() => {
  const d = props.data
  if (!d || d.length < 2) return ''
  const max = props.max ?? Math.max(...d, 1)
  const step = props.width / (d.length - 1)
  return d
    .map((v, i) => {
      const x = i * step
      const y = props.height - Math.min(v / max, 1) * (props.height - 4) - 2
      return `${x.toFixed(1)},${y.toFixed(1)}`
    })
    .join(' ')
})

const fillPoints = computed(() =>
  points.value ? `0,${props.height} ${points.value} ${props.width},${props.height}` : ''
)
</script>

<template>
  <svg :width="width" :height="height" class="sparkline" :viewBox="`0 0 ${width} ${height}`">
    <defs>
      <linearGradient id="spark-fill" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" :stop-color="color" stop-opacity="0.28" />
        <stop offset="100%" :stop-color="color" stop-opacity="0.02" />
      </linearGradient>
    </defs>
    <polygon v-if="fillPoints" :points="fillPoints" fill="url(#spark-fill)" />
    <polyline
      v-if="points"
      :points="points"
      fill="none"
      :stroke="color"
      stroke-width="1.6"
      stroke-linejoin="round"
      stroke-linecap="round"
    />
  </svg>
</template>

<style scoped>
.sparkline {
  display: block;
  width: 100%;
  height: auto;
}
</style>
