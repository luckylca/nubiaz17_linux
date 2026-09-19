package collect

import (
	"net"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

type NetInterfaceStat struct {
	Name    string   `json:"name"`
	IPv4    []string `json:"ipv4,omitempty"`
	IPv6    []string `json:"ipv6,omitempty"`
	RxBytes uint64   `json:"rx_bytes"`
	TxBytes uint64   `json:"tx_bytes"`
	RxRate  float64  `json:"rx_rate"` // bytes/sec
	TxRate  float64  `json:"tx_rate"`
	Up      bool     `json:"up"`
}

type NetworkCollector struct {
	mu       sync.Mutex
	prev     map[string][2]uint64
	prevTime time.Time
	iface    string // preferred interface, "" = auto
}

func NewNetworkCollector(iface string) *NetworkCollector {
	return &NetworkCollector{iface: iface, prev: map[string][2]uint64{}}
}

func readNetDev() map[string][2]uint64 {
	data, err := os.ReadFile("/proc/net/dev")
	if err != nil {
		return nil
	}
	out := map[string][2]uint64{}
	for _, line := range strings.Split(string(data), "\n") {
		i := strings.Index(line, ":")
		if i < 0 {
			continue
		}
		name := strings.TrimSpace(line[:i])
		f := strings.Fields(line[i+1:])
		if len(f) < 16 {
			continue
		}
		rx, _ := strconv.ParseUint(f[0], 10, 64)
		tx, _ := strconv.ParseUint(f[8], 10, 64)
		out[name] = [2]uint64{rx, tx}
	}
	return out
}

func isPhysical(name string) bool {
	if name == "lo" {
		return false
	}
	for _, p := range []string{"docker", "veth", "br-", "virb", "tailscale", "tun", "tap", "wg"} {
		if strings.HasPrefix(name, p) {
			return false
		}
	}
	return true
}

// pickInterface chooses the primary interface: configured override, else the
// interface holding the default route, else first physical one that is up.
func (n *NetworkCollector) pickInterface(counters map[string][2]uint64) string {
	if n.iface != "" {
		return n.iface
	}
	if data, err := os.ReadFile("/proc/net/route"); err == nil {
		for _, line := range strings.Split(string(data), "\n")[1:] {
			f := strings.Fields(line)
			if len(f) >= 2 && f[1] == "00000000" {
				if _, ok := counters[f[0]]; ok {
					return f[0]
				}
			}
		}
	}
	for name := range counters {
		if isPhysical(name) {
			if b, err := os.ReadFile("/sys/class/net/" + name + "/operstate"); err == nil &&
				strings.TrimSpace(string(b)) == "up" {
				return name
			}
		}
	}
	return ""
}

func ifaceAddrs(name string) (v4, v6 []string) {
	iface, err := net.InterfaceByName(name)
	if err != nil {
		return
	}
	addrs, err := iface.Addrs()
	if err != nil {
		return
	}
	for _, a := range addrs {
		ipnet, ok := a.(*net.IPNet)
		if !ok {
			continue
		}
		if ipnet.IP.IsLoopback() || ipnet.IP.IsLinkLocalUnicast() {
			continue
		}
		if ipnet.IP.To4() != nil {
			v4 = append(v4, ipnet.IP.String())
		} else {
			v6 = append(v6, ipnet.IP.String())
		}
	}
	return
}

// Sample returns stats for the primary interface plus rates.
func (n *NetworkCollector) Sample() *NetInterfaceStat {
	n.mu.Lock()
	defer n.mu.Unlock()
	counters := readNetDev()
	if counters == nil {
		return nil
	}
	now := time.Now()
	name := n.pickInterface(counters)
	st := &NetInterfaceStat{Name: name}
	if name == "" {
		return st
	}
	rxtx, ok := counters[name]
	if !ok {
		return st
	}
	st.RxBytes, st.TxBytes = rxtx[0], rxtx[1]
	if b, err := os.ReadFile("/sys/class/net/" + name + "/operstate"); err == nil {
		st.Up = strings.TrimSpace(string(b)) == "up"
	}
	st.IPv4, st.IPv6 = ifaceAddrs(name)
	if prev, ok := n.prev[name]; ok && !n.prevTime.IsZero() {
		dt := now.Sub(n.prevTime).Seconds()
		if dt > 0 {
			if rxtx[0] >= prev[0] {
				st.RxRate = float64(rxtx[0]-prev[0]) / dt
			}
			if rxtx[1] >= prev[1] {
				st.TxRate = float64(rxtx[1]-prev[1]) / dt
			}
		}
	}
	n.prev = map[string][2]uint64{name: rxtx}
	n.prevTime = now
	return st
}

// Gateway returns the IPv4 default gateway, best effort.
func Gateway() string {
	data, err := os.ReadFile("/proc/net/route")
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(data), "\n")[1:] {
		f := strings.Fields(line)
		if len(f) >= 3 && f[1] == "00000000" {
			v, err := strconv.ParseUint(f[2], 16, 32)
			if err != nil {
				continue
			}
			return net.IPv4(byte(v), byte(v>>8), byte(v>>16), byte(v>>24)).String()
		}
	}
	return ""
}
