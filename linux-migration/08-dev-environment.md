# 08 — Development environment

**Time: an evening.** Don't try to do all of this in one sitting on install day.

---

## 1. Restore your dotfiles — and fix the permissions

Copying files from NTFS loses Unix permissions. SSH will silently refuse to use a
key that's readable by anyone else, and the error message is not obvious.

```bash
# Mount the backup drive (GNOME Files will do it; note the path it uses)
BACKUP=/run/media/$USER/YOUR_DRIVE/thinkpad-backup

# SSH
mkdir -p ~/.ssh
cp -r "$BACKUP/.ssh/." ~/.ssh/
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_* ~/.ssh/config 2>/dev/null
chmod 644 ~/.ssh/*.pub ~/.ssh/known_hosts 2>/dev/null

# GPG
cp -r "$BACKUP/.gnupg" ~/
chmod 700 ~/.gnupg
find ~/.gnupg -type f -exec chmod 600 {} \;
find ~/.gnupg -type d -exec chmod 700 {} \;

# The rest
for d in .kube .aws .azure .docker .m2 .gradle; do
  [ -d "$BACKUP/$d" ] && cp -r "$BACKUP/$d" ~/
done
cp "$BACKUP/.npmrc" "$BACKUP/.gitconfig" ~/ 2>/dev/null

chmod 700 ~/.kube 2>/dev/null; chmod 600 ~/.kube/config 2>/dev/null
chmod 700 ~/.aws  2>/dev/null; chmod 600 ~/.aws/credentials 2>/dev/null

# Verify
ssh -T git@github.com
```

> **Learn:** `ls -l` shows `-rw-------` for a 600 file. The three triads are
> owner/group/other, and `600` is `rw-`/`---`/`---`. SSH refuses keys that are group-
> or world-readable because on a shared machine that would mean anyone could read
> your private key. `chmod 600` isn't a magic incantation — it's the reason the
> key is a secret at all. `man 1 chmod`, and `stat -c '%a %n' ~/.ssh/*`.

### Then: put your dotfiles in git

If they weren't already, this is the moment. The point is that your next machine —
including the desktop you're planning — takes fifteen minutes instead of an evening.

```bash
mkdir -p ~/dotfiles && cd ~/dotfiles && git init
# Move real files in, symlink them back out. GNU stow automates this:
sudo dnf install stow
# ~/dotfiles/bash/.bashrc  ->  stow bash  ->  ~/.bashrc symlinked
```

