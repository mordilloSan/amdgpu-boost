#!/bin/sh
# Raises the Radeon 760M (gfx1103, Ryzen 5 7640HS) to its high clock while the GPU is busy, and
# returns it to "auto" after a stretch of idle time.
# Why (measured 2026-11-25): in "auto" the APU firmware kept the GPU at 800 MHz while Immich ML
# (ROCm/MIGraphX) had it 62-69% busy; "high" (2599 MHz) roughly halved the busy time. "high" all the
# time would keep the clock up while the server idles, so this switches only when there is work.
set -u
LEVEL=${LEVEL_FILE:-/gpu/power_dpm_force_performance_level}
BUSY=${BUSY_FILE:-/gpu/gpu_busy_percent}
INTERVAL=${INTERVAL:-2}             # seconds between samples
BUSY_PCT=${BUSY_PCT:-20}            # a sample at or above this counts as busy
BUSY_SAMPLES=${BUSY_SAMPLES:-3}     # consecutive busy samples before switching to high
IDLE_PCT=${IDLE_PCT:-10}            # a sample below this counts as idle
IDLE_SECONDS=${IDLE_SECONDS:-300}   # continuous idle time before switching back to auto

log() { echo "$(date '+%F %T') $*"; }
set_level() {
  if echo "$1" > "$LEVEL" 2>/dev/null; then log "power level -> $1 (gpu busy ${2:-?}%)"
  else log "ERROR: cannot write '$1' to $LEVEL"; fi
}
stop() { set_level auto; exit 0; }
trap stop TERM INT

[ -r "$BUSY" ] || { log "ERROR: cannot read $BUSY"; exit 1; }
[ -w "$LEVEL" ] || { log "ERROR: $LEVEL is not writable"; exit 1; }
log "started: high after ${BUSY_SAMPLES}x${INTERVAL}s at >=${BUSY_PCT}% busy, auto after ${IDLE_SECONDS}s below ${IDLE_PCT}%"
set_level auto
busy_n=0; idle_s=0
while :; do
  b=$(cat "$BUSY" 2>/dev/null); case $b in ''|*[!0-9]*) b=0 ;; esac
  cur=$(cat "$LEVEL" 2>/dev/null)
  if [ "$b" -ge "$BUSY_PCT" ]; then busy_n=$((busy_n + 1)); else busy_n=0; fi
  if [ "$b" -lt "$IDLE_PCT" ]; then idle_s=$((idle_s + INTERVAL)); else idle_s=0; fi
  if [ "$cur" != high ] && [ "$busy_n" -ge "$BUSY_SAMPLES" ]; then
    set_level high "$b"; idle_s=0
  elif [ "$cur" = high ] && [ "$idle_s" -ge "$IDLE_SECONDS" ]; then
    set_level auto "$b"; busy_n=0
  fi
  sleep "$INTERVAL" & wait $!   # backgrounded so TERM is handled immediately
done
