# 10 — Kubernetes lab on the ThinkPad

Your laptop is now a much better Kubernetes learning machine than it was under
Windows: containers are native processes, not a hidden VM, so you can watch
Kubernetes *use Linux* — cgroups, namespaces, iptables, veth pairs — directly.

That's the real reason to run k8s on Linux. Use it.

---

## 1. The toolchain

### kubectl

Check <https://kubernetes.io/releases/> for the current stable minor version and
substitute it below.

```bash
K8S_MINOR=v1.34   # <-- set this to current stable

sudo tee /etc/yum.repos.d/kubernetes.repo >/dev/null <<REPO
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/rpm/repodata/repomd.xml.key
REPO

sudo dnf install kubectl
kubectl version --client
```

Then the two things that make `kubectl` bearable:

```bash
cat >> ~/.bashrc <<'BASHRC'
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k
export KUBE_EDITOR=vim
BASHRC
source ~/.bashrc
```

### kind — throwaway clusters in Docker

```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
kind version
```

### The quality-of-life tools

```bash
# k9s — a terminal UI for clusters. You will live in this.
curl -sL "$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest \
  | jq -r '.assets[] | select(.name=="k9s_Linux_amd64.tar.gz") | .browser_download_url')" \
  | sudo tar -xz -C /usr/local/bin k9s

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# krew — the kubectl plugin manager (see https://krew.sigs.k8s.io/docs/user-guide/setup/install/)
(
  set -x; cd "$(mktemp -d)" &&
  KREW="krew-linux_amd64" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" && ./"${KREW}" install krew
)
echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Plugins worth having on day one
kubectl krew install ctx ns stern neat tree who-can view-secret
```

Quick tour:

| Tool | What it's for |
| --- | --- |
| `k9s` | Live TUI: navigate, log, exec, delete, port-forward. `?` for help, `:` for a resource. |
| `kubectl ctx` / `ns` | Switch cluster and namespace without editing kubeconfig |
| `kubectl stern` | Tail logs from many pods at once, with colour |
| `kubectl neat` | Strip the managed-fields noise out of `get -o yaml` |
| `kubectl tree` | Show ownership chains (Deployment → ReplicaSet → Pods) |
| `kubectl who-can` | RBAC: "who can delete pods in prod?" |

### Guard rails — set these up before you need them

