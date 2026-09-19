<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useMonitorStore, type ContainerSummary } from '../stores/monitor'
import { formatBytes, formatUptime } from '../composables/format'
import GlassSheet from '../components/GlassSheet.vue'

const props = defineProps<{ open: boolean }>()
defineEmits<{ close: [] }>()

const store = useMonitorStore()
const docker = computed(() => store.snap?.docker)

const selected = ref<ContainerSummary | null>(null)
const logs = ref<string>('')
const logsOpen = ref(false)
const actionMsg = ref('')

watch(
  () => props.open,
  (v) => {
    if (!v) {
      selected.value = null
      logsOpen.value = false
    }
  }
)

function stateClass(c: ContainerSummary): string {
  if (c.state === 'running') {
    if (c.health === 'unhealthy') return 'critical'
    if (c.health === 'starting') return 'warning'
    return 'running'
  }
  if (c.state === 'restarting') return 'warning'
  return 'stopped'
}

function stateText(c: ContainerSummary): string {
  if (c.state === 'running') {
    if (c.health === 'healthy') return 'Healthy'
    if (c.health === 'unhealthy') return 'Unhealthy'
    if (c.health === 'starting') return 'Starting'
    return 'Running'
  }
  if (c.state === 'restarting') return 'Restarting'
  if (c.state === 'exited') return 'Exited'
  return c.state ? c.state[0].toUpperCase() + c.state.slice(1) : 'Unknown'
}

const selectedStats = computed(() =>
  selected.value ? store.snap?.docker?.stats?.[selected.value.id] : undefined
)

/* long-press guard for destructive actions (800 ms) */
const holdProgress = ref<string | null>(null)
let holdTimer: number | null = null

function holdStart(action: string) {
  holdProgress.value = action
  holdTimer = window.setTimeout(() => {
    holdTimer = null
    doAction(action)
  }, 800)
}
function holdEnd() {
  if (holdTimer) {
    clearTimeout(holdTimer)
    holdTimer = null
  }
  holdProgress.value = null
}

async function doAction(action: string) {
  if (!selected.value) return
  try {
    const r = await fetch('/api/docker/action', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: selected.value.id, action }),
    })
    actionMsg.value = r.ok ? `${action} ok` : `${action} failed`
  } catch {
    actionMsg.value = `${action} failed`
  }
  window.setTimeout(() => (actionMsg.value = ''), 2500)
}

async function openLogs() {
  if (!selected.value) return
  try {
    const r = await fetch(`/api/docker/logs?id=${encodeURIComponent(selected.value.id)}`)
    if (r.ok) {
      logs.value = (await r.json()).logs ?? ''
      logsOpen.value = true
    }
  } catch { /* ignore */ }
}

const now = Math.floor(Date.now() / 1000)
</script>

<template>
  <GlassSheet :open="open" title="Docker" wide @close="$emit('close')">
    <div v-if="!docker?.available" class="empty t-secondary">
      Docker unavailable
    </div>

    <!-- container list -->
    <div v-else-if="!selected" class="list">
      <button
        v-for="c in docker.containers ?? []"
        :key="c.id"
        class="row pressable"
        @click="selected = c"
      >
        <span class="state-dot" :class="stateClass(c)"></span>
        <span class="row-name">{{ c.name }}</span>
        <span class="row-state">{{ stateText(c) }}</span>
        <span v-if="docker.stats?.[c.id]" class="row-stat">
          CPU {{ docker.stats[c.id].cpu_percent.toFixed(1) }}% ·
          {{ formatBytes(docker.stats[c.id].mem_bytes) }}
        </span>
      </button>
      <div v-if="!(docker.containers?.length)" class="empty t-secondary">No containers</div>
    </div>

    <!-- container detail -->
    <div v-else class="detail">
      <button class="back-btn pressable" @click="selected = null; logsOpen = false">‹ All containers</button>

      <div class="detail-head">
        <span class="state-dot lg" :class="stateClass(selected)"></span>
        <div>
          <div class="detail-name">{{ selected.name }}</div>
          <div class="detail-image t-tertiary">{{ selected.image }}</div>
        </div>
      </div>

      <div class="fact-grid">
        <div class="fact">
          <div class="fact-value">{{ stateText(selected) }}</div>
          <div class="t-label">Status</div>
        </div>
        <div class="fact">
          <div class="fact-value">{{ selected.id.slice(0, 12) }}</div>
          <div class="t-label">ID</div>
        </div>
        <div v-if="selected.started_at" class="fact">
          <div class="fact-value">{{ formatUptime(Math.max(0, now - selected.started_at)) }}</div>
          <div class="t-label">Uptime</div>
        </div>
        <div class="fact">
          <div class="fact-value">{{ selected.restart_count }}</div>
          <div class="t-label">Restarts</div>
        </div>
        <template v-if="selectedStats">
          <div class="fact">
            <div class="fact-value">{{ selectedStats.cpu_percent.toFixed(1) }}%</div>
            <div class="t-label">CPU</div>
          </div>
          <div class="fact">
            <div class="fact-value">{{ formatBytes(selectedStats.mem_bytes) }}</div>
            <div class="t-label">Memory</div>
          </div>
          <div class="fact">
            <div class="fact-value">↓{{ formatBytes(selectedStats.net_rx) }} ↑{{ formatBytes(selectedStats.net_tx) }}</div>
            <div class="t-label">Network</div>
          </div>
          <div class="fact">
            <div class="fact-value">R {{ formatBytes(selectedStats.block_read) }} · W {{ formatBytes(selectedStats.block_write) }}</div>
            <div class="t-label">Disk IO</div>
          </div>
        </template>
        <div v-if="selected.ports?.length" class="fact span3">
          <div class="fact-value ports">{{ selected.ports.join('  ·  ') }}</div>
          <div class="t-label">Ports</div>
        </div>
      </div>

      <div class="actions">
        <button class="action-btn pressable" @click="openLogs">Logs</button>
        <button
          v-if="selected.state !== 'running'"
          class="action-btn pressable"
          @pointerdown="holdStart('start')"
          @pointerup="holdEnd"
          @pointerleave="holdEnd"
        >{{ holdProgress === 'start' ? 'Hold…' : 'Hold to Start' }}</button>
        <template v-else>
          <button
            class="action-btn warn pressable"
            @pointerdown="holdStart('stop')"
            @pointerup="holdEnd"
            @pointerleave="holdEnd"
          >{{ holdProgress === 'stop' ? 'Hold…' : 'Hold to Stop' }}</button>
          <button
            class="action-btn warn pressable"
            @pointerdown="holdStart('restart')"
            @pointerup="holdEnd"
            @pointerleave="holdEnd"
          >{{ holdProgress === 'restart' ? 'Hold…' : 'Hold to Restart' }}</button>
        </template>
      </div>
      <div v-if="actionMsg" class="action-msg t-secondary">{{ actionMsg }}</div>

      <pre v-if="logsOpen" class="logs scroll-y">{{ logs }}</pre>
    </div>
  </GlassSheet>
