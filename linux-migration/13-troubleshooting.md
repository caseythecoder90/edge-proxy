# 13 — Troubleshooting

Keep this one on your phone.

## The method, before the fixes

Panic makes you reinstall. Method makes you fix it. Every time:

1. **What changed?** `sudo dnf history`, `journalctl -b -1`, `sudo snapper -c root list`.
   Almost every "it broke by itself" has an answer here.
2. **Read the actual error.** All of it, including the line before it.
   `journalctl -xeu <unit>` gives the message *and* the hint.
3. **Form one hypothesis and one test.** Not three changes at once — then you won't
   know which one worked.
4. **Change one thing. Test. Write it down.**
5. **Undo what didn't help** before trying the next thing.

> The single most useful command on a Fedora machine that just broke:
> `sudo dnf history undo last`

---

## Won't boot

| Symptom | Likely cause | Do this |
| --- | --- | --- |
| No GRUB, straight to BIOS | Boot order or EFI entry lost | F12 boot menu → pick "Fedora". Then fix permanently with `efibootmgr -v` |
| GRUB appears, kernel panics | Bad kernel or initramfs | At GRUB pick an **older kernel**. Then `sudo dracut -f --regenerate-all` |
| "No root device found" / dracut emergency shell | Broken initramfs, or LUKS not found | Live USB → chroot (page 09) → `dracut --force --regenerate-all` |
| LUKS prompt rejects the right passphrase | Keyboard layout in initramfs | Try typing it as if on a **US QWERTY** layout. Caps Lock off. |
| Boots to a black screen, no desktop | GDM or graphics | `Ctrl+Alt+F3` for a console → `journalctl -b -p err` → `systemctl status gdm` |
| Hangs on a systemd job | A unit waiting on something | Press **Esc** at boot to see messages. Then `systemd-analyze blame` after |
| Stuck after a `/etc/fstab` edit | Bad UUID or a missing device | Boot, press `e` at GRUB, add `systemd.unit=emergency.target`, fix fstab |

**The universal recovery**: live USB → *Try Fedora* → the chroot procedure in
[09-backups-and-recovery.md](09-backups-and-recovery.md) § 4.

## Networking

```bash
# Layer by layer — find where it stops
ip link                       # is the interface up?
ip addr                       # do I have an address?
ip route                      # do I have a default route?
ping -c3 192.168.1.1          # can I reach the gateway?
ping -c3 1.1.1.1              # can I reach the internet by IP?
dig +short fedoraproject.org  # does DNS work?
curl -I https://fedoraproject.org   # does TLS/HTTP work?
```

Each step failing tells you something different. Don't skip to the end.

| Symptom | Try |
| --- | --- |
| No Wi-Fi networks listed | `nmcli radio wifi on`; `rfkill list` (hardware kill switch, **Fn+F8** on some ThinkPads) |
| Wi-Fi connects then drops | Power saving: `sudo iw dev wlan0 set power_save off`, or `/etc/NetworkManager/conf.d/wifi-powersave.conf` |
| Slow / flaky on 5 GHz | Try disabling 802.11ax in the driver module options; check `journalctl -k \| grep iwlwifi` |
| DNS resolves inconsistently | `resolvectl status` — are you getting a VPN's DNS on the wrong interface? |
| VPN kills all DNS | `resolvectl domain <iface> "~."` to route all queries there |
| Can't reach a local dev server from another device | firewalld: `sudo firewall-cmd --add-port=8080/tcp` |

## Audio / video

```bash
wpctl status                          # PipeWire: devices, streams, defaults
wpctl set-default <ID>                # change the default sink
systemctl --user restart wireplumber pipewire pipewire-pulse
```

| Symptom | Try |
| --- | --- |
| No sound at all | `wpctl status` — is the right sink default and unmuted? |
| No sound in a browser only | Flatpak permissions; check the per-app volume in Settings → Sound |
| Mic not working in Teams/Zoom | Browser permission first, then `wpctl status` sources |
| Webcam black | `sudo dnf install v4l-utils && v4l2-ctl --list-devices`; check the physical privacy shutter |
| Video stutters, fan spins up | Hardware decode missing — see page 05 `vainfo` |

## Power and battery

