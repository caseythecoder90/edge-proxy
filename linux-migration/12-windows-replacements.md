# 12 — App-for-app replacements

Install method matters: **`dnf`** for anything that needs to see your toolchains or
the system; **Flatpak** for sandboxed GUI apps.

## Daily drivers

| Windows | Linux | Install |
| --- | --- | --- |
| Edge / Chrome | Firefox (preinstalled), Chrome, Brave, Chromium | `dnf install google-chrome-stable` (needs the third-party repo enabled) |
| Windows Terminal | Ptyxis / GNOME Console (preinstalled), kitty, Alacritty | `dnf install kitty` |
| Explorer | Nautilus (preinstalled) | — |
| Notepad / Notepad++ | GNOME Text Editor, `gedit`, Neovim, VS Code | `dnf install code` |
| 7-Zip | File Roller (preinstalled), `p7zip`, `unar` | `dnf install p7zip p7zip-plugins unar` |
| Task Manager | GNOME System Monitor, `btop` | `dnf install btop` |
| Snipping Tool | GNOME Screenshot (**PrtSc**), Flameshot | `flatpak install flathub org.flameshot.Flameshot` |
| Windows Photos | Loupe (preinstalled), Shotwell | — |
| Paint | Drawing, Krita, GIMP | `flatpak install flathub org.gnome.Drawing` |
| Calculator | GNOME Calculator (preinstalled) | — |
| PowerToys | GNOME Extensions + `xdotool`/`wtype`; **Ulauncher** for the launcher | `flatpak install flathub io.ulauncher.Ulauncher` |
| Everything (search) | `fd`, `ripgrep`, `plocate` | `dnf install plocate` |
| WinDirStat | `ncdu`, Baobab (preinstalled) | `dnf install ncdu` |
| Clipboard history | GNOME extension *Clipboard Indicator* / `clipman` | extensions.gnome.org |

## Work and comms

| Windows | Linux | Notes |
| --- | --- | --- |
| Outlook (desktop) | Web Outlook, Evolution, Thunderbolt/**Thunderbird** | Evolution has the best Exchange support (`dnf install evolution evolution-ews`) |
| Teams | **Web app in Chrome** | No official Linux desktop client. Chrome's "Install app" makes it a window. Screen sharing works better in Chrome than Firefox. |
| Slack | Flatpak or web | `flatpak install flathub com.slack.Slack` |
| Zoom | Official RPM or Flatpak | `flatpak install flathub us.zoom.Zoom` |
| MS Office | **Office on the web**, LibreOffice, OnlyOffice | OnlyOffice has the best `.docx` fidelity: `flatpak install flathub org.onlyoffice.desktopeditors` |
| OneDrive | `onedriver`, `rclone`, or the web | `rclone` is the robust choice and teaches you a useful tool |
| OneNote | Web, Obsidian, Joplin, Logseq | `flatpak install flathub md.obsidian.Obsidian` |
| Adobe Reader | Evince (preinstalled), Okular | For forms/signing: Okular or Xournal++ |
| Snagit | Flameshot + Kooha (screen record) | `flatpak install flathub io.github.seadve.Kooha` |
| **Citrix Workspace** | **Citrix Workspace app for Linux** | See [07-citrix-vdi.md](07-citrix-vdi.md) |
| RDP client | Remmina, FreeRDP, GNOME Connections | `dnf install remmina remmina-plugins-rdp` |
| PuTTY | `ssh` — it's built in | `~/.ssh/config` replaces saved sessions |
| WinSCP / FileZilla | Nautilus (`sftp://host`), `rsync`, `scp`, FileZilla | Nautilus browsing SFTP is genuinely nicer |

## Development

| Windows | Linux | Notes |
| --- | --- | --- |
| WSL2 | **You are the Linux now** | Use `distrobox` or `toolbox` if you want another distro's userspace |
| Docker Desktop | `podman` + `docker-ce` | No VM. Bind mounts are fast. See page 08. |
| Visual Studio | Rider, VS Code, or JetBrains IDEs | Full VS has no Linux version |
| IntelliJ / JetBrains | Same, via Toolbox App | Identical experience |
| SQL Server Mgmt Studio | DBeaver, Azure Data Studio, `psql`/`mysql` | `flatpak install flathub io.dbeaver.DBeaverCommunity` |
| Postman | Bruno, Insomnia, `curl`, `httpie` | Bruno is local-first and git-friendly — a genuine upgrade |
| Fiddler | `mitmproxy`, browser devtools, `tcpdump` | `dnf install mitmproxy` |
| Git Bash | your actual shell | — |
| WinMerge | `meld`, `delta`, `difftastic` | `dnf install meld` |
| Notepad++ macros | `sed`/`awk`/Neovim | See page 11 week 7 |
| VirtualBox | **KVM + virt-manager** | Better performance, no Secure Boot problems |
| Hyper-V | KVM | — |

## Media and personal

| Windows | Linux | Install |
| --- | --- | --- |
| VLC | VLC, MPV | `dnf install vlc mpv` |
| Spotify | Spotify, or the web player | `flatpak install flathub com.spotify.Client` |
| iTunes/music | Rhythmbox, Strawberry | `dnf install rhythmbox` |
| OBS | OBS Studio | `flatpak install flathub com.obsproject.Studio` |
| Audacity | Audacity, Tenacity | `flatpak install flathub org.audacityteam.Audacity` |
| Photoshop | GIMP, Krita, Photopea (web) | No Adobe on Linux. This is a real loss; be honest about it. |
| Lightroom | Darktable, RawTherapee | `flatpak install flathub org.darktable.Darktable` |
| Steam | Steam + Proton | `dnf install steam` (needs third-party repos). Check [ProtonDB](https://www.protondb.com/) before buying. |
| Calibre | Calibre | `flatpak install flathub com.calibre_ebook.calibre` |

## Things with no good answer

Be honest with yourself about these:

- **Adobe Creative Cloud** — no Linux version, no reliable workaround. Photopea in a
  browser for light work; otherwise this needs a Windows machine or a VM.
- **Anti-cheat multiplayer games** — Valorant, Fortnite, Destiny 2, League (partly),
  most competitive shooters. Kernel anti-cheat blocks Linux by design.
- **Some banking / government apps** with Windows-only smartcard middleware.
- **Vendor-specific hardware configurators** (firmware flashers, radio programmers,
  some CAD dongles).

For all of these, the answer is the KVM Windows VM from page 07 Part C — or your
future desktop build keeping a Windows drive.

## A note on the GNOME desktop itself

GNOME is opinionated and it is *not* Windows. Three settings that make it click:

1. **Press the Super key and type.** That's the whole workflow — it replaces the
   Start menu, search, and Alt-Tab. Stop hunting for a taskbar.
2. **Workspaces are the point.** `Super+Page Up/Down` to switch,
   `Super+Shift+Page Up/Down` to move a window. Use one workspace per task.
3. **Extensions** for the things you miss:
   ```bash
   sudo dnf install gnome-extensions-app
   # then browse https://extensions.gnome.org in Firefox
   ```
   Worth having: *Dash to Dock* (taskbar), *Clipboard Indicator*, *Caffeine*,
   *Vitals* (sensors in the top bar), *AppIndicator support* (tray icons).

Give it two weeks before deciding you hate it. Most people who switch to KDE on day
three do it because GNOME wasn't Windows, not because KDE was better. Both are
excellent; the mistake is deciding under the stress of week one. (If after a fair
trial you do want KDE: `sudo dnf group install "KDE Plasma Workspaces"`, then pick
the session at the login screen. Nothing else breaks.)
