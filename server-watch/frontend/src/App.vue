<script setup lang="ts">
import { onMounted, onUnmounted, ref, watch } from 'vue'
import { useMonitorStore } from './stores/monitor'
import ClockView from './components/ClockView.vue'
import CpuSheet from './views/CpuSheet.vue'
import BatterySheet from './views/BatterySheet.vue'
import NetworkSheet from './views/NetworkSheet.vue'
import DockerSheet from './views/DockerSheet.vue'
import MenuSheet from './views/MenuSheet.vue'
import OverviewSheet from './views/OverviewSheet.vue'
import ProcessesSheet from './views/ProcessesSheet.vue'
import SettingsSheet from './views/SettingsSheet.vue'
import HardwareSheet from './views/HardwareSheet.vue'

const store = useMonitorStore()

const openSheet = ref<string | null>(null)
const dimmed = ref(false)
const exiting = ref(false)
const driftStyle = ref({ transform: 'translate(0px, 0px)' })

/* settings pulled from backend config for dim/burn-in */
const dimTimeoutSec = ref(120)
const nightMode = ref(true)
const burnIn = ref(true)

let idleTimer: number | null = null
let driftTimer: number | null = null

function resetIdle() {
  if (dimmed.value) dimmed.value = false
  if (idleTimer) clearTimeout(idleTimer)
  if (!nightMode.value) return
  idleTimer = window.setTimeout(() => {
    if (!openSheet.value) dimmed.value = true
  }, dimTimeoutSec.value * 1000)
}

function onUserActivity() {
  resetIdle()
}

/* burn-in protection: ultra-slow drift, a few px every few minutes */
function scheduleDrift() {
  if (driftTimer) clearInterval(driftTimer)
  driftTimer = window.setInterval(() => {
    if (!burnIn.value) return
    const x = (Math.random() * 8 - 4).toFixed(1)
    const y = (Math.random() * 8 - 4).toFixed(1)
    driftStyle.value = { transform: `translate(${x}px, ${y}px)` }
  }, 150000) // every 2.5 min; CSS transition smooths it over 140s
}

function open(name: string) {
  dimmed.value = false
  openSheet.value = name
}

async function doExit() {
  if (exiting.value) return
  exiting.value = true
  // Ask the local agent to terminate the kiosk. keepalive avoids losing the
  // request when Chromium tears the page down during the exit animation.
  fetch('/api/ui/quit', { method: 'POST', keepalive: true }).catch(() => {})
  window.setTimeout(() => window.close(), 260)
}

function applyUiConfig(c: any) {
  if (typeof c?.dim_timeout_sec === 'number') dimTimeoutSec.value = c.dim_timeout_sec
  if (typeof c?.night_mode === 'boolean') nightMode.value = c.night_mode
  if (typeof c?.burnin_protection === 'boolean') burnIn.value = c.burnin_protection
  resetIdle()
  scheduleDrift()
}

async function loadConfig() {
  try {
    const r = await fetch('/api/config')
    if (r.ok) {
      const c = await r.json()
      applyUiConfig(c)
    }
  } catch { /* defaults */ }
}

onMounted(() => {
  store.connect()
  loadConfig()
  resetIdle()
  scheduleDrift()
  // dev/preview hook: ?sheet=cpu opens a sheet on load
  const qs = new URLSearchParams(location.search)
  const initial = qs.get('sheet')
  if (initial) openSheet.value = initial
  window.addEventListener('pointerdown', onUserActivity, { passive: true })
  window.addEventListener('pointermove', throttleActivity, { passive: true })
})

let lastMove = 0
function throttleActivity() {
  const t = performance.now()
  if (t - lastMove > 5000) {
    lastMove = t
    resetIdle()
  }
}

watch(openSheet, (v) => {
  if (v) dimmed.value = false
  resetIdle()
})

onUnmounted(() => {
  window.removeEventListener('pointerdown', onUserActivity)
  window.removeEventListener('pointermove', throttleActivity)
  if (idleTimer) clearTimeout(idleTimer)
  if (driftTimer) clearInterval(driftTimer)
})
</script>

