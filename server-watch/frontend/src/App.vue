<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
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
const exiting = ref(false)
const driftStyle = ref({ transform: 'translate(0px, 0px)' })

/* The dashboard is designed in a fixed 1920x1080 space. The kiosk webview
   already normalizes its CSS viewport to the physical panel size, but keep a
   defensive scale here so any fallback browser / DPI combination still shows
   the same layout instead of overflowing. */
const DESIGN_W = 1920
const DESIGN_H = 1080
const rootScale = ref(1)
function updateScale() {
  rootScale.value = Math.min(window.innerWidth / DESIGN_W, window.innerHeight / DESIGN_H)
}
const rootStyle = computed(() => ({ transform: `scale(${rootScale.value})` }))

/* settings pulled from backend config (burn-in protection only) */
const burnIn = ref(true)

let driftTimer: number | null = null

/* Burn-in protection: move only once every five minutes. The short transition
   is deliberate; long continuous transforms are expensive on NX563J fbdev. */
function scheduleDrift() {
  if (driftTimer) clearInterval(driftTimer)
  driftTimer = window.setInterval(() => {
    if (!burnIn.value) return
    const x = Math.round(Math.random() * 6 - 3)
    const y = Math.round(Math.random() * 6 - 3)
    driftStyle.value = { transform: `translate(${x}px, ${y}px)` }
  }, 300000)
}

function open(name: string) {
  openSheet.value = name
}

async function doExit() {
  if (exiting.value) return
  exiting.value = true
  // Ask the local agent to terminate the kiosk. keepalive avoids losing the
  // request when the page is torn down during the exit animation.
  fetch('/api/ui/quit', { method: 'POST', keepalive: true }).catch(() => {})
  window.setTimeout(() => window.close(), 260)
}

function applyUiConfig(c: any) {
  if (typeof c?.burnin_protection === 'boolean') burnIn.value = c.burnin_protection
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
  scheduleDrift()
  updateScale()
  window.addEventListener('resize', updateScale, { passive: true })
  // dev/preview hook: ?sheet=cpu opens a sheet on load
  const qs = new URLSearchParams(location.search)
  const initial = qs.get('sheet')
  if (initial) openSheet.value = initial
})

onUnmounted(() => {
  window.removeEventListener('resize', updateScale)
  if (driftTimer) clearInterval(driftTimer)
})
</script>

<template>
  <div class="app-root" :class="{ exiting }">
    <!-- Pure black Apple Watch-style background: zero blur/gradient cost. -->
    <div class="bg"></div>

    <!-- Fixed 1920x1080 design space, scaled to the actual CSS viewport. -->
    <div class="design-root" :style="rootStyle">
      <!-- drift wrapper for burn-in protection -->
      <div class="drift" :style="driftStyle">
        <ClockView @open-sheet="open" @exit="doExit" />
      </div>

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

/* ---- static OLED / Apple Watch background ---- */
.bg {
  position: absolute;
  inset: 0;
  background: #000;
}

/* ---- fixed design-space root ----
   The transform also makes this the containing block for the fixed-position
   sheets, so sheets get the same 1920x1080 design space as the dashboard. */
.design-root {
  position: absolute;
  top: 0;
  left: 0;
  width: 1920px;
  height: 1080px;
  transform-origin: 0 0;
  overflow: hidden;
}

/* Burn-in drift is normally completely idle. It animates for only 1.2s
   every five minutes instead of forcing continuous software compositing. */
.drift {
  position: absolute;
  inset: 0;
  transition: transform 1200ms ease-out;
}
</style>
