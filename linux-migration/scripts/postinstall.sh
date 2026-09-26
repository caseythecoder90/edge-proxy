#!/usr/bin/env bash
#
# postinstall.sh — Fedora Workstation post-install bootstrap for a dev laptop.
#
#   >>> READ THIS SCRIPT BEFORE YOU RUN IT. <<<
#
# It is deliberately written to be read: every step is a small, named function
# that does one thing, and nothing runs unless you name it. Running a bootstrap
# script you haven't read is how you end up with a machine you don't understand,
# which is the opposite of the point.
#
# Usage:
#   ./postinstall.sh --list              show every available step
#   ./postinstall.sh --dry-run all       print what 'all' would do, run nothing
#   ./postinstall.sh dnf_tuning update   run just those two steps
#   ./postinstall.sh all                 run every step, in order
#
# Companion to ../05-first-boot.md and ../08-dev-environment.md, which explain
# WHY each of these things is done. This file is the answer key; those pages are
# the lesson.

set -euo pipefail

DRY_RUN=0

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

c_blue=$'\033[1;34m'; c_yellow=$'\033[1;33m'; c_red=$'\033[1;31m'; c_off=$'\033[0m'

log()  { printf '%s==>%s %s\n' "$c_blue"   "$c_off" "$*"; }
warn() { printf '%s!!!%s %s\n' "$c_yellow" "$c_off" "$*" >&2; }
die()  { printf '%sERR%s %s\n' "$c_red"    "$c_off" "$*" >&2; exit 1; }

# run: echo the command in dry-run mode, otherwise execute it.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '    would run: %s\n' "$*"
  else
    "$@"
  fi
}

# run_sh: same, for things that genuinely need a shell (pipes, redirection).
run_sh() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '    would run: sh -c %q\n' "$1"
  else
    bash -c "$1"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# steps  (see --list; order here is the order 'all' uses)
# ---------------------------------------------------------------------------

STEPS=(
  preflight
  dnf_tuning
  update
  rpmfusion
  codecs
  flathub
  firmware
  core_tools
  laptop
  shell
  git_setup
  editors
  containers
  kubernetes
  virtualization
  backups
  summary
)

step_preflight() {
  log "Preflight checks"
  [ -f /etc/fedora-release ] || die "This script is for Fedora. Aborting."
  cat /etc/fedora-release
  [ "$(id -u)" -ne 0 ] || die "Do NOT run this as root. It calls sudo where needed."
  have sudo || die "sudo not found."
  if ! sudo -n true 2>/dev/null; then
    log "You'll be prompted for your sudo password."
  fi
  log "Fedora release: $(rpm -E %fedora)   kernel: $(uname -r)"
}

step_dnf_tuning() {
  log "Speeding up dnf (parallel downloads)"
  if grep -q '^max_parallel_downloads' /etc/dnf/dnf.conf 2>/dev/null; then
    log "  already configured, skipping"
  else
    run_sh "echo 'max_parallel_downloads=10' | sudo tee -a /etc/dnf/dnf.conf"
  fi
}

step_update() {
  log "Full system update (this is the long one)"
  run sudo dnf upgrade --refresh -y
  warn "If the kernel or systemd updated, reboot before continuing."
}

step_rpmfusion() {
  log "Enabling RPM Fusion (free + nonfree)"
  local fedora_ver; fedora_ver="$(rpm -E %fedora)"
  if rpm -q rpmfusion-free-release >/dev/null 2>&1; then
    log "  already enabled, skipping"
    return
  fi
  run sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm"
  run sudo dnf upgrade --refresh -y
}

step_codecs() {
  log "Multimedia codecs + Intel hardware video acceleration"
  run sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
  run sudo dnf update -y @multimedia --setopt=install_weak_deps=False \
       --exclude=PackageKit-gstreamer-plugin
  run sudo dnf install -y intel-media-driver libva-utils
  if [ "$DRY_RUN" -eq 0 ] && have vainfo; then
    log "  VA-API profiles found: $(vainfo 2>/dev/null | grep -c VAProfile || echo 0)"
  fi
}

step_flathub() {
  log "Enabling the full Flathub remote"
  run flatpak remote-add --if-not-exists flathub \
      https://dl.flathub.org/repo/flathub.flatpakrepo
  run flatpak remote-modify --enable flathub
}

step_firmware() {
  log "Firmware updates via LVFS (make sure you are on AC power)"
  run sudo fwupdmgr refresh --force
  run sudo fwupdmgr get-updates || true
  warn "Review the list above, then run 'sudo fwupdmgr update' yourself."
  warn "Not automated on purpose: firmware updates reboot the machine."
}

