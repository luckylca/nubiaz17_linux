package collect

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
)

// BatteryStat describes the main battery. Pointer/omitempty fields are
// hidden in the UI when the kernel does not expose them.
type BatteryStat struct {
	Present          bool     `json:"present"`
	Name             string   `json:"name"`
	Capacity         *int     `json:"capacity,omitempty"` // percent
	Status           string   `json:"status,omitempty"`   // Charging/Discharging/Full/...
	VoltageV         *float64 `json:"voltage_v,omitempty"`
	CurrentA         *float64 `json:"current_a,omitempty"`
	PowerW           *float64 `json:"power_w,omitempty"`
	TempC            *float64 `json:"temp_c,omitempty"`
	ChargeFullAh     *float64 `json:"charge_full_ah,omitempty"`
	ChargeDesignAh   *float64 `json:"charge_design_ah,omitempty"`
	EnergyFullWh     *float64 `json:"energy_full_wh,omitempty"`
	EnergyDesignWh   *float64 `json:"energy_design_wh,omitempty"`
	CycleCount       *int     `json:"cycle_count,omitempty"`
	Health           *float64 `json:"health,omitempty"` // full/design percent
	Technology       string   `json:"technology,omitempty"`
}

type BatteryCollector struct {
	mu   sync.Mutex
	path string // e.g. /sys/class/power_supply/battery
}

func NewBatteryCollector() *BatteryCollector {
	b := &BatteryCollector{}
	b.enumerate()
	return b
}

func (b *BatteryCollector) enumerate() {
	entries, err := os.ReadDir("/sys/class/power_supply")
	if err != nil {
		return
	}
	for _, e := range entries {
		p := filepath.Join("/sys/class/power_supply", e.Name())
		typB, err := os.ReadFile(filepath.Join(p, "type"))
		if err != nil {
			continue
		}
		if strings.TrimSpace(string(typB)) == "Battery" {
			b.path = p
			return
		}
	}
}

func readStr(dir, name string) (string, bool) {
	b, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		return "", false
	}
	s := strings.TrimSpace(string(b))
	if s == "" {
		return s, false
	}
	return s, true
}

func readNum(dir, name string) (float64, bool) {
	s, ok := readStr(dir, name)
	if !ok {
		return 0, false
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, false
	}
	return v, true
}

// micro converts a sysfs value that is documented in micro-units (µV, µA,
// µWh, µAh) to base units. Heuristic guards against drivers reporting
// already-scaled values.
func micro(v float64) float64 { return v / 1e6 }

func (b *BatteryCollector) Sample() *BatteryStat {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.path == "" {
		b.enumerate()
		if b.path == "" {
			return &BatteryStat{Present: false}
		}
	}
	p := b.path
	st := &BatteryStat{Present: true, Name: filepath.Base(p)}

	if v, ok := readNum(p, "capacity"); ok {
		i := int(v + 0.5)
		st.Capacity = &i
	}
	if s, ok := readStr(p, "status"); ok {
		st.Status = s
	}
	if v, ok := readNum(p, "voltage_now"); ok {
		vv := micro(v)
		st.VoltageV = &vv
	}
	if v, ok := readNum(p, "current_now"); ok {
		vv := micro(v)
		st.CurrentA = &vv
	}
	if v, ok := readNum(p, "power_now"); ok {
		vv := micro(v)
		st.PowerW = &vv
	}
	if v, ok := readNum(p, "temp"); ok {
		// battery temp is usually 0.1°C units; sometimes plain °C
		t := v
		if t > 1000 {
			t = t / 1000
		} else if t > 150 {
			t = t / 10
		}
		st.TempC = &t
	}
	if v, ok := readNum(p, "charge_full"); ok {
		vv := micro(v)
		st.ChargeFullAh = &vv
	}
	if v, ok := readNum(p, "charge_full_design"); ok {
		vv := micro(v)
		st.ChargeDesignAh = &vv
	}
	if v, ok := readNum(p, "energy_full"); ok {
		vv := micro(v)
		st.EnergyFullWh = &vv
	}
	if v, ok := readNum(p, "energy_full_design"); ok {
		vv := micro(v)
		st.EnergyDesignWh = &vv
	}
	if v, ok := readNum(p, "cycle_count"); ok {
		i := int(v)
		st.CycleCount = &i
	}
	if s, ok := readStr(p, "technology"); ok {
		st.Technology = s
	}
	// health from charge or energy full/design
	if st.ChargeFullAh != nil && st.ChargeDesignAh != nil && *st.ChargeDesignAh > 0 {
		h := *st.ChargeFullAh / *st.ChargeDesignAh * 100
		st.Health = &h
	} else if st.EnergyFullWh != nil && st.EnergyDesignWh != nil && *st.EnergyDesignWh > 0 {
		h := *st.EnergyFullWh / *st.EnergyDesignWh * 100
		st.Health = &h
	}
	return st
}
