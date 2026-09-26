# 06 — Laptop tuning

**Time: ~1 hour.** Do the first four sections now; the rest as you notice you want them.

---

## 1. Power management — pick ONE

Fedora Workstation ships **`power-profiles-daemon`** (PPD), which is what the
Power Mode selector in GNOME Settings drives. **TLP** is the older, far more
configurable alternative.

**They conflict. Never run both.**

Start with PPD — it's already there, it's integrated, and it's good enough:

```bash
systemctl status power-profiles-daemon
powerprofilesctl list
powerprofilesctl get
powerprofilesctl set power-saver
```

Move to TLP later *only* if you have a specific complaint PPD can't fix:

```bash
# Only if you're switching. Note the mask.
sudo dnf install tlp tlp-rdw
sudo systemctl mask power-profiles-daemon
sudo systemctl enable --now tlp
sudo tlp-stat -s        # then read /etc/tlp.conf, it's well commented
```

> ⚠️ **`powertop --auto-tune` is a trap.** It enables aggressive USB autosuspend,
> which on ThinkPads causes disconnecting mice, dying webcams and flaky docks.
> Use `sudo powertop` interactively to *find* power hogs, but don't blanket-apply
> its tunables.

## 2. Battery charge thresholds — do this, it matters

Keeping a lithium battery at 100% all day is what kills it. If you're docked most
of the time, cap the charge at 80%. Lenovo firmware supports this natively and the
`thinkpad_acpi` kernel module exposes it.

Check it's available:

```bash
ls /sys/class/power_supply/BAT0/ | grep charge_control
cat /sys/class/power_supply/BAT0/charge_control_end_threshold
```

GNOME 46+ has a **Battery charge limit** toggle in Settings → Power on supported
hardware — try that first, it's one click.

If it's not there, set it yourself. Note that sysfs does not persist across reboots,
so this needs a unit — which is a perfect first systemd unit to write by hand:

```bash
sudo tee /etc/systemd/system/battery-charge-threshold.service <<'UNIT'
[Unit]
Description=Limit battery charge to 80%
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'echo 75 > /sys/class/power_supply/BAT0/charge_control_start_threshold'
ExecStart=/bin/sh -c 'echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold'

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now battery-charge-threshold.service
systemctl status battery-charge-threshold.service
cat /sys/class/power_supply/BAT0/charge_control_end_threshold   # 80
```

> **Learn — read that unit file line by line.** `Type=oneshot` means "run to
> completion, don't expect a long-lived process". `RemainAfterExit=yes` means
> systemd should consider the unit *active* after the command exits, so
> `systemctl status` shows it as applied rather than dead. `WantedBy=multi-user.target`
> is what `enable` uses to create the symlink that makes it run at boot. Look:
> `ls -l /etc/systemd/system/multi-user.target.wants/`. That symlink **is** what
> "enabled" means. Nothing magic.
>
> Before you go charge above 80% for a trip: `sudo systemctl stop battery-charge-threshold`
> then `echo 100 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold`.

## 3. Sleep behaviour

Two kinds of suspend-to-RAM exist and they behave very differently:

- **`deep` (S3)** — RAM self-refresh, everything else off. Days of standby.
- **`s2idle` (Modern Standby / s0ix)** — the CPU idles in a low-power state and the
  machine can still wake for network events. Convenient; drains more if the platform
  doesn't reach the deep s0ix substates.

Check what you have:

```bash
cat /sys/power/mem_sleep
```

`[s2idle]` alone means your model only supports s2idle — nothing to change. If it
shows `s2idle [deep]` or `[s2idle] deep`, the bracketed one is active.

To prefer `deep` when it's offered:

```bash
sudo grubby --update-kernel=ALL --args="mem_sleep_default=deep"
systemctl reboot
cat /sys/power/mem_sleep     # verify [deep]
```

> ⚠️ Test this properly before trusting it: suspend, wait 5 minutes, resume, and
> check `journalctl -b -1 -e` for errors. Some newer ThinkPads are validated only
> for s2idle and resume badly from `deep`. Revert with
> `sudo grubby --update-kernel=ALL --remove-args="mem_sleep_default=deep"`.

**Measure your drain instead of guessing:**

```bash
# Note the value, suspend for an hour, resume, note it again
cat /sys/class/power_supply/BAT0/energy_now 2>/dev/null || \
cat /sys/class/power_supply/BAT0/charge_now
```

Under ~1–2% per hour asleep is healthy. Much more than that and the platform isn't
reaching its low-power states — usually a USB device or the Wi-Fi card keeping it
awake. `journalctl -b | grep -i 'wakeup\|abort'` and `cat /proc/acpi/wakeup` are
where you look.

> **`grubby`, briefly:** it edits kernel command-line arguments for installed
> kernels (and keeps `/etc/kernel/cmdline` in sync on newer Fedora). `sudo grubby
> --info=ALL` shows what your kernels actually boot with. Knowing how to add a
> kernel parameter is a core skill — it's how you'd enable `cgroup_no_v1`,
> `intel_iommu=on`, or debug options later.

## 4. Fingerprint reader

