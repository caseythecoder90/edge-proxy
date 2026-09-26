# edge-proxy

The single reverse proxy for the VPS. This stack alone owns ports **80/443** and
**all TLS**, and routes each hostname to the right app over a shared external
Docker network called **`edge`**. Each app keeps its own private network for its
data tier, so **no app can reach another app's containers** — the proxy is the
only thing that spans them.

```
                          Internet  :80 / :443
                               │
                     ┌─────────▼──────────┐
                     │     edge-proxy      │  (this repo → /opt/edge-proxy)
                     │  nginx  +  certbot   │  owns 80/443, TLS, all routing
                     └───┬─────────────┬───┘
              edge net   │             │   edge net
        ┌────────────────▼───┐   ┌─────▼─────────────────┐
        │  personal-website   │   │      grindtrack       │
        │  app, frontend      │   │  grindtrack-app       │
        │  (+ private net for │   │  (+ private net for   │
        │   postgres, redis)  │   │   grindtrack-db)      │
        └─────────────────────┘   └───────────────────────┘

   api.caseyrquinn.com  → personal-website-app:8080
   caseyrquinn.com/www  → personal-website-frontend:80
   track.caseyrquinn.com→ grindtrack-app:8080
   anything else        → 444 (dropped)
```

> **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** explains how this works and why
> it's built this way, with diagrams in [`docs/diagrams/`](docs/diagrams/).

### Why this exists
Previously the personal-website stack's nginx owned 80/443 and *also* routed
grindtrack, and both stacks shared one network. Two problems came from that:
1. **Cross-routing** — both stacks have a service aliased `app`, so
   `proxy_pass http://app:8080` round-robined between the two backends. Pinning
   the **unique container name** (done in every block here) fixes it; the
   `zz-default-drop.conf` 444 server is a second layer.
2. **Config drift** — routing config lived half in the personal-website repo,
   half hand-edited on the VPS (`track.conf` was in neither repo). Now every
   server block lives here, in one version-controlled place.

## Repo layout
```
docker-compose.yml            nginx + certbot; joins the external `edge` network
nginx/conf.d/
  api.conf                    api.caseyrquinn.com  → personal-website-app
  site.conf                   caseyrquinn.com/www  → personal-website-frontend
  track.conf                  track.caseyrquinn.com→ grindtrack-app
  zz-default-drop.conf        unmatched host/SNI   → 444 (loaded last)
.github/workflows/deploy.yml  push to main → SSH → pull + up -d + nginx -t + reload
certbot/                      (gitignored) certs + ACME webroot, live on the VPS only
docs/ARCHITECTURE.md          how it works and why; known gaps
docs/diagrams/*.puml          topology, request flow, TLS/ACME, deploy, SSH auth
```
Every upstream uses `resolver 127.0.0.11` + a `set $upstream` variable, so an app
redeploy (new container IP) is picked up **without an nginx reload**.

---

## One-time cutover runbook

> Do this in a low-traffic window. There's a **short 80/443 swap** (seconds) when
> the personal-website nginx stops and this proxy starts. Rollback is easy (below).

**0. Push this repo to GitHub** and add the three deploy secrets to it
(`VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY` — same values the other two repos use).

**1. Create the shared network** (idempotent):
```bash
docker network create edge 2>/dev/null || true
docker network ls | grep edge      # confirm it exists
```

**2. Clone this repo on the VPS and move the certs into it.** The existing certs
carry over — nothing is re-issued.

> **The repo must end up owned by the deploy user**, because CI runs
> `git pull --ff-only` as that user. Create the directory with `sudo`, hand it
> over, then clone *without* `sudo`.
>
> `sudo git clone git@github.com:...` fails with `Permission denied (publickey)`:
> it runs as root, so SSH looks in `/root/.ssh` rather than the deploy user's
> keys. HTTPS avoids SSH entirely and works anonymously while this repo is
> public — switch to the SSH URL if it ever goes private.

```bash
sudo mkdir -p /opt/edge-proxy
sudo chown "$USER:$USER" /opt/edge-proxy
git clone https://github.com/caseythecoder90/edge-proxy.git /opt/edge-proxy   # no sudo
cd /opt/edge-proxy
```

Now copy the certs over. **One command, with `sudo`, into a `certbot` path that
does not exist yet** — the two traps below are easy to hit and produce a
convincingly wrong result rather than an error:

```bash
sudo cp -a /opt/personal-website/certbot ./certbot   # brings conf/ AND www/
sudo ls certbot/conf/live                            # expect api. , caseyrquinn.com , track.
```

