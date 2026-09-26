# 11 — A 12-week Linux curriculum

This is the page that answers "help me become a better engineer."

It's built around one idea: **Kubernetes is a very thin layer over Linux
primitives.** Every week here teaches a Linux mechanism and then shows you where
Kubernetes uses it. By week 12 you won't be someone who memorised `kubectl`
commands — you'll be someone who knows what's underneath them, which is the
difference between debugging a cluster and rebooting it.

## How to run this

- **~5 hours a week.** Three evenings of an hour, one longer session at the weekend.
- **Each week has:** concepts → commands → a build exercise → a *Chaos Friday* →
  a prove-it checkpoint.
- **Chaos Friday is the most important part.** You deliberately break something and
  fix it without help. Learning to recover calmly is a skill, and it is only
  acquired by practice.
- **Keep the notebook.** `~/notes/linux-log.md`, in git, one entry per session:
  what you did, what surprised you, what you'd forget in a month.
- **Take snapshots before Chaos Friday**: `sudo snapper -c root create -d "pre-chaos week N"`.

> **A caution:** do Chaos Friday exercises in a VM or a container where the page
> says so. Only the ones explicitly marked as safe belong on your daily driver.

```bash
# Set up a disposable VM for the dangerous exercises
sudo dnf install @virtualization virt-manager
# In virt-manager: new VM from the Fedora ISO, 2 vCPU / 4GB / 20GB, snapshot it clean.
# Alternatively, quick and disposable:
podman run --rm -it registry.fedoraproject.org/fedora:latest bash
```

---

## Week 1 — The filesystem, permissions, and who you are

**Concepts:** the Filesystem Hierarchy Standard; everything-is-a-file; inodes and
hard vs symbolic links; users, groups, and the permission triad; `umask`; setuid;
why `/tmp` is sticky.

**Commands:** `ls -l`, `stat`, `find`, `ln`, `chmod`, `chown`, `umask`, `id`,
`getent`, `df`, `du`, `ncdu`, `file`, `readlink -f`.

**Exercise**

```bash
# Read the map, then go look at the territory
man hier

# What are these directories actually for? Look, then explain each in your notes:
ls /etc /var /usr /opt /srv /run /proc /sys /dev

# Permissions, concretely
stat -c '%A %a %U %G %n' /etc/shadow /etc/passwd /tmp /usr/bin/passwd
# Why is /usr/bin/passwd 4755? What does the leading 4 mean, and why does a
# program that changes YOUR password need it?

# Hard link vs symlink — prove the difference rather than reading it
cd /tmp && echo hello > original.txt
ln original.txt hard.txt
ln -s original.txt soft.txt
ls -li original.txt hard.txt soft.txt     # compare the inode numbers
rm original.txt
cat hard.txt      # works. why?
cat soft.txt      # broken. why?
```

**Build:** a `~/bin` on your PATH with three small scripts you'll actually use.

**Chaos Friday (safe):** `chmod 000` a file you own and then recover it. Then
`chmod -R 777 ~/testdir` and explain to your notes exactly why that's dangerous.

**Prove it:** explain to yourself, out loud, why SSH refuses a private key with mode
`644`, and what `4755` on `/usr/bin/passwd` accomplishes.

**Kubernetes link:** `securityContext.runAsUser`, `fsGroup`, and
`readOnlyRootFilesystem` are exactly these concepts. `fsGroup` exists because of
group ownership on mounted volumes.

---

## Week 2 — Processes, signals, and `/proc`

**Concepts:** the process tree; PID 1; fork/exec; process states (including
zombies and `D` state); file descriptors; signals; niceness; the OOM killer.

**Commands:** `ps aux`, `ps -ef --forest`, `pstree`, `top`/`btop`, `kill`,
`pkill`, `jobs`, `bg`/`fg`, `nohup`, `lsof`, `nice`/`renice`, `strace`.

**Exercise**

