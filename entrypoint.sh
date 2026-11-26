#!/bin/sh
# The container entrypoint. The kernel creates the GPU level file as root:root 0644, so a non-root
# governor cannot write it. Started as root with only CHOWN, SETUID and SETGID, this hands that one
# file to PUID, then becomes PUID:PGID, which clears every capability, and runs governor.sh.
# The chown lasts until the file is recreated (reboot or driver reload), and every start redoes it.
# "entrypoint.sh health" (the healthcheck) drops to PUID:PGID the same way but changes nothing.
set -eu
dir=$(dirname -- "$0")
PUID=${PUID:-10001}
PGID=${PGID:-10001}
LEVEL=${LEVEL_FILE:-/gpu/power_dpm_force_performance_level}

if [ "$(id -u)" != 0 ]; then exec /bin/sh "$dir/governor.sh" "$@"; fi

for id in "$PUID" "$PGID"; do
	case $id in '' | *[!0-9]* | 0)
		echo "$(date '+%F %T') ERROR: PUID and PGID must be non-zero numbers (got $PUID:$PGID)"
		exit 1
		;;
	esac
done
if [ "${1:-}" != health ]; then
	# On failure governor.sh reports the file as not writable and exits.
	chown "$PUID" "$LEVEL" 2>/dev/null ||
		echo "$(date '+%F %T') ERROR: cannot chown $LEVEL to uid $PUID (needs cap_add: CHOWN)"
fi
exec su-exec "$PUID:$PGID" /bin/sh "$dir/governor.sh" "$@"
