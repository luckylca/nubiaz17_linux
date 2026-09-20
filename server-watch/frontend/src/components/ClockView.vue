<script setup lang="ts">
import { computed } from 'vue'
import { useMonitorStore } from '../stores/monitor'
import { useNow, formatBytes, formatKB, formatUptime } from '../composables/format'
import DigitClock from './DigitClock.vue'
import DockerOverview from './DockerOverview.vue'
import StatusPill from './StatusPill.vue'
import DashboardMetric from './DashboardMetric.vue'

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

/* ---- metrics ---- */

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
  return (b.status ?? '').toUpperCase()
})

const netRx = computed(() => formatBytes(store.snap?.network?.rx_rate ?? 0, true))
const netTx = computed(() => formatBytes(store.snap?.network?.tx_rate ?? 0, true))
const netSeverity = computed(() =>
  store.snap?.network && !store.snap.network.up ? ('critical' as const) : ('normal' as const)
)

/* The backend quotes non-ASCII SSIDs as \xNN byte escapes; turn them back
   into readable text for the footer line. */
function decodeSsid(s?: string): string {
  if (!s) return ''
  if (!s.includes('\\x')) return s
  try {
    const bytes: number[] = []
    for (let i = 0; i < s.length; i++) {
      if (s[i] === '\\' && s[i + 1] === 'x' && i + 3 < s.length) {
        bytes.push(parseInt(s.slice(i + 2, i + 4), 16))
        i += 3
      } else {
        bytes.push(s.charCodeAt(i) & 0xff)
      }
    }
    return new TextDecoder('utf-8').decode(new Uint8Array(bytes))
  } catch {
    return s
  }
}
const netFoot = computed(() =>
  decodeSsid(store.snap?.wifi?.ssid ?? store.snap?.network?.name ?? '').toUpperCase()
)

