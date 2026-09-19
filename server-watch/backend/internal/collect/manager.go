package collect

import (
	"context"
	"log"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"server-watch/backend/internal/config"
	"server-watch/backend/internal/dockerx"
)

// DockerState is the docker portion of the snapshot.
type DockerState struct {
	Available  bool                               `json:"available"`
	Containers []dockerx.ContainerSummary         `json:"containers,omitempty"`
	Stats      map[string]*dockerx.ContainerStats `json:"stats,omitempty"`
	Running    int                                `json:"running"`
	Total      int                                `json:"total"`
	Healthy    bool                               `json:"healthy"`
}

// Snapshot is the full state pushed to clients.
type Snapshot struct {
	TS        int64                `json:"ts"`
	UptimeSec int64                `json:"uptime_sec"`
	CPU       *CPUStat             `json:"cpu,omitempty"`
	Memory    *MemoryStat          `json:"memory,omitempty"`
	SoCTemp   *float64             `json:"soc_temp,omitempty"`
	Thermal   []ThermalZone        `json:"thermal,omitempty"`
	Battery   *BatteryStat         `json:"battery,omitempty"`
	Network   *NetInterfaceStat    `json:"network,omitempty"`
	Gateway   string               `json:"gateway,omitempty"`
	Wifi      *WifiStat            `json:"wifi,omitempty"`
	Storage   []StorageStat        `json:"storage,omitempty"`
	Bluetooth *BluetoothStat       `json:"bluetooth,omitempty"`
	Docker    *DockerState         `json:"docker,omitempty"`
	Status    SystemStatus         `json:"status"`
	History   map[string][]float64 `json:"history,omitempty"`
}

// Manager runs the sampling loops and keeps the latest snapshot.
type Manager struct {
	cfg *config.Config

	cpu     *CPUCollector
	thermal *ThermalCollector
	batt    *BatteryCollector
	net     *NetworkCollector
	wifi    *WifiCollector
	bt      *BluetoothCollector
	procs   *ProcessCollector
	docker  *dockerx.Client

	mu   sync.RWMutex
	snap Snapshot

	histCPU  *Ring
	histTemp *Ring
	histRx   *Ring
	histTx   *Ring

	dockerIssues   []Issue
	prevRestarts   map[string]int
	lastDockerList time.Time
}

func NewManager(cfg *config.Config) *Manager {
	m := &Manager{
		cfg:          cfg,
		cpu:          NewCPUCollector(),
		thermal:      NewThermalCollector(),
		batt:         NewBatteryCollector(),
		net:          NewNetworkCollector(cfg.NetInterface),
		wifi:         NewWifiCollector(cfg.NetInterface),
		bt:           NewBluetoothCollector(),
		procs:        NewProcessCollector(),
		histCPU:      NewRing(300),
		histTemp:     NewRing(300),
		histRx:       NewRing(300),
		histTx:       NewRing(300),
		prevRestarts: map[string]int{},
	}
	m.docker = dockerx.NewClient("")
	return m
}

// Processes returns a fresh process table (on demand, heavy).
func (m *Manager) Processes() []ProcessInfo { return m.procs.Sample() }

// Docker returns the client when Docker monitoring is enabled.
func (m *Manager) Docker() *dockerx.Client {
	if !m.cfg.DockerEnable {
		return nil
	}
	return m.docker
}

// Latest returns the current snapshot.
func (m *Manager) Latest() Snapshot {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.snap
}

// Run starts sampling loops until ctx is cancelled.
func (m *Manager) Run(ctx context.Context) {
	fast := time.Duration(m.cfg.SampleIntervalMs) * time.Millisecond
	if fast < 250*time.Millisecond {
		fast = time.Second
	}
	slow := time.Duration(m.cfg.SlowIntervalMs) * time.Millisecond
	if slow < 2*time.Second {
		slow = 10 * time.Second
	}

	// prime CPU baseline
	m.cpu.Sample()

	go func() {
		t := time.NewTicker(fast)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				m.sampleFast()
			}
		}
	}()
	go func() {
		m.sampleSlow()
		t := time.NewTicker(slow)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				m.sampleSlow()
			}
		}
	}()
	go func() {
		m.sampleDockerStats()
		t := time.NewTicker(5 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				m.sampleDockerStats()
			}
		}
	}()
}

func (m *Manager) sampleFast() {
	cpu := m.cpu.Sample()
	mem := SampleMemory()
	zones := m.thermal.Sample()
	batt := m.batt.Sample()
	netst := m.net.Sample()

	var socPtr *float64
	if t, ok := SoCTemp(zones); ok {
		socPtr = &t
		m.histTemp.Add(t)
	}
	if cpu != nil {
		m.histCPU.Add(cpu.Total)
	}
	if netst != nil {
		m.histRx.Add(netst.RxRate)
		m.histTx.Add(netst.TxRate)
	}

	m.mu.Lock()
	s := &m.snap
	s.TS = time.Now().Unix()
	s.UptimeSec = systemUptimeSec()
	if cpu != nil {
		s.CPU = cpu
	}
	s.Memory = mem
	s.Thermal = zones
	s.SoCTemp = socPtr
	s.Battery = batt
	s.Network = netst
	s.History = map[string][]float64{
		"cpu":  tail(m.histCPU.Values(), 60),
		"temp": tail(m.histTemp.Values(), 60),
		"rx":   tail(m.histRx.Values(), 60),
		"tx":   tail(m.histTx.Values(), 60),
	}
	m.refreshStatusLocked()
	m.mu.Unlock()
}

