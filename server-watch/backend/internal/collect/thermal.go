package collect

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
)

// ThermalZone is one sensor.
type ThermalZone struct {
	Name  string  `json:"name"` // sysfs type
	TempC float64 `json:"temp_c"`
}

type ThermalCollector struct {
	mu    sync.Mutex
	zones []string // paths of valid zones
	names []string
}

func NewThermalCollector() *ThermalCollector {
	t := &ThermalCollector{}
	t.enumerate()
	return t
}

func (t *ThermalCollector) enumerate() {
	matches, _ := filepath.Glob("/sys/class/thermal/thermal_zone*")
	for _, z := range matches {
		typB, err1 := os.ReadFile(filepath.Join(z, "type"))
		tempB, err2 := os.ReadFile(filepath.Join(z, "temp"))
		if err1 != nil || err2 != nil {
			continue
		}
		typ := strings.TrimSpace(string(typB))
		v, err := strconv.ParseFloat(strings.TrimSpace(string(tempB)), 64)
		if err != nil {
			continue
		}
		c := normalizeTemp(v)
		// hide clearly broken sensors
		if c < -40 || c > 150 {
			continue
		}
		t.zones = append(t.zones, z)
		t.names = append(t.names, typ)
	}
}

// normalizeTemp converts raw thermal temp to degC. Kernel thermal zones are
// normally millidegree; some drivers report plain degC.
func normalizeTemp(v float64) float64 {
	if v > 1000 || v < -1000 {
		return v / 1000
	}
	return v
}

// Sample returns all zones.
func (t *ThermalCollector) Sample() []ThermalZone {
	t.mu.Lock()
	defer t.mu.Unlock()
	if len(t.zones) == 0 {
		t.enumerate()
	}
	out := make([]ThermalZone, 0, len(t.zones))
	for i, z := range t.zones {
		tempB, err := os.ReadFile(filepath.Join(z, "temp"))
		if err != nil {
			continue
		}
		v, err := strconv.ParseFloat(strings.TrimSpace(string(tempB)), 64)
		if err != nil {
			continue
		}
		c := normalizeTemp(v)
		if c < -40 || c > 150 {
			continue
		}
		out = append(out, ThermalZone{Name: t.names[i], TempC: c})
	}
	return out
}

// SoCTemp picks the most meaningful CPU/SoC temperature.
func SoCTemp(zones []ThermalZone) (float64, bool) {
	preferred := []string{"cpu", "soc", "pm8998", "pm8994", "msm", "kryo", "tsens", "thermal"}
	best := -1
	bestScore := 99
	for i, z := range zones {
		name := strings.ToLower(z.Name)
		for score, p := range preferred {
			if strings.Contains(name, p) && score < bestScore {
				best, bestScore = i, score
			}
		}
	}
	if best < 0 && len(zones) > 0 {
		// fallback: hottest zone
		max := 0
		for i, z := range zones {
			if z.TempC > zones[max].TempC {
				max = i
			}
		}
		return zones[max].TempC, true
	}
	if best < 0 {
		return 0, false
	}
	return zones[best].TempC, true
}
