#!/bin/sh
# Installed into the DSM rootfs by rk3566_hide_emmc_bootshare.sh.
# udev is the primary guard; this script cleans mounts created by an older
# boot and masks only the matching systemd mount units.
set -u

LOG=/var/log/oec-emmc-automount.log
RULE=/etc/udev/rules.d/99-oec-ignore-emmc-boot.rules

log() {
	echo "$(date '+%F %T') [rc.d] $*" >> "$LOG" 2>/dev/null
}

[ -f "$RULE" ] || log "WARN: udev rule missing: $RULE"

# Only touch DSM external-storage mounts that come from the eMMC.
awk '$1 ~ /^\/dev\/mmcblk0/ { print $1, $2 }' /proc/mounts 2>/dev/null |
while read -r dev mp; do
	[ -n "$mp" ] || continue
	case "$mp" in
		/volumeUSB*|/volumeSDC*|*/sdshare*|*/usbshare*) ;;
		*) continue ;;
	esac

	SYSTEMCTL=/bin/systemctl
	SYSTEMD_ESCAPE=/bin/systemd-escape
	UMOUNT=/bin/umount
	[ -x "$SYSTEMCTL" ] || SYSTEMCTL=$(command -v systemctl 2>/dev/null) || true
	[ -x "$SYSTEMD_ESCAPE" ] || SYSTEMD_ESCAPE=$(command -v systemd-escape 2>/dev/null) || true
	[ -x "$UMOUNT" ] || UMOUNT=$(command -v umount 2>/dev/null) || true

	if [ -n "$SYSTEMCTL" ] && [ -n "$SYSTEMD_ESCAPE" ]; then
		unit=$("$SYSTEMD_ESCAPE" -p --suffix=mount "$mp" 2>/dev/null)
		if [ -n "$unit" ]; then
			if "$SYSTEMCTL" mask "$unit" >/dev/null 2>&1; then
				log "masked $unit"
			else
				log "WARN: failed to mask $unit"
			fi
		fi
	else
		log "SKIP mask: systemd tools not found in PATH"
	fi

	if [ -n "$UMOUNT" ] && "$UMOUNT" "$mp" 2>/dev/null; then
		log "unmounted $mp ($dev)"
	else
		log "WARN: failed to unmount $mp ($dev)"
	fi
done

exit 0
