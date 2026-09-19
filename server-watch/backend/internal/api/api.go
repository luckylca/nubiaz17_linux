package api

import (
	"context"
	"encoding/json"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"server-watch/backend/internal/collect"
	"server-watch/backend/internal/config"
	"server-watch/backend/internal/dockerx"
	"server-watch/backend/internal/hub"
)

// Server wires HTTP routes, the websocket hub and the static frontend.
type Server struct {
	mgr  *collect.Manager
	h    *hub.Hub
	dist fs.FS
}

func NewServer(m *collect.Manager, h *hub.Hub, dist fs.FS) *Server {
	return &Server{mgr: m, h: h, dist: dist}
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("/api/snapshot", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, s.mgr.Latest())
	})
	mux.HandleFunc("/api/processes", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, s.mgr.Processes())
	})
	mux.HandleFunc("/api/docker/action", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSON(w, 405, map[string]string{"error": "method not allowed"})
			return
		}
		var req struct {
			ID     string `json:"id"`
			Action string `json:"action"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, 400, map[string]string{"error": "bad request"})
			return
		}
		d := s.mgr.Docker()
		if d == nil || !d.Available() {
			writeJSON(w, 503, map[string]string{"error": "docker unavailable"})
			return
		}
		if err := d.Action(req.ID, req.Action); err != nil {
			writeJSON(w, 500, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, 200, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("/api/docker/logs", func(w http.ResponseWriter, r *http.Request) {
		d := s.mgr.Docker()
		if d == nil || !d.Available() {
			writeJSON(w, 503, map[string]string{"error": "docker unavailable"})
			return
		}
		id := r.URL.Query().Get("id")
		logs, err := d.Logs(id, 120)
		if err != nil {
			writeJSON(w, 500, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, 200, map[string]string{"logs": logs})
	})
	mux.HandleFunc("/api/config", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			writeJSON(w, 200, config.Current())
		case http.MethodPost:
			var cfg config.Config
			if err := json.NewDecoder(r.Body).Decode(&cfg); err != nil {
				writeJSON(w, 400, map[string]string{"error": "bad config"})
				return
			}
			if err := config.Save(&cfg); err != nil {
				writeJSON(w, 500, map[string]string{"error": err.Error()})
				return
			}
			writeJSON(w, 200, map[string]string{"status": "saved"})
		default:
			writeJSON(w, 405, map[string]string{"error": "method not allowed"})
		}
	})
	// quit-browser: double-tap exit — kill the kiosk browser process.
	mux.HandleFunc("/api/ui/quit", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSON(w, 405, map[string]string{"error": "method not allowed"})
			return
		}
		writeJSON(w, 200, map[string]string{"status": "ok"})
		go killKioskBrowser()
	})

	mux.HandleFunc("/api/ws", func(w http.ResponseWriter, r *http.Request) {
		s.h.ServeWS(r.Context(), w, r)
	})

	// static frontend with SPA fallback
	fileServer := http.FileServer(http.FS(s.dist))
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		p := strings.TrimPrefix(r.URL.Path, "/")
		if p != "" && !strings.Contains(p, "..") {
			if f, err := s.dist.Open(p); err == nil {
				f.Close()
				fileServer.ServeHTTP(w, r)
				return
			}
		}
		r.URL.Path = "/"
		fileServer.ServeHTTP(w, r)
	})

	return mux
}

// killKioskBrowser terminates the kiosk browser started by the launcher.
// It matches only our dedicated profile dir to avoid touching anything else.
func killKioskBrowser() {
	time.Sleep(300 * time.Millisecond) // let the exit animation play
	self := strconv.Itoa(os.Getpid())

	// preferred: PID file written by the launcher
	if b, err := os.ReadFile("/tmp/server-watch-kiosk.pid"); err == nil {
		if pid := mustAtoi(string(b)); pid > 1 && strconv.Itoa(pid) != self && isKioskProcess(pid) {
			if p, err := os.FindProcess(pid); err == nil {
				if p.Kill() == nil {
					_ = os.Remove("/tmp/server-watch-kiosk.pid")
					return
				}
			}
		}
	}

	// fallback: match the dedicated kiosk profile marker in cmdlines
	out, err := exec.Command("pgrep", "-f", "server-watch-kiosk").Output()
	if err != nil {
		return
	}
	for _, pid := range strings.Fields(string(out)) {
		if pid == self {
			continue
		}
		if p, err := os.FindProcess(mustAtoi(pid)); err == nil {
			_ = p.Kill()
		}
	}
}

func isKioskProcess(pid int) bool {
	b, err := os.ReadFile(fmt.Sprintf("/proc/%d/cmdline", pid))
	if err != nil {
		return false
	}
	cmd := strings.ReplaceAll(string(b), "\x00", " ")
	return strings.Contains(cmd, "server-watch-kiosk") ||
		strings.Contains(cmd, "server-watch-kiosk-profile") ||
		strings.Contains(cmd, "server-watch-dashboard")
}

func mustAtoi(s string) int {
	i, _ := strconv.Atoi(strings.TrimSpace(s))
	return i
}

// Broadcaster pushes snapshots at 1 Hz while clients are connected.
func (s *Server) Broadcaster(ctx context.Context) {
	t := time.NewTicker(1 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if s.h.Count() == 0 {
				continue
			}
			if msg := hub.Marshal(s.mgr.Latest()); msg != nil {
				s.h.Broadcast(msg)
			}
		}
	}
}

// Run starts the HTTP server.
func (s *Server) Run(ctx context.Context, addr string) error {
	srv := &http.Server{Addr: addr, Handler: s.Handler()}
	go func() {
		<-ctx.Done()
		shctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = srv.Shutdown(shctx)
	}()
	log.Printf("server-watch-agent listening on %s", addr)
	err := srv.ListenAndServe()
	if err == http.ErrServerClosed {
		return nil
	}
	return err
}

var _ = dockerx.NewClient // keep import used when Manager.Docker is nil-safe
