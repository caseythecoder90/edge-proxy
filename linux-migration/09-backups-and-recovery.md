# 09 — Backups, snapshots and rescue

You just proved how much a good backup is worth. Don't let the new machine be the
one without one.

**The rule: 3 copies, 2 media, 1 offsite.** Your laptop, an external drive, and
somewhere in the cloud.

Snapshots are *not* backups — they live on the same disk. They protect you from
*you* (bad upgrade, `rm -rf` in the wrong directory). Backups protect you from the
disk, the laptop, and the house. You want both, and they solve different problems.

---

## 1. restic — the actual backup

Encrypted, deduplicated, incremental, and it can target a local drive, S3, Backblaze
B2, or SFTP with the same commands.

```bash
sudo dnf install restic
mkdir -p ~/.config/restic
```

### Set it up

```bash
# A strong repository password. WRITE IT IN YOUR PASSWORD MANAGER.
# Lose it and the backups are unrecoverable by design.
head -c 32 /dev/urandom | base64 > ~/.config/restic/password
chmod 600 ~/.config/restic/password

cat > ~/.config/restic/env <<'ENV'
export RESTIC_REPOSITORY="/run/media/YOURUSER/BACKUP/restic"
export RESTIC_PASSWORD_FILE="$HOME/.config/restic/password"
ENV

cat > ~/.config/restic/excludes <<'EXCL'
/home/*/.cache
/home/*/.local/share/Trash
/home/*/.local/share/containers
/home/*/.var/app/*/cache
/home/*/Downloads
**/node_modules
**/target
**/.venv
**/__pycache__
**/*.iso
EXCL

source ~/.config/restic/env
restic init
```

### Back up and verify

```bash
source ~/.config/restic/env

restic backup "$HOME" --exclude-file="$HOME/.config/restic/excludes" --verbose
restic snapshots
restic stats

# Retention: keep a sensible ladder, then reclaim space
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune

# Integrity check — read 5% of the actual data, not just metadata
restic check --read-data-subset=5%
```

### Test the restore. Today. Not later.

```bash
mkdir -p /tmp/restore-test
restic restore latest --target /tmp/restore-test --include "$HOME/.bashrc"
diff ~/.bashrc /tmp/restore-test$HOME/.bashrc && echo "RESTORE VERIFIED"
```

> Put a monthly reminder in your calendar: *restore one real file from backup*.
> An untested backup has roughly a 50% chance of working, and you find out which
> at the worst possible moment.

### Add an offsite copy

Backblaze B2 is a few dollars a month for this amount of data:

```bash
cat > ~/.config/restic/env-b2 <<'ENV'
export RESTIC_REPOSITORY="b2:your-bucket-name:thinkpad"
export RESTIC_PASSWORD_FILE="$HOME/.config/restic/password"
export B2_ACCOUNT_ID="..."
export B2_ACCOUNT_KEY="..."
ENV
chmod 600 ~/.config/restic/env-b2
```

Same `restic backup` command with that env sourced instead.

## 2. Automate it with a systemd user timer

This is a genuinely useful thing to own, and writing it teaches you the unit/timer
pattern you'll reuse constantly.

```bash
mkdir -p ~/.config/systemd/user ~/.local/bin

cat > ~/.local/bin/backup-home.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.config/restic/env"

# Don't fail loudly when the external drive simply isn't plugged in
if [ ! -d "$RESTIC_REPOSITORY" ]; then
  echo "Backup repository not present at $RESTIC_REPOSITORY — skipping."
  exit 0
fi

echo "=== backup starting $(date -Is) ==="
restic backup "$HOME" --exclude-file="$HOME/.config/restic/excludes"
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
echo "=== backup finished $(date -Is) ==="
SCRIPT
chmod +x ~/.local/bin/backup-home.sh

cat > ~/.config/systemd/user/backup-home.service <<'UNIT'
[Unit]
Description=restic backup of $HOME
After=network-online.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/backup-home.sh
Nice=10
IOSchedulingClass=idle
UNIT

cat > ~/.config/systemd/user/backup-home.timer <<'UNIT'
[Unit]
Description=Daily restic backup

[Timer]
OnCalendar=daily
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl --user daemon-reload
systemctl --user enable --now backup-home.timer

# Let user services run when you're not logged in
loginctl enable-linger "$USER"

# Check it
systemctl --user list-timers
systemctl --user start backup-home.service
journalctl --user -u backup-home.service -n 50
```

> **Learn — every line of that timer earns its place.**
> `Persistent=true` runs a missed job after the laptop wakes up, instead of silently
> skipping a day. `RandomizedDelaySec` spreads load (crucial when it's 500 servers,
> harmless here, good habit). `IOSchedulingClass=idle` keeps the backup from making
> your machine feel slow. `%h` expands to the user's home. And because it's a
> *user* timer, it runs as you, with your keys, no root involved.
>
> Compare this to a cron entry: no logs, no dependency ordering, no catch-up, runs
> even if prerequisites aren't met. This is why systemd won.

## 3. Btrfs snapshots

Instant, near-free, on the same disk. For "I broke it five minutes ago".

```bash
sudo dnf install snapper
# The dnf plugin that snapshots before/after every transaction:
sudo dnf install python3-dnf-plugin-snapper 2>/dev/null || \
  echo "check for a dnf5 snapper plugin on your release"

sudo snapper -c root create-config /
sudo snapper -c home create-config /home

sudo snapper -c root list
sudo snapper -c root create --description "before messing with grub"
```

