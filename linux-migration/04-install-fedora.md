# 04 — Install Fedora

**Time: ~30–45 minutes.**
**This is the destructive step.** Everything on the internal drive is gone the
moment you click Install.

Before you start, say the following out loud and mean it:

- My backup is verified and **unplugged from this laptop**.
- My 2FA recovery codes are somewhere that is not this laptop.
- **Citrix connected from the live USB** (page 07, Part A).
- I have a Windows recovery USB.

If any of those is a "sort of", go back.

---

## 1. Boot the installer

1. Plug in **AC power**. Do not do this on battery.
2. Plug in **Ethernet** if you can — one less variable.
3. Insert the Fedora USB, power on, **F12**, pick the USB.
4. **Try Fedora** → then **Install to Hard Drive** from the Activities overview.
   (Or choose Install directly from the boot menu.)

## 2. Language and keyboard

Pick your language. Pick your keyboard layout carefully — **this layout is what
you'll be typing your disk passphrase on at every boot**, in the initramfs, before
your desktop's layout settings exist.

> If you use a non-US layout, keep the LUKS passphrase to characters that sit in
> the same place on both your layout and US QWERTY. Letters, digits, spaces and
> `-` `.` are safe. `@ " # $ / \ | ~ ' ;` move around between layouts and are the
> classic cause of "my correct passphrase is being rejected".

## 3. Installation destination — the important screen

1. Select your **internal NVMe drive**. Confirm the size matches your laptop's disk
   and that it is *not* an external device. If you see more than one disk, unplug
   things until you don't.
   - **If no disk is listed**, go back to page 03: the storage controller is
     probably in Intel RST mode instead of AHCI.
2. Storage configuration: **Automatic**.
3. Tick **"Encrypt my data"**.
4. Choose **"Delete all data" / reclaim all space** so the whole disk is used.
5. Set the **disk passphrase**.

### About the passphrase

This protects everything on the machine. Rules:

- **Long beats complicated.** Five or six random words (a passphrase, e.g.
  `correct-battery-marble-tundra-glass`) is stronger and far easier to type
  correctly at 7am than `Tr0ub4dor&3`.
- Store it in your **password manager on your phone**, right now, before you
  continue. If you forget it, the data is mathematically gone. There is no reset,
  no recovery, no Lenovo support call.
- You'll type it at every boot. Make it something your fingers can learn.

### What Fedora is about to build

Worth understanding, because you'll refer back to it whenever something's wrong:

```
/dev/nvme0n1
├─ nvme0n1p1   ~600 MB   vfat    /boot/efi   EFI System Partition  (unencrypted)
├─ nvme0n1p2   ~1 GB     ext4    /boot       kernels + initramfs   (unencrypted)
└─ nvme0n1p3   rest      LUKS2   ────────────────────────────────┐
                                                                  │ encrypted
                          btrfs  (inside the LUKS container)      │
                            ├─ subvolume "root"  →  /            │
                            └─ subvolume "home"  →  /home        │
                                                    ──────────────┘
```

- **`/boot/efi` and `/boot` are outside the encryption.** They have to be: GRUB
  must read the kernel and initramfs *before* anything can ask you for a passphrase.
  This is fine — they hold no secrets — but it does mean an attacker with physical
  access could tamper with your kernel ("evil maid"). Secure Boot is the mitigation,
  which is why page 03 left it on.
- **One LUKS container, one btrfs filesystem, two subvolumes.** `/` and `/home` share
  free space instead of being fixed partitions. This is much nicer than the old
  "I gave `/` 30 GB and now it's full" problem.
- **No swap partition.** Fedora uses **zram** — a compressed block device in RAM.
  Faster than disk swap and no writes to your SSD. Trade-off: **you cannot
  hibernate** (suspend-to-disk) with zram alone. Suspend-to-RAM works fine. If you
  genuinely need hibernate, that's a later project; don't complicate day one.

## 4. User account

- **Full name / username** — your username becomes `/home/<username>` and your
  default Linux identity forever. Lowercase, no spaces. Keep it the same as your
  usual handle so your dotfiles and SSH configs stay portable.
- Tick **"Make this user administrator"** — this puts you in the `wheel` group, which
  is what `sudo` checks.
- **Do not set a root password.** Leave the root account locked. Everything goes
  through `sudo`, which means every privileged action is attributable and logged.
  This is how servers are configured and it's the correct habit.
- The user password is your *login and sudo* password. It is **not** the disk
  passphrase. They should be different, and both should be in your password manager.

## 5. Install

Click **Begin Installation**. It takes 10–20 minutes. Don't close the lid.

When it finishes: **Finish Installation** → shut down → **remove the USB stick** →
power on.

## 6. First boot

1. **LUKS prompt.** A passphrase prompt on a mostly-blank screen. Type it. There's
   no feedback as you type — that's normal.
   - If it's rejected and you're sure it's right: check Caps Lock, and check the
     keyboard-layout warning above.
2. **GNOME initial setup** runs once:
   - **Third-Party Repositories: ENABLE.** This gives you Google Chrome, Steam,
     NVIDIA drivers and a filtered Flathub without extra work.
   - Location services / automatic problem reporting: your call.
   - Skip the online-account connections for now; do them later deliberately.
3. You're at a desktop.

---

## 7. Verify the install

Open a terminal and confirm reality matches the diagram:

```bash
# Partition and filesystem layout
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,TYPE

# Confirm the root filesystem is btrfs and see the subvolumes
findmnt /
sudo btrfs subvolume list /

# Confirm LUKS2 and see the key-derivation parameters
sudo cryptsetup luksDump /dev/nvme0n1p3 | head -30

# Confirm we booted UEFI (this directory only exists on an EFI boot)
ls /sys/firmware/efi >/dev/null && echo "UEFI boot: yes"

# Confirm Secure Boot is active
sudo dnf install -y mokutil && mokutil --sb-state

# Confirm zram is the swap device
swapon --show
zramctl

# Confirm SELinux is enforcing
getenforce
```

Expected: `btrfs` on `/`, subvolumes `root` and `home`, `LUKS header ... Version: 2`,
`UEFI boot: yes`, `SecureBoot enabled`, a `/dev/zram0` swap device, and `Enforcing`.

> **Learn:** read the `luksDump` output properly. `PBKDF: argon2id` with a memory
> cost in the hundreds of MB is what makes brute-forcing your passphrase expensive.
> `Keyslots:` shows up to 32 slots — each holds the master key encrypted under a
> different passphrase. That's how you can add a TPM-backed key later (page 06)
> *without* re-encrypting the disk: you're adding a keyslot, not changing the data.

---

## Checkpoint

- [ ] Boots to a GNOME desktop
- [ ] LUKS passphrase accepted, and saved in your password manager
- [ ] `lsblk` shows `crypto_LUKS` → `btrfs`
- [ ] `getenforce` says `Enforcing`
- [ ] `mokutil --sb-state` says SecureBoot enabled
- [ ] Wi-Fi connects
- [ ] USB stick removed and kept (you'll want it for rescue)

Next: [05-first-boot.md](05-first-boot.md)
