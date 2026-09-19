package collect

import (
	"os"
	"strconv"
	"strings"
)

type MemoryStat struct {
	TotalKB     uint64 `json:"total_kb"`
	UsedKB      uint64 `json:"used_kb"`
	AvailKB     uint64 `json:"avail_kb"`
	FreeKB      uint64 `json:"free_kb"`
	CachedKB    uint64 `json:"cached_kb"`
	BuffersKB   uint64 `json:"buffers_kb"`
	SwapTotalKB uint64 `json:"swap_total_kb"`
	SwapUsedKB  uint64 `json:"swap_used_kb"`
	UsedPercent float64 `json:"used_percent"`
}

func SampleMemory() *MemoryStat {
	data, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return nil
	}
	m := map[string]uint64{}
	for _, line := range strings.Split(string(data), "\n") {
		f := strings.Fields(line)
		if len(f) < 2 {
			continue
		}
		key := strings.TrimSuffix(f[0], ":")
		v, _ := strconv.ParseUint(f[1], 10, 64)
		m[key] = v // kB
	}
	st := &MemoryStat{
		TotalKB:     m["MemTotal"],
		AvailKB:     m["MemAvailable"],
		FreeKB:      m["MemFree"],
		CachedKB:    m["Cached"] + m["SReclaimable"],
		BuffersKB:   m["Buffers"],
		SwapTotalKB: m["SwapTotal"],
	}
	if st.AvailKB == 0 {
		st.AvailKB = st.FreeKB + st.CachedKB + st.BuffersKB
	}
	if st.TotalKB > st.AvailKB {
		st.UsedKB = st.TotalKB - st.AvailKB
	}
	if m["SwapTotal"] > m["SwapFree"] {
		st.SwapUsedKB = m["SwapTotal"] - m["SwapFree"]
	}
	if st.TotalKB > 0 {
		st.UsedPercent = float64(st.UsedKB) / float64(st.TotalKB) * 100
	}
	return st
}