</template>

<style scoped>
.empty { text-align: center; padding: 40px 0; }
.list { display: flex; flex-direction: column; gap: 4px; padding: 4px 0; }
.row {
  display: flex;
  align-items: center;
  gap: 14px;
  min-height: 56px;
  padding: 8px 16px;
  border-radius: var(--radius-small);
  background: rgba(255, 255, 255, 0.04);
  border: 0.5px solid rgba(255, 255, 255, 0.06);
  color: var(--text-primary);
  font-family: inherit;
  font-size: 0.98rem;
  text-align: left;
}
.row-name { flex: 1; font-weight: 500; }
.row-state { color: var(--text-secondary); font-size: 0.85rem; min-width: 84px; }
.row-stat { color: var(--text-tertiary); font-size: 0.8rem; }

.state-dot {
  width: 8px; height: 8px; border-radius: 50%;
  background: rgba(255, 255, 255, 0.25);
  flex-shrink: 0;
}
.state-dot.lg { width: 12px; height: 12px; }
.state-dot.running { background: var(--status-normal); box-shadow: 0 0 8px rgba(126, 226, 168, 0.5); }
.state-dot.warning { background: var(--status-warning); box-shadow: 0 0 8px rgba(242, 198, 109, 0.5); }
.state-dot.critical { background: var(--status-critical); box-shadow: 0 0 8px rgba(242, 139, 130, 0.5); }
.state-dot.stopped { background: rgba(255, 255, 255, 0.22); }

.back-btn {
  background: none; border: none; color: var(--accent);
  font-family: inherit; font-size: 0.92rem;
  padding: 12px 4px; min-height: 44px;
}
.detail-head { display: flex; align-items: center; gap: 14px; padding: 4px 0 14px; }
.detail-name { font-size: 1.3rem; font-weight: 500; }
.detail-image { font-size: 0.8rem; }

.fact-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px 10px;
  padding: 4px 0 8px;
}
.fact { text-align: center; }
.fact.span3 { grid-column: span 3; }
.fact-value { font-size: 0.98rem; font-weight: 500; padding-bottom: 3px; }
.ports { font-size: 0.85rem; }

.actions { display: flex; justify-content: center; gap: 12px; padding: 14px 0 4px; }
.action-btn {
  min-width: 120px; min-height: 48px;
  border-radius: var(--radius-pill);
  border: 0.5px solid var(--glass-border-soft);
  background: rgba(255, 255, 255, 0.07);
  color: var(--text-primary);
  font-family: inherit; font-size: 0.88rem; font-weight: 500;
}
.action-btn.warn { color: var(--status-warning); }
.action-msg { text-align: center; padding-top: 6px; font-size: 0.85rem; }

.logs {
  margin-top: 12px;
  max-height: 24vh;
  background: rgba(0, 0, 0, 0.35);
  border-radius: var(--radius-small);
  padding: 12px 14px;
  font-size: 0.72rem;
  line-height: 1.5;
  color: var(--text-secondary);
  white-space: pre-wrap;
  word-break: break-all;
  user-select: text;
}
</style>
