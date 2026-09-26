# 02 — Build and verify the Fedora USB

**Time: 20–30 minutes, mostly download.**
Still non-destructive to your laptop — you're only erasing USB stick #1.

---

## The easy way (recommended)

**Fedora Media Writer** downloads the correct image, verifies its checksum for you,
and writes the USB correctly. Use it.

1. Go to <https://fedoraproject.org/workstation/download/>.
2. Download **Fedora Media Writer for Windows**, install, run it.
3. Choose **Fedora Workstation**, then the **current stable x86_64** release.
   - As of late 2026 that's Fedora 44; Fedora 45 lands around the end of October.
     Take whatever the site presents as current stable. **Do not pick a Beta or
     Rawhide** for a machine you need for work.
4. Select USB stick #1 and write. It will erase the stick.

That's it. Skip to the checkpoint — or read on, because verifying by hand is a
genuinely useful skill.

---

## The way that teaches you something

Media Writer hides the verification. Doing it manually is 5 minutes and it's the
same skill you need every time you download a binary from the internet.

### 1. Download three things

From <https://fedoraproject.org/workstation/download/>, take the **Live ISO**. Then
from the checksum link on that page (or
<https://fedoraproject.org/security/>) grab:

- `Fedora-Workstation-Live-x86_64-NN-x.y.iso`
- `Fedora-Workstation-NN-x.y-x86_64-CHECKSUM`
- Fedora's GPG signing key (from the security page)

### 2. Check the hash

```powershell
Get-FileHash -Algorithm SHA256 .\Fedora-Workstation-Live-x86_64-*.iso
```

Open the `CHECKSUM` file in a text editor and compare the `SHA256 (…) = …` line for
your ISO. They must match character for character.

> **Why this matters, properly:** the hash proves the file wasn't corrupted in
> transit. It does **not** prove the file is Fedora's — an attacker who served you a
> bad ISO would also serve you a matching CHECKSUM file. That's what the GPG
> signature is for: it proves the *checksum file itself* came from Fedora. Hash =
> integrity. Signature = authenticity. This distinction is the whole reason your
> `edge-proxy` repo bothers with Let's Encrypt instead of a self-signed cert.

### 3. Check the signature (optional but this is the actual lesson)

Easiest with [Gpg4win](https://gpg4win.org/) on Windows, or do it later from the
live session. The command is the same everywhere:

```bash
gpg --import fedora.gpg
gpg --verify-files Fedora-Workstation-NN-x.y-x86_64-CHECKSUM
```

You want `Good signature from "Fedora (NN) <fedora-NN-primary@fedoraproject.org>"`.
A `WARNING: This key is not certified with a trusted signature` line is expected —
it just means you haven't personally vouched for Fedora's key.

### 4. Write the ISO

With **Rufus**: select the ISO, leave *Partition scheme* = **GPT**, *Target system*
= **UEFI (non CSM)**. When it asks ISO vs DD image mode, choose **DD Image mode**
(Fedora images are hybrid; DD mode is the safe answer).

Or use **Ventoy** if you want one stick that can hold several ISOs — very handy for
a learning machine, since you can keep Fedora, a Debian netinst, and
[SystemRescue](https://www.system-rescue.org/) on the same stick.

---

## While you're here: put the rescue tools on the stick

Add these to the Ventoy stick (or a second one) now, because the day you need them
is the day you can't download them:

- **SystemRescue** — chroot, `testdisk`, `gparted`, full toolkit.
- Your **company root CA `.pem`** from page 01.
- A text file with your Citrix URL, machine type, and BitLocker key location.

---

## Checkpoint

- [ ] Fedora USB written from a **current stable** Workstation release
- [ ] Checksum verified (and signature, if you did the long way)
- [ ] Windows recovery USB from page 01 exists and is labelled
- [ ] External backup drive is **unplugged and stored away from the laptop**
      (so you cannot accidentally target it during install)

Next: [03-bios-setup.md](03-bios-setup.md)
