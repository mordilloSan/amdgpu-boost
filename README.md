<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/amd-light.svg">
    <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/amd.svg" alt="" height="32">
  </picture>
  amdgpu-boost
</h1>

A tiny container that switches an AMD GPU to its top clock while it is busy, and back to `auto`
when it goes idle. Written for a Radeon 760M (Ryzen 5 7640HS) running Immich machine learning on
ROCm, on a Linux server.

## Why

Measured on 2026-11-25, Immich ML OCR on ROCm/MIGraphX, Linux 7.0, amdgpu driver:

- In `auto`, the firmware ran the GPU at about 2055 MHz, and dropped it to 800 MHz at times while
  it was 82–91% busy. It never used the 2599 MHz top level.
- In `high`, the GPU stays at 2599 MHz.
- Raising the BIOS power limit to 54 W changed nothing.

The amdgpu driver has no clock governor for this chip: the firmware picks the clock inside the
range the driver allows. `high` all the time would keep the GPU at 2599 MHz while the server
idles, so this switches only while there is work.

Whether this happens with other workloads (games, Vulkan compute) or only with ROCm compute has not
been tested. Reviews of the 760M on Windows, which mostly run games, do not report it.

## How it works

Every `INTERVAL` seconds it reads `gpu_busy_percent`:

- After `BUSY_SAMPLES` samples in a row at or above `BUSY_PCT`, it writes `high` to
  `power_dpm_force_performance_level`.
- After `IDLE_SECONDS` in a row below `IDLE_PCT`, it writes `auto` back.
- On stop, it writes `auto`.

It sees only those two files, and writes only the second.

## Requirements

- An AMD GPU on the `amdgpu` driver, at `/sys/class/drm/card0`. For another card number, change
  the two paths under `volumes:` in [docker-compose.yml](docker-compose.yml).
- Docker with Compose v2.

No host setup: nothing to install, no udev rules, no files in `/etc`.

## Install

Use [docker-compose.yml](docker-compose.yml) as it is. It pulls
`ghcr.io/mordillosan/amdgpu-boost` at a pinned release tag:

```sh
docker compose up -d
docker logs gpu-governor
```

In LinuxIO, create a stack from the same file. It already sets the stack and container icon.

To update, change the image tag to the new release and run `docker compose up -d` again.

## Settings

Set in `environment:` in the compose file.

| Variable | Compose file | Default | Meaning |
|---|---|---|---|
| `INTERVAL` | 2 | 2 | Seconds between samples |
| `BUSY_PCT` | 20 | 20 | A sample at or above this % counts as busy |
| `BUSY_SAMPLES` | 3 | 3 | Busy samples in a row before switching to `high` |
| `IDLE_PCT` | 10 | 10 | A sample below this % counts as idle |
| `IDLE_SECONDS` | 60 | 300 | Idle seconds in a row before switching back to `auto` |
| `READ_FAILS` | 5 | 5 | Failed reads in a row before exiting, so Docker restarts it |
| `PUID`, `PGID` | 10001 | 10001 | uid and gid the governor runs as. Must not be an account on the host |
| `TZ` | unset | unset | Time zone for the log timestamps, such as `Europe/Lisbon`. Unset, it uses the mounted `/etc/localtime` |

## Logs and health

`docker logs gpu-governor` shows the start line with the settings, every switch (for example
`power level -> high (gpu busy 87%)`) and every error. It does not log each sample.

- **Failed reads:** a driver reload or GPU reset can leave the mounted files pointing at sysfs
  files that are gone. After `READ_FAILS` failed reads in a row, the governor sets `auto` (if it
  still can) and exits 1, and `restart: unless-stopped` starts it again with fresh mounts.
- **Healthcheck:** every 30 seconds Docker checks that the busy file reads as a number and that the
  level file reads and is writable. The result is in `docker inspect gpu-governor`, under
  `State.Health`. Docker only reports it; it does not restart an unhealthy container.

## Security

The kernel creates the level file as `root:root 0644`, so only root can write it. The container
starts as root with only three capabilities (`CHOWN`, `SETUID`, `SETGID`). The entrypoint gives that
one file to `PUID`, then runs the governor as `PUID:PGID`, which clears every capability. Once
running, the governor has:

- uid 10001, no capabilities, and `no-new-privileges`
- no network and no IPC namespace sharing
- a read-only root filesystem
- 32 MB of memory and at most 16 processes
- two GPU files mounted, the busy file read-only

## What it changes on the host

Only the two sysfs files, which live in memory and reset at boot:

- **The level:** set to `high` or `auto`. A normal stop (`docker stop`, `docker compose down`,
  LinuxIO's stop) sets `auto`. `docker kill` or `docker rm -f` skips that and can leave it on
  `high`. To reset it by hand:

  ```sh
  echo auto | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level
  ```

- **The level file's owner:** uid 10001 from the first start until the next reboot or driver
  reload. Harmless once the container is gone.

Removing the container and the image leaves nothing behind.

## Development

| Target | What it does |
|---|---|
| `make check` | shellcheck, shfmt, `docker compose config` and actionlint |
| `make test` | Runs [governor.sh](governor.sh) against fake GPU files and checks every switch, failure path and the healthcheck. Needs a non-root user |
| `make docker-test` | The same tests under BusyBox `sh` in the image's base, as uid 10001 |
| `make image` | Builds the image as `gpu-governor:dev` |
| `make smoke` | Builds the image and runs it with the compose file's sandbox against fake GPU files: checks the chown, uid 10001 with no capabilities, the healthcheck, a switch and the stop |

CI runs all of them on every pull request.

Releases go through `dev/vX.Y.Z` branches with `gh release-flow`. Merging the release PR publishes
the image to GHCR (`vX.Y.Z`, and `latest` for non-prereleases) and the GitHub Release. Each release
branch must update the image tag in `docker-compose.yml` to its own version; CI checks this.

## License

[MIT](LICENSE)