> **Why `sudo` on both lines.** certbot keeps `conf/live`, `conf/archive` and
> `conf/accounts` as `drwx------ root root` because they hold private keys. Without
> `sudo`, `cp` silently creates *empty* copies of those directories and `ls` shows
> nothing — which looks exactly like a wrong path. Leave the copies root-owned;
> the containers run as root and read them fine, and a `chown -R` here would strip
> that protection off your private keys.
>
> **Why one command into a fresh path.** `cp -a A B` copies A *to* B when B does
> not exist, but *into* B when it does. Running the copy twice therefore yields
> `certbot/conf/conf`, leaving the original empty shell in place. If that has
> already happened: `sudo rm -rf certbot` and re-run the copy.

**3. Put the apps on `edge`** (each app keeps its private net for its data tier).
- **grindtrack** already declares `web: { external: true, name: edge }` and puts
  `grindtrack-app` on it — no file change needed, but its *running* container is
  still on the old network (its `edge` deploy failed earlier), so recreate it now
  that `edge` exists:
  ```bash
  cd /opt/grindtrack && git pull --ff-only
  docker compose -f gt2/docker-compose.prod.yml up -d
  docker inspect grindtrack-app --format '{{json .NetworkSettings.Networks}}'  # expect edge + internal
  ```
- **personal-website** needs its nginx + certbot **removed** and its `app` +
  `frontend` put on `edge`. Apply the changed `docker-compose.prod.yml` (see
  "personal-website changes" below) to `/opt/personal-website`, then:
```bash
cd /opt/personal-website
docker compose -f docker-compose.prod.yml up -d --remove-orphans
# recreates app/frontend on edge and REMOVES personal-website-nginx + -certbot,
# freeing 80/443. (track.conf/default.conf here are now dead — they moved to this repo.)
```

**4. Start the edge proxy** (takes 80/443):
```bash
cd /opt/edge-proxy
docker compose up -d
docker compose exec -T nginx nginx -t      # must pass
docker logs edge-nginx --tail 20
```

**5. Verify all four routes:**
```bash
curl -I https://caseyrquinn.com          # → 200 (frontend)
curl -I https://api.caseyrquinn.com/...  # → your API
curl -I https://track.caseyrquinn.com    # → 200 (grindtrack)
curl -sk -o /dev/null -w '%{http_code}\n' https://<VPS_IP>   # → 000/444 (dropped)
```
Also re-run the grindtrack GitHub deploy (or push) — it should now go green, since
`edge` exists and the proxy is routing `track.`.

### Rollback
If anything's wrong, bring the old nginx back in seconds:
```bash
cd /opt/edge-proxy && docker compose down          # release 80/443
# restore the previous /opt/personal-website/docker-compose.prod.yml (with nginx+certbot)
cd /opt/personal-website && docker compose -f docker-compose.prod.yml up -d
```
Keep a copy of the current personal-website compose before step 3 for exactly this.

---

## Ongoing maintenance
- **Change routing / add a domain:** edit `nginx/conf.d/`, commit, push. CI pulls,
  runs `nginx -t`, and hot-reloads. A bad config fails `nginx -t` (deploy red) and
  is never served. For a brand-new domain, issue its cert first:
  `docker compose run --rm certbot certonly --webroot -w /var/www/certbot -d new.example.com`.
- **App redeploys** (grindtrack / personal-website) need no proxy action — the
  `resolver` re-resolves the new container IP within 30s.
- **Certs** renew automatically via the certbot loop in this stack.

## personal-website changes (apply in that repo)
In `personal-website-backend/docker-compose.prod.yml`:
- **remove** the `nginx` and `certbot` services (they live here now),
- add `edge` (external) to the **`app`** and **`frontend`** services' networks,
- keep `app-network` for `app`/`postgres`/`redis`/`frontend` internal traffic,
- drop the `nginx`/`certbot` bits from the `networks:` section; declare `edge`
  as `external: true, name: edge`.

The `nginx/conf.d/*` and `certbot/` in that repo become dead once cut over — the
server blocks now live in this repo's `nginx/conf.d/`.
---

## Also in this repo: [`linux-migration/`](linux-migration/)

Unrelated to the proxy. A complete, step-by-step guide for moving the ThinkPad
from Windows to Fedora Linux, with a 12-week Linux + Kubernetes learning path.
Start at [`linux-migration/README.md`](linux-migration/README.md), or jump to the
[one-page checklist](linux-migration/checklist.md).
