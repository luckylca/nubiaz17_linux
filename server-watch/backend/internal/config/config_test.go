package config

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestConfigJSONUsesFrontendFieldNames(t *testing.T) {
	b, err := json.Marshal(Default())
	if err != nil {
		t.Fatal(err)
	}
	s := string(b)
	for _, key := range []string{"sample_interval_ms", "temp_warning", "night_mode", "burnin_protection", "docker_enable"} {
		if !strings.Contains(s, `"`+key+`"`) {
			t.Fatalf("JSON missing %q: %s", key, s)
		}
	}
	if strings.Contains(s, `"TempWarning"`) {
		t.Fatalf("Go field name leaked into API JSON: %s", s)
	}
}

func TestSaveUpdatesLoadedConfigInPlace(t *testing.T) {
	p := t.TempDir() + "/config.yaml"
	cfg, err := Load(p)
	if err != nil {
		t.Fatal(err)
	}
	next := *cfg
	next.TempWarning = 71.5
	if err := Save(&next); err != nil {
		t.Fatal(err)
	}
	if cfg.TempWarning != 71.5 {
		t.Fatalf("live config pointer not updated: got %v", cfg.TempWarning)
	}
	current := Current()
	if current.TempWarning != 71.5 {
		t.Fatalf("Current()=%v want 71.5", current.TempWarning)
	}
}
