# scripts/

## ⚠️ Sync gotcha: `run-michel.sh` is NOT auto-synced

`run-michel.sh` lives in git **and** at `/home/sprite/workspace/scripts/run-michel.sh`
on the sprite (referenced by `MICHEL_SCRIPT` in `webhook-server.ts`). Editing
the file in the repo does **not** update the sprite copy — the webhook runner
exec's the *sprite-local* file. After every change to `run-michel.sh`, push it
manually:

```bash
sprite exec tee /home/sprite/workspace/scripts/run-michel.sh < ./run-michel.sh > /dev/null
sprite exec chmod +x /home/sprite/workspace/scripts/run-michel.sh
```

No service restart needed — `run-michel.sh` is spawned fresh per `@michel`
mention, so the new version applies on the next webhook event.

The same applies to `webhook-server.ts` and `webhook-runner.sh`, except those
**do** need a service restart (they run as the long-lived `michel-webhook`
service). Commands below.

---

## Michel service setup (sprite) — one-time install

From your laptop:

```bash
bash scripts/install-michel-service.sh
```

What it pushes to the sprite (under `/home/sprite/workspace/scripts/`):
- `webhook-server.ts` — Bun HTTP listener on port 8080. Verifies HMAC, allowlists
  repo + `author_association`, fire-and-forgets `run-michel.sh`.
- `webhook-runner.sh` — wrapper invoked by `sprite-env services`. Sources
  `/home/sprite/.michel.env` then `exec bun run webhook-server.ts`.
- `run-michel.sh` — per-mention worker. Fresh-clones the repo, runs Claude,
  pushes branch, opens/updates PR.

Plus `/home/sprite/.michel.env` (chmod 600) holding `WEBHOOK_SECRET`,
`ALLOWED_REPOS`, `ALLOWED_ASSOCIATIONS`, `MICHEL_SCRIPT`, `WORKDIR`, `PORT`.

Re-running the installer is idempotent: service is recreated, secret in
`.env.michel` is preserved. **Re-running the installer is also the easy way to
sync all three scripts at once** if you've modified more than one.

---

## Updating individual files on the sprite (without re-running the installer)

### `run-michel.sh` (no restart)

```bash
sprite exec tee /home/sprite/workspace/scripts/run-michel.sh < ./run-michel.sh > /dev/null
sprite exec chmod +x /home/sprite/workspace/scripts/run-michel.sh
```

### `webhook-server.ts` (restart required)

```bash
sprite exec tee /home/sprite/workspace/scripts/webhook-server.ts < ./webhook-server.ts > /dev/null
sprite exec -- sprite-env services restart michel-webhook
```

### `webhook-runner.sh` (restart required)

```bash
sprite exec tee /home/sprite/workspace/scripts/webhook-runner.sh < ./webhook-runner.sh > /dev/null
sprite exec chmod +x /home/sprite/workspace/scripts/webhook-runner.sh
sprite exec -- sprite-env services restart michel-webhook
```

---

## Service control

```bash
sprite exec -- sprite-env services list
sprite exec -- sprite-env services logs michel-webhook --tail 100
sprite exec -- sprite-env services restart michel-webhook
sprite exec -- sprite-env services stop michel-webhook
sprite exec -- sprite-env services start michel-webhook
```

Smoke check:

```bash
sprite url   # grab the URL line
curl -fsS <sprite-url>/healthz   # expect: ok
```

---

## Headless rendering fonts (sprite)

**Symptom:** Playwright/Chromium screenshots taken on the sprite render text in a
monospace fallback (ugly, "broken" look) while the same page on your Mac renders
proper sans-serif. PM sees a "drift" between local and sprite screenshots.

**Cause — not a code bug.** The app uses Tailwind v4's default `font-sans` stack
(`system-ui, -apple-system, "Segoe UI", Roboto, …`). macOS resolves these to San
Francisco/Helvetica. The sprite's headless Chromium runs on Ubuntu, which ships
with almost no fonts (≈16) and none matching that stack → the whole chain falls
through to a default mono-ish face.

**Fix — install sans-serif fonts on the sprite (one-time):**

```bash
sprite exec -s test-michel -- sudo apt-get update -qq
sprite exec -s test-michel -- sudo apt-get install -y \
  fonts-liberation fonts-noto-core fonts-dejavu-core
```

- `fonts-liberation` — Arial/Helvetica metric-compatible sans; satisfies the
  `system-ui`/`-apple-system` fallback chain.
- `fonts-noto-core` + `fonts-dejavu-core` — broad Unicode coverage + bold weights.