```bash
# Everything about a process is a file
sleep 1000 &
PID=$!
ls -l /proc/$PID/            # look at all of it
cat /proc/$PID/cmdline | tr '\0' ' '; echo
ls -l /proc/$PID/fd/         # its open file descriptors
cat /proc/$PID/status | head -20
cat /proc/$PID/limits

# Signals
kill -l                      # the whole list
kill -TERM $PID              # polite: "please clean up and exit"
# vs kill -KILL — which the process cannot catch, and so cannot clean up after.
# THIS is why a pod has terminationGracePeriodSeconds.

# Watch syscalls happen
strace -f -e trace=openat,read,write ls /etc 2>&1 | head -30

# What has this port open?
sudo lsof -i :22
sudo ss -tulpn | grep :22
```

**Build:** a script that finds the top 5 memory consumers and logs them, run from a
systemd timer next week.

**Chaos Friday (safe):** run `cat /dev/zero | head -c 100G > /dev/null` and watch
memory in `btop`. Then trigger a real OOM kill in a **container**:
`podman run --rm -m 50m alpine sh -c 'yes | tr \\n x | head -c 100m | grep n'` and
find the kill in `journalctl -k | grep -i oom`.

**Prove it:** explain SIGTERM vs SIGKILL, and connect it to what happens when a pod
is deleted.

**Kubernetes link:** `terminationGracePeriodSeconds` is the gap between the SIGTERM
and the SIGKILL. `preStop` hooks, `OOMKilled` (exit code 137 = 128 + 9 = SIGKILL),
and exit code 143 (= 128 + 15 = SIGTERM). Those numbers stop being magic this week.

---

## Week 3 — systemd

The single highest-value week for someone doing infrastructure work.

**Concepts:** units and unit types; targets; dependencies (`Wants`/`Requires`/
`After`); the journal; timers; user vs system units; `systemd-analyze`; cgroup
integration; service hardening directives.

**Commands:** `systemctl`, `journalctl`, `systemd-analyze`, `systemd-cgls`,
`systemd-cgtop`, `loginctl`, `systemd-run`.

**Exercise**

```bash
systemctl list-units --type=service
systemctl cat sshd.service          # read a real, well-written unit
systemctl show sshd.service | head -40
systemctl list-dependencies graphical.target

# The journal is a structured database, not a text file
journalctl -u sshd --since "1 hour ago"
journalctl -b -p err                # this boot, errors and worse
journalctl -f                       # follow
journalctl -u sshd -o json-pretty | head -40      # see the actual fields
journalctl --disk-usage

# Run a throwaway command as a transient unit, fully supervised
systemd-run --user --unit=demo sleep 300
systemctl --user status demo
systemd-cgls                        # the cgroup tree — note every service has one
```

**Build:** write a service + timer from scratch for the week-2 script. Then harden
it and observe the difference:

```bash
sudo systemd-analyze security my-thing.service
# Then add: NoNewPrivileges=yes, PrivateTmp=yes, ProtectSystem=strict,
# ProtectHome=yes, RestrictAddressFamilies=AF_UNIX, CapabilityBoundingSet=
# ...and re-run. Watch the score improve and understand each line.
```

**Chaos Friday (VM!):** break a unit file deliberately (bad `ExecStart` path,
circular `After=`), and diagnose it purely from `systemctl status` and
`journalctl -xeu`.

**Prove it:** write a timer that runs every 10 minutes, survives reboots, catches up
after downtime, and logs to the journal — from memory.

**Kubernetes link:** `systemd-analyze security` maps almost one-to-one onto a pod
`securityContext` (`allowPrivilegeEscalation` ↔ `NoNewPrivileges`, `capabilities.drop`
↔ `CapabilityBoundingSet`, `readOnlyRootFilesystem` ↔ `ProtectSystem=strict`).
The kubelet itself is a systemd unit, and it puts every pod in a cgroup slice.

---

## Week 4 — Packages, repos, and building from source

**Concepts:** RPM vs dnf; repository metadata and GPG signing; dependency
resolution; transaction history; what a `.spec` file is; when to build from source.

**Commands:** `dnf`, `rpm -q`, `dnf repoquery`, `dnf history`, `rpm -V`,
`dnf provides`, `dnf download --source`.

**Exercise**

