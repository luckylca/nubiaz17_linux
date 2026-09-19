import { ref, onMounted, onUnmounted } from 'vue'

/** current time, updated every 250ms */
export function useNow() {
  const now = ref(new Date())
  let t: number
  onMounted(() => {
    t = window.setInterval(() => {
      now.value = new Date()
    }, 250)
  })
  onUnmounted(() => clearInterval(t))
  return now
}

export function formatBytes(b: number, perSec = false): string {
  if (!isFinite(b) || b < 0) b = 0
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let i = 0
  while (b >= 1024 && i < units.length - 1) {
    b /= 1024
    i++
  }
  const v = b >= 100 ? Math.round(b) : b >= 10 ? b.toFixed(1) : b.toFixed(b >= 1 ? 1 : 0)
  return `${v} ${units[i]}${perSec ? '/s' : ''}`
}

export function formatKB(kb: number): string {
  return formatBytes(kb * 1024)
}

export function formatUptime(sec: number): string {
  if (sec < 60) return `${sec}s`
  if (sec < 3600) return `${Math.floor(sec / 60)}m`
  if (sec < 86400) return `${Math.floor(sec / 3600)}h ${Math.floor((sec % 3600) / 60)}m`
  return `${Math.floor(sec / 86400)}d ${Math.floor((sec % 86400) / 3600)}h`
}
