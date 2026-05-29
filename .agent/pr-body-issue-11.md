Closes #11

## Summary
Adds a severity concept (high/medium/low) to tasks with color-coded badges visible on each Kanban card. Replaces the previous inline edit mode with a right-side drawer that allows editing name, description, and severity via a dropdown. Existing tasks default to medium severity.

## Changes
- Added `Severity` type (`high` | `medium` | `low`) and `severity` field to `Task` interface in both `src/db.ts` (server) and `src/api.ts` (client)
- Added `severity` column to SQLite schema with CHECK constraint and `ALTER TABLE` migration for existing databases in `src/db.ts`
- Updated `PATCH /api/tasks/:id` in `src/server.ts` to validate and persist severity
- Created `src/components/TaskDrawer.tsx` — right-side drawer with name, description, and severity dropdown fields
- Updated `src/components/TaskCard.tsx` — removed inline edit mode, added severity badge (red/yellow/green), edit button now opens drawer
- Updated `src/components/Column.tsx` — added `onEdit` prop to pass through to TaskCard
- Updated `src/App.tsx` — added `drawerTask` state, wired drawer open/close, added `severity` to `updateTask` patch type

## How to verify
1. Run `bun install && bun run dev`
2. Open http://localhost:3000
3. Create a new task — it should appear with a "Medium" severity badge (yellow)
4. Click the edit button (✎) on a task card — a right-side drawer should slide in
5. Change the severity dropdown to "High" or "Low" and click Save
6. The drawer closes and the card's severity badge updates immediately
7. Verify the change persists by refreshing the page

## Testing
No automated test suite exists. Verified manually via Playwright MCP:
- API endpoints tested with curl: POST creates tasks with `severity: "medium"` default, PATCH updates severity correctly
- UI verified: severity badges render with correct colors (red for high, yellow for medium, green for low)
- Full flow verified: open drawer → change severity → save → drawer closes → Kanban reflects update
- Typecheck passes: `bunx tsc --noEmit` exits cleanly

## Notes for reviewer
The previous inline edit in TaskCard has been fully replaced by the drawer, per the issue requirements. The drawer uses only a dropdown for severity selection (no duplicate buttons), addressing the feedback in the PR #14 discussion. The `ALTER TABLE` migration in `db.ts` is wrapped in a try/catch so it's safe to run on both fresh and existing databases.

## Artifacts
<!-- ARTIFACTS_PLACEHOLDER -->