Verify (count should jump from ~16 to ~295):

```bash
sprite exec -s test-michel -- sh -c 'fc-list | wc -l'
```

Notes:
- Persists on the sprite disk across hibernation. Re-run only if the sprite is
  rebuilt from a base image — consider folding it into provisioning so it's not
  manual.
- Headless Chromium picks the fonts up immediately; no service or browser restart.
- **Separate, unrelated drift:** the narrow/centered layout in sprite screenshots
  is just a smaller default viewport. Set it per-shot with Playwright
  `browser_resize 1920x1080` before capturing.

---

## Docker + Docker Compose (sprite)

The sprite ships **no Docker** out of the box (`docker: command not found`). This
section installs Docker Engine + the `docker compose` plugin and runs the daemon
as a managed service. Verified working: `docker run hello-world`, bridge
networking, and `docker compose up` all succeed.

### Source: Ubuntu 25.10 universe (no external repo)

The sprite is Ubuntu 25.10 (questing); all packages come from the distro's own
`universe`, so there's **no `download.docker.com` repo and no codename pinning**.

```bash
sprite exec -s test-michel -- sudo apt-get update -qq
sprite exec -s test-michel -- sudo apt-get install -y \
  docker.io docker-compose-v2 docker-buildx iptables
```

- `docker.io` (29.x) — Engine + CLI + `dockerd` (pulls in `containerd` + `runc`).
- `docker-compose-v2` — provides the `docker compose` subcommand.
- `docker-buildx` — `docker buildx` builder.
- `iptables` — needed for the default bridge network.

Let the CLI reach the socket without `sudo`:

```bash
sprite exec -s test-michel -- sudo usermod -aG docker sprite
```

(Applies to new shells; `sprite exec` opens fresh shells, so it's effective on the
next exec — no logout needed.)

### No systemd → dockerd runs as a `sprite-env` service

PID 1 on the sprite is **tini, not systemd**, so `systemctl start docker` does
**not** work. The installer creates a `docker.service` symlink that never fires.
Instead we run `dockerd` as a managed `sprite-env` service (same mechanism as
`michel-webhook` — survives hibernation, auto-restarts) via the
**`dockerd-runner.sh`** wrapper.

The wrapper re-execs `dockerd` under passwordless `sudo` and lets dockerd start
its **own** containerd (no standalone containerd, because nothing would supervise
it without systemd):

```bash
exec sudo dockerd --host=unix:///var/run/docker.sock
```

> ⚠️ **Sync gotcha** (same as `run-michel.sh` above): `dockerd-runner.sh` lives in
> git **and** at `/home/sprite/workspace/scripts/dockerd-runner.sh` on the sprite.
> Editing the repo copy does not update the sprite. After every change, push it:
>
> ```bash
> sprite exec -s test-michel tee /home/sprite/workspace/scripts/dockerd-runner.sh < scripts/dockerd-runner.sh > /dev/null
> sprite exec -s test-michel chmod +x /home/sprite/workspace/scripts/dockerd-runner.sh
> sprite exec -s test-michel -- sprite-env services restart dockerd
> ```

Register the service once:

```bash
sprite exec -s test-michel -- sprite-env services create dockerd \
  --cmd bash \
  --args /home/sprite/workspace/scripts/dockerd-runner.sh \
  --dir /home/sprite/workspace
```

Control it:

```bash
sprite exec -s test-michel -- sprite-env services list
sprite exec -s test-michel -- sprite-env services get dockerd
sprite exec -s test-michel -- sprite-env services restart dockerd
sprite exec -s test-michel -- sprite-env services stop dockerd
```

Daemon logs: `/.sprite/logs/services/dockerd.log` on the sprite.

### Verify

```bash
sprite exec -s test-michel -- docker info | grep -E "Server Version|Storage Driver|Cgroup"
sprite exec -s test-michel -- docker run --rm hello-world      # prints "Hello from Docker!"
sprite exec -s test-michel -- docker compose version
```

Expected: Storage Driver `overlayfs`, Cgroup Version `2`, hello-world banner.

### Notes

- The installed packages persist on the sprite disk and are captured in a
  **checkpoint**, so they survive hibernation and restore.
- A `sprite-env` **service definition** may need re-creating after a full sprite
  rebuild from a base image — re-run the `services create dockerd` command above.
- **Bridge networking works** despite Ubuntu's nftables backend; Docker 29 handles
  it. If a future kernel/sprite breaks it, fall back to `--iptables=false` in
  `dockerd-runner.sh` and run containers with `--network host`.
