package collect

import (
	"fmt"
	"sync"

	"server-watch/backend/internal/config"
)

type Severity int

const (
	Normal Severity = iota
	Warning
	Critical
)

func (s Severity) String() string {
	switch s {
	case Warning:
		return "warning"
	case Critical:
		return "critical"
	default:
		return "normal"
	}
}

type Issue struct {
	Component string   `json:"component"`
	Detail    string   `json:"detail"`
	Severity  string   `json:"severity"`
	sev       Severity `json:"-"`
}

type SystemStatus struct {
	Level  string  `json:"level"` // normal / warning / critical
	Issues []Issue `json:"issues,omitempty"`
}

// Evaluate computes overall status from latest metrics.
func Evaluate(cfg *config.Config, cpu *CPUStat, socTemp float64, hasTemp bool,
	batt *BatteryStat, mem *MemoryStat, storage []StorageStat, net *NetInterfaceStat,
	dockerOK bool, dockerIssues []Issue) SystemStatus {

	level := Normal
	var issues []Issue
	add := func(comp, detail string, sev Severity) {
		if sev > level {
			level = sev
		}
		issues = append(issues, Issue{Component: comp, Detail: detail, Severity: sev.String(), sev: sev})
	}

	if hasTemp {
		if socTemp >= cfg.TempCritical {
			add("CPU", fmt.Sprintf("Temperature %.0f°C", socTemp), Critical)
		} else if socTemp >= cfg.TempWarning {
			add("CPU", fmt.Sprintf("Temperature %.0f°C", socTemp), Warning)
		}
	}
	if batt != nil && batt.Present && batt.TempC != nil {
		if *batt.TempC >= cfg.BattTempWarning+5 {
			add("Battery", fmt.Sprintf("Temperature %.0f°C", *batt.TempC), Critical)
		} else if *batt.TempC >= cfg.BattTempWarning {
			add("Battery", fmt.Sprintf("Temperature %.0f°C", *batt.TempC), Warning)
		}
	}
	if mem != nil && mem.UsedPercent >= cfg.MemoryWarning {
		add("Memory", fmt.Sprintf("%.0f%% used", mem.UsedPercent), Warning)
	}
	for _, s := range storage {
		if s.UsedPct >= cfg.StorageWarning {
			add("Storage", fmt.Sprintf("%s %.0f%% full", s.Mount, s.UsedPct), Warning)
		}
	}
	if net != nil && net.Name != "" && !net.Up {
		add("Network", net.Name+" down", Critical)
	}
	if !dockerOK {
		// docker unavailable is not an alert; UI shows "unavailable"
	} else {
		for _, i := range dockerIssues {
			add(i.Component, i.Detail, i.sev)
		}
	}
	return SystemStatus{Level: level.String(), Issues: issues}
}

// Ring is a fixed-size float history buffer.
type Ring struct {
	mu   sync.Mutex
	data []float64
	n    int
	size int
}

func NewRing(size int) *Ring { return &Ring{data: make([]float64, size), size: size} }

func (r *Ring) Add(v float64) {
	r.mu.Lock()
	r.data[r.n%r.size] = v
	r.n++
	r.mu.Unlock()
}

// Values returns oldest→newest.
func (r *Ring) Values() []float64 {
	r.mu.Lock()
	defer r.mu.Unlock()
	count := r.n
	if count > r.size {
		count = r.size
	}
	out := make([]float64, count)
	for i := 0; i < count; i++ {
		idx := (r.n - count + i) % r.size
		out[i] = r.data[idx]
	}
	return out
}
