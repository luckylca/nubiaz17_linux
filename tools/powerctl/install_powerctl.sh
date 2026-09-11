#!/bin/sh
# install_powerctl.sh — run ON THE DEVICE (Ubuntu rootfs) as root.
#
# Replaces the systemctl symlinks /usr/sbin/{reboot,poweroff,halt,shutdown}
# with wrappers around /usr/sbin/powerctl (direct reboot(2) syscall), so
# shutdown/reboot actually work without systemd. The original symlinks are
# just links to ../bin/systemctl; nothing is lost (no binary is removed).
#
# powerctl itself must already be at /usr/sbin/powerctl (scp it over).
set -eu

command -v /usr/sbin/powerctl >/dev/null || { echo "missing /usr/sbin/powerctl"; exit 1; }
chmod 755 /usr/sbin/powerctl

mk() {
    name="$1"; mode="$2"
    rm -f "/usr/sbin/$name"   # remove the systemctl symlink first: writing
                              # through it would clobber /usr/bin/systemctl
    cat > "/usr/sbin/$name" <<EOF
#!/bin/sh
# $name without systemd: sync + direct reboot(2) via powerctl (see
# tools/powerctl in nubiaz17_linux repo). Replaces a systemctl symlink
# that silently did nothing (no systemd on this rootfs).
sync
exec /usr/sbin/powerctl $mode
EOF
    chmod 755 "/usr/sbin/$name"
}

# shutdown parses flags: support "shutdown -h now", "shutdown -r now",
# bare "shutdown now" -> poweroff.
rm -f /usr/sbin/shutdown
cat > /usr/sbin/shutdown <<'EOF'
#!/bin/sh
# Minimal systemd-free shutdown(8): -h/--halt/-P -> poweroff, -r -> reboot.
mode=poweroff
for a in "$@"; do
    case "$a" in
        -r|--reboot) mode=reboot ;;
        -h|--halt|-P|--poweroff) mode=poweroff ;;
    esac
done
sync
exec /usr/sbin/powerctl "$mode"
EOF
chmod 755 /usr/sbin/shutdown

mk poweroff poweroff
mk halt poweroff
mk reboot reboot

echo "installed:"
ls -l /usr/sbin/powerctl /usr/sbin/poweroff /usr/sbin/halt /usr/sbin/reboot /usr/sbin/shutdown
