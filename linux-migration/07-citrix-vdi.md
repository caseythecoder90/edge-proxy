# 07 — Citrix VDI on Linux

This page has two halves:

- **Part A — the pre-wipe gate.** Run this *before* you destroy Windows. Linked
  from page 03.
- **Part B — the real install** on your new Fedora system.

Citrix ships and supports a native **Citrix Workspace app for Linux**, so the
expected outcome here is "it works". But your VDI is your job, so we prove it
rather than assume it.

> **Check policy first.** Some employers only permit managed devices, or only
> permit the Workspace app version they ship. A five-minute message to IT asking
> "is Citrix Workspace app for Linux supported here?" is cheaper than finding out
> on a Monday. If they say no, stop and read *Part C — if it doesn't work*.

---

# Part A — The pre-wipe gate

## Test 1: the HTML5 fallback (do this from Windows, 5 minutes)

This establishes your floor. If it works, you will always have *some* access from
Linux, regardless of the native client.

1. Open your StoreFront URL in **Chrome or Edge**.
2. Log in.
3. Look for **"Use light version"**, **"Use web browser"**, or a settings toggle
   for the HTML5 receiver. Launch a desktop with it.
4. Does it render? Keyboard work? Clipboard work? Sound, if you need it?

Record the answer. If yes, the worst case on Linux is "browser-based VDI", which is
usable.

If your company's StoreFront doesn't offer it, that's not fatal — it just means the
native client test below is now load-bearing.

## Test 2: the native client from a Fedora live USB (30 minutes)

This is the real test. You'll run Fedora entirely from RAM without touching your
disk, install the Citrix client into that temporary session, and connect.

### Boot the live session

1. Plug in the Fedora USB and **AC power**. Plug in **Ethernet** if you have it —
   it removes Wi-Fi as a variable.