step_core_tools() {
  log "Core CLI toolkit"
  run sudo dnf group install -y "Development Tools"
  run sudo dnf install -y \
    gcc-c++ make cmake pkgconf \
    git git-delta gh curl wget vim-enhanced neovim tmux \
    htop btop ripgrep fd-find fzf bat eza jq tree ncdu \
    wl-clipboard unzip p7zip rsync stow direnv \
    iproute bind-utils nmap-ncat tcpdump traceroute whois \
    strace ltrace lsof sysstat iotop-c powertop \
    smartmontools pciutils usbutils dmidecode inxi \
    gnome-tweaks dconf-editor gnome-shell-extension-appindicator
}

step_laptop() {
  log "Laptop tuning: battery charge threshold at 80%"
  if [ ! -e /sys/class/power_supply/BAT0/charge_control_end_threshold ]; then
    warn "  This machine does not expose charge thresholds. Skipping."
    return
  fi
  run_sh "sudo tee /etc/systemd/system/battery-charge-threshold.service >/dev/null <<'UNIT'
[Unit]
Description=Limit battery charge to 80%
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'echo 75 > /sys/class/power_supply/BAT0/charge_control_start_threshold'
ExecStart=/bin/sh -c 'echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold'

[Install]
WantedBy=multi-user.target
UNIT"
  run sudo systemctl daemon-reload
  run sudo systemctl enable --now battery-charge-threshold.service
  warn "Read ../06-laptop-tuning.md §2 to understand the unit you just installed."
}

step_shell() {
  log "Shell quality of life (~/.bashrc)"
  if grep -q '# --- postinstall.sh additions ---' ~/.bashrc 2>/dev/null; then
    log "  already applied, skipping"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '    would append history/alias/fzf config to ~/.bashrc\n'
    return
  fi
  cat >> ~/.bashrc <<'BASHRC'

# --- postinstall.sh additions ---
HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend cmdhist checkwinsize globstar autocd cdspell
PROMPT_COMMAND="history -a; ${PROMPT_COMMAND:-}"

export EDITOR=vim
export VISUAL=vim

alias ll='eza -lah --git --group-directories-first'
alias lt='eza --tree --level=2'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias sc='systemctl'
alias scu='systemctl --user'
alias jf='journalctl -f'
alias jb='journalctl -b -p err'

[ -f /usr/share/fzf/shell/key-bindings.bash ] && . /usr/share/fzf/shell/key-bindings.bash
eval "$(direnv hook bash)" 2>/dev/null || true
# --- end postinstall.sh additions ---
BASHRC
  log "  appended. 'source ~/.bashrc' or open a new terminal."
}

step_git_setup() {
  log "Git defaults (identity is left for you to set)"
  run git config --global init.defaultBranch main
  run git config --global pull.rebase true
  run git config --global rebase.autoStash true
  run git config --global push.autoSetupRemote true
  run git config --global diff.algorithm histogram
  run git config --global rerere.enabled true
  run git config --global merge.conflictstyle zdiff3
  if have delta; then
    run git config --global core.pager delta
    run git config --global interactive.diffFilter 'delta --color-only'
    run git config --global delta.navigate true
  fi
  warn "Set your identity yourself:"
  warn "  git config --global user.name  'Your Name'"
  warn "  git config --global user.email 'you@example.com'"
  warn "Commit signing: see ../08-dev-environment.md §4"
}

step_editors() {
  log "VS Code (Microsoft repo)"
  if rpm -q code >/dev/null 2>&1; then
    log "  already installed, skipping"
  else
    run sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    run_sh "sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'REPO'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
REPO"
    run sudo dnf install -y code
  fi

  log "Raising inotify limits (JetBrains IDEs and file watchers need this)"
  run_sh "sudo tee /etc/sysctl.d/99-inotify.conf >/dev/null <<'SYSCTL'
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=1024
SYSCTL"
  run sudo sysctl --system
}

step_containers() {
  log "Containers: podman (native) and Docker CE (for kind)"
  run sudo dnf install -y podman podman-compose buildah skopeo distrobox

  if rpm -q docker-ce >/dev/null 2>&1; then
    log "  docker-ce already installed, skipping repo setup"
  else
    run sudo dnf install -y dnf-plugins-core
    # dnf5 syntax first, fall back to dnf4
    run_sh "sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo \
            || sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo"
    run sudo dnf install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
    run sudo systemctl enable --now docker
    run sudo usermod -aG docker "$USER"
    warn "Added you to the 'docker' group. LOG OUT AND BACK IN for it to take effect."
    warn "Understand the trade-off first: ../08-dev-environment.md §7."
  fi

  log "Allowing rootless containers to bind ports >= 80"
  run_sh "echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-rootless-ports.conf >/dev/null"
  run sudo sysctl --system
}

