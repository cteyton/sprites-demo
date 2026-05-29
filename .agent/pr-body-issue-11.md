Closes #11

## Summary
Adds a `severity` field (`high`, `medium`, `low`) to tasks, displayed as color-coded badges on Kanban cards. Replaces the inline card editor with a right-side drawer that allows editing name, description, and severity via a dropdown. Existing tasks automatically default to `medium` severity through a schema migration.

## Changes
- Added `severity` column to the SQLite schema in `src/db.ts` with an `ALTER TABLE` migration for existing databases
- Added `Severity` type and `severity` field to the client-side `Task` type in `src/api.ts`
- Updated `PATCH /api/tasks/:id` in `src/server.ts` to accept and validate the `severity` field
- Updated `src/db.ts` prepared `update` query to include `severity`
- Created `src/components/TaskDrawer.tsx` — a right-side drawer with name, description, and severity dropdown
- Updated `src/components/TaskCard.tsx` — removed inline editing, added severity badge with color coding (red=high, yellow=medium, green=low), edit button now opens drawer
- Updated `src/components/Column.tsx` to pass `onOpenDrawer` callback instead of `onUpdate` to cards
- Updated `src/App.tsx` to manage drawer state and wire up the new `TaskDrawer` component

## How to verify
1. Run `bun install && bun run dev`
2. Open http://localhost:3000
3. Create a new task — it should appear with a "medium" severity badge
4. Click the edit (pencil) button on a task card — a drawer should slide in from the right
5. Change the severity dropdown to "high" or "low" and click Save
6. Verify the drawer closes and the card now shows the updated severity badge color

## Testing
No automated test suite is configured. Verified manually via Playwright MCP: created tasks, opened drawer, changed severity, confirmed badges update on Kanban after save. Screenshots and video captured as artifacts.

## Notes for reviewer
Nothing special to flag.

## Artifacts
<!-- ARTIFACTS_PLACEHOLDER -->
