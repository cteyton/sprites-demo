Closes #8

## Summary
Adds a sticky footer displaying "Made from Bordeaux with Love - 2026" with a dark slate background, right-aligned text, and vertical centering. The page layout is wrapped in a flex column so the footer always sits at the bottom of the viewport.

## Changes
- Modified `src/App.tsx`: wrapped the page content in a `flex flex-col min-h-screen` container, moved existing content into a `<main>` with `flex-1`, and added a `<footer>` with `bg-slate-800` background, `justify-end` for right alignment, and `items-center` for vertical centering.

## How to verify
1. Run `bun install && bun run dev`
2. Open http://localhost:3000
3. Confirm the dark footer is visible at the bottom of the page with the text "Made from Bordeaux with Love - 2026" aligned to the right and vertically centered.

## Testing
No automated tests — verified visually via Playwright screenshot. Typecheck passes (`bunx tsc --noEmit`).

## Notes for reviewer
Nothing special to flag.

## Artifacts
<!-- ARTIFACTS_PLACEHOLDER -->
