<script setup lang="ts">
import { computed } from 'vue'
import type { ContainerSummary } from '../stores/monitor'

const props = defineProps<{
  available: boolean
  containers?: ContainerSummary[]
  running: number
  total: number
}>()

defineEmits<{ click: [] }>()

const rows = computed(() =>
  [...(props.containers ?? [])].sort((a, b) => a.name.localeCompare(b.name))
)

/* Auto-layout: pick a column count that keeps every service on screen.
   The home dashboard must never scroll or hide containers. */
const cols = computed(() => {
  const n = rows.value.length
  if (n <= 2) return 1
  if (n <= 6) return 2
  if (n <= 12) return 3
  return 4
})
const rowCount = computed(() => Math.max(1, Math.ceil(rows.value.length / cols.value)))
/* Compress typography as the list grows so everything stays visible. */
const nameSize = computed(() => (rowCount.value <= 3 ? 36 : rowCount.value <= 5 ? 29 : 24))
const stateSize = computed(() => (rowCount.value <= 3 ? 24 : rowCount.value <= 5 ? 20 : 17))

const listStyle = computed(() => ({ gridTemplateColumns: `repeat(${cols.value}, minmax(0, 1fr))` }))
const nameStyle = computed(() => ({ fontSize: `${nameSize.value}px` }))
const stateStyle = computed(() => ({ fontSize: `${stateSize.value}px` }))

function stateText(c: ContainerSummary): string {
  if (c.state === 'running') {
    if (c.health === 'healthy') return 'HEALTHY'
    if (c.health === 'unhealthy') return 'UNHEALTHY'
    if (c.health === 'starting') return 'STARTING'
    return 'RUNNING'
  }
  if (c.state === 'restarting') return 'RESTARTING'
  if (c.state === 'paused') return 'PAUSED'
  if (c.state === 'exited') return 'EXITED'
  if (c.state === 'dead') return 'DEAD'
  return (c.state || 'UNKNOWN').toUpperCase()
}

function stateClass(c: ContainerSummary): string {
  if (c.state === 'running') {
    if (c.health === 'unhealthy') return 'critical'
    if (c.health === 'starting') return 'warning'
    return 'ok'
  }
  if (c.state === 'restarting' || c.state === 'paused') return 'warning'
  return 'critical'
}
</script>

<template>
  <button class="docker-overview pressable" @click="$emit('click')">
    <div class="docker-head">
      <div class="docker-title">DOCKER SERVICES</div>
      <div class="docker-count" :class="{ ok: available && running > 0 }">
        {{ available ? `${running} RUNNING · ${total} TOTAL` : 'UNAVAILABLE' }}
      </div>
    </div>

    <div v-if="!available" class="docker-empty">Docker daemon unavailable</div>
    <div v-else-if="rows.length === 0" class="docker-empty">No containers</div>
    <div v-else class="docker-list" :style="listStyle">
      <div v-for="c in rows" :key="c.id" class="docker-row">
        <span class="state-dot" :class="stateClass(c)"></span>
        <span class="docker-name" :style="nameStyle">{{ c.name }}</span>
        <span class="docker-state" :class="stateClass(c)" :style="stateStyle">{{ stateText(c) }}</span>
      </div>
    </div>
  </button>
</template>

<style scoped>
/* Sizes are real device pixels inside the fixed 1920x1080 design space. */
.docker-overview {
  width: 100%;
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  padding: 30px 34px 28px;
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 34px;
  background: #0c0c0e;
  color: var(--text-primary);
  font-family: inherit;
  text-align: left;
  overflow: hidden;
}
.docker-overview:active { background: #1a1a1c; }
.docker-head {
  flex: none;
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 24px;
  margin-bottom: 24px;
}
.docker-title {
  color: var(--text-tertiary);
  font-size: 24px;
  font-weight: 650;
  letter-spacing: 0.18em;
}
.docker-count {
  color: var(--text-secondary);
  font-size: 24px;
  font-weight: 500;
  letter-spacing: 0.06em;
  white-space: nowrap;
}
.docker-count.ok { color: var(--status-normal); }
.docker-list {
  flex: 1;
  min-height: 0;
  display: grid;
  grid-auto-rows: minmax(0, 1fr);
  gap: 16px;
}
.docker-row {
  display: grid;
  grid-template-columns: 14px minmax(0, 1fr) auto;
  align-items: center;
  gap: 16px;
  min-height: 0;
  padding: 8px 24px;
  border: 1px solid rgba(255, 255, 255, 0.05);
  border-radius: 20px;
  background: #111113;
}
.state-dot {
  width: 13px;
  height: 13px;
  border-radius: 50%;
  background: var(--text-tertiary);
}
.state-dot.ok { background: var(--status-normal); }
.state-dot.warning { background: var(--status-warning); }
.state-dot.critical { background: var(--status-critical); }
.docker-name {
  min-width: 0;
  overflow: hidden;
  color: var(--text-primary);
  font-weight: 500;
  line-height: 1.15;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.docker-state {
  color: var(--text-secondary);
  font-weight: 600;
  letter-spacing: 0.08em;
  white-space: nowrap;
}
.docker-state.ok { color: var(--status-normal); }
.docker-state.warning { color: var(--status-warning); }
.docker-state.critical { color: var(--status-critical); }
.docker-empty {
  padding: 16px 0;
  color: var(--text-secondary);
  font-size: 26px;
}
</style>
