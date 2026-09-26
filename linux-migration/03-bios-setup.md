# 03 — ThinkPad BIOS setup

**Time: 15 minutes.**
Still reversible. You're changing firmware settings, not touching the disk.

> Menu names vary a little by model and BIOS version. If a setting below doesn't
> exist on yours, it's fine — it means the default is already correct.

## Getting in

1. Shut down fully (**Shift+click Restart** if Windows Fast Startup is on, or just
   `shutdown /s /t 0`).
2. Power on and press **F1** repeatedly. (**F12** is the one-time boot menu.)
3. On some models you press **Enter** to interrupt startup, then **F1**.

---

## The settings that matter

### `Security` → `Virtualization`

| Setting | Set to | Why |
| --- | --- | --- |
| **Intel (VMX) Virtualization Technology** | **Enabled** | KVM, `virt-manager`, Windows VMs, minikube's VM driver. |
| **Intel VT-d Feature** | **Enabled** | IOMMU — PCI passthrough, and some container/VM isolation features. |

**This is the one people forget** and then spend an hour confused about why
`virt-manager` says KVM isn't available.

### `Security` → `Security Chip`

| Setting | Set to | Why |
| --- | --- | --- |
| **Security Chip** | **Enabled** (TPM 2.0 / "Active") | Needed if you want TPM-backed LUKS auto-unlock later (page 06). |

Do **not** "Clear Security Chip" while Windows/BitLocker is still installed — that
destroys the BitLocker key material. After the wipe it's harmless.

### `Security` → `Secure Boot`

| Setting | Set to | Why |
| --- | --- | --- |
| **Secure Boot** | **Enabled** | Fedora's bootloader and kernel are signed by a key Microsoft's CA trusts, so Fedora installs and boots fine with Secure Boot on. Leave it on — it's real protection. |

You only need to disable it if you later install an unsigned out-of-tree kernel
module (VirtualBox, some Wi-Fi drivers). The better answer in that case is to sign
the module with your own MOK key, not to turn Secure Boot off. You won't need this.

### `Config` → `Storage` → `Controller Mode` (if present)

| Setting | Set to | Why |
| --- | --- | --- |
| **SATA/NVMe Controller Mode** | **AHCI** / **NVMe**, *not* **Intel RST** | In RST mode the NVMe drive is hidden behind Intel's RAID shim and **the Linux installer will not see your disk at all.** |

Most 2021+ ThinkPads ship in AHCI already. If it's set to RST and you switch it,
**Windows will blue-screen on next boot** — irrelevant here since you're wiping,
but don't do it and then expect to go back without the recovery USB.

> If the Fedora installer says "no disks found", this is almost always the cause.

### `Config` → `Power` → `Sleep State` (older models only)

| Setting | Set to | Why |
| --- | --- | --- |
| **Sleep State** | **Linux (S3)** if the option exists | Deep sleep. Much better battery drain than Windows "Modern Standby" (s2idle). |

2021+ ThinkPads mostly removed this option and only support `s2idle`. Page 06 shows
how to check which one you actually got and what to do about drain.

### `Config` → `Thunderbolt(TM) 3/4`

| Setting | Set to | Why |
| --- | --- | --- |
| **Thunderbolt BIOS Assist Mode** | **Disabled** (default) | Enabling it hands TB control to the OS pre-boot and causes dock quirks on Linux. Only enable if a specific dock needs it. |
| **Security Level** | **User Authorization** (default) | Fine on Linux — you authorise devices via `boltctl`. |

### `Config` → `Keyboard/Mouse`

Optional quality-of-life:

- **Fn and Ctrl Key swap** — if you want the bottom-left key to be Ctrl. Purely taste.
- **F1–F12 as primary function** — set this if you live in terminals and IDEs and are
  tired of pressing Fn. (`Fn+Esc` toggles FnLock at runtime too.)

### `Startup` → `Boot`

| Setting | Set to | Why |
| --- | --- | --- |
| **UEFI/Legacy Boot** | **UEFI Only** | Modern install, required for Secure Boot. |
| **CSM Support** | **Disabled** | Legacy BIOS compatibility layer — not wanted. |
| **Boot order** | USB HDD above the internal NVMe *for now* | Or just use **F12** each time, which is cleaner. |

### Passwords — read the warning

You *may* set a **Supervisor Password** (locks BIOS settings) and a **Power-On
Password**. Both are good hardening.

> ⚠️ **A forgotten ThinkPad Supervisor Password is not recoverable.** Not by Lenovo,
> not by removing the CMOS battery. The remedy is a new mainboard. If you set one,
> put it in your password manager **immediately**, before you leave the BIOS screen.

There's no need to set one today. LUKS is what actually protects your data.

---

## Save and verify

**F10** → Save and Exit.

Boot back into Windows once and confirm it still works. You haven't burned any
bridges yet, and the next step is the one that decides everything.

---

## Checkpoint

- [ ] VT-x and VT-d **Enabled**
- [ ] TPM / Security Chip **Enabled**
- [ ] Secure Boot **Enabled**
- [ ] Storage controller is **AHCI/NVMe**, not RST
- [ ] UEFI Only, CSM Disabled
- [ ] Any BIOS password you set is in your password manager
- [ ] Windows still boots

**Now go do the Citrix gate**: [07-citrix-vdi.md](07-citrix-vdi.md) → *"Pre-wipe
test"*. Come back to [04-install-fedora.md](04-install-fedora.md) only after it passes.
