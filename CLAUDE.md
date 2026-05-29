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

There is no build, lint, typecheck, or test script defined in `package.json`. To typecheck manually: `bunx tsc --noEmit`. There is no test runner configured.

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

A comment containing `@michel` on an issue in `cteyton/sprites-demo` triggers `scripts/run-michel.sh <owner/repo> <issue_number>` on the `test-michel` sprite. Authorization: `comment.author_association ∈ {OWNER, MEMBER, COLLABORATOR}`.

Pieces:
- `scripts/webhook-server.ts` — Bun HTTP listener on port 8080 inside the sprite. Validates the `X-Hub-Signature-256` HMAC, allowlists repo + association, then fire-and-forgets `run-michel.sh`. Logs every request as one JSON line to stdout.
- `scripts/run-michel.sh` — runs **inside an isolated per-mention dir** `/home/sprite/runs/issue-<N>-<ts>-<pid>/repo` via `gh repo clone`, so concurrent or retriggered `@michel` calls never share state. Pushes with `--force-with-lease`; if a PR already exists for `agent/issue-<N>` it updates the body instead of erroring on duplicate.
- `scripts/install-michel-service.sh` — one-time setup from your laptop. Uploads the listener, registers it as a `sprite-env services` service (survives hibernation), runs `sprite url update --auth public`, and prints the GitHub webhook config.
- `.env.michel` (gitignored) — holds `WEBHOOK_SECRET` (shared with GitHub) and the allowlists. `.env.michel.example` is the template.

Setup:
```bash
bash scripts/install-michel-service.sh   # idempotent; generates secret on first run
```

Operate:
```bash
sprite exec -- sprite-env services list
sprite exec -- sprite-env services logs michel-webhook --tail 100
sprite exec -- sprite-env services stop michel-webhook   # pause without uninstalling
```

Out of scope: no per-issue lock (concurrent `@michel` mentions race on the same branch), no status comment back to the issue, single-repo.
