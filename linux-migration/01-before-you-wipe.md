# 01 — Before you wipe (do all of this in Windows)

**Time: 2–3 hours, most of it waiting on copies.**
**Nothing here is destructive.** At the end of this page Windows is still installed
and working exactly as before — you've just made it safe to destroy.

## What you need

- **USB stick #1** — 8 GB+, for Fedora. Will be erased.
- **USB stick #2** — 32 GB, for the Windows 11 recovery drive. Will be erased.
  *(Optional but strongly recommended. Skip only if you genuinely never want Windows back.)*
- **An external drive** — big enough for your whole user profile, ideally 2× that.
- **Your phone**, for photographing screens and for 2FA.

---

## 1. Find unpushed code first

The single most common "oh no" after a wipe is a repo with uncommitted work. Do
this before anything else, because it's the only backup that's awkward to fix later.

Open **PowerShell** and scan your dev folders:

```powershell
# Adjust the roots to wherever you keep code
$roots = @("$HOME\source", "$HOME\repos", "$HOME\Documents", "$HOME\dev", "C:\dev")

foreach ($root in $roots) {
  if (-not (Test-Path $root)) { continue }
  Get-ChildItem -Path $root -Recurse -Directory -Filter ".git" -ErrorAction SilentlyContinue |
    ForEach-Object {
      $repo = $_.Parent.FullName
      Push-Location $repo
      $dirty  = git status --porcelain
      $ahead  = git log --branches --not --remotes --oneline 2>$null
      $stash  = git stash list 2>$null
      if ($dirty -or $ahead -or $stash) {
        Write-Host "`n=== $repo ===" -ForegroundColor Yellow
        if ($dirty) { Write-Host "  uncommitted changes:"; $dirty | Select-Object -First 10 }
        if ($ahead) { Write-Host "  UNPUSHED commits:" -ForegroundColor Red; $ahead }
        if ($stash) { Write-Host "  stashes:" -ForegroundColor Red; $stash }
      }
      Pop-Location
    }
}
Write-Host "`nScan complete." -ForegroundColor Green
```

Commit and push everything it finds. **Stashes do not survive a wipe** — either
apply and commit them, or `git stash show -p > patchfile.patch` and back up the patch.

> **Learn:** `git log --branches --not --remotes` means "commits on any local branch
> that are on no remote." Worth memorising — it's the real answer to "have I pushed
> everything?", which `git status` does not tell you.

---

## 2. Save the BitLocker recovery key

Windows 11 turns on Device Encryption silently on most modern ThinkPads. If you
ever need to boot Windows again — including from the recovery USB — you may need
this key. Save it even though you're wiping.

```powershell
# Run as Administrator
manage-bde -status
manage-bde -protectors -get C:
```

Copy the 48-digit **Numerical Password** somewhere off the machine: your password
manager, plus a photo on your phone. Also check it's escrowed to your Microsoft
account at <https://account.microsoft.com/devices/recoverykey>.

## 3. Record your Windows product key

Your ThinkPad's licence lives in firmware and reactivates automatically on a
reinstall, but record it anyway — it's free to do and it's what you'd need for a
Windows VM later.

```powershell
(Get-CimInstance -ClassName SoftwareLicensingService).OA3xOriginalProductKey
```

## 4. Write down the hardware

You'll want this if you have to search for a model-specific quirk.

```powershell
Get-CimInstance Win32_ComputerSystem     | Select-Object Manufacturer, Model, SystemFamily
Get-CimInstance Win32_BIOS               | Select-Object SMBIOSBIOSVersion, ReleaseDate
Get-CimInstance Win32_Processor          | Select-Object Name
Get-CimInstance Win32_DiskDrive          | Select-Object Model, Size
Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter } | Select-Object Name
```

Record the **machine type (4 characters, e.g. `21CB`)** from the sticker on the
bottom of the laptop too. Put all of it in a note on your phone.

---

## 5. Back up your data

### The list people forget

Copy each of these to the external drive. The dotfolders are the ones that hurt.

| Path (Windows) | What it is | Where it goes on Linux |
| --- | --- | --- |
| `%USERPROFILE%\.ssh` | **SSH private keys** | `~/.ssh` (chmod 600!) |
| `%USERPROFILE%\.gnupg` | GPG keys — commit signing | `~/.gnupg` (chmod 700) |
| `%USERPROFILE%\.kube` | kubeconfigs | `~/.kube` |
| `%USERPROFILE%\.aws`, `.azure`, `.config\gcloud` | cloud credentials | same paths |
| `%USERPROFILE%\.docker\config.json` | registry logins | `~/.docker/` |
| `%USERPROFILE%\.m2\settings.xml` | Maven repo creds/mirrors | `~/.m2/` |
| `%USERPROFILE%\.gradle\gradle.properties` | Gradle creds | `~/.gradle/` |
| `%USERPROFILE%\.npmrc` | npm tokens | `~/.npmrc` |
| `%USERPROFILE%\.gitconfig` | git identity + aliases | `~/.gitconfig` |
| `%APPDATA%\Code\User\` | VS Code settings, keybindings, snippets | `~/.config/Code/User/` |
| `%APPDATA%\JetBrains\` | IntelliJ/GoLand config | `~/.config/JetBrains/` |
| `%USERPROFILE%\Documents`, `Desktop`, `Pictures`, `Downloads` | the obvious stuff | `~/` |
| `%APPDATA%\Microsoft\Windows\PowerShell` | shell profile (for reference) | n/a — rewrite for bash |

PowerShell to grab the dotfiles in one shot (set `$dest` to your external drive):

```powershell
$dest = "E:\thinkpad-backup"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$items = @(".ssh", ".gnupg", ".kube", ".aws", ".azure", ".docker",
           ".m2", ".gradle", ".npmrc", ".gitconfig", ".config\gcloud")