```bash
# Is the reader recognised by libfprint?
fprintd-list "$USER"        # "no devices available" means it's not supported (yet)
lsusb | grep -iE 'synaptics|goodix|validity|elan'
```

If a device is listed, enrol via **Settings → Users → Fingerprint Login**, or:

```bash
fprintd-enroll
fprintd-verify
```

> Fingerprint then works for `sudo` and unlock, but **not** for the LUKS passphrase
> at boot — that happens before any of this exists. Not all ThinkPad readers are
> supported by `libfprint`; if yours isn't, check
> <https://fprint.freedesktop.org/supported-devices.html> for your USB ID.

## 5. Display scaling

GNOME on Wayland handles HiDPI well. Settings → Displays → **Scale**. If you only
see 100%/200%, enable fractional scaling:

```bash
gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']"
# log out and back in
```

Legacy X11 apps (some Java/Electron things) may look soft under fractional scaling
because they're scaled by XWayland. Newer mutter versions have a native XWayland
scaling feature; check what your version offers:

```bash
gsettings describe org.gnome.mutter experimental-features
```

## 6. Keyboard and pointing devices

```bash
# Caps Lock as Ctrl — your pinky will thank you in vim/emacs/tmux
gsettings set org.gnome.desktop.input-sources xkb-options "['ctrl:nocaps']"

# Touchpad
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true
gsettings set org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true
```

**FnLock**: `Fn + Esc` toggles whether the top row is F1–F12 or media keys.

**TrackPoint**: middle-button scroll works out of the box with libinput. Speed lives
in GNOME Settings → Mouse & Touchpad. For low-level sensitivity:

```bash
find /sys/devices -name sensitivity -path '*serio*' 2>/dev/null
# then: echo 200 | sudo tee <that path>   (range 0-255)
```

Persist it with a udev rule if you like it — same pattern as the battery unit above.

## 7. Thunderbolt dock

```bash
sudo dnf install bolt
boltctl list                 # devices and their auth status
boltctl enroll <UUID>        # trust a dock permanently
```

GNOME also prompts on first connect. If a dock's displays don't come up, check
`boltctl list` shows it as `authorized`, then `journalctl -b | grep -i thunderbolt`.

## 8. Sensors and fan

```bash
sudo dnf install lm_sensors
sudo sensors-detect --auto
sensors
```

> Leave fan control alone. `thinkfan` exists, but the firmware's fan curve is well
> tuned and getting this wrong cooks a CPU silently. Not worth it.

## 9. Optional, later: TPM2 auto-unlock for LUKS

Once you're settled, you can have the TPM release the disk key automatically at
boot *as long as the firmware state is unchanged*, so you stop typing the
passphrase. The disk is still encrypted; a thief who pulls the SSD gets nothing,
and tampering with the boot chain changes the PCR measurements so the TPM refuses.

> ⚠️ **Read all of this before running any of it.**
> - **Keep your passphrase.** It stays in a separate keyslot. You will still need it
>   after a BIOS update, a Secure Boot key change, or anything that changes PCR 7.
> - This trades some security for convenience: an attacker with the powered-on
>   machine no longer needs your passphrase to boot it. Keep a strong login password
>   and a short screen-lock timeout.
> - Do this **only after** you've done a firmware update and settled your BIOS settings.

```bash
sudo dnf install tpm2-tools

# Confirm the TPM is there and PCR 7 (Secure Boot state) is populated
sudo tpm2_pcrread sha256:7

# Find the LUKS partition
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT

# Enrol a TPM-bound keyslot, bound to Secure Boot state (PCR 7)
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p3

# Tell the initramfs to try the TPM. Append tpm2-device=auto to the options
# column of the LUKS line in /etc/crypttab:
sudo vim /etc/crypttab
#   luks-xxxx UUID=xxxx none discard,tpm2-device=auto

# Rebuild the initramfs so it contains the TPM2 support
sudo dracut --force --regenerate-all

systemctl reboot
```

If it doesn't unlock automatically, it falls back to asking for the passphrase —
which is why keeping the passphrase matters. To undo:

```bash
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p3
# remove tpm2-device=auto from /etc/crypttab, then:
sudo dracut --force --regenerate-all
```

> **Learn:** `sudo cryptsetup luksDump /dev/nvme0n1p3` before and after. You'll see
> a new keyslot and a `systemd-tpm2` token. Two independent ways to unwrap the same
> master key. This is exactly the envelope-encryption pattern KMS services use —
> the data key never changes, only the things that can unwrap it.

---

## Checkpoint

- [ ] Exactly one of PPD or TLP is running (`systemctl status power-profiles-daemon tlp`)
- [ ] Battery charge threshold set (and you understand the unit file you wrote)
- [ ] You know whether you're on `s2idle` or `deep`, and have measured suspend drain
- [ ] Suspend/resume works reliably (lid close, 5 min, open)
- [ ] Fingerprint enrolled, or confirmed unsupported
- [ ] Display scaling looks right, internal + external
- [ ] Caps Lock is Ctrl, tap-to-click on
- [ ] Dock/monitors work, if you have them

Next: [08-dev-environment.md](08-dev-environment.md) — or
[07-citrix-vdi.md](07-citrix-vdi.md) Part B if you want work access sorted first.
