#!/bin/sh
# Arctic Linux - system startup
# Run by busybox init as sysinit. Keep it readable: this is the file people
# open first when something will not boot.
# shellcheck shell=sh disable=SC2039

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

. /etc/arctic/rc.lib 2>/dev/null || {
	# rc.lib is what prints the pretty status lines. Without it, stay silent
	# but keep booting.
	begin() { printf ' * %s\n' "$*"; }
	good()  { :; }
	bad()   { printf '   failed: %s\n' "$*"; }
}

QUIET=0
case " $(cat /proc/cmdline 2>/dev/null) " in
*" quiet "*|*" arctic.splash "*) QUIET=1 ;;
esac

banner

# --------------------------------------------------------------- pseudo filesystems
begin "mounting kernel filesystems"
mountpoint -q /proc || mount -t proc     -o nosuid,noexec,nodev proc  /proc
mountpoint -q /sys  || mount -t sysfs    -o nosuid,noexec,nodev sys   /sys
mountpoint -q /run  || mount -t tmpfs    -o nosuid,nodev,mode=755 run /run
mountpoint -q /dev  || mount -t devtmpfs -o nosuid,mode=755 dev /dev
mkdir -p /dev/pts /dev/shm /run/lock /run/arctic
mountpoint -q /dev/pts || mount -t devpts -o nosuid,noexec,gid=5,mode=620 devpts /dev/pts
mountpoint -q /dev/shm || mount -t tmpfs  -o nosuid,nodev,mode=1777 shm /dev/shm
[ -d /sys/kernel/security ] && mount -t securityfs securityfs /sys/kernel/security 2>/dev/null
[ -d /sys/firmware/efi ] && mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null
good

# ------------------------------------------------------------------------ devices
begin "starting the device manager"
# Arctic uses busybox mdev with libudev-zero, so there is no systemd-derived
# udev in the base system. eudev is available in extra for anyone who wants it.
if [ -x /sbin/udevd ] && [ -f /etc/arctic/services/udev ]; then
	/sbin/udevd --daemon 2>/dev/null
	udevadm trigger --action=add --type=subsystems 2>/dev/null
	udevadm trigger --action=add --type=devices 2>/dev/null
	udevadm settle --timeout=30 2>/dev/null
else
	printf '/sbin/mdev\n' >/proc/sys/kernel/hotplug
	mdev -s
	[ -x /sbin/mdev ] && mdev -df & 2>/dev/null
fi
good

begin "loading kernel modules"
for f in /etc/modules-load.d/*.conf; do
	[ -f "$f" ] || continue
	while read -r m; do
		case "$m" in ''|\#*) continue ;; esac
		modprobe "$m" 2>/dev/null || :
	done <"$f"
done
good

# --------------------------------------------------------------------- filesystems
begin "checking filesystems"
if [ -f /forcefsck ] || grep -q ' forcefsck' /proc/cmdline 2>/dev/null; then
	fsck -A -T -a 2>/dev/null; rm -f /forcefsck
else
	fsck -A -T -a -P 2>/dev/null || {
		bad "fsck wants attention"
		printf '\n  Dropping to a repair shell. Run fsck, then exit to continue.\n\n'
		sh
	}
fi
good

begin "remounting the root filesystem read-write"
mount -o remount,rw / 2>/dev/null
good

begin "mounting the remaining filesystems"
mount -a -t nosquashfs,noproc,nosysfs,nodevtmpfs 2>/dev/null || mount -a 2>/dev/null
good

begin "activating swap"
swapon -a 2>/dev/null || :
if [ -f /etc/arctic/zram.conf ]; then
	. /etc/arctic/zram.conf
	if [ -b /dev/zram0 ] || modprobe zram 2>/dev/null; then
		echo "${ZRAM_ALGO:-zstd}" >/sys/block/zram0/comp_algorithm 2>/dev/null
		echo "${ZRAM_SIZE:-4G}"   >/sys/block/zram0/disksize 2>/dev/null
		mkswap /dev/zram0 >/dev/null 2>&1 && swapon -p 100 /dev/zram0 2>/dev/null
	fi
fi
good

# ------------------------------------------------------------------------- system
begin "setting the hostname"
[ -f /etc/hostname ] && hostname -F /etc/hostname 2>/dev/null || hostname arctic
good

begin "setting the console font and keymap"
[ -f /etc/vconsole.conf ] && . /etc/vconsole.conf
[ -n "${KEYMAP:-}" ] && loadkmap </usr/share/keymaps/"$KEYMAP".bmap 2>/dev/null || :
[ -n "${FONT:-}" ] && setfont /usr/share/consolefonts/"$FONT".psf 2>/dev/null || :
good

begin "seeding the random pool"
[ -f /var/lib/arctic/random-seed ] && \
	cat /var/lib/arctic/random-seed >/dev/urandom 2>/dev/null
mkdir -p /var/lib/arctic
dd if=/dev/urandom of=/var/lib/arctic/random-seed bs=512 count=1 2>/dev/null
chmod 600 /var/lib/arctic/random-seed
good

begin "setting the clock"
[ -e /dev/rtc0 ] && hwclock --hctosys --utc 2>/dev/null || :
good

begin "cleaning up /tmp and /run"
rm -rf /tmp/.[!.]* /tmp/* 2>/dev/null || :
rm -f /run/*.pid /run/arctic/* 2>/dev/null || :
: >/var/run/utmp 2>/dev/null || :
good

begin "bringing up the loopback interface"
ip link set lo up 2>/dev/null || ifconfig lo 127.0.0.1 up 2>/dev/null
good

# ------------------------------------------------------------------------ services
if [ -d /etc/arctic/services ]; then
	for s in /etc/arctic/services/*; do
		[ -e "$s" ] || continue
		n=$(basename "$s")
		[ "$n" = "udev" ] && continue     # already handled above
		[ -x "/etc/rc.d/$n" ] || continue
		begin "starting $n"
		if "/etc/rc.d/$n" start >/dev/null 2>&1; then good; else bad "$n"; fi
	done
fi

# ----------------------------------------------------------------------- greeting
# A finished install says hello exactly once.
if [ -f /var/lib/arctic/firstboot ]; then
	rm -f /var/lib/arctic/firstboot
	[ -x /usr/bin/arctic-firstboot ] && /usr/bin/arctic-firstboot
fi

rc_done
exit 0