Recovering a file from a snapshot:

```bash
sudo snapper -c root list
sudo snapper -c root status 3..4                    # what changed between snapshots
sudo snapper -c root diff 3..4 /etc/fstab
sudo snapper -c root undochange 3..4 /etc/fstab     # revert just that file
```

> ⚠️ **Two honest caveats on Fedora:**
> 1. Fedora's subvolumes are named `root` and `home`, not the openSUSE `@/.snapshots`
>    layout. Full one-command *system rollback* isn't supported the way it is on
>    openSUSE — snapper here is for recovering files and diffs, not for booting into
>    an old system state.
> 2. **Timeshift's Btrfs mode expects the Ubuntu `@`/`@home` layout and will not
>    work on a default Fedora install.** Use snapper, or Timeshift in *rsync* mode.

### The one you'll actually use most

```bash
sudo dnf history                 # every transaction, numbered
sudo dnf history info 42
sudo dnf history undo 42         # roll back that transaction
sudo dnf history undo last
```

This has saved more Fedora systems than snapshots have.

## 4. Rescue: when it won't boot

Print this section, or keep it on your phone. Rehearse it **once, now, while
nothing is broken** — that's the whole point of a rescue drill.

### First: is it actually broken?

At the GRUB menu (hold **Esc** or **Shift** during boot if it doesn't appear),
pick an **older kernel**. Fedora keeps the last three. If the old kernel boots,
your problem is the new kernel and you have a working system to fix it from.

### The chroot procedure

Boot the Fedora live USB → **Try Fedora** → Terminal.

```bash
# 1. Find the disk
lsblk -o NAME,SIZE,FSTYPE,PARTLABEL

# 2. Unlock the encrypted partition
sudo cryptsetup luksOpen /dev/nvme0n1p3 cryptroot

# 3. Mount the btrfs subvolumes in the right places
sudo mount -o subvol=root /dev/mapper/cryptroot /mnt
sudo mount -o subvol=home /dev/mapper/cryptroot /mnt/home
sudo mount /dev/nvme0n1p2 /mnt/boot
sudo mount /dev/nvme0n1p1 /mnt/boot/efi

# 4. Bind the kernel's virtual filesystems so the chroot behaves
for d in dev dev/pts proc sys run; do sudo mount --bind /$d /mnt/$d; done

# 5. Enter the broken system
sudo chroot /mnt /bin/bash
```

You are now root inside your installed system. Common repairs:

```bash
# Rebuild the initramfs (fixes: LUKS won't unlock, no root device found)
dracut --force --regenerate-all --verbose

# Reinstall the kernel
dnf reinstall kernel-core kernel-modules

# Regenerate the GRUB config
grub2-mkconfig -o /boot/grub2/grub.cfg

# Reinstall the EFI bootloader
dnf reinstall shim-x64 grub2-efi-x64

# Undo the dnf transaction that broke it
dnf history
dnf history undo last

# Force an SELinux relabel on next boot (fixes: mysterious permission failures
# after restoring files or after running with SELinux disabled)
touch /.autorelabel
```

Then:

```bash
exit
sudo umount -R /mnt
sudo cryptsetup luksClose cryptroot
sudo reboot
```

### Other rescue entry points

| Situation | Do this |
| --- | --- |
| Boots, but no graphical desktop | `Ctrl+Alt+F3` for a text console. Log in, `journalctl -b -p err`. |
| Want to boot to a shell without the desktop | At GRUB press `e`, append `systemd.unit=multi-user.target` to the `linux` line, `Ctrl+X`. |
| Total emergency shell | Same, but `systemd.unit=emergency.target`. |
| Forgot your user password | Same, but `rd.break`, then `mount -o remount,rw /sysroot`, `chroot /sysroot`, `passwd youruser`, `touch /.autorelabel`, exit twice. |
| Disk full and nothing works | `ncdu /`, `journalctl --vacuum-size=200M`, `dnf clean all`, `podman system prune -a` |
| Need to know what changed | `sudo dnf history`, `sudo snapper -c root list`, `journalctl -b -1` |

> **Do the drill.** Tonight, boot the live USB and do steps 1–5 above, look around,
> and exit without changing anything. Ten minutes. The difference between someone
> who panics at a boot failure and someone who fixes it in fifteen minutes is
> entirely whether they've typed `cryptsetup luksOpen` before.

## 5. Keep an escape kit

On the Ventoy/rescue USB from page 02:

- Fedora Workstation live ISO
- SystemRescue ISO
- A text file: LUKS unlock steps (above), your Citrix URL, your hardware model
- Your company root CA `.pem`

Your LUKS passphrase, restic repository password, and 2FA recovery codes live in
your password manager **and** on paper somewhere sensible. Not on the laptop.

---

## Checkpoint

- [ ] `restic snapshots` lists at least one snapshot
- [ ] You restored a real file and diffed it successfully
- [ ] `systemctl --user list-timers` shows `backup-home.timer`
- [ ] `loginctl enable-linger` done
- [ ] An offsite copy exists (B2/S3/other machine)
- [ ] restic repo password is in your password manager
- [ ] snapper configured, `sudo snapper -c root list` works
- [ ] **You have rehearsed the live-USB chroot at least once**

Next: [10-kubernetes-lab.md](10-kubernetes-lab.md)
