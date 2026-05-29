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

---

## Worker pool (parallel `@michel` runs)

To run several `@michel` issues **in parallel**, the controller (`test-michel`)
dispatches each run to a dedicated **worker sprite** instead of running
`run-michel.sh` itself. Each worker is its own VM, so the app a run boots
(`bun run dev` on `:3000`, `docker compose`, …) never collides with another
worker's app — the `:3000` of `michel-worker-1` and `michel-worker-2` are on
different machines. Real parallelism = number of workers.

> **Why a pool and not "boot the app N times on one sprite":** apps hide shared
> state (fixed ports, DB names, services). Per-VM isolation solves it once for
> any app; per-app port-parameterising does not scale.

> **Checkpoints are intra-sprite** (`sprite restore` only rewinds the *same*
> sprite — there is no clone-from-snapshot across sprites). So each worker is
> provisioned independently and gets its own `clean` checkpoint; between runs the
> dispatcher `restore`s that checkpoint to wipe the dirty overlay.

### Provision a worker (one-time, from the laptop)

```bash
bash scripts/provision-worker.sh michel-worker-1
```

It is idempotent and installs the **full verification stack** so a run never
races a cold dependency download:
- Docker + Compose (as above) + `jq`
- **Google Chrome** (`google-chrome-stable`) — Playwright MCP uses the `chrome`
  channel and needs `/opt/google/chrome/chrome`; the base image ships no browser.
- **Sans-serif fonts** (`fonts-liberation fonts-noto-core fonts-dejavu-core`) —
  else screenshots render in a mono fallback (see "Headless rendering fonts").
- Pre-warmed Playwright `chromium` + `ffmpeg` (video recording).
- `claude` CLI; injected `gh` + `claude` credentials (piped, never printed).

Then it takes a `clean` checkpoint and records its id into `.env.michel`
(`WORKER_CLEAN_CKPT_michel_worker_1=v2`). Add more workers by re-running with
`michel-worker-2`, `-3`, … and list them in `WORKER_SPRITES`.

> ⚠️ Re-provision (or re-install Chrome/fonts) after a worker is rebuilt from a
> base image — like the dockerd service, these live in the writable overlay only.

### How dispatch works

`webhook-server.ts` spawns `dispatch-michel.sh <repo> <issue>` on the controller,
which: claims a free worker (per-worker `flock` — one run per worker; waiting on
the lock is the FIFO queue when all are busy), runs `run-michel.sh` **inside** it
via `sprite -s <worker> exec` (blocking), then cleans `/tmp/michel-runs`,
`restore`s the worker's clean checkpoint, and releases the lock. The controller
drives workers via the in-sprite `sprite` CLI, authed by `SPRITE_TOKEN` (set up by
`install-michel-service.sh`).

### Replicate the whole setup from scratch

Assumes a fresh laptop with `sprite` + `gh` CLIs installed and logged in
(`sprite login`, `gh auth login` as the bot/owner account), and a controller
sprite that already has the `claude` CLI authenticated (its
`~/.claude/.credentials.json` is the source copied into each worker).

```bash
# 1. Config — copy the template and fill in the real values.
cp .env.michel.example .env.michel
#    Set: WEBHOOK_SECRET (openssl rand -hex 32), ALLOWED_REPOS,
#         CONTROLLER_ORG (e.g. cedric-teyton),
#         SPRITE_TOKEN (from `sprite org list` / dashboard → Access Tokens),
#         WORKER_SPRITES=michel-worker-1   (csv; grow as you add workers)

# 2. Provision each worker (one-time; ~3-5 min each — full stack install).
bash scripts/provision-worker.sh michel-worker-1
#    Fills WORKER_CLEAN_CKPT_michel_worker_1=<id> into .env.michel automatically.

# 3. Deploy the controller (webhook listener + dispatcher + sprite auth).
bash scripts/install-michel-service.sh
#    Prints the GitHub webhook config (Payload URL + secret) to paste into
#    each repo's Settings → Webhooks (Issue comments event only).

# 4. Smoke-check.
sprite -s test-michel url                       # grab the URL
curl -fsS <sprite-url>/healthz                  # expect: ok
#    Then comment "@michel" on a test issue → a PR should appear.
```

To **scale**, provision more workers and append them to `WORKER_SPRITES`, then
re-run `install-michel-service.sh` to push the updated list to the controller:

```bash
bash scripts/provision-worker.sh michel-worker-2
bash scripts/provision-worker.sh michel-worker-3
#  edit .env.michel: WORKER_SPRITES=michel-worker-1,michel-worker-2,michel-worker-3
bash scripts/install-michel-service.sh
```

### Reset & lifecycle (verified behaviour)

- **Between runs the dispatcher resets the worker** by (a) `rm -rf /tmp/michel-runs`
  and (b) `sprite restore <clean-checkpoint>`. `restore` rewinds the **home
  overlay** (`~/.claude` history/cache, `~/.config/gh`, git config) so per-run
  state never drifts. Baked packages (Docker, Chrome, fonts, claude) live in the
  checkpoint and survive the restore.
- **`/tmp` is NOT part of the checkpoint** (tmpfs), so `restore` alone does not
  clean it — that is why the dispatcher wipes `/tmp/michel-runs` explicitly.
  `run-michel.sh` keeps its workspace on failure, so without this it would
  accumulate across dispatches.
- **Restore + wake measured ≈ 15 s** — comfortably within a single mention's
  dispatch latency.
- **Idle workers hibernate** (`cold` in the dashboard) and cost ~storage only; a
  dispatch's `sprite exec` wakes them on demand. Workers are **never destroyed**:
  `sprite destroy` would delete the checkpoint too, forcing a full re-provision
  (minutes) on the next mention. Persistent-but-hibernated = cheap idle + fast
  reuse; that is the intended model.

### Operate / debug the pool

```bash
sprite -o <org> list                                  # worker states (running/warm/cold)
sprite -o <org> -s michel-worker-1 checkpoint list    # clean checkpoint id(s)
sprite -s test-michel exec -- sprite-env services logs michel-webhook --tail 100
sprite -o <org> -s michel-worker-1 exec -- bash -lc 'fc-list | wc -l; ls -x ~/.cache/ms-playwright'
sprite -o <org> -s michel-worker-1 restore <id>       # manual reset
```
