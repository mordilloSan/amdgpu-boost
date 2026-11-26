# The gpu-governor image: governor.sh on Alpine, run by BusyBox sh. Dependabot bumps the base.
FROM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

LABEL org.opencontainers.image.title="gpu-governor" \
	org.opencontainers.image.description="Holds the Radeon 760M at its high clock while busy, auto when idle" \
	org.opencontainers.image.source="https://github.com/mordilloSan/amdgpu-boost" \
	org.opencontainers.image.licenses="MIT"

# tzdata, so TZ=Region/City works for the log timestamps (without TZ, the time zone comes from a
# mounted /etc/localtime, or is UTC). su-exec, so the entrypoint can drop from root to PUID:PGID.
RUN apk add --no-cache su-exec tzdata

# Owned by root, so the governor, running as PUID, can run the scripts but not change them.
COPY entrypoint.sh governor.sh /usr/local/bin/

# Starts as root on purpose: entrypoint.sh chowns the GPU level file to PUID (default 10001), then
# runs governor.sh as PUID:PGID with no capabilities. docker-compose.yml grants only CHOWN, SETUID
# and SETGID. The thresholds come from the environment (see governor.sh for the defaults).
# So there is no USER line, and the scanner's missing-user rules are silenced here and on the
# HEALTHCHECK. The nosemgrep comment must stay on the line right above the instruction.
# nosemgrep: codacy.tools-configs.dockerfile.security.missing-user-entrypoint.missing-user-entrypoint
ENTRYPOINT ["/bin/sh", "/usr/local/bin/entrypoint.sh"]

# Unhealthy when the busy file stops reading as a number, or the level file stops reading or
# being writable by PUID. governor.sh exits on failed reads itself; this also catches a busy file
# that reads garbage, which governor.sh counts as idle. Docker only reports the state, it does not
# restart on it. Runs through the entrypoint, so it checks as PUID, not as root.
# nosemgrep: codacy.tools-configs.dockerfile.security.missing-user.missing-user
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
	CMD ["/bin/sh", "/usr/local/bin/entrypoint.sh", "health"]