| Symptom | Try |
| --- | --- |
| Heavy drain while suspended | Page 06 § 3 — check `mem_sleep`, then `cat /proc/acpi/wakeup` for devices waking it |
| Doesn't wake from suspend | `journalctl -b -1 -e`; try `mem_sleep_default=s2idle` if you forced `deep` |
| Fan loud, machine hot | `sensors`, `powertop`, `powerprofilesctl set power-saver`. Check for a runaway process first. |
| Battery not charging past 80% | That's your own threshold from page 06 § 2 |
| Poor battery life generally | `powertop` → Tunables tab (read, don't auto-tune); make sure video decode is offloaded |

## Disk full

```bash
df -h
ncdu /                                 # find the big things interactively
sudo journalctl --vacuum-size=200M     # journal is a common culprit
sudo dnf clean all
podman system prune -a                 # dangling images/layers
docker system prune -a
rm -rf ~/.cache/*                      # safe; apps rebuild it
sudo btrfs filesystem usage /          # btrfs "free space" is subtler than df suggests
sudo snapper -c root list              # old snapshots hold space
```

> On Btrfs, `df` can say you have space while writes fail, because metadata and data
> are allocated in separate chunks. `btrfs filesystem usage` is the honest answer.
> `sudo btrfs balance start -dusage=50 /` reclaims over-allocated chunks.

## Graphics and display

| Symptom | Try |
| --- | --- |
| External monitor not detected | Check it's not a Thunderbolt auth issue: `boltctl list` |
| Screen tearing or flicker | Try the Xorg session at the login screen (gear icon) to isolate Wayland |
| Blurry apps at fractional scaling | XWayland scaling — see page 06 § 5 |
| Wrong refresh rate | Settings → Displays; verify with `wlr-randr` or in GNOME's own panel |
| Everything broken after a driver update | `sudo dnf history undo last`, or boot an older kernel |

## Containers and Kubernetes

| Symptom | Try |
| --- | --- |
| `permission denied` on a podman bind mount | SELinux — add `:Z` to the volume flag (`-v /host:/ctr:Z`) |
| `docker` needs sudo | You're not in the `docker` group yet, or haven't logged out since |
| Rootless container can't bind :80 | `net.ipv4.ip_unprivileged_port_start` — page 08 § 7 |
| `kind create cluster` hangs | `docker info`; check inotify limits (page 08 § 5); `kind delete cluster` and retry |
| Pods stuck `Pending` | `kubectl describe pod` — almost always resources or a missing PVC |
| Pods `CrashLoopBackOff` | `kubectl logs --previous <pod>` — the *previous* container is where the error is |
| `ImagePullBackOff` | `kubectl describe pod`; check the registry secret and the image tag |

## When something is "slow"

```bash
uptime                 # load average — but remember it includes D-state
vmstat 1 5             # r (runnable) and b (blocked); si/so (swapping); wa (I/O wait)
iostat -xz 1 5         # %util and await per device
pidstat -d 1 5         # which process is doing the I/O
btop                   # overview
journalctl -f          # is something erroring in a loop?
```

Then pick the saturated resource and dig in. This is the week-12 runbook — write
your own version.

## Getting help well

When you ask on a forum, Matrix, or Reddit, include:

```bash
# Paste the output of these with your question:
cat /etc/os-release
uname -r
inxi -Fzx            # dnf install inxi — a great one-shot hardware+software summary
journalctl -b -p err --no-pager | tail -50
systemctl --failed
```

Good places: [Fedora Discussion](https://discussion.fedoraproject.org/),
[r/Fedora](https://reddit.com/r/Fedora), the Fedora Matrix rooms,
[Arch Wiki](https://wiki.archlinux.org/) (distro-agnostic and the best Linux
documentation that exists), and [ThinkWiki](https://www.thinkwiki.org/) for
model-specific quirks.

**A good question** says what you expected, what happened, what you already tried,
and includes the actual error. You'll get an answer in minutes instead of a day.

## Rolling all the way back to Windows

No shame in it, and it's straightforward:

1. Boot the Windows recovery USB from page 01 (F12 → USB).
2. Choose **Recover from a drive** → *Fully clean the drive*.
3. Let it reinstall. Your OEM licence reactivates automatically from firmware.
4. Restore from your external backup.
5. Reinstall Lenovo Vantage and let it update.

About 90 minutes. Then, if you want, come back to this with dual-boot instead — the
laptop is a means, not the goal.