step_kubernetes() {
  log "Kubernetes client tooling"
  warn "Set K8S_MINOR to the current stable minor from https://kubernetes.io/releases/"
  local k8s_minor="${K8S_MINOR:-v1.34}"
  log "  using ${k8s_minor}"

  if [ ! -f /etc/yum.repos.d/kubernetes.repo ]; then
    run_sh "sudo tee /etc/yum.repos.d/kubernetes.repo >/dev/null <<REPO
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${k8s_minor}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${k8s_minor}/rpm/repodata/repomd.xml.key
REPO"
  fi
  run sudo dnf install -y kubectl

  if ! have kind; then
    log "  installing kind"
    run_sh "curl -Lo /tmp/kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 \
            && chmod +x /tmp/kind && sudo mv /tmp/kind /usr/local/bin/kind"
  fi

  if ! have helm; then
    log "  installing helm"
    run_sh "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
  fi

  if ! have k9s; then
    log "  installing k9s"
    run_sh "curl -sL \"\$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest \
            | jq -r '.assets[] | select(.name==\"k9s_Linux_amd64.tar.gz\") | .browser_download_url')\" \
            | sudo tar -xz -C /usr/local/bin k9s"
  fi

  if ! grep -q '__start_kubectl' ~/.bashrc 2>/dev/null; then
    if [ "$DRY_RUN" -eq 0 ]; then
      cat >> ~/.bashrc <<'KUBE'

# kubectl completion + alias
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k
export KUBE_EDITOR=vim
KUBE
    else
      printf '    would append kubectl completion to ~/.bashrc\n'
    fi
  fi
}

step_virtualization() {
  log "KVM / libvirt / virt-manager"
  run sudo dnf install -y @virtualization virt-manager
  run sudo systemctl enable --now libvirtd
  run sudo usermod -aG libvirt "$USER"
  if [ "$DRY_RUN" -eq 0 ]; then
    sudo virt-host-validate 2>/dev/null | head -10 || true
  fi
  warn "Log out and back in for the 'libvirt' group to apply."
}

step_backups() {
  log "restic (backup tool) — setup is NOT automated"
  run sudo dnf install -y restic borgbackup snapper
  warn "Backups are deliberately manual: the repository password is something"
  warn "only you should generate and store. Follow ../09-backups-and-recovery.md."
}

step_summary() {
  log "Done. Verify:"
  cat <<'SUMMARY'

    systemctl --failed                  # should be empty
    vainfo | grep -c VAProfile          # > 0
    fwupdmgr get-updates                # review, then update manually
    podman run --rm fedora echo ok      # rootless containers
    docker run --rm hello-world         # after logging out and back in
    kubectl version --client
    sudo virt-host-validate | head

  Still to do by hand (on purpose — read the pages, don't paste):
    - git identity + SSH commit signing   -> 08-dev-environment.md §4
    - restore dotfiles, chmod 600 keys    -> 08-dev-environment.md §1
    - restic repository + systemd timer   -> 09-backups-and-recovery.md
    - Citrix Workspace + company CA       -> 07-citrix-vdi.md
    - rehearse the live-USB chroot rescue -> 09-backups-and-recovery.md §4

SUMMARY
}

# ---------------------------------------------------------------------------
# dispatcher
# ---------------------------------------------------------------------------

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

list_steps() {
  printf 'Available steps (in the order "all" runs them):\n\n'
  local s
  for s in "${STEPS[@]}"; do printf '  %s\n' "$s"; done
  printf '\n  all   run every step above, in order\n'
}

main() {
  local args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --list)    list_steps; exit 0 ;;
      -h|--help) usage; exit 0 ;;
      -*)        die "Unknown option: $1" ;;
      *)         args+=("$1") ;;
    esac
    shift
  done

  [ "${#args[@]}" -gt 0 ] || { usage; echo; list_steps; exit 1; }

  local to_run=()
  if [ "${args[0]}" = "all" ]; then
    to_run=("${STEPS[@]}")
  else
    local a s found
    for a in "${args[@]}"; do
      found=0
      for s in "${STEPS[@]}"; do [ "$a" = "$s" ] && found=1 && break; done
      [ "$found" -eq 1 ] || die "Unknown step: $a  (try --list)"
      to_run+=("$a")
    done
  fi

  [ "$DRY_RUN" -eq 1 ] && warn "DRY RUN — nothing will be changed."

  local s
  for s in "${to_run[@]}"; do
    "step_${s}"
    echo
  done
}

main "$@"
