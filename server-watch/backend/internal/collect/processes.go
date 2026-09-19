package collect

import (
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

type ProcessInfo struct {
	PID       int     `json:"pid"`
	Name      string  `json:"name"`
	User      string  `json:"user"`
	State     string  `json:"state"`
	CPUPercent float64 `json:"cpu_percent"`
	MemKB     uint64  `json:"mem_kb"`
	Threads   int     `json:"threads"`
	UptimeSec int64   `json:"uptime_sec"`
}

type ProcessCollector struct {
	mu       sync.Mutex
	prev     map[int]uint64 // pid -> total jiffies
	prevTime time.Time
	clkTck   int64
	pageKB   int64
}

func NewProcessCollector() *ProcessCollector {
	clk := int64(100)
	page := int64(4096)
	// best-effort without syscall deps; standard on Linux arm64
	return &ProcessCollector{prev: map[int]uint64{}, clkTck: clk, pageKB: page / 1024}
}

var bootTimeOnce sync.Once
var bootTime int64

func getBootTime() int64 {
	bootTimeOnce.Do(func() {
		if data, err := os.ReadFile("/proc/stat"); err == nil {
			for _, line := range strings.Split(string(data), "\n") {
				if strings.HasPrefix(line, "btime ") {
					v, _ := strconv.ParseInt(strings.TrimSpace(strings.TrimPrefix(line, "btime ")), 10, 64)
					bootTime = v
					return
				}
			}
		}
		bootTime = time.Now().Unix()
	})
	return bootTime
}

func uidToName(uid string) string {
	// minimal: avoid reading /etc/passwd every time
	if uid == "0" {
		return "root"
	}
	return uid
}

func readUID(path string) string {
	b, err := os.ReadFile(path + "/status")
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(b), "\n") {
		if strings.HasPrefix(line, "Uid:") {
			f := strings.Fields(line)
			if len(f) >= 2 {
				return f[1]
			}
		}
	}
	return ""
}

// Sample scans /proc. Intended to be called on demand or at slow cadence.
func (p *ProcessCollector) Sample() []ProcessInfo {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return nil
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	now := time.Now()
	dt := now.Sub(p.prevTime).Seconds()

	uptime := now.Unix() - getBootTime()
	_ = uptime

	cur := map[int]uint64{}
	var out []ProcessInfo
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		dir := "/proc/" + e.Name()
		statB, err := os.ReadFile(dir + "/stat")
		if err != nil {
			continue
		}
		stat := string(statB)
		l := strings.Index(stat, "(")
		r := strings.LastIndex(stat, ")")
		if l < 0 || r < 0 || r <= l {
			continue
		}
		name := stat[l+1 : r]
		f := strings.Fields(stat[r+1:])
		if len(f) < 22 {
			continue
		}
		// f[0]=state ... f[11]=utime f[12]=stime f[17]=num_threads f[19]=starttime
		utime, _ := strconv.ParseUint(f[11], 10, 64)
		stime, _ := strconv.ParseUint(f[12], 10, 64)
		total := utime + stime
		startJ, _ := strconv.ParseInt(f[19], 10, 64)
		threads, _ := strconv.Atoi(f[17])

		var cpuPct float64
		if prevTotal, ok := p.prev[pid]; ok && dt > 0 {
			delta := float64(total - prevTotal)
			cpuPct = delta / float64(p.clkTck) / dt * 100
		}
		cur[pid] = total

		var memKB uint64
		if sb, err := os.ReadFile(dir + "/statm"); err == nil {
			sf := strings.Fields(string(sb))
			if len(sf) >= 2 {
				pages, _ := strconv.ParseInt(sf[1], 10, 64)
				memKB = uint64(pages) * uint64(p.pageKB)
			}
		}
		upSec := int64(0)
		if p.clkTck > 0 {
			upSec = uptime - startJ/p.clkTck
			if upSec < 0 {
				upSec = 0
			}
		}
		out = append(out, ProcessInfo{
			PID:        pid,
			Name:       name,
			User:       uidToName(readUID(dir)),
			State:      f[0],
			CPUPercent: cpuPct,
			MemKB:      memKB,
			Threads:    threads,
			UptimeSec:  upSec,
		})
	}
	p.prev = cur
	p.prevTime = now

	// top by CPU then memory
	sort.Slice(out, func(i, j int) bool {
		if out[i].CPUPercent != out[j].CPUPercent {
			return out[i].CPUPercent > out[j].CPUPercent
		}
		return out[i].MemKB > out[j].MemKB
	})
	return out
}
