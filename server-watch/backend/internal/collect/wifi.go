package collect

import (
	"bufio"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// WifiStat describes the current Wi-Fi link. Fields are omitted when
// unavailable.
type WifiStat struct {
	Enabled   bool    `json:"enabled"`
	Interface string  `json:"interface,omitempty"`
	SSID      string  `json:"ssid,omitempty"`
	State     string  `json:"state,omitempty"`   // wpa_state e.g. COMPLETED
	SignalDbm *int    `json:"signal_dbm,omitempty"`
	SignalPct *int    `json:"signal_pct,omitempty"`
	FreqMHz   *int    `json:"freq_mhz,omitempty"`
	BitrateMb float64 `json:"bitrate_mb,omitempty"`
}

// WifiCollector talks to wpa_supplicant over its control socket (no shell
// forks) and falls back to /proc/net/wireless for signal level.
type WifiCollector struct {
	iface string
}

func NewWifiCollector(preferredIface string) *WifiCollector {
	w := &WifiCollector{iface: preferredIface}
	if w.iface == "" {
		w.iface = w.findWifiIface()
	}
	return w
}

func (w *WifiCollector) findWifiIface() string {
	entries, err := os.ReadDir("/sys/class/net")
	if err != nil {
		return ""
	}
	for _, e := range entries {
		if st, err := os.Stat(filepath.Join("/sys/class/net", e.Name(), "wireless")); err == nil && st.IsDir() {
			return e.Name()
		}
	}
	// qcacld style: /sys/class/net/wlan0/phy80211
	for _, e := range entries {
		if st, err := os.Stat(filepath.Join("/sys/class/net", e.Name(), "phy80211")); err == nil && st.IsDir() {
			return e.Name()
		}
	}
	return ""
}

// wpaRequest sends one command to the wpa_supplicant control interface.
func wpaRequest(ctrlDir, iface, cmd string) (string, error) {
	// local bind path
	local := filepath.Join(os.TempDir(), "server-watch-wpa-"+iface)
	os.Remove(local)
	laddr := &net.UnixAddr{Name: local, Net: "unixgram"}
	raddr := &net.UnixAddr{Name: filepath.Join(ctrlDir, iface), Net: "unixgram"}
	conn, err := net.DialUnix("unixgram", laddr, raddr)
	if err != nil {
		return "", err
	}
	defer conn.Close()
	defer os.Remove(local)
	conn.SetDeadline(time.Now().Add(800 * time.Millisecond))
	if _, err := conn.Write([]byte(cmd)); err != nil {
		return "", err
	}
	buf := make([]byte, 8192)
	n, err := conn.Read(buf)
	if err != nil {
		return "", err
	}
	return string(buf[:n]), nil
}

func signalPctFromDbm(dbm int) int {
	// map -100..-50 dBm to 0..100
	if dbm >= -50 {
		return 100
	}
	if dbm <= -100 {
		return 0
	}
	return 2 * (dbm + 100)
}

func (w *WifiCollector) Sample() *WifiStat {
	st := &WifiStat{}
	iface := w.iface
	if iface == "" {
		iface = w.findWifiIface()
		if iface == "" {
			return st
		}
		w.iface = iface
	}
	st.Enabled = true
	st.Interface = iface

	// try wpa_supplicant control sockets
	ctrlDirs := []string{"/run/wpa_supplicant", "/var/run/wpa_supplicant"}
	for _, dir := range ctrlDirs {
		if _, err := os.Stat(filepath.Join(dir, iface)); err != nil {
			continue
		}
		if resp, err := wpaRequest(dir, iface, "STATUS"); err == nil {
			sc := bufio.NewScanner(strings.NewReader(resp))
			for sc.Scan() {
				line := sc.Text()
				k, v, ok := strings.Cut(line, "=")
				if !ok {
					continue
				}
				switch k {
				case "ssid":
					st.SSID = v
				case "wpa_state":
					st.State = v
				case "freq":
					if f, err := strconv.Atoi(v); err == nil {
						st.FreqMHz = &f
					}
				}
			}
		}
		if resp, err := wpaRequest(dir, iface, "SIGNAL_POLL"); err == nil {
			sc := bufio.NewScanner(strings.NewReader(resp))
			for sc.Scan() {
				line := sc.Text()
				k, v, ok := strings.Cut(line, "=")
				if !ok {
					continue
				}
				switch k {
				case "RSSI":
					if d, err := strconv.Atoi(v); err == nil {
						st.SignalDbm = &d
						p := signalPctFromDbm(d)
						st.SignalPct = &p
					}
				case "AVG_RSSI":
					if st.SignalDbm == nil {
						if d, err := strconv.Atoi(v); err == nil {
							st.SignalDbm = &d
							p := signalPctFromDbm(d)
							st.SignalPct = &p
						}
					}
				case "LINKSPEED":
					if f, err := strconv.ParseFloat(v, 64); err == nil {
						st.BitrateMb = f
					}
				}
			}
		}
		break
	}

	// fallback signal from /proc/net/wireless (driver-level)
	if st.SignalDbm == nil {
		if data, err := os.ReadFile("/proc/net/wireless"); err == nil {
			for _, line := range strings.Split(string(data), "\n") {
				if !strings.HasPrefix(strings.TrimSpace(line), iface+":") {
					continue
				}
				f := strings.Fields(strings.TrimPrefix(strings.TrimSpace(line), iface+":"))
				// fields: status link level noise ...
				if len(f) >= 3 {
					lvlStr := strings.TrimSuffix(f[2], ".")
					if d, err := strconv.Atoi(lvlStr); err == nil {
						// qcacld reports dBm as negative in "level"
						if d > 0 {
							d = d - 256 // some drivers report unsigned
						}
						if d < 0 && d > -120 {
							st.SignalDbm = &d
							p := signalPctFromDbm(d)
							st.SignalPct = &p
						}
					}
				}
			}
		}
	}
	return st
}
