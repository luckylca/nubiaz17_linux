package config

import (
	"os"
	"path/filepath"
	"sync"

	"gopkg.in/yaml.v3"
)

// Config is the agent configuration. All fields have sane defaults and the
// file is created on first start.
type Config struct {
	Listen           string  `yaml:"listen" json:"listen"`
	SampleIntervalMs int     `yaml:"sample_interval_ms" json:"sample_interval_ms"`
	SlowIntervalMs   int     `yaml:"slow_interval_ms" json:"slow_interval_ms"`
	TempWarning      float64 `yaml:"temp_warning" json:"temp_warning"`
	TempCritical     float64 `yaml:"temp_critical" json:"temp_critical"`
	BattTempWarning  float64 `yaml:"batt_temp_warning" json:"batt_temp_warning"`
	StorageWarning   float64 `yaml:"storage_warning" json:"storage_warning"`
	MemoryWarning    float64 `yaml:"memory_warning" json:"memory_warning"`
	NightMode        bool    `yaml:"night_mode" json:"night_mode"`
	DimTimeoutSec    int     `yaml:"dim_timeout_sec" json:"dim_timeout_sec"`
	BurnInProtection bool    `yaml:"burnin_protection" json:"burnin_protection"`
	DockerEnable     bool    `yaml:"docker_enable" json:"docker_enable"`
	BluetoothEnable  bool    `yaml:"bluetooth_enable" json:"bluetooth_enable"`
	NetInterface     string  `yaml:"net_interface" json:"net_interface"`
}

func Default() *Config {
	return &Config{
		Listen:           "127.0.0.1:8765",
		SampleIntervalMs: 2000,
		SlowIntervalMs:   20000,
		TempWarning:      65,
		TempCritical:     78,
		BattTempWarning:  43,
		StorageWarning:   85,
		MemoryWarning:    90,
		NightMode:        true,
		DimTimeoutSec:    120,
		BurnInProtection: true,
		DockerEnable:     true,
		BluetoothEnable:  true,
	}
}

func DefaultPath() string {
	if p := os.Getenv("SERVER_WATCH_CONFIG"); p != "" {
		return p
	}
	// system location first, then user config
	if _, err := os.Stat("/etc/server-watch"); err == nil {
		return "/etc/server-watch/config.yaml"
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "server-watch", "config.yaml")
}

var (
	mu   sync.RWMutex
	cur  *Config
	path string
)

// Load reads the config file, creating a default one if missing.
func Load(p string) (*Config, error) {
	if p == "" {
		p = DefaultPath()
	}
	cfg := Default()
	data, err := os.ReadFile(p)
	if err != nil {
		if os.IsNotExist(err) {
			if mkerr := os.MkdirAll(filepath.Dir(p), 0o755); mkerr == nil {
				out, _ := yaml.Marshal(cfg)
				_ = os.WriteFile(p, out, 0o644)
			}
		} else {
			return nil, err
		}
	} else if len(data) > 0 {
		if uerr := yaml.Unmarshal(data, cfg); uerr != nil {
			return nil, uerr
		}
	}
	mu.Lock()
	cur, path = cfg, p
	mu.Unlock()
	return cfg, nil
}

// Current returns the active config (never nil).
func Current() *Config {
	mu.RLock()
	defer mu.RUnlock()
	if cur == nil {
		return Default()
	}
	copy := *cur
	return &copy
}

// Path returns the active config file path.
func Path() string {
	mu.RLock()
	defer mu.RUnlock()
	return path
}

// Save writes cfg to the active path and makes it current.
func Save(cfg *Config) error {
	mu.Lock()
	defer mu.Unlock()
	out, err := yaml.Marshal(cfg)
	if err != nil {
		return err
	}
	if path == "" {
		path = DefaultPath()
	}
	if err := os.WriteFile(path, out, 0o644); err != nil {
		return err
	}
	if cur == nil {
		cur = cfg
	} else {
		// Keep pointer identity stable: collectors hold the object returned by
		// Load, so mutating it makes thresholds/toggles take effect live.
		*cur = *cfg
	}
	return nil
}
