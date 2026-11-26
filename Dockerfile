# The gpu-governor image: governor.sh on Alpine, run by BusyBox sh. Dependabot bumps the base.
FROM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

LABEL org.opencontainers.image.title="gpu-governor" \
	org.opencontainers.image.description="Holds the Radeon 760M at its high clock while busy, auto when idle" \
	org.opencontainers.image.source="https://github.com/mordilloSan/amdgpu-boost" \
	org.opencontainers.image.licenses="MIT"

# Owned by root, so the user below can run the script but not change it.
COPY governor.sh /usr/local/bin/governor.sh

# No account needed: a bare uid with no capabilities. The host's udev rule
# (udev/99-amdgpu-boost.rules) gives this uid the one sysfs file it writes.
USER 10001:10001

# The thresholds come from the environment (see governor.sh for the defaults).
ENTRYPOINT ["/bin/sh", "/usr/local/bin/governor.sh"]

# Unhealthy when the busy file stops reading as a number, or the level file stops reading or
# being writable. governor.sh exits on failed reads itself; this also catches a busy file that
# reads garbage, which governor.sh counts as idle. Docker only reports the state, it does not
# restart on it.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
	CMD ["/bin/sh", "/usr/local/bin/governor.sh", "health"]
