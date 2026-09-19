package dockerx

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Client is a minimal Docker Engine API client over the unix socket.
// It never shells out to the docker CLI.
type Client struct {
	hc    *http.Client
	avail bool
	mu    sync.Mutex
}

func NewClient(socket string) *Client {
	if socket == "" {
		socket = "/var/run/docker.sock"
	}
	tr := &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			var d net.Dialer
			d.Timeout = 3 * time.Second
			return d.DialContext(ctx, "unix", socket)
		},
	}
	return &Client{hc: &http.Client{Transport: tr, Timeout: 5 * time.Second}}
}

func (c *Client) get(path string, out any) error {
	req, err := http.NewRequest("GET", "http://docker"+path, nil)
	if err != nil {
		return err
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return fmt.Errorf("docker api %s: %s", path, resp.Status)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

func (c *Client) post(path string) error {
	req, err := http.NewRequest("POST", "http://docker"+path, nil)
	if err != nil {
		return err
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 && resp.StatusCode != 304 {
		return fmt.Errorf("docker api %s: %s", path, resp.Status)
	}
	return nil
}

// Available reports whether the docker daemon answers.
func (c *Client) Available() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	var v map[string]any
	if err := c.get("/_ping", &v); err != nil {
		// ping returns plain text; use version instead
		var ver map[string]any
		if err2 := c.get("/version", &ver); err2 != nil {
			c.avail = false
			return false
		}
	}
	c.avail = true
	return true
}

type ContainerSummary struct {
	ID       string   `json:"id"`
	Name     string   `json:"name"`
	Image    string   `json:"image"`
	State    string   `json:"state"`  // running/exited/...
	Status   string   `json:"status"` // human string
	Health   string   `json:"health,omitempty"`
	Started  int64    `json:"started_at"`
	Ports    []string `json:"ports,omitempty"`
	Restarts int      `json:"restart_count"`
}

type ContainerStats struct {
	ID         string  `json:"id"`
	CPUPercent float64 `json:"cpu_percent"`
	MemBytes   uint64  `json:"mem_bytes"`
	MemLimit   uint64  `json:"mem_limit"`
	NetRx      uint64  `json:"net_rx"`
	NetTx      uint64  `json:"net_tx"`
	BlockR     uint64  `json:"block_read"`
	BlockW     uint64  `json:"block_write"`
	PIDs       int     `json:"pids"`
}

type rawContainer struct {
	ID     string   `json:"Id"`
	Names  []string `json:"Names"`
	Image  string   `json:"Image"`
	State  string   `json:"State"`
	Status string   `json:"Status"`
	Ports  []struct {
		IP          string `json:"IP"`
		PrivatePort uint16 `json:"PrivatePort"`
		PublicPort  uint16 `json:"PublicPort"`
		Type        string `json:"Type"`
	} `json:"Ports"`
}

type rawInspect struct {
	State struct {
		StartedAt string `json:"StartedAt"`
		ExitCode  int    `json:"ExitCode"`
		Health    struct {
			Status string `json:"Status"`
		} `json:"Health"`
	} `json:"State"`
	RestartCount int `json:"RestartCount"`
}

// ListContainers returns all containers (running and stopped).
func (c *Client) ListContainers() ([]ContainerSummary, error) {
	var raw []rawContainer
	if err := c.get("/containers/json?all=1", &raw); err != nil {
		return nil, err
	}
	out := make([]ContainerSummary, 0, len(raw))
	for _, rc := range raw {
		cs := ContainerSummary{
			ID:    rc.ID,
			Name:  strings.TrimPrefix(firstOr(rc.Names, ""), "/"),
			Image: rc.Image,
			State: rc.State,
		}
		// split health out of Status ("Up 2 hours (healthy)")
		status := rc.Status
		if i := strings.Index(status, "("); i > 0 {
			cs.Health = strings.TrimSuffix(strings.TrimSpace(status[i+1:]), ")")
			status = strings.TrimSpace(status[:i])
		}
		cs.Status = status
		for _, p := range rc.Ports {
			if p.PublicPort != 0 {
				cs.Ports = append(cs.Ports, fmt.Sprintf("%d→%d/%s", p.PublicPort, p.PrivatePort, p.Type))
			} else {
				cs.Ports = append(cs.Ports, fmt.Sprintf("%d/%s", p.PrivatePort, p.Type))
			}
		}
		out = append(out, cs)
	}
	return out, nil
}

// Inspect fills started time and restart count.
func (c *Client) Inspect(id string) (started int64, restarts int, health string, exitCode int, err error) {
	var ri rawInspect
	if err = c.get("/containers/"+id+"/json", &ri); err != nil {
		return
	}
	restarts = ri.RestartCount
	health = ri.State.Health.Status
	exitCode = ri.State.ExitCode
	if t, terr := time.Parse(time.RFC3339Nano, ri.State.StartedAt); terr == nil {
		started = t.Unix()
	}
	return
}

type rawStats struct {
	CPUStats struct {
		CPUUsage struct {
			TotalUsage uint64 `json:"total_usage"`
		} `json:"cpu_usage"`
		SystemUsage uint64 `json:"system_cpu_usage"`
		OnlineCPUs  uint32 `json:"online_cpus"`
	} `json:"cpu_stats"`
	PreCPUStats struct {
		CPUUsage struct {
			TotalUsage uint64 `json:"total_usage"`
		} `json:"cpu_usage"`
		SystemUsage uint64 `json:"system_cpu_usage"`
	} `json:"precpu_stats"`
	MemoryStats struct {
		Usage uint64 `json:"usage"`
		Limit uint64 `json:"limit"`
		Stats struct {
			InactiveFile uint64 `json:"inactive_file"`
			Cache        uint64 `json:"cache"`
		} `json:"stats"`
	} `json:"memory_stats"`
	Networks map[string]struct {
		RxBytes uint64 `json:"rx_bytes"`
		TxBytes uint64 `json:"tx_bytes"`
	} `json:"networks"`
	BlkioStats struct {
		IoServiceBytes []struct {
			Op    string `json:"op"`
			Value uint64 `json:"value"`
		} `json:"io_service_bytes_recursive"`
	} `json:"blkio_stats"`
	PidsStats struct {
		Current int `json:"current"`
	} `json:"pids_stats"`
}

// StatsOne takes a one-shot stats sample for a container (stream=false).
func (c *Client) StatsOne(id string) (*ContainerStats, error) {
	var rs rawStats
	req, err := http.NewRequest("GET", "http://docker/containers/"+id+"/stats?stream=false&one-shot=true", nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("stats %s: %s", id[:12], resp.Status)
	}
	if err := json.NewDecoder(resp.Body).Decode(&rs); err != nil {
		return nil, err
	}
	st := &ContainerStats{ID: id}
	cpuDelta := float64(rs.CPUStats.CPUUsage.TotalUsage - rs.PreCPUStats.CPUUsage.TotalUsage)
	sysDelta := float64(rs.CPUStats.SystemUsage - rs.PreCPUStats.SystemUsage)
	online := float64(rs.CPUStats.OnlineCPUs)
	if online == 0 {
		online = 1
	}
	if sysDelta > 0 && cpuDelta > 0 {
		st.CPUPercent = cpuDelta / sysDelta * online * 100
	}
	st.MemBytes = rs.MemoryStats.Usage - rs.MemoryStats.Stats.InactiveFile
	if rs.MemoryStats.Stats.InactiveFile == 0 && rs.MemoryStats.Usage > rs.MemoryStats.Stats.Cache {
		st.MemBytes = rs.MemoryStats.Usage - rs.MemoryStats.Stats.Cache
	}
	st.MemLimit = rs.MemoryStats.Limit
	for _, n := range rs.Networks {
		st.NetRx += n.RxBytes
		st.NetTx += n.TxBytes
	}
	for _, io := range rs.BlkioStats.IoServiceBytes {
		switch io.Op {
		case "read", "Read":
			st.BlockR += io.Value
		case "write", "Write":
			st.BlockW += io.Value
		}
	}
	st.PIDs = rs.PidsStats.Current
	return st, nil
}

// Action performs start/stop/restart on a container.
func (c *Client) Action(id, action string) error {
	switch action {
	case "start", "stop", "restart":
		return c.post("/containers/" + id + "/" + action)
	default:
		return fmt.Errorf("unsupported action %q", action)
	}
}

// Logs returns the last n lines of container logs (stdout+stderr).
func (c *Client) Logs(id string, tail int) (string, error) {
	if tail <= 0 || tail > 500 {
		tail = 100
	}
	req, err := http.NewRequest("GET",
		fmt.Sprintf("http://docker/containers/%s/logs?stdout=true&stderr=true&tail=%d&timestamps=true", id, tail), nil)
	if err != nil {
		return "", err
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 4*1024*1024))
	if err != nil {
		return "", err
	}
	// Non-TTY containers use Docker's 8-byte multiplex header. TTY-enabled
	// containers return raw text, so detect the framing before decoding.
	if len(data) < 8 || (data[0] != 1 && data[0] != 2) || data[1] != 0 || data[2] != 0 || data[3] != 0 {
		return string(data), nil
	}
	var sb strings.Builder
	for off := 0; off+8 <= len(data); {
		hdr := data[off : off+8]
		size := int(binary.BigEndian.Uint32(hdr[4:8]))
		off += 8
		if size < 0 || off+size > len(data) {
			break
		}
		sb.Write(data[off : off+size])
		off += size
	}
	return sb.String(), nil
}

func firstOr(s []string, d string) string {
	if len(s) > 0 {
		return s[0]
	}
	return d
}
