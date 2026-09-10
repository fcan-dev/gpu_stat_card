# GPU Stat Card

A native macOS menu bar app that shows live GPU stats — temperature, fan,
VRAM, power, and utilization — for a remote NVIDIA GPU, pulled over SSH and
rendered in a click-to-open widget card.

<p align="center">
  <img width="282" height="382" alt="SCR-20260910-jwal" src="https://github.com/user-attachments/assets/f8ff32f5-77b5-4846-a07e-46d20573cb72" />
</p>

## How it works

- A status-bar icon (plus the current GPU temperature) sits in the macOS menu
  bar. Hover over it to reveal the card; it hides again when you move away.
- The card shows: reachability dot, GPU name + host + last-updated time,
  temperature (color-coded), fan %, a VRAM usage bar, a power bar, and
  utilization %.
- Every `refresh_seconds` (default 5) the app runs
  `ssh <host> "nvidia-smi --query-gpu=… --format=csv,noheader"` and parses the
  reply. It reuses your existing `~/.ssh/config` (user + key), so no passwords
  are needed in the app.
- If the server drops, the dot turns red and the card keeps the last known
  sample, dimmed, with the time it went unreachable.

## Requirements

- macOS 14+ (Apple Silicon).
- SSH key access to a host running an NVIDIA GPU with `nvidia-smi` (configured
  in `~/.ssh/config` — e.g. your Tailscale or LAN host).

## Download

Prebuilt universal (Apple Silicon + Intel) binaries are on the
[Releases](https://github.com/fcan-dev/gpu_stat_card/releases) page — download
the `GPUStatCard-x.y.z-universal.zip`, unzip, and drag `GPUStatCard.app` to
Applications.

The app is ad-hoc signed (not notarized), so on first launch macOS will show
an "unidentified developer" warning: right-click the app → **Open** → **Open**
to get past it (one time only).

## Build

```sh
scripts/build.sh          # produces dist/GPUStatCard.app
open dist/GPUStatCard.app # launch it
```

For development, run it straight from the source:

```sh
swift run GPUStatCard
```

## Config

`GPUStatCard` reads `~/.config/gpu-stat-card/config.json`. It's auto-created
with defaults on first run:

```json
{
  "host" : "gpu-server",
  "refresh_seconds" : 5
}
```

- `host` — any SSH destination that works with your `~/.ssh/config`
  (e.g. `gpu-server` or `user@10.0.0.5`).
- `refresh_seconds` — poll interval (clamped to 2–60).

The file is re-read every poll, so editing it retargets the app live — no
restart needed. Use the card's **Edit Config** button to open it.

## Quit

Open the card and press **Quit**, or kill the process.

## Notes

- Verifies against a real server via the raw `nvidia-smi` CSV output, which
  includes units (`0 %`, `22424 MiB`, `103.31 W`); the parser strips the unit
  tokens. The `-nounits` flag is not recognized on the target driver.
