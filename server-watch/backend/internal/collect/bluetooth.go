package collect

import (
	"strings"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
)

type BTDevice struct {
	Name      string `json:"name"`
	Address   string `json:"address"`
	Connected bool   `json:"connected"`
}

type BluetoothStat struct {
	Available bool       `json:"available"`
	Powered   bool       `json:"powered"`
	Adapter   string     `json:"adapter,omitempty"`
	Devices   []BTDevice `json:"devices,omitempty"`
}

type BluetoothCollector struct {
	mu       sync.Mutex
	disabled bool
}

func NewBluetoothCollector() *BluetoothCollector { return &BluetoothCollector{} }

func (b *BluetoothCollector) Sample() *BluetoothStat {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.disabled {
		return &BluetoothStat{Available: false}
	}
	st := &BluetoothStat{}

	conn, err := dbus.ConnectSystemBus()
	if err != nil {
		return st
	}
	defer conn.Close()

	obj := conn.Object("org.bluez", "/")
	var managed map[dbus.ObjectPath]map[string]map[string]dbus.Variant
	call := obj.Call("org.freedesktop.DBus.ObjectManager.GetManagedObjects", 0)
	if call.Err != nil {
		// bluez not running — mark unavailable (don't permanently disable;
		// it may start later, but we retry at slow-loop cadence anyway)
		return st
	}
	if call.Store(&managed) != nil {
		return st
	}
	st.Available = true
	for path, ifaces := range managed {
		if ad, ok := ifaces["org.bluez.Adapter1"]; ok {
			if st.Adapter == "" {
				if name, ok := ad["Alias"].Value().(string); ok {
					st.Adapter = name
				} else if name, ok := ad["Name"].Value().(string); ok {
					st.Adapter = name
				}
				if pw, ok := ad["Powered"].Value().(bool); ok {
					st.Powered = pw
				}
			}
		}
		if dv, ok := ifaces["org.bluez.Device1"]; ok {
			_ = path
			var d BTDevice
			if name, ok := dv["Alias"].Value().(string); ok {
				d.Name = name
			} else if name, ok := dv["Name"].Value().(string); ok {
				d.Name = name
			}
			if addr, ok := dv["Address"].Value().(string); ok {
				d.Address = addr
			}
			if cn, ok := dv["Connected"].Value().(bool); ok {
				d.Connected = cn
			}
			if d.Connected && d.Name != "" {
				st.Devices = append(st.Devices, d)
			}
		}
	}
	if strings.TrimSpace(st.Adapter) == "" {
		// bluez running but no adapter (e.g. hci down)
		st.Adapter = ""
	}
	_ = time.Now
	return st
}
