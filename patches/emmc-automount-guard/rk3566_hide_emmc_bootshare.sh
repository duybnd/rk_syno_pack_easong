#!/bin/sh
# Installed into the DSM uInitrd by patches/0000-rk-initrd-fixes.sh.
# Runs from linuxrc.syno.impl after the real rootfs is mounted, and installs
# the udev rule plus the rootfs rc.d cleanup payload on every boot.
set -u

RootMnt="${1:-}"
RULE_SRC="${OEC_EMMC_RULE_SRC:-/etc/udev/rules.d/99-oec-ignore-emmc-boot.rules}"
RCD_SRC="${OEC_EMMC_RCD_SRC:-/usr/syno/sbin/oec_hide_emmc_bootshare_rcd.sh}"
LOG=/tmp/oec-emmc-automount.log

log() {
	echo "$(date '+%F %T') [hook] $*" >> "$LOG" 2>/dev/null
}

[ -n "$RootMnt" ] && [ -d "$RootMnt" ] || exit 0
[ -f "$RULE_SRC" ] || { log "missing rule: $RULE_SRC"; exit 0; }
[ -f "$RCD_SRC" ] || { log "missing rc.d payload: $RCD_SRC"; exit 0; }

mkdir -p "$RootMnt/etc/udev/rules.d" 2>/dev/null || {
	log "cannot create rootfs udev dir"
	exit 0
}
cp -f "$RULE_SRC" "$RootMnt/etc/udev/rules.d/99-oec-ignore-emmc-boot.rules" 2>>"$LOG" || {
	log "failed to install udev rule"
	exit 0
}
chmod 0644 "$RootMnt/etc/udev/rules.d/99-oec-ignore-emmc-boot.rules" 2>/dev/null || true

if [ -d "$RootMnt/usr/local/etc" ]; then
	mkdir -p "$RootMnt/usr/local/etc/rc.d" 2>/dev/null || {
		log "cannot create rootfs rc.d dir"
		exit 0
	}
	cp -f "$RCD_SRC" "$RootMnt/usr/local/etc/rc.d/Z99oec_hide_emmc_bootshare.sh" 2>>"$LOG" || {
		log "failed to install rc.d payload"
		exit 0
	}
	chmod 0755 "$RootMnt/usr/local/etc/rc.d/Z99oec_hide_emmc_bootshare.sh" 2>/dev/null || true
else
	log "rootfs has no /usr/local/etc, skipped rc.d payload"
fi

log "installed eMMC automount guard into $RootMnt"
exit 0
