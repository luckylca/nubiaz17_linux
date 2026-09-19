<script setup lang="ts">
import { ref, watch } from 'vue'
import GlassSheet from '../components/GlassSheet.vue'

const props = defineProps<{ open: boolean }>()
const emit = defineEmits<{ close: []; configSaved: [config: Config] }>()

interface Config {
  listen: string
  sample_interval_ms: number
  slow_interval_ms: number
  temp_warning: number
  temp_critical: number
  batt_temp_warning: number
  storage_warning: number
  memory_warning: number
  night_mode: boolean
  dim_timeout_sec: number
  burnin_protection: boolean
  docker_enable: boolean
  bluetooth_enable: boolean
  net_interface: string
}

const cfg = ref<Config | null>(null)
const savedMsg = ref('')

watch(
  () => props.open,
  async (v) => {
    if (!v) return
    try {
      const r = await fetch('/api/config')
      if (r.ok) cfg.value = await r.json()
    } catch { /* ignore */ }
  }
)

async function save() {
  if (!cfg.value) return
  try {
    const r = await fetch('/api/config', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(cfg.value),
    })
    savedMsg.value = r.ok ? 'Saved' : 'Save failed'
    if (r.ok) emit('configSaved', { ...cfg.value })
  } catch {
    savedMsg.value = 'Save failed'
  }
  window.setTimeout(() => (savedMsg.value = ''), 2000)
}
</script>

<template>
  <GlassSheet :open="open" title="Settings" @close="$emit('close')">
    <div v-if="!cfg" class="t-secondary" style="text-align:center; padding: 30px 0">Loading…</div>
    <div v-else class="settings">
      <div class="setting-row">
        <span class="setting-label">Night mode (auto dim)</span>
        <button class="toggle pressable" :class="{ on: cfg.night_mode }" @click="cfg.night_mode = !cfg.night_mode">
          <span class="knob"></span>
        </button>
      </div>
      <div class="setting-row">
        <span class="setting-label">Burn-in protection</span>
        <button class="toggle pressable" :class="{ on: cfg.burnin_protection }" @click="cfg.burnin_protection = !cfg.burnin_protection">
          <span class="knob"></span>
        </button>
      </div>
      <div class="setting-row">
        <span class="setting-label">Docker monitor</span>
        <button class="toggle pressable" :class="{ on: cfg.docker_enable }" @click="cfg.docker_enable = !cfg.docker_enable">
          <span class="knob"></span>
        </button>
      </div>
      <div class="setting-row">
        <span class="setting-label">Bluetooth</span>
        <button class="toggle pressable" :class="{ on: cfg.bluetooth_enable }" @click="cfg.bluetooth_enable = !cfg.bluetooth_enable">
          <span class="knob"></span>
        </button>
      </div>

      <div class="setting-row">
        <span class="setting-label">Dim timeout (s)</span>
        <input v-model.number="cfg.dim_timeout_sec" type="number" class="num" min="15" max="3600" />
      </div>
      <div class="setting-row">
        <span class="setting-label">Temp warning (°C)</span>
        <input v-model.number="cfg.temp_warning" type="number" class="num" min="40" max="100" />
      </div>
      <div class="setting-row">
        <span class="setting-label">Temp critical (°C)</span>
        <input v-model.number="cfg.temp_critical" type="number" min="50" max="120" class="num" />
      </div>
      <div class="setting-row">
        <span class="setting-label">Battery temp warning (°C)</span>
        <input v-model.number="cfg.batt_temp_warning" type="number" min="30" max="60" class="num" />
      </div>
      <div class="setting-row">
        <span class="setting-label">Storage warning (%)</span>
        <input v-model.number="cfg.storage_warning" type="number" min="50" max="99" class="num" />
      </div>
      <div class="setting-row">
        <span class="setting-label">Memory warning (%)</span>
        <input v-model.number="cfg.memory_warning" type="number" min="50" max="99" class="num" />
      </div>

      <div class="save-row">
        <button class="save-btn pressable" @click="save">Save</button>
        <span class="t-secondary saved">{{ savedMsg }}</span>
      </div>
      <div class="t-tertiary note">Sampling interval and listen address apply after agent restart. Display and alert settings apply immediately.</div>
    </div>
  </GlassSheet>
</template>

<style scoped>
.settings { display: flex; flex-direction: column; gap: 4px; padding: 4px 0; }
.setting-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  min-height: 56px;
  padding: 6px 4px;
  border-bottom: 0.5px solid rgba(255, 255, 255, 0.05);
}
.setting-label { font-size: 0.95rem; color: var(--text-primary); }
.toggle {
  width: 62px; height: 36px;
  border-radius: var(--radius-pill);
  border: 0.5px solid var(--glass-border-soft);
  background: rgba(255, 255, 255, 0.07);
  position: relative;
  transition: background var(--dur-fast);
}
.toggle.on { background: rgba(138, 180, 248, 0.35); }
.knob {
  position: absolute;
  top: 3px; left: 3px;
  width: 28px; height: 28px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.85);
  transition: transform var(--dur-med) var(--spring);
}
.toggle.on .knob { transform: translateX(26px); }
.num {
  width: 110px; min-height: 44px;
  border-radius: var(--radius-small);
  border: 0.5px solid var(--glass-border-soft);
  background: rgba(255, 255, 255, 0.06);
  color: var(--text-primary);
  font-family: inherit; font-size: 0.95rem;
  text-align: center;
  outline: none;
}
.save-row { display: flex; align-items: center; justify-content: center; gap: 16px; padding: 18px 0 4px; }
.save-btn {
  min-width: 160px; min-height: 50px;
  border-radius: var(--radius-pill);
  border: 0.5px solid var(--glass-border);
  background: rgba(138, 180, 248, 0.22);
  color: var(--text-primary);
  font-family: inherit; font-size: 0.95rem; font-weight: 600;
}
.saved { font-size: 0.85rem; }
.note { text-align: center; font-size: 0.75rem; padding-top: 8px; }
</style>
