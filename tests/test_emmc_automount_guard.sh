#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_BASE="${TMPDIR:-/tmp/opencode}"
mkdir -p "$TMP_BASE"
WORK="$(mktemp -d "$TMP_BASE/oec-emmc-guard.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

pass() {
	echo "PASS: $*"
}

INITRD="$WORK/initrd"
mkdir -p "$INITRD/etc" "$INITRD/etc.defaults" "$INITRD/usr/syno/web/webman"
cat >"$INITRD/linuxrc.syno" <<'EOF'
#!/bin/sh
RunWithLog() { :; }
	if RunWithLog /var/log/linuxrc.syno.log /linuxrc.syno.impl; then
		echo ok
	fi
EOF
chmod 0755 "$INITRD/linuxrc.syno"
cat >"$INITRD/linuxrc.syno.impl" <<'EOF'
#!/bin/sh
Mnt=/mnt
if [ -f ${Mnt}/.noroot ]; then
  echo noroot
fi
EOF
printf 'maxdisks="1"\nsupportportmappingv2="yes"\n' >"$INITRD/etc/synoinfo.conf"
printf 'maxdisks="1"\nsupportportmappingv2="yes"\n' >"$INITRD/etc.defaults/synoinfo.conf"

sh "$ROOT_DIR/patches/0000-rk-initrd-fixes.sh" "$INITRD" >/dev/null

RULE="$INITRD/etc/udev/rules.d/99-oec-ignore-emmc-boot.rules"
HOOK="$INITRD/usr/syno/sbin/rk3566_hide_emmc_bootshare.sh"
RCD="$INITRD/usr/syno/sbin/oec_hide_emmc_bootshare_rcd.sh"
HOOK_LINE='/bin/sh /usr/syno/sbin/rk3566_hide_emmc_bootshare.sh "$Mnt"'

[ -f "$RULE" ] || fail "udev rule missing"
grep -Fq 'KERNEL=="mmcblk0"' "$RULE" || fail "whole-disk rule missing"
grep -Fq 'KERNEL=="mmcblk0p*"' "$RULE" || fail "partition rule missing"
grep -Fq 'ENV{SYNO_DEV_DISKPORTTYPE}=""' "$RULE" || fail "port type clear missing"
[ -x "$HOOK" ] || fail "rootfs sync hook missing or not executable"
[ -x "$RCD" ] || fail "rc.d payload missing or not executable"
count=$(grep -Fc "$HOOK_LINE" "$INITRD/linuxrc.syno.impl")
[ "$count" = "1" ] || fail "hook count is $count, expected 1"
pass "payload and linuxrc hook installed"

! grep -q '^support_emmc_boot=' "$INITRD/etc/synoinfo.conf" || fail "support_emmc_boot must not be set"
! grep -q '^support_emmc_boot=' "$INITRD/etc.defaults/synoinfo.conf" || fail "support_emmc_boot must not be set in etc.defaults"
pass "support_emmc_boot stays unset"

sh "$ROOT_DIR/patches/0000-rk-initrd-fixes.sh" "$INITRD" >/dev/null
count=$(grep -Fc "$HOOK_LINE" "$INITRD/linuxrc.syno.impl")
[ "$count" = "1" ] || fail "hook count after second run is $count, expected 1"
pass "patch script is idempotent"

ROOTFS="$WORK/rootfs"
mkdir -p "$ROOTFS/etc" "$ROOTFS/usr/local/etc"
OEC_EMMC_RULE_SRC="$RULE" OEC_EMMC_RCD_SRC="$RCD" sh "$HOOK" "$ROOTFS"
[ -f "$ROOTFS/etc/udev/rules.d/99-oec-ignore-emmc-boot.rules" ] || fail "rootfs rule not installed"
[ -x "$ROOTFS/usr/local/etc/rc.d/Z99oec_hide_emmc_bootshare.sh" ] || fail "rootfs rc.d not installed"
pass "rootfs sync hook installs rule and rc.d"

echo "All eMMC automount guard tests passed."