func systemUptimeSec() int64 {
	b, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return 0
	}
	f := strings.Fields(string(b))
	if len(f) == 0 {
		return 0
	}
	v, err := strconv.ParseFloat(f[0], 64)
	if err != nil || v < 0 {
		return 0
	}
	return int64(v)
}

func (m *Manager) sampleSlow() {
	storage := SampleStorage()
	wifi := m.wifi.Sample()
	var bt *BluetoothStat
	if m.cfg.BluetoothEnable {
		bt = m.bt.Sample()
	}

	m.mu.Lock()
	m.snap.Storage = storage
	m.snap.Wifi = wifi
	m.snap.Gateway = Gateway()
	if bt != nil && bt.Available {
		m.snap.Bluetooth = bt
	} else {
		m.snap.Bluetooth = nil
	}
	m.mu.Unlock()

	m.sampleDockerList()
}

func (m *Manager) sampleDockerList() {
	if !m.cfg.DockerEnable {
		m.mu.Lock()
		m.snap.Docker = nil
		m.dockerIssues = nil
		m.refreshStatusLocked()
		m.mu.Unlock()
		return
	}
	if m.docker == nil {
		return
	}
	if !m.docker.Available() {
		m.mu.Lock()
		m.snap.Docker = &DockerState{Available: false}
		m.mu.Unlock()
		return
	}
	containers, err := m.docker.ListContainers()
	if err != nil {
		log.Printf("docker list: %v", err)
		return
	}
	var issues []Issue
	running := 0
	for i := range containers {
		c := &containers[i]
		started, restarts, health, exitCode, err := m.docker.Inspect(c.ID)
		if err == nil {
			c.Started = started
			c.Restarts = restarts
			if health != "" {
				c.Health = health
			}
			if prev, ok := m.prevRestarts[c.ID]; ok && restarts > prev {
				issues = append(issues, Issue{
					Component: "Docker", Detail: c.Name + " restarted",
					Severity: Warning.String(), sev: Warning,
				})
			}
			m.prevRestarts[c.ID] = restarts
			if c.State == "exited" && exitCode != 0 {
				issues = append(issues, Issue{
					Component: "Docker", Detail: c.Name + " exited unexpectedly",
					Severity: Warning.String(), sev: Warning,
				})
			}
		}
		if c.State == "running" {
			running++
			if c.Health == "unhealthy" {
				issues = append(issues, Issue{
					Component: "Docker", Detail: c.Name + " unhealthy",
					Severity: Critical.String(), sev: Critical,
				})
			}
		}
	}
	m.mu.Lock()
	ds := &DockerState{
		Available:  true,
		Containers: containers,
		Running:    running,
		Total:      len(containers),
		Healthy:    len(issues) == 0,
	}
	if m.snap.Docker != nil && m.snap.Docker.Stats != nil {
		ds.Stats = m.snap.Docker.Stats
	}
	m.snap.Docker = ds
	m.dockerIssues = issues
	m.refreshStatusLocked()
	m.mu.Unlock()
}

func (m *Manager) sampleDockerStats() {
	if !m.cfg.DockerEnable || m.docker == nil {
		return
	}
	m.mu.RLock()
	ds := m.snap.Docker
	m.mu.RUnlock()
	if ds == nil || !ds.Available {
		return
	}
	stats := map[string]*dockerx.ContainerStats{}
	for _, c := range ds.Containers {
		if c.State != "running" {
			continue
		}
		if st, err := m.docker.StatsOne(c.ID); err == nil {
			stats[c.ID] = st
		}
	}
	m.mu.Lock()
	if m.snap.Docker != nil {
		m.snap.Docker.Stats = stats
	}
	m.mu.Unlock()
}

// refreshStatusLocked recomputes status from m.snap; caller holds mu.
func (m *Manager) refreshStatusLocked() {
	s := &m.snap
	var soc float64
	hasSoc := false
	if s.SoCTemp != nil {
		soc, hasSoc = *s.SoCTemp, true
	}
	dockerOK := s.Docker != nil && s.Docker.Available
	s.Status = Evaluate(m.cfg, s.CPU, soc, hasSoc, s.Battery, s.Memory,
		s.Storage, s.Network, dockerOK, m.dockerIssues)
}

func tail(v []float64, n int) []float64 {
	if len(v) <= n {
		return v
	}
	return v[len(v)-n:]
}