const mem = computed(() => store.snap?.memory)
const rootDisk = computed(() => store.snap?.storage?.find((s) => s.mount === '/') ?? store.snap?.storage?.[0])
const avgFreq = computed(() => {
  const f = store.snap?.cpu?.freq_mhz ?? []
  if (!f.length) return null
  return Math.round(f.reduce((a, b) => a + b, 0) / f.length)
})
const cpuDetail = computed(() => {
  const parts: string[] = []
  if (store.snap?.soc_temp != null) parts.push(`${Math.round(store.snap.soc_temp)}°C`)
  if (store.snap?.cpu) parts.push(`LOAD ${store.snap.cpu.load1.toFixed(2)}`)
  return parts.join(' · ')
})
const cpuFoot = computed(() => {
  const parts: string[] = []
  if (store.snap?.cpu?.cores) parts.push(`${store.snap.cpu.cores} CORES`)
  if (avgFreq.value != null) parts.push(`${avgFreq.value} MHz`)
  return parts.join(' · ')
})
const memoryDetail = computed(() => mem.value ? `${formatKB(mem.value.used_kb)} / ${formatKB(mem.value.total_kb)}` : '')
const memoryFoot = computed(() => mem.value ? `${formatKB(mem.value.avail_kb)} AVAILABLE` : '')
const storageDetail = computed(() => rootDisk.value ? `${formatBytes(rootDisk.value.used_b)} / ${formatBytes(rootDisk.value.total_b)}` : '')
const storageFoot = computed(() => rootDisk.value ? `${formatBytes(rootDisk.value.avail_b)} FREE · ${rootDisk.value.mount}` : '')
const batteryFoot = computed(() => {
  const b = store.snap?.battery
  if (!b?.present) return ''
  const parts: string[] = []
  if (b.temp_c != null) parts.push(`${Math.round(b.temp_c)}°C`)
  if (b.voltage_v != null) parts.push(`${b.voltage_v.toFixed(2)}V`)
  return parts.join(' · ')
})
const uptimeText = computed(() => formatUptime(store.snap?.uptime_sec ?? 0))
const uptimeDetail = computed(() => (store.snap?.cpu?.governor ?? '').toUpperCase())
const uptimeFoot = computed(() => {
  const cpu = store.snap?.cpu
  if (!cpu) return ''
  return `${cpu.running ?? 0} RUN · ${cpu.threads ?? 0} THREADS`
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
  // Touch on the NX563J is translated through evdev/uinput, so finger taps
  // naturally wander more than a mouse click. Keep this deliberately
  // forgiving while still requiring two taps in the large center area.
  if (dt <= 600 && Math.hypot(dx, dy) <= 80) {
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
  <main class="dashboard">
    <header class="topline">
      <div class="brand-block">
        <div class="brand">SERVER WATCH</div>
        <div class="host">NX563J · {{ (store.snap?.network?.name ?? 'LOCAL').toUpperCase() }}</div>
      </div>
      <StatusPill class="status-strip" :text="pillText" :level="pillLevel" @click="emit('openSheet', 'menu')" />
    </header>

    <section class="main-panel">
      <!-- The clock remains the visual anchor. Double-tap only this block to exit. -->
      <section class="clock-zone" @pointerdown="onClockTap">
        <DigitClock :time="timeStr" class="big-clock" />
        <div class="date-line">{{ dateStr }}</div>
      </section>

      <section class="metrics-grid">
        <DashboardMetric
          label="CPU"
          :value="store.snap?.cpu ? `${Math.round(store.snap.cpu.total)}%` : '—'"
          :detail="cpuDetail"
          :foot="cpuFoot"
          :severity="cpuSeverity"
          @click="emit('openSheet', 'cpu')"
        />
        <DashboardMetric
          label="Memory"
          :value="mem ? `${Math.round(mem.used_percent)}%` : '—'"
          :detail="memoryDetail"
          :foot="memoryFoot"
          @click="emit('openSheet', 'hardware')"
        />
        <DashboardMetric
          label="Storage"
          :value="rootDisk ? `${Math.round(rootDisk.used_pct)}%` : '—'"
          :detail="storageDetail"
          :foot="storageFoot"
          @click="emit('openSheet', 'hardware')"
        />
        <DashboardMetric
          label="Battery"
          :value="battText"
          :detail="battSub"
          :foot="batteryFoot"
          @click="emit('openSheet', 'battery')"
        />
        <DashboardMetric
          label="Network"
          :value="`↓ ${netRx}`"
          :detail="`↑ ${netTx}`"
          :foot="netFoot"
          :severity="netSeverity"
          @click="emit('openSheet', 'network')"
        />
        <DashboardMetric
          label="Uptime"
          :value="uptimeText"
          :detail="uptimeDetail"
          :foot="uptimeFoot"
          @click="emit('openSheet', 'overview')"
        />
      </section>
    </section>

    <section class="docker-section">
      <DockerOverview
        :available="store.snap?.docker?.available ?? false"
        :containers="store.snap?.docker?.containers"
        :running="store.snap?.docker?.running ?? 0"
        :total="store.snap?.docker?.total ?? 0"
        @click="emit('openSheet', 'docker')"
      />
    </section>
  </main>
</template>

<style scoped>
/* Fixed 1920x1080 design space: every size below is a real device pixel. */
.dashboard {
  width: 1920px;
  height: 1080px;
  display: flex;
  flex-direction: column;
  gap: 34px;
  padding: 46px 60px 44px;
  overflow: hidden;
}

/* ---- header ---- */
.topline {
  flex: none;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 32px;
  min-height: 64px;
}
.brand {
  color: var(--text-secondary);
  font-size: 27px;
  font-weight: 650;
  letter-spacing: 0.24em;
}
.host {
  margin-top: 7px;
  color: var(--text-tertiary);
  font-size: 21px;
  font-weight: 500;
  letter-spacing: 0.1em;
}

/* ---- clock + metrics ---- */
.main-panel {
  flex: 1;
  min-height: 0;
  display: flex;
  gap: 48px;
}
.clock-zone {
  flex: none;
  width: 640px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 30px;
  touch-action: manipulation;
}
.big-clock {
  font-size: 252px;
}
.date-line {
  color: var(--text-tertiary);
  font-size: 33px;
  font-weight: 500;
  letter-spacing: 0.3em;
  text-indent: 0.3em;
  white-space: nowrap;
}
.metrics-grid {
  flex: 1;
  min-width: 0;
  min-height: 0;
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  grid-template-rows: repeat(2, minmax(0, 1fr));
  gap: 24px;
}

/* ---- docker ---- */
.docker-section {
  flex: none;
  height: 330px;
  min-height: 0;
  overflow: hidden;
}
</style>
