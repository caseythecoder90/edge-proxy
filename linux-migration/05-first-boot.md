# 05 — The first 60 minutes

**Time: ~1 hour, mostly downloads.**

Order matters here: update first, then add repos, then install things. Doing it the
other way round means re-downloading half of it.

---

## 1. Make dnf less slow

`dnf` downloads one package at a time by default. Fix that once:

```bash
sudo tee -a /etc/dnf/dnf.conf <<'CONF'
max_parallel_downloads=10
CONF
```

Optionally add `keepcache=True` if you have disk to spare and reinstall packages
often (it stops dnf deleting downloaded RPMs after install).

> **Learn:** `/etc/dnf/dnf.conf` is a plain INI file, and `man 5 dnf.conf`
> documents every option. Getting into the habit of "check the man page for the
> config file, not just the command" is one of the bigger step-changes in Linux
> competence. Try `man 5 dnf.conf` now and skim it.

## 2. Full update, then reboot

```bash
sudo dnf upgrade --refresh
```

If the kernel or `systemd` updated (it almost certainly did — the install ISO is
months old), reboot:

```bash
systemctl reboot
```

## 3. Set a hostname

Your machine will show up in your own SSH configs, in `kubectl` node lists, in your
router. Give it a name you'll recognise.

```bash
sudo hostnamectl set-hostname thinkpad
hostnamectl    # look at the whole output — it tells you the chassis type,
               # firmware version, kernel, and hardware vendor too
```

## 4. RPM Fusion — codecs and extra firmware

Fedora ships only patent-unencumbered software by default. RPM Fusion is the
community repo with the rest. This is what makes video actually play.

```bash
sudo dnf install \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

sudo dnf upgrade --refresh
```

> **Learn:** `rpm -E %fedora` expands an RPM macro to your Fedora version number.
> Try `rpm -E %fedora`, `rpm -E %{_arch}`, `rpm -E %{_libdir}`. Macros like these
> are how spec files stay portable across releases — the same idea as a variable in
> a Helm chart.

### Codecs

```bash
# Replace the stripped-down ffmpeg with the full build
sudo dnf swap ffmpeg-free ffmpeg --allowerasing

# Full multimedia stack
sudo dnf update @multimedia --setopt="install_weak_deps=False" \
     --exclude=PackageKit-gstreamer-plugin
```

### Hardware video acceleration (Intel)

Offloads video decode to the iGPU — matters a lot for battery life in video calls
and YouTube.

```bash
sudo dnf install intel-media-driver libva-utils
vainfo | head -20
```

`vainfo` should list `VAProfileH264…`, `VAProfileHEVC…` etc. If it errors, you may
have an older Intel generation that wants `libva-intel-driver` from RPM Fusion instead.

## 5. Flatpak / Flathub

Fedora enables a *filtered* Flathub by default. Enable the full one so you can
install everything:

```bash
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak remote-modify --enable flathub
flatpak update
```