```bash
rpm -qa | wc -l                      # how many packages?
rpm -qi bash                          # metadata
rpm -ql bash | head                   # what files did it install?
rpm -qf /usr/bin/ls                   # which package owns this file?
dnf provides '*/bin/dig'              # I need this command — what do I install?
rpm -V bash                           # has anything been modified since install?

dnf repoquery --requires --resolve bash
dnf repolist -v
dnf history
sudo dnf history info last

# GPG: why can you trust these packages?
rpm -qa gpg-pubkey* --qf '%{version}-%{release} %{summary}\n'
```

**Build:** build one small program from source (`./configure && make && sudo make
install` or a Go/Rust binary). Then do it again into `/usr/local` and explain why
`/usr/local` exists and why `make install` into `/usr` is rude.

**Chaos Friday (VM):** `sudo dnf remove` something load-bearing, then recover with
`dnf history undo`.

**Prove it:** find which package owns a given file, verify it hasn't been tampered
with, and roll back a transaction.

**Kubernetes link:** a container image is a package format with the same problems —
dependency resolution, provenance, signing. Look at `skopeo inspect` and
[cosign](https://github.com/sigstore/cosign) alongside `rpm -qi` and GPG.

---

## Week 5 — Networking, part 1

**Concepts:** interfaces and addresses; routing tables; ARP; DNS resolution order;
`systemd-resolved`; NetworkManager; sockets and listening ports; TCP handshake;
MTU; firewalld zones.

**Commands:** `ip`, `ss`, `dig`, `resolvectl`, `nmcli`, `traceroute`, `mtr`,
`tcpdump`, `curl -v`, `firewall-cmd`.

**Exercise**

```bash
ip addr
ip route
ip -s link                       # per-interface stats: errors, drops
ip neigh                         # the ARP cache

ss -tulpn                        # all listening sockets + owning process
ss -tan state established

resolvectl status                # which DNS server for which interface
dig +trace fedoraproject.org     # watch recursion happen, root -> TLD -> authoritative
dig @1.1.1.1 example.com AAAA

# Watch a TCP handshake
sudo tcpdump -n -i any 'tcp port 443 and host example.com' &
curl -sS https://example.com > /dev/null
# Identify SYN, SYN-ACK, ACK in the output. Then the TLS ClientHello.

nmcli device status
nmcli connection show
```

**Build:** run a container publishing a port, then trace the path from `curl
localhost:8080` all the way to the process inside — through `ss`, `iptables-save`
or `nft list ruleset`, and `/proc/<pid>/net`.

**Chaos Friday (safe):** break your own DNS (point `resolvectl` at a dead server),
diagnose it from symptoms alone, and fix it. Then block your own outbound 443 with
firewalld and observe exactly how each tool fails differently.

**Prove it:** given "the website is slow", produce a structured diagnosis using
`dig`, `curl -w`, `mtr`, and `ss` — and know which layer each one tells you about.

**Kubernetes link:** Service DNS (`svc.cluster.local`), CoreDNS, `ndots:5` and why
it causes surprising latency, kube-proxy's iptables rules, and NetworkPolicy. This
week is the prerequisite for understanding any of it.

---

## Week 6 — Storage

**Concepts:** block devices; partition tables; filesystems; mounting and `/etc/fstab`;
UUIDs vs device names; LVM; Btrfs subvolumes and snapshots; LUKS; swap; the page
cache.

**Commands:** `lsblk`, `blkid`, `findmnt`, `mount`, `df`, `du`, `fdisk`/`parted`,
`mkfs`, `btrfs`, `cryptsetup`, `lvs`/`vgs`/`pvs`, `smartctl`.

**Exercise**

```bash
lsblk -f
findmnt --real                        # the full mount tree
cat /etc/fstab                        # read every field; man 5 fstab
sudo btrfs filesystem usage /
sudo btrfs subvolume list /
sudo cryptsetup luksDump /dev/nvme0n1p3

# Build a filesystem in a file — completely safe, endlessly instructive
truncate -s 1G /tmp/disk.img
mkfs.ext4 /tmp/disk.img
mkdir -p /tmp/mnt && sudo mount -o loop /tmp/disk.img /tmp/mnt
df -h /tmp/mnt
sudo umount /tmp/mnt

# Add LUKS to the loop file and repeat. Now you've encrypted a disk
# with zero risk to anything real.
sudo cryptsetup luksFormat /tmp/disk.img
sudo cryptsetup luksOpen /tmp/disk.img testcrypt
sudo mkfs.ext4 /dev/mapper/testcrypt
sudo cryptsetup luksClose testcrypt

# Disk health — actually check your SSD
sudo smartctl -a /dev/nvme0n1 | head -40
```

**Build:** a Btrfs snapshot-before-upgrade workflow, and prove you can restore a
file from a snapshot.

**Chaos Friday (VM!):** put a bad UUID in `/etc/fstab`, reboot, land in emergency
mode, and recover. **Do this in a VM.** It is the single most common way people
make a Linux machine unbootable, and having done it once deliberately is worth a
great deal.

**Prove it:** explain why `/etc/fstab` uses UUIDs rather than `/dev/sda1`, and what
a Btrfs snapshot actually copies (hint: almost nothing).

**Kubernetes link:** PersistentVolumes, StorageClasses, CSI drivers, access modes,
and `volumeMounts` are all this, wrapped in an API. `emptyDir` is `tmpfs` or a
directory; `hostPath` is a bind mount.

---

## Week 7 — The shell, properly

**Concepts:** word splitting and quoting (the source of most shell bugs); pipes and
redirection; exit codes; `set -euo pipefail`; process substitution; regular
expressions; `awk` as a real language.

**Commands:** `grep -E`, `sed`, `awk`, `cut`, `sort`, `uniq`, `tr`, `xargs`,
`tee`, `jq`, `shellcheck`.

**Exercise**

```bash
sudo dnf install ShellCheck

# Quoting: run this and work out why it does what it does
touch "my file.txt"
for f in $(ls); do echo "[$f]"; done      # broken
for f in *;        do echo "[$f]"; done   # correct

# The classic pipeline — who is hitting my server?
journalctl -u sshd --since "7 days ago" \
  | grep "Failed password" \
  | awk '{print $(NF-3)}' \
  | sort | uniq -c | sort -rn | head

# awk is a programming language, not a column-printer
ps aux | awk 'NR>1 {mem[$1] += $6} END {for (u in mem) printf "%-12s %8.1f MB\n", u, mem[u]/1024}' | sort -k2 -rn
```

**Build:** a genuinely good script with `set -euo pipefail`, argument parsing, a
`--help`, a `--dry-run`, and a `trap` for cleanup. Run `shellcheck` on it until
it's silent. Then run `shellcheck` on every script you've ever written.

**Chaos Friday (safe):** take a bad script (write one on purpose: unquoted
variables, no error handling) and make it robust. Note in your log every class of
bug you found.

**Prove it:** explain what `set -euo pipefail` does, each flag separately, and one
case where `-e` does *not* save you.

**Kubernetes link:** every container entrypoint, init container, `postStart` hook,
and CI job is a shell script. Most flaky pipelines are quoting bugs.

---

## Week 8 — Users, sudo, and SSH

**Concepts:** `/etc/passwd`, `/etc/shadow`, `/etc/group`; PAM; `sudoers`; SSH key
auth; host keys and TOFU; agent forwarding (and why it's risky); `authorized_keys`
options; hardening `sshd`.

**Commands:** `useradd`, `usermod`, `passwd`, `chage`, `visudo`, `ssh-keygen`,
`ssh-copy-id`, `sshd -T`, `journalctl -u sshd`.

**Exercise**

```bash
getent passwd "$USER"        # each colon-separated field — name them all
sudo getent shadow "$USER"   # the hash format: $id$salt$hash. Which algorithm?
groups; id

sudo cat /etc/sudoers.d/* 2>/dev/null
sudo visudo -c                # syntax check without breaking sudo

ssh-keygen -t ed25519 -C "test key" -f /tmp/testkey
ssh-keygen -lf /tmp/testkey.pub          # fingerprint
sudo sshd -T | sort | less               # the EFFECTIVE config, not just the file
```

**Build:** harden your VPS's sshd (the one in your `edge-proxy` deploy pipeline) and
document each change:

```
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
AllowUsers youruser
MaxAuthTries 3
```

**Keep a second SSH session open while you do this.** Test the new config in the
second session before closing the first. This habit will save you eventually.

**Chaos Friday (VM!):** lock yourself out of a VM via sshd config, then recover via
the console. Learn the difference between "I can fix this" and "I need physical
access."

**Prove it:** explain why key auth is better than passwords in terms of what
crosses the network, and what a host key fingerprint protects you from.

**Kubernetes link:** ServiceAccounts, RBAC Roles and RoleBindings are the same
authorisation model. `kubectl auth can-i` is `sudo -l`.

---

## Week 9 — SELinux and system hardening

Most people's relationship with SELinux is `setenforce 0`. Don't be most people —
this is a genuine differentiator in RHEL shops, and you're going to meet it on
every managed Kubernetes node.

**Concepts:** DAC vs MAC; contexts (`user:role:type:level`); type enforcement;
booleans; file context rules; the audit log; permissive vs enforcing.

**Commands:** `getenforce`, `ls -Z`, `ps -Z`, `semanage`, `restorecon`, `setsebool`,
`ausearch`, `sealert`, `audit2allow`.

**Exercise**

```bash
sudo dnf install policycoreutils-python-utils setroubleshoot-server

getenforce
ls -Z /var/www/html 2>/dev/null; ls -Z /etc/passwd
ps -eZ | head
getsebool -a | head -30

# Cause a denial on purpose, then diagnose it properly
sudo dnf install httpd
echo "hi" | sudo tee /var/www/html/index.html
sudo restorecon -Rv /var/www/html
sudo systemctl start httpd && curl -s localhost

# Now break the label and watch it fail
sudo chcon -t user_home_t /var/www/html/index.html
curl -s localhost                       # 403
sudo ausearch -m AVC -ts recent
sudo sealert -a /var/log/audit/audit.log | head -40
sudo restorecon -v /var/www/html/index.html
curl -s localhost                       # works again
```

**Build:** get a rootless podman container serving a bind-mounted host directory.
You'll hit a denial. Fix it properly with `:Z` on the mount or with `semanage
fcontext`, not by disabling SELinux. Write up what `:z` vs `:Z` does.

**Chaos Friday (safe):** relabel something wrongly, diagnose it from
`ausearch`/`sealert` alone, and fix it with `restorecon`.

**Prove it:** explain the difference between file *permissions* and file *context*,
and describe a case where a process is root and still denied.

**Kubernetes link:** `seLinuxOptions` in a pod securityContext; `container_t`; why
volume mounts fail on RHEL/OpenShift nodes; the CKS exam.

---

## Week 10 — Namespaces and cgroups: build a container by hand

The week everything clicks.

**Concepts:** the six-plus namespace types (mnt, pid, net, uts, ipc, user, cgroup);
cgroup v2 controllers; `clone()`/`unshare()`; capabilities; seccomp; OverlayFS;
what an OCI image actually is.

**Commands:** `unshare`, `nsenter`, `lsns`, `systemd-cgls`, `systemd-cgtop`,
`capsh`, `skopeo`, `podman`.

**Exercise — make a container with no container runtime**

```bash
# 1. A new UTS + PID + mount namespace
sudo unshare --uts --pid --mount --fork --mount-proc bash
  hostname mycontainer
  ps aux            # you are PID 1 and you can see almost nothing. why?
  lsns
  exit

# 2. Give it a root filesystem
mkdir -p /tmp/rootfs
podman export "$(podman create alpine)" | tar -x -C /tmp/rootfs
sudo unshare --uts --pid --mount --fork --mount-proc \
     chroot /tmp/rootfs /bin/sh
  # You are now "in a container". No Docker involved.
  exit

# 3. Constrain it with cgroups v2
sudo mkdir -p /sys/fs/cgroup/demo
echo "+memory +cpu" | sudo tee /sys/fs/cgroup/cgroup.subtree_control
echo "50M" | sudo tee /sys/fs/cgroup/demo/memory.max
echo $$  | sudo tee /sys/fs/cgroup/demo/cgroup.procs   # put THIS shell in it
cat /sys/fs/cgroup/demo/memory.current
# now allocate memory in this shell and watch it get killed

# 4. Compare with the real thing
podman run --rm -m 50m --name demo alpine sh -c 'cat /sys/fs/cgroup/memory.max'
lsns                                    # namespaces on the host
```

**Build:** write a ~40-line bash script that runs a command in its own UTS/PID/mount
namespace, in a chroot, with a memory limit. That script is, conceptually, a
container runtime. You will never again think of containers as magic.

**Chaos Friday (safe):** set a cgroup CPU limit on a real workload and measure the
throttling in `/sys/fs/cgroup/.../cpu.stat`. Correlate `nr_throttled` with observed
latency.

**Prove it:** explain what a container *is*, in terms of Linux primitives, in under
60 seconds and without using the word "lightweight".

**Kubernetes link:** all of it. Pods share a network and IPC namespace (that's why
containers in a pod reach each other on `localhost`). The pause container holds
those namespaces open. `resources.limits` writes `cpu.max` and `memory.max`. CPU
throttling from over-tight limits is one of the most common production problems in
Kubernetes, and after this week you can prove it with numbers.

---

## Week 11 — Networking, part 2: build container networking by hand

**Concepts:** network namespaces; veth pairs; bridges; NAT and masquerading;
`iptables`/`nftables` chains and tables; conntrack; port forwarding.

**Commands:** `ip netns`, `ip link add ... type veth`, `brctl`/`ip link ... type
bridge`, `nft`, `iptables-save`, `conntrack`.

**Exercise — build a container network from scratch**

```bash
# Two namespaces that can talk to each other over a veth pair
sudo ip netns add ns1
sudo ip netns add ns2
sudo ip link add veth1 type veth peer name veth2
sudo ip link set veth1 netns ns1
sudo ip link set veth2 netns ns2
sudo ip netns exec ns1 ip addr add 10.0.0.1/24 dev veth1
sudo ip netns exec ns2 ip addr add 10.0.0.2/24 dev veth2
sudo ip netns exec ns1 ip link set veth1 up
sudo ip netns exec ns2 ip link set veth2 up
sudo ip netns exec ns1 ping -c3 10.0.0.2      # they can talk

# Now give ns1 internet access via NAT — exactly what Docker does
sudo ip netns exec ns1 ip route add default via 10.0.0.2
sudo sysctl -w net.ipv4.ip_forward=1
sudo nft add table ip nat
sudo nft 'add chain ip nat postrouting { type nat hook postrouting priority 100 ; }'
sudo nft add rule ip nat postrouting ip saddr 10.0.0.0/24 masquerade

# Clean up
sudo ip netns del ns1; sudo ip netns del ns2

# Then look at what podman/docker actually created
ip link                    # find the bridge
sudo nft list ruleset | head -60
```

**Build:** diagram your own laptop's container networking: from `curl
localhost:8080` to the process in the container, naming every hop (loopback →
DNAT rule → bridge → veth → container's eth0). Put the diagram in your notes.

**Chaos Friday (VM):** add a firewall rule that blocks something subtle (say, DNS
over UDP but not TCP) and debug it from symptoms only.

**Prove it:** explain what happens, packet by packet, when a pod on node A talks to
a ClusterIP Service backed by a pod on node B.

**Kubernetes link:** CNI plugins do exactly the veth/bridge/route dance above.
kube-proxy writes the DNAT rules. Cilium replaces them with eBPF. NetworkPolicy is
filtering at these same hooks. After this week, `kubectl describe networkpolicy`
means something.

---

## Week 12 — Performance and a troubleshooting method

**Concepts:** the USE method (Utilisation, Saturation, Errors); load average vs CPU
usage; the page cache; I/O latency; run queues; flame graphs; how to form and test
a hypothesis under pressure.

**Commands:** `vmstat`, `iostat`, `mpstat`, `pidstat`, `sar`, `iotop`, `perf`,
`btop`, `ss -i`, `journalctl`.

**Exercise**

```bash
sudo dnf install sysstat perf
sudo systemctl enable --now sysstat        # historical data collection

vmstat 1 10          # columns r, b, si, so, wa — know what each means
iostat -xz 1 5       # %util, await, aqu-sz
mpstat -P ALL 1 5
pidstat -d 1 5       # per-process I/O
sar -u 1 5

# Load average is NOT CPU usage on Linux — it includes uninterruptible sleep (D state).
# A machine with load 20 and idle CPUs is almost certainly blocked on I/O.
uptime; nproc; vmstat 1 3

# Profile something
perf top
```

**Build:** write a **runbook** in your notes:
*"The server is slow" — a 10-minute triage.* Each step should be a command, what
you're looking for, and what it rules in or out. This is a document you'll reuse
for years, and it's an excellent thing to be able to talk about in an interview.

**Chaos Friday (VM):** generate three different failure modes — CPU-bound,
I/O-bound, and memory-pressure — and confirm you can distinguish them from metrics
alone, before knowing which you caused.

**Prove it:** given a slow machine, produce a structured diagnosis in ten minutes
that identifies which resource is saturated and what to do about it.

**Kubernetes link:** `kubectl top`, resource requests vs limits, CPU throttling,
Prometheus node-exporter metrics — all of them are the numbers above, collected.

---

## After week 12

You now know more about Linux than most working developers. Some directions:

| Direction | Start with |
| --- | --- |
| **Prove it** | CKA, then LFCS or RHCSA (RHCSA is a genuinely hard, genuinely respected practical exam) |
| **Go deeper on the kernel** | eBPF — `bpftrace`, `bcc-tools`, then Cilium |
| **Go wider on platform** | Terraform, Ansible, a real CI/CD pipeline for the VPS |
| **Build the homelab** | When you build the desktop: Proxmox, three VMs, a real multi-node k8s cluster with kubeadm |
| **Contribute** | Fedora packaging, or file a good bug report with a bisected kernel regression |

### Books that are worth the money

- **"How Linux Works" — Brian Ward.** The best single book for exactly where you are.
- **"The Linux Programming Interface" — Michael Kerrisk.** Reference. Enormous.
  Definitive. Read the chapters you need.
- **"Systems Performance" — Brendan Gregg.** The USE method's source, and the best
  performance book in existence.
- **"Kubernetes Up & Running"**, then **"Programming Kubernetes"** when you want to
  write controllers.
- **"The Phoenix Project"** / **"The DevOps Handbook"** for why any of this matters
  organisationally.

### Free and excellent

- [Linux Journey](https://linuxjourney.com/) — structured beginner-to-intermediate
- [OverTheWire: Bandit](https://overthewire.org/wargames/bandit/) — 30 shell puzzles,
  genuinely the best way to build fluency. Do these in week 1–2.
- [Julia Evans' zines and blog](https://jvns.ca/) — the best explanations of
  strace, networking, and debugging anywhere
- [Brendan Gregg's site](https://www.brendangregg.com/linuxperf.html)
- [SadServers](https://sadservers.com/) — broken servers to fix, timed. Excellent
  practice for weeks 5–12.
- `man` pages. Really. `man 7 signal`, `man 5 systemd.exec`, `man 8 ip`, `man 7
  namespaces` are all superb.

### The habit that matters most

Every time something breaks — and things will break — **resist the urge to reboot
or reinstall.** Diagnose it. Write down what you found. That single discipline,
sustained for a year, is the whole difference.

---

## Checkpoint

- [ ] `~/notes/linux-log.md` exists, is in git, and has 12+ weeks of entries
- [ ] You've written a systemd service and timer from memory
- [ ] You've built a container by hand with `unshare` + `chroot` + cgroups
- [ ] You've built container networking by hand with veth pairs and NAT
- [ ] You've recovered a VM from a broken `/etc/fstab` and a broken sshd config
- [ ] You've fixed an SELinux denial properly, without `setenforce 0`
- [ ] You have a "server is slow" runbook you wrote yourself
