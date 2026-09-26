# ThinkPad: Windows → Fedora Linux

A complete, ordered migration guide for a developer who wants Linux to be both a
daily driver *and* a teaching machine — specifically for learning Linux systems
and Kubernetes.

**Target setup**

| Decision | Choice | Why |
| --- | --- | --- |
| Distro | Fedora Workstation (current stable) | Upstream of RHEL, so it teaches you the world your production containers actually run in: systemd, SELinux, cgroups v2, podman, firewalld. New kernels = best 2021+ ThinkPad support. |
| Disk | Full wipe, Linux only | You said you're done with Windows. Clean break, whole disk, no bootloader weirdness. |
| Encryption | LUKS2 full-disk | Laptop. Non-negotiable. |
| Filesystem | Btrfs (Fedora default) | Snapshots, compression, and a genuinely useful thing to learn. |
| Hardware | Recent Intel ThinkPad (2021+) | Everything works out of the box. No proprietary GPU drivers needed. |
| Risk | Citrix VDI for work | **This is the one thing that can block you.** We test it before we wipe. |

---

## Before anything else: what you need to have

| | Required? | Notes |
| --- | --- | --- |
| **A USB stick, 8 GB or larger** | **Yes** | Non-negotiable. You cannot install an OS onto the disk you're currently booted from — the installer has to boot from somewhere else. Any cheap stick. It gets erased. |
| **Somewhere to put your backup** | **Yes** | An external drive, or cloud storage with room for your whole user profile. |
| **A second USB stick, 32 GB** | Recommended | For a Windows 11 recovery drive. This is your rollback if you change your mind — about 90 minutes back to Windows. Skip only if you're certain. |
| **AC power** | Yes | Don't install on battery. |
| **An evening, and a spare day after it** | Yes | Not the night before you need the laptop for work. |

Nothing else. No second computer, no network boot setup, no paid software.

---

## Read this part first

There is exactly one rule in this guide:

> **Do not wipe Windows until Citrix has connected to your work VDI from a Fedora
> live USB.**

Everything in `01` and `02` happens while Windows is still installed and bootable.
If Citrix can't reach your VDI from Linux, you stop, and you've lost nothing but an
evening. Page `07` covers what to do in that case.

The second rule, which is not really a rule but you'll wish it were:

> **Do not do this the night before you need the laptop for work.**
> Do it on a Friday evening or a Saturday morning. Give yourself a slack day.

---

## The order

Work through these in order. Each page ends with a **Checkpoint** — a thing you can
verify — so you always know whether it's safe to continue.

### Phase 1 — Prepare (Windows still installed, ~2–3 hours)

| Page | What |
| --- | --- |
| [00-decisions.md](00-decisions.md) | The plan, the reasoning, and what you're trading away |
| [01-before-you-wipe.md](01-before-you-wipe.md) | Inventory, backups, BitLocker key, firmware update, recovery USB |
| [02-install-media.md](02-install-media.md) | Build + verify the Fedora USB |
| [03-bios-setup.md](03-bios-setup.md) | ThinkPad BIOS settings |
| [07-citrix-vdi.md](07-citrix-vdi.md) § *Pre-wipe test* | **The gate.** Prove Citrix works from the live USB |

### Phase 2 — Install (~1 hour)

| Page | What |
| --- | --- |
| [04-install-fedora.md](04-install-fedora.md) | The install itself, partitioning, LUKS |
| [05-first-boot.md](05-first-boot.md) | The first 60 minutes: updates, repos, codecs, firmware |
| [06-laptop-tuning.md](06-laptop-tuning.md) | Power, suspend, fingerprint, display scaling, TrackPoint |

### Phase 3 — Make it yours (~an evening)

| Page | What |
| --- | --- |
| [07-citrix-vdi.md](07-citrix-vdi.md) | Full Citrix Workspace setup + fallbacks |
| [08-dev-environment.md](08-dev-environment.md) | Shell, git, SSH/GPG, editors, JVM/Node/Python, containers |
| [09-backups-and-recovery.md](09-backups-and-recovery.md) | restic + systemd timers, Btrfs snapshots, rescue procedures |
| [12-windows-replacements.md](12-windows-replacements.md) | App-for-app replacement table |

### Phase 4 — Learn (12 weeks, the actual point)

| Page | What |
| --- | --- |
| [10-kubernetes-lab.md](10-kubernetes-lab.md) | kind/k3s, the toolchain, and a capstone: move your VPS stacks to k3s |
| [11-linux-learning-path.md](11-linux-learning-path.md) | A 12-week curriculum with exercises, built around how Kubernetes actually uses Linux |

### Always

| Page | What |
| --- | --- |
| [13-troubleshooting.md](13-troubleshooting.md) | Won't boot, LUKS won't unlock, Wi-Fi dead, chroot rescue, rollback |
| [checklist.md](checklist.md) | One-page critical path. Print it or open it on your phone. |
| [scripts/postinstall.sh](scripts/postinstall.sh) | Sectioned bootstrap script — **read it before you run it** |

---

## How to use this if you want to actually learn something

You asked to become a better engineer, so a note on method.

Everything in here can be pasted into a terminal. If you do that, you will have a
working Fedora laptop and you will have learned almost nothing. The commands are
the *answer key*, not the lesson.

A better loop, which costs maybe 30% more time:

1. **Read the paragraph before the command.** Every command block in this guide is
   preceded by what it does and why. If that explanation doesn't make sense, stop
   there — that's the thing worth learning today.
2. **Predict before you run.** "What will this change? Which file? Which service
   restarts?" Then run it and check whether you were right.
3. **Verify, don't assume.** Every section has a checkpoint. Run it.
4. **Keep a lab notebook.** `~/notes/linux-log.md`, in git. One line per thing you
   fixed and how you diagnosed it. In six months this is the most valuable file on
   the machine, and it's how you'll answer interview questions with specifics
   instead of vibes.
5. **`man` before Google.** `man systemd.unit`, `man 5 crypttab`, `man ip`. Fedora
   ships excellent man pages. The habit of reading them is most of the gap between
   people who "use Linux" and people who understand it.

One more: **break it on purpose, in the lab, on a schedule.** Page 11 has a
"chaos Friday" exercise each week. Recovering from a broken system you broke
yourself, with notes, is the single fastest way to stop being afraid of the OS.
