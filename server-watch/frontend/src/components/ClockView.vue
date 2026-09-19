<script setup lang="ts">
import { computed } from 'vue'
import { useMonitorStore } from '../stores/monitor'
import { useNow, formatBytes } from '../composables/format'
import DigitClock from './DigitClock.vue'
import Complication from './Complication.vue'
import StatusPill from './StatusPill.vue'

const emit = defineEmits<{
  openSheet: [name: string]
  exit: []
}>()

const store = useMonitorStore()
const now = useNow()

const timeStr = computed(() => {
  const d = now.value
  const hh = d.getHours().toString().padStart(2, '0')
  const mm = d.getMinutes().toString().padStart(2, '0')
  return `${hh}:${mm}`
})

const dateStr = computed(() => {
  const d = now.value
  const day = d.toLocaleDateString('en-US', { weekday: 'long' }).toUpperCase()
  const mon = d.toLocaleDateString('en-US', { month: 'short' }).toUpperCase()
  return `${day} · ${mon} ${d.getDate()}`
})

/* ---- complications ---- */

const cpuTempText = computed(() => {
  const t = store.snap?.soc_temp
  return t == null ? '—' : `${Math.round(t)}°`
})
const cpuSeverity = computed(() => {
  const t = store.snap?.soc_temp
  if (t == null) return 'normal' as const
  if (t >= 78) return 'critical' as const
  if (t >= 65) return 'warning' as const
  return 'normal' as const
})

const battText = computed(() => {
  const b = store.snap?.battery
  if (!b?.present || b.capacity == null) return '—'
  return `${b.capacity}%`
})
const battSub = computed(() => {
  const b = store.snap?.battery
  if (!b?.present) return ''
  return b.status ?? ''
})

const netRx = computed(() => formatBytes(store.snap?.network?.rx_rate ?? 0, true))
const netTx = computed(() => formatBytes(store.snap?.network?.tx_rate ?? 0, true))
const netSeverity = computed(() =>
  store.snap?.network && !store.snap.network.up ? ('critical' as const) : ('normal' as const)
)

const dockerText = computed(() => {
  const d = store.snap?.docker
  if (!d?.available) return '—'
  return `${d.running} / ${d.total}`
})
const dockerSeverity = computed(() => {
  const d = store.snap?.docker
  if (!d?.available) return 'normal' as const
  return d.healthy ? ('normal' as const) : ('warning' as const)
})

const pillText = computed(() => {
  const st = store.snap?.status
  if (!store.connected) return 'CONNECTING'
  if (!store.snap) return 'SYNCING'
  if (!st || st.level === 'normal') return 'ALL SYSTEMS NORMAL'
  const n = st.issues?.length ?? 0
  if (n === 1) {
    const i = st.issues![0]
    return `${i.component} · ${i.detail}`.toUpperCase()
  }
  return `${n} SERVICES REQUIRE ATTENTION`
})
const pillLevel = computed(() => (store.snap?.status?.level ?? 'normal') as 'normal' | 'warning' | 'critical')

/* ---- double tap to exit ---- */

let lastTap = 0
let lastX = 0
let lastY = 0

function onClockTap(e: PointerEvent) {
  const t = performance.now()
  const dt = t - lastTap
  const dx = e.clientX - lastX
  const dy = e.clientY - lastY
  if (dt <= 450 && Math.hypot(dx, dy) <= 30) {
    lastTap = 0
    emit('exit')
    return
  }
  lastTap = t
  lastX = e.clientX
  lastY = e.clientY
}
</script>

<template>
  <div class="clock-view">
    <!-- complications -->
    <div class="comp-slot tl">
      <Complication
        :primary="cpuTempText"
        :secondary="store.snap?.cpu ? `${Math.round(store.snap.cpu.total)}%` : ''"
        label="CPU"
        :severity="cpuSeverity"
        @click="emit('openSheet', 'cpu')"
      />
    </div>
    <div class="comp-slot tr">
      <Complication
        :primary="battText"
        :secondary="battSub"
        label="Battery"
        @click="emit('openSheet', 'battery')"
      />
    </div>
    <div class="comp-slot bl">
      <Complication
        :primary="`↓ ${netRx}`"
        :secondary="`↑ ${netTx}`"
        label="Network"
        :severity="netSeverity"
        @click="emit('openSheet', 'network')"
      />
    </div>
    <div class="comp-slot br">
      <Complication
        :primary="dockerText"
        secondary=""
        label="Docker"
        :severity="dockerSeverity"
        @click="emit('openSheet', 'docker')"
      />
    </div>

    <!-- center clock: double-tap exits -->
    <div class="clock-center" @pointerdown="onClockTap">
      <DigitClock :time="timeStr" class="big-clock" />
      <div class="date-line">{{ dateStr }}</div>
    </div>

    <div class="pill-slot">
      <StatusPill :text="pillText" :level="pillLevel" @click="emit('openSheet', 'menu')" />
    </div>
  </div>
</template>

<style scoped>
.clock-view {
  position: absolute;
  inset: 0;
}
.comp-slot {
  position: absolute;
  z-index: 5;
}
.tl { top: var(--safe-y); left: var(--safe-x); }
.tr { top: var(--safe-y); right: var(--safe-x); }
.bl { bottom: var(--safe-y); left: var(--safe-x); }
.br { bottom: var(--safe-y); right: var(--safe-x); }

.clock-center {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 2.2vh;
}
.big-clock {
  font-size: clamp(84px, 22vh, 240px);
}
.date-line {
  font-size: clamp(14px, 2.6vh, 24px);
  font-weight: 500;
  letter-spacing: 0.34em;
  color: var(--text-tertiary);
  text-indent: 0.34em; /* balance letter-spacing */
}
.pill-slot {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 12vh;
  display: flex;
  justify-content: center;
  z-index: 5;
}
</style>
