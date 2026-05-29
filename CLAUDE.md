# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the app

This is a Bun-native project — there is no separate bundler, dev server, or build step. Bun handles TypeScript, JSX, and (via `bun-plugin-tailwind` configured in `bunfig.toml`) Tailwind v4 transpilation when it serves `src/index.html`.

```bash
bun install         # one-time
bun run dev         # dev server with --hot reload (src/server.ts)
bun run start       # same server without hot reload
```

The server listens on `PORT` (default `3000`). Open <http://localhost:3000>.

`package.json` defines `test` (`bun test --pass-with-no-tests`) and `build` (`bun build src/index.html --outdir=dist --target=browser`). No lint script. To typecheck manually: `bunx tsc --noEmit`. The test runner (`bun test`) has no tests yet — UI verification is via the MCP browser servers.

## Architecture

Single-process full-stack app: one Bun server (`src/server.ts`) serves both the HTML/JS bundle and the JSON API from the same origin.

**Server side (`src/server.ts` + `src/db.ts`)**
- `bun.serve({ routes })` declarative routing. The `/` route returns the imported `index.html` module, which Bun auto-bundles (TS, TSX, CSS-with-tailwind) on demand.
- `/api/tasks` (GET, POST) and `/api/tasks/:id` (PATCH, DELETE) implement a CRUD REST surface for tasks.
- `src/db.ts` opens `tasks.sqlite` via `bun:sqlite` in WAL mode and runs `CREATE TABLE IF NOT EXISTS` on import — there are no migration files. Prepared statements are exported as the `queries` object; the server calls them directly. The sqlite file is git-ignored.
- Input validation lives in the route handlers (length caps `MAX_NAME=200`, `MAX_DESC=500`, status enum check). All error responses go through the `bad()` helper.

**Client side (`src/client.tsx` → `src/App.tsx` → `src/components/*`)**
- React 19 with `StrictMode`. Kanban board with three fixed columns (`todo`, `in_progress`, `done`).
- Drag-and-drop via `@dnd-kit/core`: `Column` is the `useDroppable` target, `TaskCard` is `useDraggable`. Dragging is disabled while a card is in inline-edit mode. Edit/delete buttons stop pointerdown propagation so they don't start a drag.
- `App.tsx` is the only state owner. `updateTask` and `deleteTask` do **optimistic updates with rollback** on API failure — preserve this pattern when adding mutations.
- `src/api.ts` is the thin fetch wrapper; the shared `handle<T>` parses JSON errors into `Error.message`.

**Type duplication, by design**
`Task` and `Status` are declared in **both** `src/db.ts` (server) and `src/api.ts` (client). They are not shared — the client never imports from `db.ts`, because doing so would pull `bun:sqlite` into the browser bundle. If you change the schema, update both copies.

## MCP servers

`.mcp.json` configures two MCP servers (`playwright`, `chrome-devtools`) for browser automation. Playwright writes recordings to `./videos`. Use these for UI verification — there is no automated test suite.

## Conventions worth keeping

- All errors surface to the user via the red banner in `App.tsx`; mutations should call `setError` on failure, not throw silently.
- Position ordering: new tasks get `MAX(position)+1` within the `todo` column. Status changes via drag do not currently renumber positions — be aware before adding reorder-within-column UX.
- Tailwind v4 is imported with `@import "tailwindcss";` in `src/styles.css` — no `tailwind.config.js`. Class scanning happens automatically.
- `PATCH /api/tasks/:id` is a field-merge: omitted fields fall back to current row values. Client can send partial patches (`{ status }` alone is valid).
- `createTask` is **not** optimistic — only `updateTask`/`deleteTask` are. New cards appear after server confirms.
- Drag activation threshold: `PointerSensor` requires 5px movement before drag starts, so pointerdown on a card without movement is still a click.

## Michel webhook (GitHub `@michel` → sprite)

A comment containing `@michel` on an issue in `cteyton/sprites-demo` hits the webhook listener on the **controller** sprite (`test-michel`), which **dispatches** the run to a **worker sprite** from a pool. Authorization: `comment.author_association ∈ {OWNER, MEMBER, COLLABORATOR}`.

Pieces:
- `scripts/webhook-server.ts` — Bun HTTP listener on port 8080 on the controller. Validates the `X-Hub-Signature-256` HMAC, allowlists repo + association, then spawns `DISPATCH_SCRIPT` (`dispatch-michel.sh`). The controller no longer runs `run-michel.sh` itself. Logs every request as one JSON line to stdout.
- `scripts/dispatch-michel.sh` — picks a free worker from `WORKER_SPRITES`, takes a per-issue lock (`/var/michel/locks`, falls back to `/tmp/michel/locks`), and runs `run-michel.sh` on that worker via the sprite CLI. Real parallelism = number of workers.
- `scripts/run-michel.sh` — runs **on a worker sprite** in an isolated per-mention dir `/home/sprite/runs/issue-<N>-<ts>-<pid>/repo` via `gh repo clone`, so concurrent or retriggered `@michel` calls never share state. Pushes with `--force-with-lease`; if a PR already exists for `agent/issue-<N>` it updates the body instead of erroring on duplicate.
- `scripts/provision-worker.sh` — provisions a worker sprite (Docker, repo checkout, clean checkpoint) from your laptop: `bash scripts/provision-worker.sh <worker-name>`.
- `scripts/webhook-runner.sh` / `scripts/dockerd-runner.sh` — service entrypoints for the listener and dockerd inside the sprite.
- `scripts/install-michel-service.sh` — one-time setup from your laptop. Uploads the listener, registers it as a `sprite-env services` service (survives hibernation), runs `sprite url update --auth public`, and prints the GitHub webhook config.
- `.env.michel` (gitignored) — holds `WEBHOOK_SECRET` (shared with GitHub), the allowlists, plus the worker-pool vars `WORKER_SPRITES`, `SPRITE_TOKEN`, `CONTROLLER_ORG`, and per-worker checkpoint ids. On the sprite this env lives at `/home/sprite/.michel.env`. `.env.michel.example` is the template.

Setup:
```bash
bash scripts/install-michel-service.sh   # idempotent; generates secret on first run
```

Operate:
```bash
sprite exec -- sprite-env services list
sprite exec -- tail -n 100 /.sprite/logs/services/michel-webhook.log   # no `services logs` subcommand; read the file
sprite exec -- sprite-env services stop michel-webhook   # pause without uninstalling
```

**Sync gotcha:** `run-michel.sh`, `webhook-server.ts`, and `webhook-runner.sh` are NOT auto-synced to the sprite — editing the repo copy does nothing until you push it (`sprite exec tee /home/sprite/workspace/scripts/<file> < ./scripts/<file>`). `run-michel.sh` applies on the next mention (spawned fresh); `webhook-server.ts`/`webhook-runner.sh` need a service restart. See `scripts/README.md`.

Out of scope: no status comment back to the issue, single-repo.
