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
