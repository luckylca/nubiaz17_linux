package collect

import (
	"os"
	"strconv"
	"strings"
	"sync"
)

// CPUStat is one sample of CPU state.
type CPUStat struct {
	Total     float64  `json:"total"`      // percent 0-100
	PerCore   []float64 `json:"per_core"`  // percent per core
	FreqMHz   []int    `json:"freq_mhz"`  // per-core current freq
	MaxMHz    []int    `json:"max_mhz"`   // per-core max freq
	Load1     float64  `json:"load1"`
	Load5     float64  `json:"load5"`
	Load15    float64  `json:"load15"`
	Running   int      `json:"running"`
	Threads   int      `json:"threads"`
	Governor  string   `json:"governor,omitempty"`
	Cores     int      `json:"cores"`
}

type cpuTimes struct{ user, nice, system, idle, iowait, irq, softirq, steal uint64 }

func (c cpuTimes) total() uint64 {
	return c.user + c.nice + c.system + c.idle + c.iowait + c.irq + c.softirq + c.steal
}
func (c cpuTimes) busy() uint64 { return c.total() - c.idle - c.iowait }

type CPUCollector struct {
	mu    sync.Mutex
	prev  []cpuTimes // [0]=aggregate, then per-core
	cores int
}

func NewCPUCollector() *CPUCollector { return &CPUCollector{} }

func parseStatLine(line string) cpuTimes {
	f := strings.Fields(line)
	var t cpuTimes
	if len(f) < 8 {
		return t
	}
	vals := make([]uint64, 8)
	for i := 1; i <= 8; i++ {
		v, _ := strconv.ParseUint(f[i], 10, 64)
		vals[i-1] = v
	}
	t = cpuTimes{vals[0], vals[1], vals[2], vals[3], vals[4], vals[5], vals[6], vals[7]}
	return t
}

func readCPUTimes() []cpuTimes {
	data, err := os.ReadFile("/proc/stat")
	if err != nil {
		return nil
	}
	var out []cpuTimes
	for _, line := range strings.Split(string(data), "\n") {
		if !strings.HasPrefix(line, "cpu") {
			break
		}
		out = append(out, parseStatLine(line))
	}
	return out
}

// Sample returns current CPU stats; first call returns nil (needs a delta).
func (c *CPUCollector) Sample() *CPUStat {
	now := readCPUTimes()
	if len(now) == 0 {
		return nil
	}
	c.mu.Lock()
	defer c.mu.Unlock()

	st := &CPUStat{Cores: len(now) - 1}
	c.cores = st.Cores
	if c.prev != nil && len(c.prev) == len(now) {
		usage := func(a, b cpuTimes) float64 {
			dt := float64(b.total() - a.total())
			db := float64(b.busy() - a.busy())
			if dt <= 0 {
				return 0
			}
			p := db / dt * 100
			if p < 0 {
				p = 0
			}
			if p > 100 {
				p = 100
			}
			return p
		}
		st.Total = usage(c.prev[0], now[0])
		st.PerCore = make([]float64, len(now)-1)
		for i := 1; i < len(now); i++ {
			st.PerCore[i-1] = usage(c.prev[i], now[i])
		}
	}
	c.prev = now

	// frequencies
	st.FreqMHz = readFreqs("scaling_cur_freq")
	st.MaxMHz = readFreqs("cpuinfo_max_freq")
	if g, err := os.ReadFile("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"); err == nil {
		st.Governor = strings.TrimSpace(string(g))
	}
	// loadavg
	if lb, err := os.ReadFile("/proc/loadavg"); err == nil {
		f := strings.Fields(string(lb))
		if len(f) >= 4 {
			st.Load1, _ = strconv.ParseFloat(f[0], 64)
			st.Load5, _ = strconv.ParseFloat(f[1], 64)
			st.Load15, _ = strconv.ParseFloat(f[2], 64)
			if parts := strings.Split(f[3], "/"); len(parts) == 2 {
				st.Running, _ = strconv.Atoi(parts[0])
				st.Threads, _ = strconv.Atoi(parts[1])
			}
		}
	}
	return st
}

func readFreqs(name string) []int {
	entries, err := os.ReadDir("/sys/devices/system/cpu")
	if err != nil {
		return nil
	}
	var out []int
	for i := 0; ; i++ {
		found := false
		for _, e := range entries {
			if e.Name() == "cpu"+strconv.Itoa(i) {
				found = true
				break
			}
		}
		if !found {
			break
		}
		b, err := os.ReadFile("/sys/devices/system/cpu/cpu" + strconv.Itoa(i) + "/cpufreq/" + name)
		if err != nil {
			out = append(out, 0)
			continue
		}
		khz, _ := strconv.Atoi(strings.TrimSpace(string(b)))
		out = append(out, khz/1000)
	}
	return out
}