foreach ($i in $items) {
  $src = Join-Path $HOME $i
  if (Test-Path $src) {
    Write-Host "copying $i"
    Copy-Item -Path $src -Destination (Join-Path $dest $i) -Recurse -Force
  }
}
Copy-Item "$env:APPDATA\Code\User"  (Join-Path $dest "vscode-user")  -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "$env:APPDATA\JetBrains"  (Join-Path $dest "jetbrains")    -Recurse -Force -ErrorAction SilentlyContinue
```

Then the big folders (`robocopy` is better than Explorer for this — it resumes and logs):

```powershell
robocopy "$HOME\Documents" "E:\thinkpad-backup\Documents" /E /R:2 /W:2 /TEE /LOG+:E:\backup.log
robocopy "$HOME\Desktop"   "E:\thinkpad-backup\Desktop"   /E /R:2 /W:2 /TEE /LOG+:E:\backup.log
robocopy "$HOME\Pictures"  "E:\thinkpad-backup\Pictures"  /E /R:2 /W:2 /TEE /LOG+:E:\backup.log
robocopy "$HOME\Downloads" "E:\thinkpad-backup\Downloads" /E /R:2 /W:2 /TEE /LOG+:E:\backup.log
```

### WSL, if you use it

WSL distros are disk images that die with the wipe:

```powershell
wsl --list --verbose
wsl --export Ubuntu E:\thinkpad-backup\wsl-ubuntu.tar
```

On Fedora you won't import this — you'll just *be* Linux — but keep the tarball
so you can pull config out of it. (`tar -tf` to browse, `tar -xf ... path` to extract.)

### Browsers

Don't rely on copying profile folders across — export properly:

- **Bookmarks**: Chrome/Edge → `chrome://bookmarks` → ⋮ → Export. Firefox →
  Bookmarks → Manage → Import & Backup → Export to HTML.
- **Passwords**: get them into a real password manager (Bitwarden, 1Password) now,
  not into a CSV. If you must export a CSV, delete it after import.
- **Sign in to Chrome/Firefox sync** so extensions and tabs come across automatically.

---

## 6. The two things that will actually ruin your week

### 2FA / authenticator apps

If your only TOTP seeds live in a desktop authenticator, **you will lock yourself
out of your own accounts.** Before you wipe:

- Move TOTP seeds to a phone app or your password manager.
- Print/save **recovery codes** for: GitHub, your Google account, AWS, your bank,
  your work SSO. Put them in the password manager *and* on paper.
- If your work SSO uses a Windows-only MFA client, check now whether Linux is supported.

### Your work VDI access

You cannot test this after you wipe. Page [07-citrix-vdi.md](07-citrix-vdi.md) has
the full pre-wipe test — you'll run it after the USB is built (page 02). For now,
while you're in Windows, collect:

- Your **StoreFront / Workspace URL** (e.g. `https://vdi.company.com` or a
  `.cloud.com` Workspace URL). Copy it out of the Citrix Workspace app:
  ⚙ → *Accounts*.
- Whether login is **username+password**, **SAML/SSO in a browser**, or **smart card**.
- Your company's **internal CA certificate**, if they use one. In Windows:
  `certlm.msc` → Trusted Root Certification Authorities → find your company's root →
  right-click → All Tasks → Export → **Base-64 encoded X.509 (.CER)**. Save it to
  the external drive as `company-root-ca.pem`. This file is the difference between
  "Citrix works" and "SSL error 61" on Linux.
- A note of whether the StoreFront page offers **"use light version"/HTML5** — that's
  your browser-based fallback and it works on any OS.

---

## 7. Update the firmware — from Windows, now

Do this in Windows where it's easy. Fedora can also do firmware updates via `fwupd`
(page 06), and Lenovo supports that well, but starting from current firmware
eliminates a whole class of install-day weirdness.

1. Open **Lenovo Vantage** (or **Lenovo System Update**) from the Start menu.
2. Install **all** updates, including BIOS/UEFI and Thunderbolt/dock firmware.
3. **Plug in AC power.** Reboot as many times as it asks.
4. Re-run until it reports no updates.

## 8. Make the Windows recovery USB

Your escape hatch. Takes ~45 minutes, mostly unattended.

1. Insert USB stick #2 (32 GB).
2. Start → search **"Create a recovery drive"**.
3. Tick **"Back up system files to the recovery drive"**.
4. Let it run. Label the stick with a marker and put it in a drawer.

> Alternative: Lenovo's *Digital Recovery* service can ship/download a recovery
> image for your serial number. The built-in tool is faster.

## 9. Verify the backup — do not skip this

An unverified backup is a rumour.

1. **Unplug the external drive, plug it back in.** Does it mount?
2. Open three files *from the external drive*, not from a cache: a document, a
   photo, and `.ssh\id_ed25519.pub`.
3. Check sizes match:

```powershell
$src = (Get-ChildItem "$HOME\Documents" -Recurse -File | Measure-Object Length -Sum)
$dst = (Get-ChildItem "E:\thinkpad-backup\Documents" -Recurse -File | Measure-Object Length -Sum)
"source: {0} files, {1:N0} bytes" -f $src.Count, $src.Sum
"backup: {0} files, {1:N0} bytes" -f $dst.Count, $dst.Sum
```

4. **Ideally: a second copy.** Cloud (OneDrive/Drive/Backblaze) or a second drive.
   One copy is not a backup. If the external drive dies during the restore — and
   this happens — you want somewhere else to go.

---

## Checkpoint

Do not continue until every one of these is true:

- [ ] No repo has unpushed commits, uncommitted changes, or stashes you care about
- [ ] BitLocker recovery key saved off-machine (two places)
- [ ] Windows product key recorded
- [ ] Machine type / model / BIOS version noted on your phone
- [ ] Dotfolders copied (`.ssh`, `.gnupg`, `.kube`, `.aws`, `.m2`, …)
- [ ] Documents / Desktop / Pictures copied and **size-verified**
- [ ] WSL distros exported (if applicable)
- [ ] Bookmarks exported, passwords in a password manager
- [ ] **2FA seeds on your phone, recovery codes printed**
- [ ] Citrix URL, auth method, and company root CA `.pem` saved
- [ ] BIOS/firmware fully updated via Lenovo Vantage
- [ ] Windows recovery USB created and labelled
- [ ] Backup verified by opening files *from the backup drive*
- [ ] Second copy exists

Next: [02-install-media.md](02-install-media.md)
