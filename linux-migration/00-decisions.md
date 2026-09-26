# 00 — The decisions, and what they cost you

Short page. Read it once so you know *why* you're doing each thing, then move on.

---

## Why Fedora and not Ubuntu

Both are fine. The reason to pick Fedora given your goals:

Your containers, your VPS images, and roughly every Kubernetes node you will ever
touch professionally run some variant of the Red Hat / systemd / cgroups v2 world.
Fedora is the upstream of RHEL. Learning on Fedora means:

- **SELinux is on and enforcing by default.** This is annoying for about two weeks
  and then it's a skill. It's also the single most common "why doesn't my container
  volume mount work on the RHEL box" question in the industry.
- **cgroups v2, unified hierarchy, by default** — which is exactly the mechanism
  Kubernetes uses to enforce CPU/memory limits. You can literally `cat` the files
  the kubelet writes.
- **podman is native**, rootless, and systemd-integrated. Podman is closer to how a
  kubelet actually runs containers (no daemon, OCI runtime directly) than Docker is.
- **Fresh kernels** — matters for a 2021+ ThinkPad (Wi-Fi, power management, Thunderbolt).
- **dnf + rpm** is what you'll use on RHEL/Rocky/Alma in a job.

What it costs you:

- **~13-month release lifecycle.** You will do a major version upgrade roughly twice
  a year. It's one command and it usually just works, but it's not Ubuntu LTS's
  "ignore it for 5 years."
- **Some vendor docs only ship `.deb`.** Almost always there's an `.rpm` or a
  tarball. Occasionally you'll use a container or Distrobox to get around it.
- **Non-free codecs are a manual step** (covered on page 05).

> If at any point you decide you'd rather have Ubuntu LTS, nothing in pages 08–11 of
> this guide changes except `dnf` → `apt`. The learning path is distro-agnostic.

## Why full wipe and not dual-boot

You said you're done with Windows, and dual-boot has a failure mode that catches
people: Windows feature updates periodically stomp on the EFI boot entries, and
you get to learn `efibootmgr` under time pressure on a Monday morning. Also, a
dual-boot machine is an escape hatch, and escape hatches stop you learning.

**The cost:** if Citrix doesn't work, you have no laptop for work. That's why the
Citrix gate on page 07 exists and why it's mandatory.

**Your actual escape hatch** is not a Windows partition. It's:
1. A verified backup (page 01).
2. A Windows 11 recovery USB (page 01) — a wiped ThinkPad can be back on Windows in
   about 90 minutes if you truly need it. Your Windows licence is burned into the
   firmware (OEM digital licence), so it reactivates automatically.

That's a better escape hatch than dual-boot because it doesn't sit there tempting you.

## Why LUKS full-disk encryption

It's a laptop; it leaves the house. Without FDE, anyone with the laptop has your
SSH keys, your kubeconfigs, your `~/.aws/credentials`, and your browser session
cookies. With FDE they have an expensive paperweight.

**The cost:** a passphrase at every boot. Page 06 has an optional TPM2 auto-unlock
setup that removes the typing while keeping the protection against a stolen disk —
do that *after* you're comfortable, not on day one.

## Why Btrfs

Fedora's default. You get:
- **Transparent compression** (`zstd:1`) — real space savings on source trees and
  container layers.
- **Snapshots** — page 09 sets these up. Cheap, instant, and a genuine safety net
  for "I just ran a bad `dnf` transaction."
- **Subvolumes** — a concept that transfers directly to understanding how container
  image layers and CSI volume snapshots work.

**The cost:** slightly more to learn. Worth it. Page 11 week 6 covers it properly.

## What you're actually trading away

Be honest with yourself about these before you wipe:

| You lose | Reality |
| --- | --- |
| Desktop MS Office | Web Office works. LibreOffice for local files. Track-changes fidelity on complex .docx is imperfect. |
| Anti-cheat games | Valorant, Fortnite, Destiny 2, most competitive shooters: will not run. Everything else on Steam: Proton handles it, often better than Windows. |
| Some corporate MDM/VPN clients | Check yours. Most enterprise VPNs (GlobalProtect, AnyConnect, FortiClient) have Linux clients. |
| "It just works" hardware moments | Rare on a ThinkPad, but you will spend an occasional evening on something. That's the tuition. |
| Adobe CC | No Linux version, no workaround. Affinity: no. GIMP/Krita/Darktable/Inkscape if you can live with them. |

| You gain | Reality |
| --- | --- |
| A machine that works like a server | Everything you learn transfers to prod. |
| Containers without a VM | Docker Desktop on Windows is a Linux VM in a trenchcoat. On Linux it's just processes. Volume mounts are fast. |
| A real package manager | `dnf install` instead of hunting installers. |
| Full control | Nothing reboots itself at 3am. Nothing shows you ads in the start menu. |
| Kubernetes on hard mode, correctly | `kind`/`k3s` run natively, fast, and you can inspect every layer. |

---

**Checkpoint:** you understand what you're trading away and you're still in.
Go to [01-before-you-wipe.md](01-before-you-wipe.md).
