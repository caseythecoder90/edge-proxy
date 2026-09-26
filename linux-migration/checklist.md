# The one-page checklist

Open this on your phone. Everything here is expanded elsewhere in the guide.

---

## ☐ PHASE 1 — Before you wipe *(Windows still installed)*

**Page [01](01-before-you-wipe.md)**

- [ ] Scan all repos for uncommitted / unpushed / stashed work → push it
- [ ] BitLocker recovery key saved **off-machine**, twice
- [ ] Windows product key recorded
- [ ] Model + machine type + BIOS version noted on phone
- [ ] `.ssh` `.gnupg` `.kube` `.aws` `.m2` `.gradle` `.npmrc` `.gitconfig` copied
- [ ] VS Code + JetBrains settings copied
- [ ] Documents / Desktop / Pictures copied, **sizes verified**
- [ ] WSL distros exported
- [ ] Bookmarks exported; passwords in a password manager
- [ ] **2FA seeds moved to phone; recovery codes printed**
- [ ] Citrix store URL + auth method recorded
- [ ] **Company root CA exported as `.pem`**
- [ ] BIOS/firmware fully updated via Lenovo Vantage
- [ ] **Windows recovery USB created** (32 GB) and labelled
- [ ] Backup verified by opening files *from the backup drive*
- [ ] Second copy exists (cloud or 2nd drive)

**Page [02](02-install-media.md)**

- [ ] Fedora Workstation USB written from **current stable**
- [ ] Checksum verified
- [ ] Backup drive **unplugged and put away**

**Page [03](03-bios-setup.md)** — F1 at boot

- [ ] Intel VT-x **Enabled**
- [ ] Intel VT-d **Enabled**
- [ ] Security Chip / TPM **Enabled**
- [ ] Secure Boot **Enabled**
- [ ] Storage controller **AHCI/NVMe**, not RST
- [ ] UEFI Only, CSM Disabled
- [ ] Windows still boots

## 🚦 THE GATE — [07 Part A](07-citrix-vdi.md)

- [ ] HTML5 receiver tested from Windows (your floor)
- [ ] Booted Fedora live USB → **Try Fedora**
- [ ] Hardware checked: Wi-Fi, audio, trackpad, TrackPoint, keys, webcam, suspend
- [ ] Citrix Workspace RPM installed in the live session
- [ ] Company CA copied to `/opt/Citrix/ICAClient/keystore/cacerts/` + `ctx_rehash`
- [ ] **Connected to the VDI and did 10 minutes of real work**
- [ ] Clipboard both ways, keyboard layout, monitors, audio all verified

> ### 🛑 All green? Continue. Anything red? Read [07 Part C](07-citrix-vdi.md) — do not wipe.

---

## ☐ PHASE 2 — Install

**Page [04](04-install-fedora.md)**

- [ ] AC power connected
- [ ] Correct disk selected (size matches internal NVMe)
- [ ] **"Encrypt my data" ticked**
- [ ] LUKS passphrase set **and saved in password manager**
- [ ] User created, "make administrator" ticked, **no root password**
- [ ] USB removed before first boot
- [ ] Third-party repositories **enabled** in initial setup
- [ ] Verified: btrfs, LUKS2, UEFI, Secure Boot, `getenforce` = Enforcing

**Page [05](05-first-boot.md)**

- [ ] `max_parallel_downloads=10` in `/etc/dnf/dnf.conf`
- [ ] `sudo dnf upgrade --refresh` + reboot
- [ ] Hostname set
- [ ] RPM Fusion free + nonfree
- [ ] `dnf swap ffmpeg-free ffmpeg --allowerasing` + `@multimedia`
- [ ] `intel-media-driver`; `vainfo` shows profiles
- [ ] Flathub fully enabled
- [ ] `fwupdmgr update`
- [ ] Core toolkit installed
- [ ] `systemctl --failed` is empty

**Page [06](06-laptop-tuning.md)**

- [ ] Exactly one of power-profiles-daemon / TLP running
- [ ] Battery charge threshold set (80%)
- [ ] Suspend/resume tested; drain measured
- [ ] Fingerprint enrolled or confirmed unsupported
- [ ] Display scaling correct
- [ ] Caps→Ctrl, tap-to-click

---

## ☐ PHASE 3 — Make it yours

- [ ] [07 Part B](07-citrix-vdi.md) — Citrix installed permanently, CA in place
- [ ] [08](08-dev-environment.md) — dotfiles restored, **`chmod 600` on keys**
- [ ] [08](08-dev-environment.md) — `ssh -T git@github.com` works
- [ ] [08](08-dev-environment.md) — signed commit shows **Verified** on GitHub
- [ ] [08](08-dev-environment.md) — dotfiles in a git repo
- [ ] [08](08-dev-environment.md) — podman + docker + mise working
- [ ] [09](09-backups-and-recovery.md) — restic repo initialised, **restore tested**
- [ ] [09](09-backups-and-recovery.md) — backup timer enabled + `loginctl enable-linger`
- [ ] [09](09-backups-and-recovery.md) — offsite copy configured
- [ ] [09](09-backups-and-recovery.md) — **live-USB chroot rescue rehearsed once**
- [ ] [12](12-windows-replacements.md) — your daily apps installed

---

## ☐ PHASE 4 — Learn

- [ ] [10](10-kubernetes-lab.md) — kind cluster up, `k9s` working
- [ ] [10](10-kubernetes-lab.md) — Ingress + TLS serving locally
- [ ] [11](11-linux-learning-path.md) — `~/notes/linux-log.md` created and in git
- [ ] [11](11-linux-learning-path.md) — week 1 started
- [ ] Calendar reminder: **restore one file from backup, monthly**

---

## Emergency numbers

| Thing | Where |
| --- | --- |
| Won't boot | [13](13-troubleshooting.md) + [09 § 4](09-backups-and-recovery.md) chroot |
| Citrix broken | [07 Part B](07-citrix-vdi.md) problem table |
| Roll back to Windows | [13](13-troubleshooting.md) last section, ~90 min |
| BIOS | **F1** · Boot menu **F12** · GRUB menu **Esc/Shift** · Console **Ctrl+Alt+F3** |