Put the current context in your prompt (starship's `kubernetes` module), and use
`direnv` so `KUBECONFIG` is explicit per project:

```bash
cd ~/projects/somerepo
echo 'export KUBECONFIG=$PWD/.kube/config' > .envrc
direnv allow
```

> Most "I destroyed the wrong environment" stories start with an unnoticed
> `kubectl config current-context`. Solve it structurally now, while your only
> cluster is a disposable one.

## 2. Your first cluster

A single-node cluster teaches you less than a multi-node one, and kind gives you
multi-node for free. Make it ingress-ready from the start:

```bash
mkdir -p ~/k8s-lab && cd ~/k8s-lab

cat > kind-cluster.yaml <<'YAML'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: lab
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 8080
        protocol: TCP
      - containerPort: 443
        hostPort: 8443
        protocol: TCP
  - role: worker
  - role: worker
YAML

kind create cluster --config kind-cluster.yaml
kubectl cluster-info --context kind-lab
kubectl get nodes -o wide
```

### Now look at what actually happened

This is the part you couldn't do on Windows. Your "nodes" are containers on your
laptop, and you can walk straight into one:

```bash
docker ps                                    # three "nodes"
docker exec -it lab-control-plane bash

# Inside the node:
crictl ps                          # containers via the CRI — what kubelet sees
systemctl status kubelet           # the kubelet is an ordinary systemd service
ls /etc/kubernetes/manifests/      # static pods: apiserver, etcd, scheduler, controller-manager
head -40 /etc/kubernetes/manifests/kube-apiserver.yaml
ps aux | grep kube-apiserver       # it's just a process
exit
```

> **Sit with that for a minute.** The control plane is four processes, defined by
> YAML files in a directory the kubelet watches. etcd is a database. The scheduler
> is a program that writes a node name into a pod object. There is no magic in
> Kubernetes, only layers — and from here you can open every one of them.

## 3. A progression that actually builds understanding

Do these in order. **Write the YAML by hand** for the first four. No Helm yet, no
copy-paste from a chart. You're learning the object model.

### Project 1 — Pod → Deployment → Service, by hand

```bash
kubectl create namespace lab
kubectl config set-context --current --namespace=lab
```

Write `nginx-deployment.yaml` yourself: 3 replicas, resource requests *and* limits,
a liveness probe, a readiness probe, and a `securityContext` with
`runAsNonRoot: true`. Then a ClusterIP Service in front of it.

Then answer these by experiment, not by reading:

- Delete a pod. How long until it's back, and who recreated it? (`kubectl get events -w`)
- `kubectl scale --replicas=5` — which controller acted?
- `kubectl rollout restart deployment/nginx`, then `kubectl get rs -w`. Why are there
  two ReplicaSets?
- Set the memory limit to `10Mi`. What does `kubectl describe pod` say? (Look for
  `OOMKilled`, and note *which* exit code.)
- Break the **liveness** probe. Then fix it and break the **readiness** probe instead.
  Which one restarts the container? Which one changes
  `kubectl get endpointslices`?

> That last pair is the most commonly misunderstood thing in Kubernetes:
> **liveness restarts a container; readiness removes it from load balancing.**
> Learn it by breaking each one, and you'll never mix them up again.

### Project 2 — Config, secrets, and the 12-factor shape

A ConfigMap for config and a Secret for credentials, each mounted two ways (env
vars and files). Then:

```bash
kubectl get secret mysecret -o jsonpath='{.data.password}' | base64 -d
```

...and notice that Secrets are **base64, not encrypted**. Read about
[encryption at rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/),
then set up `sops` + `age` so you can commit encrypted secrets to git safely.

### Project 3 — Ingress and TLS

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s
```

Route two hostnames to two services via Ingress, reachable on
`http://localhost:8080`. Then add cert-manager with a self-signed ClusterIssuer and
get TLS working end to end.

> **You have already built this.** Your `edge-proxy` repo is exactly this pattern:
> one nginx owning 80/443, routing hostnames to backends, with certbot for TLS.
> `ingress-nginx` *is* nginx, generating that same config from Ingress objects, and
> cert-manager *is* certbot as a controller. Open `nginx/conf.d/*.conf` next to
> `kubectl get ingress -o yaml` and map them onto each other line by line. That
> comparison will teach you more than any tutorial, because you already understand
> one side of it.

### Project 4 — State

A StatefulSet running Postgres with a PersistentVolumeClaim. Then:

- Delete the pod. Does the data survive? Why?
- Delete the StatefulSet. Does the PVC survive? Why?
- Read about `volumeClaimTemplates`, reclaim policies, and StorageClasses.

### Project 5 — Package it

*Now* Helm. Write a chart for **grindtrack**: `values.yaml` for image tag, replicas,
resources and ingress host; templates for Deployment, Service, Ingress, ConfigMap.
Run `helm template` and read the generated output — that's the step that makes Helm
click. Then do the same thing with `kustomize` and work out why both exist.

### Project 6 — Observability

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
```

Then expose `/metrics` from your own app, write a ServiceMonitor, build a dashboard,
and set an alert that fires when you scale to zero. Learn PromQL — it's a small
language with an enormous payoff.

### Project 7 — GitOps

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Put your manifests in a git repo, point an ArgoCD Application at it, and stop
running `kubectl apply` by hand. Then delete a Deployment manually and watch ArgoCD
put it back. That single demo *is* the idea of GitOps.

## 4. The capstone: move your VPS to k3s

You have a real system with real traffic — `edge-proxy` fronting `personal-website`
and `grindtrack`. Migrating it is the best Kubernetes project available to you,
because it has real consequences and a real rollback.

**k3s** is the right target: one binary, conformant Kubernetes, light enough for a
single VPS.

Sequence, all rehearsed on kind locally first:

1. **Rehearse locally.** Reproduce all three stacks on your kind cluster — same
   images, same env, Ingress instead of nginx vhosts.
2. **Map the pieces.**

   | docker-compose today | Kubernetes equivalent |
   | --- | --- |
   | a `services:` entry | Deployment + Service |
   | `ports:` on the proxy | Ingress + ingress controller |
   | shared external `edge` network | Services (cluster-wide DNS) |
   | per-app private network | Namespace + default-deny NetworkPolicy |
   | certbot renewal timer | cert-manager + a Let's Encrypt ClusterIssuer |
   | `.env` files | ConfigMap + Secret |
   | named volumes | PersistentVolumeClaim (k3s local-path) |
   | `restart: unless-stopped` | the Deployment controller |
   | the `zz-default-drop.conf` 444 server | default backend / no matching Ingress |

   Note something satisfying: the cross-routing bug your README describes — two
   stacks both aliasing `app`, so `proxy_pass http://app:8080` round-robined between
   them — **cannot happen** in Kubernetes, because a Service name is namespace-scoped
   and resolves as `app.grindtrack.svc.cluster.local`. Namespaces are the general
   form of the fix you applied by hand with unique container names. Write that up in
   your notes; understanding *why* a platform prevents a bug you've personally hit is
   worth a dozen tutorials.
3. **Build a staging VPS** (a second cheap droplet is fine):
   `curl -sfL https://get.k3s.io | sh -`
4. **Deploy there** and get real Let's Encrypt TLS working on a staging subdomain.
5. **Cut over** with DNS, keeping the docker-compose stack running until the new one
   is proven. Keep the old stack for a week.
6. **Write the post-mortem** in your notes: what was harder than expected, what
   you'd do differently.

Give yourself one explicit stretch goal: reproduce the isolation property your
README claims ("no app can reach another app's containers") using a default-deny
NetworkPolicy per namespace. You'll discover that **k3s's default Flannel backend
does not enforce NetworkPolicy** and you'll need Calico or Cilium instead. That
discovery — "the API accepted my policy, but is anything actually enforcing it?" —
is one of the most valuable lessons in the whole ecosystem.

> **Don't rush this.** It's a 6–10 week project alongside everything else. The value
> is in doing it properly with a rollback plan, not in finishing fast.

## 5. Kubernetes-is-Linux exercises

Short exercises that connect the two halves of what you're learning. Do one a week
alongside page 11.

```bash
# 1. cgroups: find a pod's memory limit in the node's filesystem
docker exec -it lab-worker bash
find /sys/fs/cgroup -name memory.max | head
# ...then compare with `kubectl get pod <p> -o jsonpath='{.spec.containers[0].resources}'`

# 2. namespaces: a pod is a shared set of Linux namespaces
docker exec -it lab-worker bash
ls -l /proc/1/ns/              # net, pid, mnt, uts, ipc, cgroup
crictl ps -q | head -1 | xargs crictl inspect | grep -i pid
# nsenter -t <PID> -n ip addr  # enter just that container's network namespace

# 3. the pause container: why every pod has one
crictl ps -a | grep -i pause

# 4. service networking: where does a ClusterIP actually live?
docker exec -it lab-worker bash
iptables-save | grep KUBE-SERVICES | head
# A ClusterIP is not an interface anywhere. It's a DNAT rule. That's the whole trick.

# 5. cluster DNS
kubectl run -it --rm dnstest --image=busybox:1.36 --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local

# 6. debug a distroless container that has no shell
kubectl debug -it <pod> --image=busybox:1.36 --target=<container>
```

## 6. Certification, if you want it

**CKA** is the one worth doing for your goals: hands-on, entirely in a terminal,
and it forces exactly the skills above.

- Practice on [killer.sh](https://killer.sh) — two sessions come with exam
  registration and they're harder than the real thing.
- It's open-book against kubernetes.io. Practise *navigating those docs fast*; that
  is itself an exam skill.
- Know the imperative commands cold — there is no time to write YAML from scratch:
  ```bash
  kubectl create deployment web --image=nginx --replicas=3 --dry-run=client -o yaml > d.yaml
  kubectl expose deployment web --port=80 --target-port=8080 --dry-run=client -o yaml
  kubectl run tmp --image=busybox --restart=Never -it --rm -- sh
  kubectl create job --from=cronjob/backup manual-backup
  ```
- Be fluent enough in vim to edit YAML: `:set number`, `dd`, `yy`, `>>`, and
  `:set tabstop=2 shiftwidth=2 expandtab`.
- Learn `etcdctl snapshot save/restore` and `kubeadm upgrade`. They're on the exam
  and they're what people skip.

**CKAD** if you're more app-focused. **CKS** after CKA if security interests you —
it pairs well with the SELinux work you'll be doing anyway.

---

## Checkpoint

- [ ] `kind create cluster` works; `kubectl get nodes` shows 3 nodes
- [ ] You've `exec`'d into a kind node and found the kubelet and the static pod manifests
- [ ] You can explain liveness vs readiness *from having broken both*
- [ ] `k9s` opens and you can navigate it
- [ ] An Ingress with TLS serves a page on `https://localhost:8443`
- [ ] You've found a pod's memory limit under `/sys/fs/cgroup` on the node
- [ ] You've mapped your `edge-proxy` nginx config onto an Ingress resource

Next: [11-linux-learning-path.md](11-linux-learning-path.md)
