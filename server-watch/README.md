# Server Watch for NX563J Ubuntu

Server Watch turns the Nubia Z17/NX563J Ubuntu desktop into a landscape desk clock with an Apple Watch-inspired, OLED-first low-overhead interface. The clock is intentionally the visual focus; CPU, battery, network and Docker are quiet complications that expand into detailed sheets only when touched.

## Current architecture

- **Go agent**: reads `/proc`, `/sys`, Wi-Fi, BlueZ and the Docker Engine Unix socket.
- **Vue 3 + TypeScript UI**: clock face, flat Apple Watch-style complications, sheets, process view and Docker controls.
- **Transport**: WebSocket snapshots with HTTP fallback.
- **Binding**: `127.0.0.1:8765` by default; not exposed to the LAN.
- **NX563J boot model**: this rootfs has no systemd PID 1. The agent is therefore supervised from `rc.boot.ubuntu` by `server-watch-agent-run`, matching the rest of this phone's service model.
- **Display**: Xorg/fbdev. The default design uses pure black backgrounds, opaque dark surfaces and no realtime blur/shadow effects because this device has CPU-rendered X rather than a normal DRM/GPU desktop stack.

## Main interactions

- The center clock is the primary view.
- Tap CPU, Battery, Network or Docker to open a lightweight dark detail sheet.
- Tap the center status pill for Overview / Hardware / Processes / Docker / Network / Settings.
- In dim mode the first touch only wakes the face.
- Double-tap the **large center clock** to leave kiosk mode and return to LXQt. The background agent remains running.

## Build on the Mac

```bash
cd /Users/lucky/Desktop/project/nubiaz17_linux/server-watch
./scripts/build.sh
```

Outputs:

- `dist/server-watch-agent-linux-arm64`
- `dist/server-watch-agent-darwin-arm64`

The frontend is embedded into the Go binary before the ARM64 build.

## Deploy to the phone

The script probes the known NX563J USB and Tailscale addresses automatically:

```bash
./scripts/deploy.sh
```

Or force an address:

```bash
PHONE=192.168.1.186 ./scripts/deploy.sh
```

The default SSH key is `../work/nx563j_key`.

Deployment installs:

- `/usr/local/bin/server-watch-agent`
- `/usr/local/bin/server-watch-agent-run`
- `/usr/local/bin/server-watch-dashboard`
- `/usr/local/bin/server-watch-webview` (the single full-dashboard WebKitGTK UI)
- `/usr/local/bin/server-watch-device-check`
- `/etc/server-watch/config.yaml`
- `/root/.local/share/applications/server-watch.desktop`
- `/root/Desktop/Server Watch.desktop`

The installer adds an idempotent boot hook to the existing NX563J Ubuntu boot script and starts the agent immediately.

## Validate on the phone

```bash
/usr/local/bin/server-watch-device-check
wget -qO- http://127.0.0.1:8765/api/health
wget -qO- http://127.0.0.1:8765/api/snapshot
```

Agent log:

```bash
tail -f /var/log/server-watch-agent.log
```

## Configuration

`/etc/server-watch/config.yaml`

Important keys:

```yaml
listen: 127.0.0.1:8765
sample_interval_ms: 2000
slow_interval_ms: 20000
temp_warning: 65
temp_critical: 78
batt_temp_warning: 43
storage_warning: 85
memory_warning: 90
night_mode: true
dim_timeout_sec: 120
burnin_protection: true
docker_enable: true
bluetooth_enable: true
net_interface: ""
```

Display/alert toggles can be changed from the Settings sheet. The listen address and sampling cadence require an agent restart because the sampling tickers and HTTP listener are created at process startup.

## Docker

The agent talks directly to `/var/run/docker.sock`; it does not shell out to `docker stats` every second. The UI shows container state, health, CPU, memory, network, block IO, ports, restart count and bounded recent logs. Start/Stop/Restart use a long-press guard to reduce accidental actions on the touchscreen.

## Device-specific notes

- Chromium launched as root requires `--no-sandbox`; the kiosk launcher supplies it.
- The launcher currently supports Chromium/Chrome, Falkon and Firefox if installed.
- The NX563J X session is expected at `DISPLAY=:0` with `/root/.Xauthority`.
- No repeated framebuffer screenshots or FBIOPAN_DISPLAY loop should be added here; the parent Nubia research documents prior mdss deadlocks caused by repeated fb0 operations.
- Missing hardware nodes are treated as optional. The UI hides unavailable details instead of filling the screen with `N/A` values.

## Uninstall

On the phone:

```bash
cd /tmp/server-watch-pkg
sh uninstall.sh
```

The uninstaller removes Server Watch binaries and its own boot-hook line. It deliberately keeps `/etc/server-watch/config.yaml` and does not touch Docker containers, images or volumes.
