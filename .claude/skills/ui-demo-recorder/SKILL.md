---
name: ui-demo-recorder
description: Record polished UI demo videos and screenshots of a running web app using Playwright MCP — for client deliverables, release notes, feature walkthroughs, or bug repros. Produces an HD WebM video with chapter markers, an animated cursor overlay, and an optional subtitle bar that narrates each step (positioned deliberately so it never masks the UI being demonstrated), plus full-page screenshots at each step. Use this whenever the user asks to "record a demo", "create a screencast", "make a UI walkthrough video", "document this feature with video", "show the client how X works", "capture screenshots of the app", or anything similar — even when the user only says "make a video" or "take screenshots" in the context of a running frontend. Also use it when the user wants to demonstrate a workflow, generate marketing-quality footage of an app, or produce repeatable visual documentation.
---

# UI Demo Recorder

Produce client-ready UI documentation (HD video + screenshots) from a running web app using the Playwright MCP video tools.

## When to reach for this skill

- "Record a demo / walkthrough / screencast / video of the app"
- "Take screenshots of the feature working"
- "Show the client what X looks like"
- "Document this flow visually"
- "Make a GIF/video of clicking through Y"

The deliverable is always one or more of:
- WebM video (1440×900 HD by default), with optional chapter cards
- Full-page PNG screenshots at key moments
- An animated cursor overlay so viewers can follow what's being clicked

## Why a skill exists for this

The Playwright MCP video tools work, but they have several non-obvious gotchas that waste a lot of time if you discover them mid-recording:

1. The video tools live behind an opt-in flag (`--caps=devtools`) and are silently absent if the MCP server wasn't launched with it.
2. There are usually **two different Playwright MCP tool prefixes** in the deferred-tools list (a stock one and a plugin one). They use **different browser contexts**, and only one of them can record video. Mixing them mid-session causes "Browser is already in use" errors.
3. The recorder doesn't render the OS cursor — videos look like the app is operating itself unless you inject a fake cursor.
4. Any `location.reload()` wipes the injected cursor — it must be reinjected.
5. The output file lands at the *project root*, not in whatever `--output-dir` says.

This skill codifies the working recipe so the model doesn't relearn it every time.

## Pre-flight check (do this first, every time)

### 1. Confirm the Playwright MCP has `--caps=devtools`

Open `.mcp.json` (project root or `~/.claude/.mcp.json`). The Playwright server entry **must** include `--caps=devtools` in its args. If it doesn't, video tools won't be exposed.