2. Power on, press **F12**, choose the USB device.
3. At the GRUB menu choose **"Start Fedora-Workstation-Live"** (or "Test this media
   & start Fedora"; the test adds a few minutes and is worth doing once).
4. At the welcome screen click **"Try Fedora"**. ← **Not "Install to Hard Drive."**

You are now running Linux with your Windows install completely untouched. Nothing
you do in this session is written to the internal disk.

### Sanity-check the hardware while you're here

Free reconnaissance. Open **Terminal** (Super key → type "terminal"):

```bash
# Wi-Fi: is there a wireless device and is it connected?
nmcli device status

# Audio: are there output devices?
wpctl status

# Graphics: which driver bound?
lspci -k | grep -A3 -i vga

# Any firmware the kernel wanted but couldn't find?
sudo dmesg | grep -i 'firmware' | grep -iv 'loaded\|direct' | head -20

# Battery / power reporting
upower -i $(upower -e | grep BAT)
```

Also physically test: **trackpad, TrackPoint, all three mouse buttons, keyboard
backlight (Fn+Space), volume keys, brightness keys, webcam (open Cheese if
installed), fingerprint reader presence (`lsusb | grep -i -E 'synaptics|goodix|validity'`),
and the suspend/resume cycle (close the lid, wait 30s, open it).**

Write down anything that misbehaves. Almost certainly nothing will.

### Install the Citrix client in the live session

The live session's writable layer lives in RAM, so keep it lean and don't reboot —
you lose everything on reboot, which is the point.

```bash
# 1. Get the RPM.
#    Go to https://www.citrix.com/downloads/workspace-app/linux/
#    Take: "Citrix Workspace app for Linux" -> Full Package (Self-Service Support)
#          -> x86_64 -> the *.rpm for RHEL/Fedora  (file looks like ICAClient-rhel-*.rpm)
#    Download it in Firefox; it lands in ~/Downloads.

cd ~/Downloads
sudo dnf install ./ICAClient-rhel-*.x86_64.rpm
```

`dnf` resolves the dependencies itself. If it names something it can't find, install
that and retry — on Fedora the usual suspects are GTK3, WebKitGTK (for the embedded
browser used by SAML/SSO logins), and `krb5-libs` for Kerberos.

### Install your company's root CA — this is the step everyone misses

If your company terminates TLS with an internal CA (most do), Citrix will fail with
**"SSL error 61: You have not chosen to trust <CA name>"**. The Workspace app keeps
its *own* certificate store; adding the CA to the system trust store is not enough.

Copy the `company-root-ca.pem` you exported on page 01 onto the live machine (USB
stick, or re-export from a browser), then:

```bash
sudo cp company-root-ca.pem /opt/Citrix/ICAClient/keystore/cacerts/
sudo /opt/Citrix/ICAClient/util/ctx_rehash
```

`ctx_rehash` regenerates the hash-named symlinks OpenSSL uses to find certificates
by subject hash. Without it the file is invisible to the client.

> **Learn:** `ls -l /opt/Citrix/ICAClient/keystore/cacerts/` before and after. The
> `abcd1234.0` symlinks are the same trick `/etc/ssl/certs` uses — look at
> `openssl x509 -hash -noout -in company-root-ca.pem` and you'll see where the name
> comes from. This is the same trust-chain machinery your `edge-proxy` nginx
> depends on, viewed from the client side.

### Connect

```bash
/opt/Citrix/ICAClient/selfservice
```

Add your store when prompted (the URL from page 01), authenticate, and launch your
desktop.

CLI alternative, useful for diagnosing:

```bash
/opt/Citrix/ICAClient/util/storebrowse --addstore https://vdi.company.com
/opt/Citrix/ICAClient/util/storebrowse -E    # enumerate published resources
```

### The gate

Actually do a slice of your real job in the session for ten minutes:

- [ ] Desktop launches and is responsive
- [ ] Keyboard maps correctly (check `@ " # \ | ~` and arrow/Home/End keys)
- [ ] Copy/paste works **in both directions**
- [ ] Multiple monitors work, if you use them
- [ ] Audio works, if you take calls through it
- [ ] Screen resolution / scaling is usable
- [ ] Session survives 15 minutes without dropping
- [ ] Anything else your job depends on (smart card, USB redirection, printing)

**All green → wipe with confidence.** Go to [04-install-fedora.md](04-install-fedora.md).

**Red → do not wipe.** Read Part C below.

---

# Part B — Citrix on your installed Fedora

Same steps as the live test, done permanently. Run these after page 05.

```bash
cd ~/Downloads
sudo dnf install ./ICAClient-rhel-*.x86_64.rpm

sudo cp ~/backup/company-root-ca.pem /opt/Citrix/ICAClient/keystore/cacerts/
sudo /opt/Citrix/ICAClient/util/ctx_rehash

/opt/Citrix/ICAClient/selfservice
```

### Where everything lives

| Path | What |
| --- | --- |
| `/opt/Citrix/ICAClient/` | Install root |
| `/opt/Citrix/ICAClient/selfservice` | The GUI app |
| `/opt/Citrix/ICAClient/util/configmgr` | Preferences GUI (DPI, keyboard, audio, drive mapping) |
| `/opt/Citrix/ICAClient/util/storebrowse` | CLI: add stores, list resources, launch |
| `/opt/Citrix/ICAClient/util/ctx_rehash` | Re-index the cert store after adding a CA |
| `/opt/Citrix/ICAClient/keystore/cacerts/` | **Citrix's own** CA trust store |
| `~/.ICAClient/wfclient.ini` | Per-user client config |
| `~/.ICAClient/All_Regions.ini` | Per-user policy/feature config |
| `~/.ICAClient/cache/` | Session cache — delete this when things get weird |

Give yourself a launcher: `selfservice` usually installs a `.desktop` entry, so it
shows up in the Activities overview as "Citrix Workspace". If it doesn't:

```bash
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/citrix-workspace.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Citrix Workspace
Exec=/opt/Citrix/ICAClient/selfservice
Icon=/opt/Citrix/ICAClient/icons/manifest.png
Categories=Network;RemoteAccess;
Terminal=false
DESKTOP
update-desktop-database ~/.local/share/applications
```

### Make `.ica` files launch properly

If you launch from the StoreFront web page, the browser downloads a `.ica` file that
has to be handed to `wfica`. The RPM registers this, but if Firefox keeps asking:

```bash
xdg-mime default wfica.desktop application/x-ica
xdg-mime query default application/x-ica   # verify
```

### Common problems and their fixes

| Symptom | Cause | Fix |
| --- | --- | --- |
| **SSL error 61** — "not chosen to trust" | Company CA missing from Citrix's own store | Copy the PEM into `keystore/cacerts/`, run `ctx_rehash` |
| **SSL error 4/47/29** | Wrong store URL, TLS version mismatch, or proxy | Check the URL; test with `openssl s_client -connect vdi.company.com:443 -showcerts` |
| **Login window blank / white** | Missing WebKitGTK for the embedded browser | `sudo dnf install webkit2gtk4.1` (or whatever `dnf` names), relaunch |
| **Wrong keyboard layout in session** | Client keyboard mapping | `configmgr` → Keyboard → set layout explicitly, or try Unicode keyboard mode |
| **No audio** | ALSA/PipeWire routing | Fedora ships `pipewire-alsa`; check `wpctl status`, and `configmgr` → Audio |
| **Tiny UI on a HiDPI screen** | No DPI matching | `configmgr` → look for DPI matching; or launch with `GDK_SCALE=2 /opt/Citrix/ICAClient/selfservice` |
| **USB redirection not working** | `ctxusbd` not running | `systemctl status ctxusbd` → `sudo systemctl enable --now ctxusbd` |
| **Smart card auth fails** | Missing PC/SC stack | `sudo dnf install pcsc-lite pcsc-tools opensc` ; `sudo systemctl enable --now pcscd` ; test with `pcsc_scan` |
| **Session weirdness after an upgrade** | Stale cache | `rm -rf ~/.ICAClient/cache/*` and relaunch |
| **Something is silently blocked** | SELinux denial | `sudo ausearch -m AVC -ts recent` — see below |

### If you suspect SELinux

Don't disable SELinux. Diagnose it:

```bash
sudo ausearch -m AVC,USER_AVC -ts recent
sudo dnf install setroubleshoot-server   # gives human-readable explanations
sudo sealert -a /var/log/audit/audit.log
```

`sealert` tells you the exact `semanage`/`setsebool` command to fix it. To test
whether SELinux is even the problem without disabling it permanently:

```bash
sudo setenforce 0      # permissive, temporary, reverts on reboot
# ...reproduce the problem...
sudo setenforce 1      # back to enforcing
```

If it works in permissive mode, it's SELinux and `sealert` will tell you the proper
policy fix. Turning it off is the answer to a different, worse question.

> **Learn:** this is one of the highest-value Linux skills for a Kubernetes career.
> "Container can't write to the volume on the RHEL node" is, nine times out of ten,
> an SELinux label (`:z`/`:Z` on a podman mount, `seLinuxOptions` in a pod spec).
> Getting comfortable with `ausearch` and `sealert` now pays off repeatedly.

---

# Part C — If Citrix doesn't work

In rough order of preference.

### 1. HTML5 receiver in a browser

If Test 1 passed, this is your floor. Works in Chrome/Chromium. Slightly worse
clipboard and peripheral support, fine for most work. Install Chrome:

```bash
sudo dnf install fedora-workstation-repositories
sudo dnf config-manager setopt google-chrome.enabled=1
sudo dnf install google-chrome-stable
```

### 2. Windows 11 in a KVM virtual machine — the strong fallback

This is a genuinely good answer and it's why page 01 had you record the product
key. You get a real Windows with the real Citrix client, and since the VDI session
is remote anyway, the VM needs no GPU.

```bash
sudo dnf install @virtualization virt-manager
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER   # log out and back in
```

Then: download a Windows 11 ISO from Microsoft, create the VM in `virt-manager`
(4 vCPU / 8 GB RAM / 80 GB disk), add an emulated **TPM 2.0** device and set the
firmware to **UEFI** — Windows 11 requires both. Install the
[virtio-win guest drivers](https://github.com/virtio-win/virtio-win-pkg-scripts)
for decent disk and network speed.

Cost: ~80 GB of disk and ~8 GB of RAM while it's running. Your ThinkPad can do this.

> **Bonus:** setting this up teaches you KVM, libvirt, virtual networking and
> virtio — all directly relevant background for how cloud VMs and Kubernetes nodes
> actually work.

### 3. Ask IT for an alternative

Many companies that offer Citrix also offer plain RDP over VPN, or VMware Horizon
(which also has a Linux client), or a web-based remote desktop. Worth one email.
On Linux, RDP is `remmina` (`sudo dnf install remmina remmina-plugins-rdp`) or
`freerdp`, and both are excellent.

### 4. Don't wipe — dual-boot instead

If none of the above works and the VDI is non-negotiable, that's a legitimate
answer. Shrink the Windows partition from Windows' own Disk Management (leave
Windows ≥ 100 GB), disable **Fast Startup** (Control Panel → Power Options →
Choose what the power buttons do → uncheck *Turn on fast startup*), and install
Fedora into the free space, letting the installer use the existing EFI partition.
You still get to learn Linux; you just keep the escape hatch.

You said you're building a desktop later anyway — a dual-boot ThinkPad now and a
Linux-only desktop later is a perfectly sensible path, not a defeat.
