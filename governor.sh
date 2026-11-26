#!/bin/sh
# Holds the Radeon 760M (gfx1103, Ryzen 5 7640HS) at its top clock while the GPU is busy, and
# returns it to "auto" after a stretch of idle time.
# Why (measured 2026-11-25, Immich ML OCR on ROCm/MIGraphX): in "auto" the APU firmware ran the GPU
# at about 2055 MHz, dropped it to 800 MHz at times while it was 82-91% busy, and never picked the
# 2599 MHz top level. "high" pins 2599 MHz. Raising the BIOS power limit to 54 W changed nothing.
# The amdgpu driver has no clock governor for this chip (the firmware picks the clock inside the
# range the driver allows), so the switching is done here. "high" all the time would keep the clock
# at 2599 MHz while the server idles, so this switches only when there is work.
set -u
LEVEL=${LEVEL_FILE:-/gpu/power_dpm_force_performance_level}
BUSY=${BUSY_FILE:-/gpu/gpu_busy_percent}
INTERVAL=${INTERVAL:-2}           # seconds between samples
BUSY_PCT=${BUSY_PCT:-20}          # a sample at or above this counts as busy
BUSY_SAMPLES=${BUSY_SAMPLES:-3}   # consecutive busy samples before switching to high
IDLE_PCT=${IDLE_PCT:-10}          # a sample below this counts as idle
IDLE_SECONDS=${IDLE_SECONDS:-300} # continuous idle time before switching back to auto
# Failed reads of either file in a row before exiting 1, so the restart policy mounts them again.
# A driver reload or GPU reset can leave the bind mounts pointing at sysfs files that are gone.
# A read that works but is not a number still counts as idle, not as a failure.
READ_FAILS=${READ_FAILS:-5}

# "governor.sh health" is the container healthcheck: healthy (exit 0) while the busy file reads as a
# number and the level file reads and is writable. It never writes the level file.
if [ "${1:-}" = health ]; then
	b=$(cat "$BUSY" 2>/dev/null) || exit 1
	case $b in '' | *[!0-9]*) exit 1 ;; esac
	cat "$LEVEL" >/dev/null 2>&1 && [ -w "$LEVEL" ]
	exit
fi

log() { echo "$(date '+%F %T') $*"; }
set_level() {
	if echo "$1" >"$LEVEL" 2>/dev/null; then
		log "power level -> $1 (gpu busy ${2:-?}%)"
	else log "ERROR: cannot write '$1' to $LEVEL"; fi
}
stop() {
	set_level auto
	exit "${1:-0}"
}
trap stop TERM INT

[ -r "$BUSY" ] || {
	log "ERROR: cannot read $BUSY"
	exit 1
}
[ -w "$LEVEL" ] || {
	log "ERROR: $LEVEL is not writable by uid $(id -u) (install udev/99-amdgpu-boost.rules on the host)"
	exit 1
}
log "started: high after ${BUSY_SAMPLES}x${INTERVAL}s at >=${BUSY_PCT}% busy, auto after ${IDLE_SECONDS}s below ${IDLE_PCT}%"
set_level auto
busy_n=0
idle_s=0
fails=0
while :; do
	read_ok=1
	b=$(cat "$BUSY" 2>/dev/null) || read_ok=0
	case $b in '' | *[!0-9]*) b=0 ;; esac
	cur=$(cat "$LEVEL" 2>/dev/null) || read_ok=0
	if [ "$read_ok" = 1 ]; then fails=0; else fails=$((fails + 1)); fi
	if [ "$fails" -ge "$READ_FAILS" ]; then
		log "ERROR: $fails failed reads of $BUSY or $LEVEL in a row, exiting to be restarted"
		stop 1
	fi
	if [ "$b" -ge "$BUSY_PCT" ]; then busy_n=$((busy_n + 1)); else busy_n=0; fi
	if [ "$b" -lt "$IDLE_PCT" ]; then idle_s=$((idle_s + INTERVAL)); else idle_s=0; fi
	if [ "$cur" != high ] && [ "$busy_n" -ge "$BUSY_SAMPLES" ]; then
		set_level high "$b"
		idle_s=0
	elif [ "$cur" = high ] && [ "$idle_s" -ge "$IDLE_SECONDS" ]; then
		set_level auto "$b"
		busy_n=0
	fi
	sleep "$INTERVAL" &
	wait $! # backgrounded so TERM is handled immediately
done
