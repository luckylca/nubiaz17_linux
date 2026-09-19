<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { formatKB, formatUptime } from '../composables/format'
import GlassSheet from '../components/GlassSheet.vue'

const props = defineProps<{ open: boolean }>()
defineEmits<{ close: [] }>()

interface Proc {
  pid: number
  name: string
  user: string
  state: string
  cpu_percent: number
  mem_kb: number
  threads: number
  uptime_sec: number
}

const procs = ref<Proc[]>([])
const query = ref('')
const sortKey = ref<'cpu' | 'mem' | 'pid'>('cpu')
let refreshTimer: number | null = null

async function refresh() {
  try {
    const r = await fetch('/api/processes')
    if (r.ok) procs.value = (await r.json()) ?? []
  } catch { /* keep stale */ }
}

watch(
  () => props.open,
  (v) => {
    if (v) {
      refresh()
      refreshTimer = window.setInterval(refresh, 5000)
    } else if (refreshTimer) {
      clearInterval(refreshTimer)
      refreshTimer = null
    }
  }
)

const filtered = computed(() => {
  let list = procs.value
  const q = query.value.trim().toLowerCase()
  if (q) list = list.filter((p) => p.name.toLowerCase().includes(q) || String(p.pid).includes(q))
  const sorted = [...list]
  if (sortKey.value === 'cpu') sorted.sort((a, b) => b.cpu_percent - a.cpu_percent)
  else if (sortKey.value === 'mem') sorted.sort((a, b) => b.mem_kb - a.mem_kb)
  else sorted.sort((a, b) => a.pid - b.pid)
  return sorted.slice(0, 80)
})
</script>

<template>
  <GlassSheet :open="open" title="Processes" wide @close="$emit('close')">
    <div class="toolbar">
      <input v-model="query" class="search" placeholder="Search processes" />
      <div class="sort-btns">
        <button class="sort-btn pressable" :class="{ active: sortKey === 'cpu' }" @click="sortKey = 'cpu'">CPU</button>
        <button class="sort-btn pressable" :class="{ active: sortKey === 'mem' }" @click="sortKey = 'mem'">MEM</button>
        <button class="sort-btn pressable" :class="{ active: sortKey === 'pid' }" @click="sortKey = 'pid'">PID</button>
      </div>
    </div>

    <div class="proc-head">
      <span class="c-pid">PID</span>
      <span class="c-name">Name</span>
      <span class="c-cpu">CPU</span>
      <span class="c-mem">Memory</span>
      <span class="c-user">User</span>
      <span class="c-state">S</span>
      <span class="c-thr">Thr</span>
      <span class="c-up">Up</span>
    </div>
    <div v-for="p in filtered" :key="p.pid" class="proc-row">
      <span class="c-pid t-tertiary">{{ p.pid }}</span>
      <span class="c-name">{{ p.name }}</span>
      <span class="c-cpu">{{ p.cpu_percent.toFixed(1) }}%</span>
      <span class="c-mem">{{ formatKB(p.mem_kb) }}</span>
      <span class="c-user t-secondary">{{ p.user }}</span>
      <span class="c-state t-tertiary">{{ p.state }}</span>
      <span class="c-thr t-tertiary">{{ p.threads }}</span>
      <span class="c-up t-tertiary">{{ formatUptime(p.uptime_sec) }}</span>
    </div>
    <div v-if="!filtered.length" class="t-secondary" style="text-align:center; padding: 30px 0">
      No processes
    </div>
  </GlassSheet>
</template>

<style scoped>
.toolbar {
  display: flex;
  gap: 12px;
  align-items: center;
  padding-bottom: 12px;
  position: sticky;
  top: -6px;
}
.search {
  flex: 1;
  min-height: 48px;
  border-radius: var(--radius-pill);
  border: 0.5px solid var(--glass-border-soft);
  background: rgba(255, 255, 255, 0.06);
  color: var(--text-primary);
  font-family: inherit;
  font-size: 0.95rem;
  padding: 0 20px;
  outline: none;
}
.search::placeholder { color: var(--text-tertiary); }
.sort-btns { display: flex; gap: 6px; }
.sort-btn {
  min-width: 58px; min-height: 48px;
  border-radius: var(--radius-pill);
  border: 0.5px solid var(--glass-border-soft);
  background: rgba(255, 255, 255, 0.05);
  color: var(--text-tertiary);
  font-family: inherit; font-size: 0.8rem; font-weight: 600; letter-spacing: 0.08em;
}
.sort-btn.active { color: var(--text-primary); background: rgba(255, 255, 255, 0.12); }

.proc-head, .proc-row {
  display: grid;
  grid-template-columns: 52px 1fr 60px 76px 70px 26px 40px 64px;
  gap: 8px;
  align-items: center;
  padding: 7px 4px;
  font-size: 0.82rem;
}
.proc-head {
  color: var(--text-tertiary);
  font-size: 0.68rem;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  border-bottom: 0.5px solid rgba(255, 255, 255, 0.09);
  position: sticky;
  top: 44px;
  background: transparent;
}
.proc-row { border-bottom: 0.5px solid rgba(255, 255, 255, 0.04); }
.c-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
</style>