`stow` is the simple option. [`chezmoi`](https://www.chezmoi.io/) is the
better-for-multiple-machines option (templating, secrets, per-host differences).
Either is fine; having none is not.

**Never commit secrets.** `.ssh/id_*`, `.aws/credentials`, `.npmrc` tokens,
`.m2/settings.xml` passwords stay out. Add a `.gitignore` and consider
[`git-secrets`](https://github.com/awslabs/git-secrets) or `gitleaks`.

## 2. Terminal

Fedora ships **Ptyxis** (container-aware, good defaults) on recent releases, or
GNOME Console. Both are fine. If you want more:

```bash
sudo dnf install alacritty       # minimal, GPU-accelerated
sudo dnf install kitty           # more features, tabs/layouts built in
```

Fonts that make terminals readable:

```bash
sudo dnf install jetbrains-mono-fonts fira-code-fonts
```

## 3. Shell

**Stay on bash.** Seriously. Every server you SSH into has bash, every CI runner
script is bash, and every Kubernetes debug container drops you into `sh` or `bash`.
Deep bash fluency transfers everywhere; zsh fluency mostly doesn't. Make bash nice
instead of replacing it.

```bash
cat >> ~/.bashrc <<'BASHRC'

# ---- history: keep everything, share across sessions ----
HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend cmdhist
PROMPT_COMMAND="history -a; ${PROMPT_COMMAND:-}"

# ---- sane shell options ----
shopt -s checkwinsize globstar autocd cdspell

# ---- editor ----
export EDITOR=vim
export VISUAL=vim

# ---- aliases ----
alias ll='eza -lah --git --group-directories-first'
alias lt='eza --tree --level=2'
alias cat='bat --paging=never'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias please='sudo $(history -p !!)'

# systemd / journal shortcuts you will use constantly
alias sc='systemctl'
alias scu='systemctl --user'
alias jf='journalctl -f'
alias jb='journalctl -b -p err'

# ---- fzf: Ctrl-R for fuzzy history, Ctrl-T for files ----
[ -f /usr/share/fzf/shell/key-bindings.bash ] && . /usr/share/fzf/shell/key-bindings.bash
BASHRC

source ~/.bashrc
```

A prompt that shows git branch, exit status and kube-context — all three genuinely
prevent mistakes:

```bash
curl -sS https://starship.rs/install.sh | sh
echo 'eval "$(starship init bash)"' >> ~/.bashrc
```

Then in `~/.config/starship.toml` enable the `kubernetes` module — seeing which
cluster you're pointed at, in your prompt, will one day stop you running something
destructive against the wrong one.

> **Learn:** `Ctrl-R` (reverse history search) is the single highest-return keyboard
> shortcut in a shell. With fzf bound to it, it's fuzzy. Use it for a week and you'll
> stop retyping commands forever. Also learn `!!`, `!$`, `Alt-.`, and `Ctrl-A/E/W/U`.

## 4. Git

```bash
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global rebase.autoStash true
git config --global push.autoSetupRemote true
git config --global diff.algorithm histogram
git config --global rerere.enabled true          # remembers conflict resolutions
git config --global core.pager delta
git config --global interactive.diffFilter 'delta --color-only'
git config --global delta.navigate true
git config --global merge.conflictstyle zdiff3   # shows the common ancestor
```

### Sign your commits with your SSH key

Much simpler than GPG, and GitHub verifies it:

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true

# Tell git which keys to trust for verification locally
echo "you@example.com $(cat ~/.ssh/id_ed25519.pub)" >> ~/.config/git/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers
```

Then add the same public key to GitHub a **second** time, as a *Signing Key*
(Settings → SSH and GPG keys → New SSH key → key type **Signing Key**).

### SSH agent

```bash
# Fedora runs a user-level ssh-agent via systemd
systemctl --user enable --now ssh-agent.service 2>/dev/null || true
echo 'export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"' >> ~/.bashrc
```

And an `~/.ssh/config` — this is the file that makes SSH pleasant:

```
Host *
    AddKeysToAgent yes
    ServerAliveInterval 60
    ServerAliveCountMax 3

Host vps
    HostName your.vps.ip
    User youruser
    IdentityFile ~/.ssh/id_ed25519

Host github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
```

Now `ssh vps` works. `man 5 ssh_config` — this file can do far more than you think
(jump hosts, port forwards, per-host keys, connection multiplexing).

## 5. Editors

**VS Code** (Microsoft repo, not Flatpak — the Flatpak is sandboxed away from your
toolchains):

```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo tee /etc/yum.repos.d/vscode.repo <<'REPO'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
REPO
sudo dnf install code
```

**JetBrains** — use the Toolbox App (handles updates and multiple IDEs):
download from <https://www.jetbrains.com/toolbox-app/>, extract, run the binary.

```bash
# JetBrains IDEs watch a lot of files; Fedora's default inotify limit is low
sudo tee /etc/sysctl.d/99-inotify.conf <<'SYSCTL'
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=1024
SYSCTL
sudo sysctl --system
```

**Neovim** — worth learning even if it's not your daily driver, because `vi` is on
every server and `kubectl edit` drops you into it. Start with
[kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim). At minimum learn:
`i a o` / `Esc` / `:w` `:q` `:q!` / `dd` `yy` `p` / `/search` `n` / `gg` `G` / `u` `Ctrl-r`.
That's enough to never be stranded.

## 6. Language toolchains

Use a version manager rather than system packages for anything you develop against
— system packages are for system tools.

```bash
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
exec bash

mise use -g node@lts
mise use -g python@3.12
mise use -g go@latest
mise use -g java@temurin-21
mise ls
```

`mise` also reads a per-project `.mise.toml`, so `cd`-ing into a repo switches
versions automatically. Same idea as `nvm`/`pyenv`/`sdkman`, one tool.

For JVM work you'll still want system Maven/Gradle:

```bash
sudo dnf install maven gradle
```

Python system rule: **never `pip install` outside a venv**, and never with `sudo` —
that fights with `dnf` over the same files and eventually breaks system tools that
are written in Python (`dnf` itself is one).

```bash
python -m venv .venv && source .venv/bin/activate     # per project
sudo dnf install pipx && pipx install ruff            # for global CLI tools
```

## 7. Containers — podman *and* Docker

Fedora ships **podman**: daemonless, rootless by default, and much closer to how a
kubelet actually runs containers.

```bash
sudo dnf install podman podman-compose buildah skopeo

podman run --rm -it registry.fedoraproject.org/fedora:latest bash
podman info | head -30
```

Read that `podman info` output. Note `cgroupVersion: v2`, `rootless: true`,
`ociRuntime: crun`. You're running a container as your own user with no daemon —
compare that to Docker Desktop on Windows, where "the container" is a process
inside a hidden Linux VM.

You'll still want **Docker CE**, because `kind` and a lot of tooling assumes it:

```bash
sudo dnf install dnf-plugins-core
# dnf5 (Fedora 41+):
sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
# dnf4 equivalent: sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"     # log out and back in
docker run --rm hello-world
```

> ⚠️ **Understand what you just did.** Adding yourself to the `docker` group is
> effectively giving yourself passwordless root: `docker run -v /:/host -it alpine
> chroot /host` is a root shell. That's an acceptable trade on your own laptop —
> but it's why you should *never* do it on a shared or production box, and why
> rootless podman exists. Know the trade-off you're making; don't just copy the command.

Useful extras:

```bash
sudo dnf install distrobox            # run any distro's userspace on top of Fedora
distrobox create -n ubuntu -i ubuntu:24.04
distrobox enter ubuntu                # your home dir, Ubuntu's packages
```

This is the answer whenever a vendor only ships a `.deb`.

### Rootless containers and low ports

Rootless podman can't bind ports below 1024 by default:

```bash
echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-rootless-ports.conf
sudo sysctl --system
```

## 8. Firewall

Fedora runs `firewalld` and blocks inbound by default.

```bash
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --list-all

# Example: expose a dev server on the local network temporarily
sudo firewall-cmd --add-port=8080/tcp              # this boot only
sudo firewall-cmd --add-port=8080/tcp --permanent  # persist
sudo firewall-cmd --reload
```

> The `--permanent` / runtime split confuses everyone once. Runtime changes vanish
> on reload/reboot; permanent changes don't apply until `--reload`. Doing both is
> the normal pattern. `man firewall-cmd`.

## 9. Virtualization

You enabled VT-x/VT-d on page 03; turn it into something usable:

```bash
sudo dnf install @virtualization virt-manager
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt "$USER"

# Verify KVM is actually available
lsmod | grep kvm
sudo virt-host-validate | head -20
```

## 10. Secrets

```bash
sudo dnf install pass age
flatpak install flathub com.bitwarden.desktop     # or 1Password's official rpm
```

For encrypting secrets *in* a git repo (Kubernetes manifests especially), learn
[`sops`](https://github.com/getsops/sops) with `age`. You'll want it on page 10.

## 11. direnv — per-directory environments

```bash
sudo dnf install direnv
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
```

Then a `.envrc` per project sets `KUBECONFIG`, `AWS_PROFILE`, etc. automatically
when you `cd` in, and unsets them when you leave. This prevents the "oops, wrong
cluster" class of accident.

---

## Checkpoint

- [ ] `ssh -T git@github.com` authenticates
- [ ] A test commit shows **Verified** on GitHub
- [ ] Dotfiles are in a git repo and pushed
- [ ] `podman run --rm fedora echo ok` works **without sudo**
- [ ] `docker run --rm hello-world` works, and you can explain why `docker` group ≈ root
- [ ] `mise ls` shows your toolchains; `java -version`, `node -v`, `python -V` work
- [ ] `sudo virt-host-validate` passes the KVM checks
- [ ] Your prompt shows the git branch

Next: [09-backups-and-recovery.md](09-backups-and-recovery.md)
