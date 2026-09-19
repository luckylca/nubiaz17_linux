import { defineStore } from 'pinia'

export interface CPUStat {
  total: number
  per_core: number[]
  freq_mhz: number[]
  max_mhz: number[]
  load1: number
  load5: number
  load15: number
  running: number
  threads: number
  governor?: string
  cores: number
}

export interface MemoryStat {
  total_kb: number
  used_kb: number
  avail_kb: number
  free_kb: number
  cached_kb: number
  buffers_kb: number
  swap_total_kb: number
  swap_used_kb: number
  used_percent: number
}

export interface ThermalZone { name: string; temp_c: number }

export interface BatteryStat {
  present: boolean
  name: string
  capacity?: number
  status?: string
  voltage_v?: number
  current_a?: number
  power_w?: number
  temp_c?: number
  charge_full_ah?: number
  charge_design_ah?: number
  energy_full_wh?: number
  energy_design_wh?: number
  cycle_count?: number
  health?: number
  technology?: string
}

export interface NetStat {
  name: string
  ipv4?: string[]
  ipv6?: string[]
  rx_bytes: number
  tx_bytes: number
  rx_rate: number
  tx_rate: number
  up: boolean
}

export interface WifiStat {
  enabled: boolean
  interface?: string
  ssid?: string
  state?: string
  signal_dbm?: number
  signal_pct?: number
  freq_mhz?: number
  bitrate_mb?: number
}

export interface StorageStat {
  mount: string
  device: string
  fs_type: string
  total_b: number
  used_b: number
  avail_b: number
  used_pct: number
}

export interface BluetoothStat {
  available: boolean
  powered: boolean
  adapter?: string
  devices?: { name: string; address: string; connected: boolean }[]
}

export interface ContainerSummary {
  id: string
  name: string
  image: string
  state: string
  status: string
  health?: string
  started_at: number
  ports?: string[]
  restart_count: number
}

export interface ContainerStats {
  id: string
  cpu_percent: number
  mem_bytes: number
  mem_limit: number
  net_rx: number
  net_tx: number
  block_read: number
  block_write: number
  pids: number
}

export interface DockerState {
  available: boolean
  containers?: ContainerSummary[]
  stats?: Record<string, ContainerStats>
  running: number
  total: number
  healthy: boolean
}

export interface Issue { component: string; detail: string; severity: string }
export interface SystemStatus { level: string; issues?: Issue[] }

export interface Snapshot {
  ts: number
  uptime_sec: number
  cpu?: CPUStat
  memory?: MemoryStat
  soc_temp?: number
  thermal?: ThermalZone[]
  battery?: BatteryStat
  network?: NetStat
  gateway?: string
  wifi?: WifiStat
  storage?: StorageStat[]
  bluetooth?: BluetoothStat
  docker?: DockerState
  status: SystemStatus
  history?: Record<string, number[]>
}

interface MonitorState {
  snap: Snapshot | null
  connected: boolean
}

let ws: WebSocket | null = null
let reconnectTimer: number | null = null
let pollTimer: number | null = null
let backoff = 1000

export const useMonitorStore = defineStore('monitor', {
  state: (): MonitorState => ({ snap: null, connected: false }),
  getters: {
    statusLevel: (s): string => s.snap?.status?.level ?? 'normal',
    dockerStats: (s) => (id: string) => s.snap?.docker?.stats?.[id],
  },
  actions: {
    connect() {
      if (ws) return
      const proto = location.protocol === 'https:' ? 'wss' : 'ws'
      try {
        ws = new WebSocket(`${proto}://${location.host}/api/ws`)
      } catch {
        this.startPolling()
        return
      }
      ws.onopen = () => {
        this.connected = true
        backoff = 1000
        this.stopPolling()
      }
      ws.onmessage = (ev) => {
        try {
          this.snap = JSON.parse(ev.data as string)
        } catch { /* ignore malformed frame */ }
      }
      ws.onclose = () => {
        ws = null
        this.connected = false
        this.startPolling()
        scheduleReconnect(this)
      }
      ws.onerror = () => {
        ws?.close()
      }
    },
    startPolling() {
      if (pollTimer) return
      pollTimer = window.setInterval(async () => {
        try {
          const r = await fetch('/api/snapshot')
          if (r.ok) {
            this.snap = await r.json()
            this.connected = true
          }
        } catch {
          this.connected = false
        }
      }, 2000)
    },
    stopPolling() {
      if (pollTimer) {
        clearInterval(pollTimer)
        pollTimer = null
      }
    },
  },
})

function scheduleReconnect(store: ReturnType<typeof useMonitorStore>) {
  if (reconnectTimer) return
  reconnectTimer = window.setTimeout(() => {
    reconnectTimer = null
    backoff = Math.min(backoff * 2, 15000)
    store.connect()
  }, backoff)
}