Working config:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--caps=devtools", "--output-dir=./videos"]
    }
  }
}
```

If you have to add the flag, tell the user — they have to reload MCP (`/mcp` reconnect or restart Claude Code) before `browser_start_video` becomes callable.

### 2. Confirm the right tool prefix

Use `ToolSearch` for `mcp__playwright__browser_start_video`. The video tools belong to the `mcp__playwright__browser_*` family. Use the **same prefix** for every browser interaction in the recording — `browser_navigate`, `browser_click`, `browser_type`, `browser_snapshot`, `browser_wait_for`, `browser_evaluate`, `browser_close`. **Do not mix in `mcp__plugin_playwright_playwright__browser_*`** — that's a different MCP server with a different browser context; mixing causes "Browser is already in use".

### 3. Get the app running

Start the dev server in the background and probe it before recording. If a clean state matters (empty board, no leftover data), wipe via the API or seed via a script — do not record over stale state.

## Recording recipe

The recipe in plain English:
1. Make sure no browser tab is currently open on the Playwright side.
2. Start the video.
3. Navigate to the app.
4. Inject the cursor overlay.
5. Add a chapter card.
6. Drive the UI (click, type slowly, wait for visible feedback).
7. Whenever the page reloads, reinject the cursor.
8. Add chapter cards between major sections.
9. Stop the video.
10. Move the file from project root into `videos/`.
11. Kill the dev server.

### Starting the video (with the common pitfall)

```
mcp__playwright__browser_start_video(
  filename="<name>.webm",
  size={"width": 1440, "height": 900}
)
```

If you get `Error: Screencast is already started`, a previous session left a recorder open. Call `mcp__playwright__browser_stop_video` (it returns one or more stub WebMs at the project root), delete the stubs, then call `start_video` again. This is normal.

If you get `Browser is already in use for ... use --isolated`, a non-recording Playwright session has the persistent profile locked. Call `mcp__playwright__browser_close` first, then start_video.

### Injecting the cursor overlay

The Playwright video recorder is a CDP screencast of the viewport — the real OS cursor is never in the frame. To make the video readable, inject a DOM cursor that listens to `mousemove`/`mousedown`/`mouseup` (Playwright's pointer events do dispatch these in capture phase).

Run the script in `scripts/inject-cursor.js` via `browser_evaluate` immediately after every navigate or reload:

```
mcp__playwright__browser_evaluate(function=<contents of scripts/inject-cursor.js>)
```

The cursor is:
- A blue radial-gradient disk with a soft glow
- Animates with a 220ms CSS transition so jumps look smooth
- Turns red and shrinks on `mousedown`
- Emits an expanding ring "ripple" on click

Reinject after every `location.reload()` — there is no `initScript` equivalent exposed in MCP, so it has to be a manual step.

### Chapter cards

`mcp__playwright__browser_video_chapter` renders a full-screen card with a blurred backdrop over the page for a configurable duration. Use it for:
- The opening title
- Between major sections ("1. Create tasks", "2. Edit", "3. Move", "4. Delete")
- A final card

Default duration of 1500–3000ms reads well at normal playback speed.

### Subtitle bar (continuous narration)

Chapter cards interrupt the action. For inline narration that doesn't hide the UI — short captions that explain each step while the viewer watches the click happen — inject a subtitle bar via `scripts/inject-subtitles.js`. Bundle it with the cursor injection so both go in with one `browser_evaluate`.

The script exposes `window.__setSubtitle(text)`. Call it before each step:

```
mcp__playwright__browser_evaluate(function="() => window.__setSubtitle('Type the task name')")
```

Pass an empty string or `null` to hide the bar.

**Pick the position deliberately.** The default is bottom-center. A subtitle that sits over the very area the viewer needs to watch defeats the purpose — they'll either miss the action or miss the caption.

- If the action happens in the **header/top bar** (a form, search input, primary CTA at the top), use the **bottom** position (default).
- If the action happens in a **footer, sticky action bar, or fixed bottom CTA**, switch to the **top** position by passing `{position: 'top'}` to the injector, or call `window.__moveSubtitle('top')` mid-recording.
- If a single screen has critical content at both top and bottom, reposition between steps with `window.__moveSubtitle` so the bar always sits on the inert side of the UI.

The bar fades + slides on text change (280ms) so swaps look intentional rather than glitchy. Reinject after `location.reload()` along with the cursor.

### Lead-in dead air

The recorder buffers for a second or two after `start_video` before useful frames appear. Combined with MCP tool round-trip latency, the first ~10–25 seconds of the WebM can show an empty page or `about:blank`. Mitigations:

1. Set the first subtitle and a chapter card **before** the first `wait_for` — gives the viewer something to read during the lead-in.
2. Keep the gap between `start_video`, `navigate`, and the inject-overlays `browser_evaluate` as tight as possible — no intermediate snapshots.
3. If a strict deliverable timeline matters, trim the WebM in post with ffmpeg (`-ss <seconds>`); only available if the user has ffmpeg installed.

### Typing and clicking — make it watchable

- `browser_type(..., slowly=true)` types one character at a time. Use it for any text the viewer should read.
- Before each `browser_click`, take a fresh `browser_snapshot` to get current refs (refs change after re-renders).
- After actions that change the DOM, call `browser_wait_for(text=<expected new content>)` instead of arbitrary sleeps — recordings made of `wait_for` look like a real user; recordings made of fixed sleeps look robotic.

### When a click doesn't propagate (drag-drop and friends)

The Playwright `browser_drag` tool dispatches mouse events but does **not** reliably trigger libraries that use pointer-event sensors (e.g. `@dnd-kit`'s `PointerSensor`). If you see the drag "land" on the wrong drop zone or no state change happens, don't fight it. Switch to driving state via the app's API:

```
mcp__playwright__browser_evaluate(function=`async () => {
  // fetch + PATCH the relevant endpoint
  // then location.reload()
}`)
```

Then reinject the cursor. The video still shows the column visually changing — viewers don't see the difference.

### Screenshots

Use `browser_take_screenshot(filePath=..., fullPage=true)` for full-page PNGs at moments worth capturing as stills. Number them (`01-initial.png`, `02-typing.png`, ...) so they sort correctly. Save them under `screenshots/` inside the project.

If the project doesn't have ffmpeg/ImageMagick installed and you also want a GIF or MP4 from a sequence of stills (for an environment that can't play WebM), use a Python venv with `Pillow` (GIF) or `imageio-ffmpeg` (MP4) — both ship a usable binary so brew install isn't needed.

## Stopping and packaging

```
mcp__playwright__browser_stop_video()
mcp__playwright__browser_close()
```

The WebM lands at the **project root**, not in `videos/`, regardless of what `--output-dir` says. Move it:

```bash
mv ./<name>.webm ./videos/
```

Kill the dev server you started in the background. Don't leave it running.

## What "good" looks like

- Resolution 1440×900 or larger
- Smooth cursor that's clearly visible against the app's UI
- 3–6 chapter cards (intro, 2–4 sections, outro)
- ~30 seconds to 2 minutes total — anything longer should be split
- File size 4–15 MB for typical demos; if it's bigger, the run was too long
- No console errors visible in the video (close DevTools if it was open)

## What to tell the user at the end

Hand over:
- The path of the final WebM
- A one-line summary of the chapters
- Anything that was faked (e.g. "drag-drop was driven via the API because dnd-kit doesn't respond to MCP drag synth")
- A reminder that WebM may need a modern browser or VLC to play; offer to also produce an MP4 if the client uses a tool that doesn't accept WebM

## Reference material

- `scripts/inject-cursor.js` — paste-ready cursor overlay
- `scripts/inject-subtitles.js` — paste-ready subtitle bar with `__setSubtitle` / `__moveSubtitle` helpers
- `scripts/check-mcp-config.sh` — one-liner to confirm `--caps=devtools` is set
- `references/playwright-mcp-tools.md` — table of the relevant tools and their gotchas
