# Architecture

How the edge proxy works and why it is built this way. The [README](../README.md)
covers *operating* it — cutover, rollback, day-to-day maintenance. This document
covers the design decisions behind it.

Diagram sources live in [`diagrams/`](diagrams/) and are the reference for each
section below. See [Rendering the diagrams](#rendering-the-diagrams) at the end.

| Diagram | What it answers |
| --- | --- |
| [`topology.puml`](diagrams/topology.puml) | What runs on the host, and which container can reach which |
| [`request-flow.puml`](diagrams/request-flow.puml) | What happens to one HTTPS request, end to end |
| [`tls-acme.puml`](diagrams/tls-acme.puml) | How certificates are issued and renewed |
| [`deploy-pipeline.puml`](diagrams/deploy-pipeline.puml) | What `git push origin main` actually does |
| [`ssh-key-auth.puml`](diagrams/ssh-key-auth.puml) | How the CI runner proves its identity to the VPS |

---

## 1. The core idea

One stack owns ports 80 and 443 and all TLS. Every application sits behind it and
is reached only by hostname. The proxy is the **only** container that spans app
boundaries.

```
Internet :80/:443  →  edge-nginx  →  (edge network)  →  each app container
```

Two properties fall out of this, and both are the point of the repo:

**Isolation.** Each app joins the shared `edge` network *and* keeps a private
network for its own data tier. The proxy never joins those private networks, and
the two app stacks share no network with each other. `grindtrack-app` cannot
reach `postgres`; `personal-website-app` cannot reach `grindtrack-db`. Adding an
app widens the blast radius by exactly one hostname.

**One source of truth.** Every server block that exists on the VPS is in
`nginx/conf.d/` in this repo. Before this stack, routing lived half in the
personal-website repo and half in files hand-edited on the server — `track.conf`
existed in no repo at all. Config drift is the failure mode this design exists to
prevent, which is why the deploy is built to break loudly rather than merge
(§5).

See [`topology.puml`](diagrams/topology.puml).

---

## 2. Routing

Every hostname resolves to the same public IP. DNS says nothing about which app
answers — that is decided entirely by the TLS **SNI** (to pick a certificate) and
then the HTTP **Host** header (to pick a server block). nginx checks both.

| Hostname | Goes to | Certificate | File |
| --- | --- | --- | --- |
| `caseyrquinn.com` | `personal-website-frontend:80` | `caseyrquinn.com` | `site.conf` |
| `www.caseyrquinn.com` | 301 → apex | `caseyrquinn.com` (SAN) | `site.conf` |
| `api.caseyrquinn.com` | `personal-website-app:8080` | `api.caseyrquinn.com` | `api.conf` |
| `track.caseyrquinn.com` | `grindtrack-app:8080` | `track.caseyrquinn.com` | `track.conf` |
| *anything else* | **444**, connection closed | apex cert (to finish the handshake) | `zz-default-drop.conf` |

`www` redirects to the apex so that HSTS and search engines see one canonical
hostname. Both names are on a single certificate, issued with
`-d caseyrquinn.com -d www.caseyrquinn.com`.

### Port 80 is only ever a doorway

Every `:80` block contains exactly two locations, and the order matters:

```nginx
location /.well-known/acme-challenge/ { root /var/www/certbot; }
location / { return 301 https://$host$request_uri; }
```

The ACME location must come **first**. If the catch-all redirect were first, the
Let's Encrypt validation request would be bounced to HTTPS and renewal would fail
— the classic way a proxy locks itself out of its own certificates. Nothing but
the ACME challenge is ever served over plain HTTP.

### The 444 default server

Anything arriving with a Host or SNI matching no `server_name` — direct-IP
probes, spoofed Host headers, a stale DNS record pointing at this IP — is closed
with nginx's non-standard **444**: no response at all, not even a status line.

This is a second layer, not the primary defence. What actually prevents
cross-routing is pinning unique container names (§3). The `default_server` flag
on the `listen` directive is what makes this block the fallback; the `zz-`
filename prefix is convention, so it sorts last in `conf.d/` and reads as the
final word. Note that a default TLS server still needs a certificate to complete
a handshake before it can close the connection, which is why it reuses the apex
cert even though the connection is dropped regardless.

---

## 3. Upstreams: why they are variables

Every proxied location looks like this rather than a plain `proxy_pass`:

```nginx
resolver 127.0.0.11 valid=30s;
set $upstream http://grindtrack-app:8080;
proxy_pass $upstream;
```

**Why a variable.** A literal hostname in `proxy_pass` is resolved **once**, when
nginx loads its config, and the resulting IP is pinned for the process lifetime.
Redeploying an app gives its container a new IP, and the proxy would keep sending
traffic to the old one — 502s until someone reloaded nginx. Holding the target in
a variable forces a fresh lookup through `resolver` at request time, so app
redeploys need no proxy action; the new IP is picked up within the 30s TTL.

**Why the container name, not the service alias.** Both app stacks define a
service called `app`, so both register the alias `app` on the `edge` network.
`proxy_pass http://app:8080` round-robins between two unrelated backends — this
was a real bug in the previous setup, not a hypothetical. Every block here pins
the unique **container** name (`grindtrack-app`, `personal-website-app`), which
is unambiguous across stacks.

**The tradeoff.** Variable `proxy_pass` bypasses nginx `upstream` blocks, so
there is no connection-keepalive pool to the backends. At this traffic level the
extra TCP handshake per request is not worth trading away redeploy-without-reload.

Because `$upstream` carries no URI path, the original request URI is forwarded
unchanged — no path rewriting anywhere in this proxy.

See [`request-flow.puml`](diagrams/request-flow.puml).

---

## 4. Headers

All three HTTPS blocks set the same security headers (`always`, so they apply to
error responses too):

```nginx
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

HSTS is set with `includeSubDomains` on the apex, which commits every
`*.caseyrquinn.com` name to HTTPS-only for a year. All of them already are, but
this is worth remembering before pointing a plain-HTTP subdomain at this host —
browsers that have seen the apex will refuse it.

`api.conf` additionally raises `client_max_body_size` to 15M for uploads. The
nginx default is 1M, and exceeding it produces a 413 at the proxy that never
reaches the app.

### X-Forwarded-For is deliberately inconsistent

| File | Directive | Behaviour |
| --- | --- | --- |
| `api.conf`, `site.conf` | `$proxy_add_x_forwarded_for` | **append** to any existing header |
| `track.conf` | `$remote_addr` | **overwrite** — discard what the client sent |

This asymmetry is intentional. grindtrack's login rate limiter keys on the *first*
entry in `X-Forwarded-For`. If a client's own header were preserved, an attacker
could inject a fabricated earlier hop and rotate that value to get a fresh
rate-limit bucket on every request. Overwriting means the first entry is always
the real peer address as nginx observed it.

The append form is the conventional choice and is correct when a backend only
reads XFF for logging. **Any app that makes a security decision based on client
IP must be given the overwrite form** — this is the rule to apply when adding a
route.

---

## 5. Deploy

Push to `main` → GitHub Actions → SSH to the VPS → pull, apply, validate, reload.
See [`deploy-pipeline.puml`](diagrams/deploy-pipeline.puml) and
[`ssh-key-auth.puml`](diagrams/ssh-key-auth.puml).

Three properties are worth calling out:

**The runner uploads nothing.** It opens an SSH session and types commands. The
code reaches the VPS because the *VPS* pulls it from GitHub itself. Nothing in
the pipeline holds the repo contents.

**`git pull --ff-only` refuses to merge.** If someone hand-edits a tracked file
on the server, the pull fails and the deploy goes red, rather than silently
creating a merge commit that forks the server from the repo. Given that config
drift is what this repo exists to prevent, a loud break is the correct outcome.

**`nginx -t` runs before `nginx -s reload`.** A syntax error fails the job and the
reload never executes, so a broken config is never loaded — the proxy keeps
serving the last good one. A reload is not a restart: new workers start on the
new config while old workers finish in-flight requests, so no connection is
dropped and the TLS listeners are never released.

Because `nginx/conf.d` is a bind mount, edited config files are visible inside the
container immediately; `docker compose up -d` recreates containers only if
`docker-compose.yml` itself changed.

---

## 6. TLS and certificate lifecycle

Certificates are issued through the ACME **HTTP-01** challenge. certbot runs a
loop rather than a cron job:

```sh
while :; do certbot renew; sleep 12h & wait $!; done
```

`certbot renew` is a no-op until a certificate is within 30 days of expiry, so
running it twice a day indefinitely is safe and generates no load on Let's
Encrypt.

The two containers cooperate through shared host directories:

- `certbot/www` → the ACME webroot. certbot writes the challenge token; nginx
  serves it over plain `:80` from `/var/www/certbot`.
- `certbot/conf` → `/etc/letsencrypt`. certbot writes certificates; nginx mounts
  it **read-only** and reads from it.

Both are gitignored. Certificates and private keys live only on the VPS and must
never enter this repo.

See [`tls-acme.puml`](diagrams/tls-acme.puml).

### Why nginx reloads itself every six hours

**nginx reads certificates into memory at start-up and at reload.** certbot
writes a renewed certificate to the shared volume and then stops — it has no way
to tell nginx, which goes on serving the copy it loaded at its last reload.

For a while the only thing that reloaded nginx was a push to `main` triggering
the deploy workflow. That masked the problem without solving it. The exposure was
concrete: certificates are valid 90 days and renew at 30 days remaining, leaving
a 30-day window in which a repo with no pushes results in an expired certificate
and a full-page browser interstitial. Long quiet periods are exactly when this
stack is *least* likely to see a push.

So the nginx service reloads itself on a timer, independent of deploys:

```yaml
    command: >
      /bin/sh -c 'while :; do sleep 6h & wait $${!}; nginx -s reload; done
      & exec nginx -g "daemon off;"'
```

Three details in that line matter:

- **`$${!}`** — Compose interpolates `$`, so `$$` escapes it; the container sees
  `${!}`, the PID of the backgrounded `sleep`. Backgrounding the sleep and
  `wait`ing on it keeps the loop interruptible by SIGTERM, which a bare
  `sleep 6h` would not be. The certbot entrypoint uses the same construct.
- **`exec`** — without it, `/bin/sh` stays PID 1 and does not forward signals to
  its children, so `docker stop` would hang for its full timeout and then SIGKILL
  nginx. With `exec`, nginx replaces the shell in the same process and becomes
  PID 1, receiving SIGTERM/SIGQUIT directly for a graceful shutdown. The
  backgrounded reload loop is a separate process and survives the `exec`
  untouched.
- **Six hours** — well inside the 30-day renewal window, and a reload costs
  nothing: no connection is dropped and no TLS listener is released (§5).

certbot also declares `restart: unless-stopped`. Docker only restarts containers
that have a policy, so without it a host reboot would bring nginx back and leave
certbot down — silently, with the first symptom an expired certificate up to 90
days later. The two settings are a pair: one keeps certificates being renewed,
the other keeps renewed certificates being served, and a failure of either is
invisible locally.

### Still recommended: expiry monitoring

Both mechanisms above fail silently if they fail at all — a container serving a
stale certificate is running normally by every local measure, so the proxy cannot
self-report this. An external check on remaining validity (any uptime service
does this, or a cron'd
`openssl s_client -connect host:443 </dev/null | openssl x509 -noout -enddate`)
turns a site-down incident into a warning weeks ahead.

### Adding a new domain

1. Point DNS at the VPS.
2. Issue the certificate — the proxy must already be up to answer the challenge:
   ```bash
   docker compose run --rm certbot certonly --webroot -w /var/www/certbot -d new.example.com
   ```
3. Add a `conf.d/*.conf` with the `:80` doorway and `:443` block, following an
   existing file. Pin the unique container name and choose the XFF form
   deliberately (§4).
4. Put the app's container on the `edge` network.
5. Commit and push — CI validates and reloads.

Step 2 comes before step 3: nginx will not start if a `ssl_certificate` path does
not exist, so committing a server block for an unissued certificate takes the
whole proxy down at the next recreate. `nginx -t` in CI catches this only if the
file is genuinely missing on the VPS at that moment — which it will be. The
deploy goes red and the *running* proxy is unaffected, but the repo is then in a
state that cannot be deployed until the certificate exists.

---

## Rendering the diagrams

The `.puml` sources are the artifact of record; no rendered images are committed,
so nothing can go stale.

- **IntelliJ** — the PlantUML Integration plugin renders on the fly in a tool
  window. Diagrams other than sequence diagrams normally need Graphviz;
  `topology.puml` sets `!pragma layout smetana` to use PlantUML's pure-Java
  layout engine instead, so it renders without a Graphviz install.
- **Command line** — with `plantuml.jar` and a JRE:
  ```bash
  java -jar plantuml.jar -tsvg -charset UTF-8 docs/diagrams/*.puml
  ```
  A non-zero exit means a diagram failed to parse; the error is written into the
  generated image.
- **VS Code** — the PlantUML extension (jebbs.plantuml), `Alt+D` to preview.

`_style.iuml` is shared styling included by every diagram and is not renderable on
its own. Colour is consistent across the set: **blue** the proxy, **green** app
containers, **grey** data tier and private networks, **red** dropped traffic or a
failed deploy step, **purple** off-host systems (GitHub, Let's Encrypt).

One PlantUML detail worth knowing when editing: creole monospace markers (`""`)
cannot be used inside a quoted label such as a `participant` declaration — the
quotes terminate the label early and the diagram fails to parse. Use
`<font:monospaced>text</font>` there instead. Inside notes and arrow messages,
which are not quote-delimited, `""` works normally.