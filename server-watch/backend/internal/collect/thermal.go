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

// plausibleTemp reports whether a temperature reading is physically
// plausible for a phone SoC/battery sensor. Readings at or below 5 °C are
// treated as dead sensors (e.g. Qualcomm LLM/GLM islands that read 0 while
// their subsystem is asleep) rather than real temperatures.
func plausibleTemp(c float64) bool {
	return c > 5 && c < 130
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
		if _, err := strconv.ParseFloat(strings.TrimSpace(string(tempB)), 64); err != nil {
			continue
		}
		// Keep the zone even if currently implausible (a sleeping sensor
		// may wake up); Sample filters implausible readings.
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
		if !plausibleTemp(c) {
			continue // dead/sleeping sensor — hide rather than show 0°C
		}
		out = append(out, ThermalZone{Name: t.names[i], TempC: c})
	}
	return out
}

// SoCTemp picks the most meaningful CPU/SoC temperature. Zone readings are
// already filtered for plausibility by Sample.
func SoCTemp(zones []ThermalZone) (float64, bool) {
	// exact-name preferences first (msm_therm is the SoC sensor on this
	// Qualcomm platform), then substring fallbacks.
	exact := []string{"msm_therm", "soc_therm", "cpu_therm", "kryo_therm", "pm8998_tz", "pm8994_tz"}
	for _, want := range exact {
		for _, z := range zones {
			if strings.EqualFold(z.Name, want) {
				return z.TempC, true
			}
		}
	}
	preferred := []string{"cpu", "msm", "kryo", "tsens", "pm8998", "pm8994", "thermal", "soc"}
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
		// fallback: hottest plausible zone
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