<template>
  <div class="app-root" :class="{ dimmed, exiting }">
    <!-- slow living background -->
    <div class="bg">
      <div class="bg-gradient"></div>
      <div class="bg-glow g1"></div>
      <div class="bg-glow g2"></div>
      <div class="bg-glow g3"></div>
      <div class="bg-vignette"></div>
    </div>

    <!-- drift wrapper for burn-in protection -->
    <div class="drift" :style="driftStyle">
      <ClockView @open-sheet="open" @exit="doExit" />
    </div>

    <!-- In night/dim mode the first touch is wake-only, Apple Watch style. -->
    <div v-if="dimmed" class="wake-layer" @pointerdown.stop.prevent="resetIdle"></div>

    <!-- sheets -->
    <MenuSheet :open="openSheet === 'menu'" @close="openSheet = null" @open="open" />
    <CpuSheet :open="openSheet === 'cpu'" @close="openSheet = null" />
    <BatterySheet :open="openSheet === 'battery'" @close="openSheet = null" />
    <NetworkSheet :open="openSheet === 'network'" @close="openSheet = null" />
    <DockerSheet :open="openSheet === 'docker'" @close="openSheet = null" />
    <OverviewSheet :open="openSheet === 'overview'" @close="openSheet = null" />
    <HardwareSheet :open="openSheet === 'hardware'" @close="openSheet = null" />
    <ProcessesSheet :open="openSheet === 'processes'" @close="openSheet = null" />
    <SettingsSheet
      :open="openSheet === 'settings'"
      @close="openSheet = null"
      @config-saved="applyUiConfig"
    />
  </div>
</template>

<style scoped>
.app-root {
  position: fixed;
  inset: 0;
  overflow: hidden;
  transition: opacity 240ms ease-in, transform 240ms ease-in;
}
.app-root.exiting {
  opacity: 0;
  transform: scale(0.98);
}

/* ---- background ---- */
.bg {
  position: absolute;
  inset: 0;
  background: var(--bg-0);
}
.bg-gradient {
  position: absolute;
  inset: -20%;
  background:
    radial-gradient(60% 55% at 22% 28%, rgba(38, 54, 92, 0.55) 0%, transparent 60%),
    radial-gradient(55% 60% at 78% 72%, rgba(24, 42, 66, 0.5) 0%, transparent 62%),
    radial-gradient(45% 40% at 60% 20%, rgba(52, 62, 98, 0.28) 0%, transparent 60%),
    linear-gradient(160deg, var(--bg-1) 0%, var(--bg-0) 55%, var(--bg-2) 100%);
  animation: background-arrive 700ms var(--ease-out) both;
}
.bg-glow {
  position: absolute;
  border-radius: 50%;
  opacity: 0.6;
}
.g1 {
  width: 46vmax; height: 46vmax;
  left: -12vmax; top: -16vmax;
  background: radial-gradient(circle, rgba(70, 100, 170, 0.16), transparent 65%);
}
.g2 {
  width: 40vmax; height: 40vmax;
  right: -10vmax; bottom: -14vmax;
  background: radial-gradient(circle, rgba(46, 78, 120, 0.14), transparent 65%);
}
.g3 {
  width: 26vmax; height: 26vmax;
  left: 40vw; top: 60vh;
  background: radial-gradient(circle, rgba(90, 110, 170, 0.07), transparent 60%);
}
.bg-vignette {
  position: absolute;
  inset: 0;
  background: radial-gradient(120% 120% at 50% 42%, transparent 55%, rgba(0, 0, 0, 0.5) 100%);
}

@keyframes background-arrive {
  from { opacity: 0.72; transform: scale(1.015); }
  to { opacity: 1; transform: scale(1); }
}

/* ---- burn-in drift wrapper: mostly idle; moves only briefly every 2.5 min ---- */
.drift {
  position: absolute;
  inset: 0;
  transition: transform 8s ease-in-out;
}
.wake-layer {
  position: absolute;
  inset: 0;
  z-index: 30;
  background: transparent;
  touch-action: none;
}

/* ---- night dim mode ---- */
.dimmed .bg-gradient,
.dimmed .bg-glow {
  animation-play-state: paused;
}
.dimmed .drift {
  transition: opacity 1200ms ease, transform 8s ease-in-out;
}
.dimmed :deep(.complication),
.dimmed :deep(.status-pill) {
  opacity: 0.07;
  transition: opacity 1200ms ease;
  pointer-events: none;
}
.dimmed :deep(.date-line) {
  opacity: 0.35;
  transition: opacity 1200ms ease;
}
.dimmed :deep(.big-clock) {
  opacity: 0.92;
}
.dimmed .bg {
  filter: brightness(0.7);
  transition: filter 1500ms ease;
}
.bg { transition: filter 800ms ease; }

:deep(.complication),
:deep(.status-pill),
:deep(.date-line) {
  transition: opacity 800ms ease;
}
</style>
