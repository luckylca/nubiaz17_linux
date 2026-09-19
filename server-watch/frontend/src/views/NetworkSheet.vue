<script setup lang="ts">
import { computed } from 'vue'
import { useMonitorStore } from '../stores/monitor'
import { formatBytes } from '../composables/format'
import GlassSheet from '../components/GlassSheet.vue'
import Sparkline from '../components/Sparkline.vue'

defineProps<{ open: boolean }>()
defineEmits<{ close: [] }>()

const store = useMonitorStore()
const net = computed(() => store.snap?.network)
const wifi = computed(() => store.snap?.wifi)
const rxHist = computed(() => store.snap?.history?.rx ?? [])
const txHist = computed(() => store.snap?.history?.tx ?? [])

const fmtRate = formatBytes
</script>

<template>
  <GlassSheet :open="open" title="Network" @close="$emit('close')">
    <div class="rate-row">
      <div class="rate">
        <div class="rate-value">↓ {{ fmtRate(net?.rx_rate ?? 0, true) }}</div>
        <Sparkline :data="rxHist" :height="44" />
      </div>
      <div class="rate">
        <div class="rate-value">↑ {{ fmtRate(net?.tx_rate ?? 0, true) }}</div>
        <Sparkline :data="txHist" :height="44" color="rgba(126, 226, 168, 0.8)" />
      </div>
    </div>

    <div class="fact-grid">
      <div class="fact">
        <div class="fact-value">{{ net?.name || '—' }}</div>
        <div class="t-label">Interface</div>
      </div>
      <div v-for="ip in net?.ipv4 ?? []" :key="ip" class="fact">
        <div class="fact-value">{{ ip }}</div>
        <div class="t-label">IPv4</div>
      </div>
      <div v-for="ip in net?.ipv6 ?? []" :key="ip" class="fact">
        <div class="fact-value ip6">{{ ip }}</div>
        <div class="t-label">IPv6</div>
      </div>
      <div v-if="store.snap?.gateway" class="fact">
        <div class="fact-value">{{ store.snap.gateway }}</div>
        <div class="t-label">Gateway</div>
      </div>
      <div class="fact">
        <div class="fact-value">{{ fmtRate(net?.rx_bytes ?? 0) }}</div>
        <div class="t-label">Total RX</div>
      </div>
      <div class="fact">
        <div class="fact-value">{{ fmtRate(net?.tx_bytes ?? 0) }}</div>
        <div class="t-label">Total TX</div>
      </div>
    </div>

    <template v-if="wifi?.enabled">
      <h3 class="section">Wi-Fi</h3>
      <div class="fact-grid">
        <div v-if="wifi.ssid" class="fact">
          <div class="fact-value">{{ wifi.ssid }}</div>
          <div class="t-label">SSID</div>
        </div>
        <div v-if="wifi.signal_dbm != null" class="fact">
          <div class="fact-value">{{ wifi.signal_dbm }} dBm</div>
          <div class="t-label">Signal</div>
        </div>
        <div v-if="wifi.freq_mhz != null" class="fact">
          <div class="fact-value">{{ wifi.freq_mhz > 5000 ? '5 GHz' : '2.4 GHz' }}</div>
          <div class="t-label">Band</div>
        </div>
        <div v-if="wifi.bitrate_mb" class="fact">
          <div class="fact-value">{{ wifi.bitrate_mb }} Mb/s</div>
          <div class="t-label">Bitrate</div>
        </div>
        <div v-if="wifi.state" class="fact">
          <div class="fact-value">{{ wifi.state }}</div>
          <div class="t-label">State</div>
        </div>
      </div>
    </template>

    <template v-if="store.snap?.bluetooth?.available">
      <h3 class="section">Bluetooth</h3>
      <div class="fact-grid">
        <div class="fact">
          <div class="fact-value">{{ store.snap.bluetooth.powered ? 'On' : 'Off' }}</div>
          <div class="t-label">{{ store.snap.bluetooth.adapter || 'Adapter' }}</div>
        </div>
        <div v-for="d in store.snap.bluetooth.devices ?? []" :key="d.address" class="fact">
          <div class="fact-value">{{ d.name }}</div>
          <div class="t-label">Connected</div>
        </div>
      </div>
    </template>
  </GlassSheet>
</template>

<style scoped>
.rate-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20px;
  padding: 4px 0 12px;
}
.rate-value { font-size: 1.15rem; font-weight: 400; padding-bottom: 6px; }
.section {
  font-size: 0.78rem;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--text-tertiary);
  font-weight: 500;
  margin: 18px 0 4px;
  text-align: center;
}
.fact-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px 10px;
  padding: 8px 0;
}
.fact { text-align: center; }
.fact-value { font-size: 1rem; font-weight: 500; padding-bottom: 3px; word-break: break-all; }
.ip6 { font-size: 0.78rem; }
</style>