> **When to use which:** `dnf` for anything system-level, CLI, or that you want
> integrated (shells, compilers, drivers, daemons). **Flatpak** for sandboxed GUI
> apps (Slack, Spotify, Bitwarden, OBS). Flatpaks are isolated, which is good for
> security and occasionally annoying for file access — `flatpak override` and
> [Flatseal](https://flathub.org/apps/com.github.tchx84.Flatseal) adjust permissions.
> **Never** install developer toolchains as Flatpaks.

## 6. Firmware updates from Linux

Lenovo publishes firmware to the LVFS, so `fwupd` can update your BIOS, Thunderbolt
controller, and SSD from Linux. This is genuinely excellent and worth knowing about.

```bash
fwupdmgr refresh --force
fwupdmgr get-devices          # everything fwupd can see
fwupdmgr get-updates
fwupdmgr update               # reboots into a firmware-update mode if needed
```

**Plug in AC power** before running `update`.

## 7. The core toolkit

These are the tools the rest of this guide (and page 11's exercises) assume.

```bash
# Build essentials
sudo dnf group install "Development Tools"
sudo dnf install gcc-c++ make cmake pkgconf

# Everyday CLI
sudo dnf install \
  git git-delta gh curl wget vim-enhanced neovim tmux \
  htop btop ripgrep fd-find fzf bat eza jq tree ncdu \
  wl-clipboard unzip p7zip rsync

# System inspection — you will use all of these on page 11
sudo dnf install \
  iproute bind-utils nmap-ncat tcpdump traceroute whois \
  strace ltrace lsof sysstat iotop-c powertop \
  smartmontools pciutils usbutils dmidecode util-linux

# Desktop niceties
sudo dnf install gnome-tweaks dconf-editor \
  gnome-shell-extension-appindicator
```

Quick tour of what you just installed, because unknown tools are useless tools:

| Tool | Replaces | Try right now |
| --- | --- | --- |
| `btop` | Task Manager | `btop` |
| `rg` (ripgrep) | grep, but fast | `rg -n 'PermitRootLogin' /etc/ssh/` |
| `fd` | find, but sane | `fd -e conf . /etc/systemd` |
| `bat` | cat with syntax highlighting | `bat /etc/fstab` |
| `eza` | ls | `eza -lah --git --tree --level=2` |
| `jq` | JSON surgery | `fwupdmgr get-devices --json \| jq '.Devices[].Name'` |
| `ss` (iproute) | netstat | `ss -tulpn` |
| `dig` (bind-utils) | nslookup | `dig +short fedoraproject.org` |
| `lsof` | "what has this file open?" | `sudo lsof -i :22` |
| `strace` | "what syscalls is it making?" | `strace -f -e trace=openat ls /tmp 2>&1 \| head` |
| `journalctl` | Event Viewer | `journalctl -b -p err` |

## 8. Look at your own boot

Two commands that teach you more about systemd than an hour of reading:

```bash
systemd-analyze                  # total boot time, split by firmware/loader/kernel/userspace
systemd-analyze blame | head -20 # slowest units
systemd-analyze critical-chain   # the dependency path that actually gated boot
```

`blame` shows slow units; `critical-chain` shows which of them were *on the critical
path*. A unit can be slow and irrelevant. That distinction — latency vs. critical
path — is the same reasoning you'll apply to pod startup and init containers later.

## 9. Automatic security updates (optional, recommended)

```bash
sudo dnf install dnf-automatic
# On newer Fedora the package may be named dnf5-plugin-automatic — find the timer:
systemctl list-unit-files | grep -i automatic
```

Edit `/etc/dnf/automatic.conf` and set `upgrade_type = security` and
`apply_updates = yes`, then enable whichever timer the previous command showed:

```bash
sudo systemctl enable --now dnf-automatic.timer
systemctl list-timers            # see it alongside every other scheduled job
```

> **Learn:** `systemctl list-timers` is the systemd replacement for `crontab -l`,
> and systemd timers are strictly better: they log to the journal, they can depend
> on other units, they catch up after downtime (`Persistent=true`), and they can
> trigger on events rather than just clock times. You'll write one yourself on page 09.

---

## Checkpoint

```bash
# Codecs work
ffmpeg -version | head -1

# Hardware decode available
vainfo 2>/dev/null | grep -c VAProfile     # should be > 0

# Flathub fully enabled
flatpak remotes --show-details | grep flathub

# Firmware up to date
fwupdmgr get-updates                        # "No updates available" is the goal

# No failed services
systemctl --failed                          # should be "0 loaded units listed"
```

- [ ] `sudo dnf upgrade` says nothing to do
- [ ] RPM Fusion free + nonfree enabled
- [ ] `vainfo` reports profiles
- [ ] Flathub enabled, `flatpak update` clean
- [ ] `fwupdmgr get-updates` clean
- [ ] `systemctl --failed` is empty
- [ ] You ran `systemd-analyze critical-chain` and looked at it

Next: [06-laptop-tuning.md](06-laptop-tuning.md)
