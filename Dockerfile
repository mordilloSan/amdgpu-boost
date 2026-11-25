# The gpu-governor image: governor.sh on Alpine, run by BusyBox sh. Dependabot bumps the base.
FROM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

LABEL org.opencontainers.image.title="gpu-governor" \
	org.opencontainers.image.description="Holds the Radeon 760M at its high clock while busy, auto when idle" \
	org.opencontainers.image.source="https://github.com/mordilloSan/amdgpu-boost" \
	org.opencontainers.image.licenses="MIT"

COPY governor.sh /usr/local/bin/governor.sh

# Runs as root on purpose: the sysfs level file is root-owned (0644), and owner write needs no
# capabilities, so docker-compose.yml drops them all. The thresholds come from the environment
# (see governor.sh for the defaults).
ENTRYPOINT ["/bin/sh", "/usr/local/bin/governor.sh"]

# Unhealthy when the busy file stops reading as a number, or the level file stops reading.
# governor.sh exits on failed reads itself; this also catches a busy file that reads garbage,
# which governor.sh counts as idle. Docker only reports the state, it does not restart on it.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
	CMD b=$(cat "${BUSY_FILE:-/gpu/gpu_busy_percent}") && \
	case $b in '' | *[!0-9]*) exit 1 ;; esac && \
	cat "${LEVEL_FILE:-/gpu/power_dpm_force_performance_level}" >/dev/null
