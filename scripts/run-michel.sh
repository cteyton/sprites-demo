#!/usr/bin/env bash
# ~/run-michel.sh — usage: ./run-michel.sh <repo> <issue-number>

set -euo pipefail

REPO="${1:?usage: $0 <owner/repo> <issue-number>}"
ISSUE="${2:?usage: $0 <owner/repo> <issue-number>}"

ERROR_LOG="${MICHEL_ERROR_LOG:-/tmp/michel-runs/last-error.log}"
mkdir -p "$(dirname "${ERROR_LOG}")"
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "[$(date -Is)] run-michel.sh failed (rc=$rc) repo=${REPO} issue=${ISSUE} run=${RUN_ID:-?} line=${LINENO}" >> "${ERROR_LOG}"; fi' EXIT

# Fresh per-run workspace so concurrent/retriggered mentions never share state.
# /tmp is used by default because the sprite-env service runs as a user whose
# write access to /home/sprite is not guaranteed. Override with RUNS_BASE.
RUN_ID="issue-${ISSUE}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
RUN_ROOT="${RUNS_BASE:-/tmp/michel-runs}/${RUN_ID}"
WORKDIR="${RUN_ROOT}/repo"
BRANCH="agent/issue-${ISSUE}"
ARTIFACTS_DIR=".agent/artifacts/issue-${ISSUE}"
PR_BODY_PATH=".agent/pr-body-issue-${ISSUE}.md"

echo "==> [1/7] Fetching issue #${ISSUE} from ${REPO}"
ISSUE_JSON=$(gh issue view "${ISSUE}" --repo "${REPO}" --json number,title,body,labels,comments)
ISSUE_TITLE=$(echo "${ISSUE_JSON}" | jq -r '.title')
ISSUE_BODY=$(echo "${ISSUE_JSON}" | jq -r '.body')
ISSUE_COMMENTS=$(echo "${ISSUE_JSON}" | jq -r '.comments[] | "[\(.author.login)]: \(.body)"')

echo "Issue: ${ISSUE_TITLE}"

echo "==> [2/7] Fresh-cloning ${REPO} into ${WORKDIR} (run ${RUN_ID})"
mkdir -p "${RUN_ROOT}"
gh repo clone "${REPO}" "${WORKDIR}" -- --branch main
cd "${WORKDIR}"
git checkout -b "${BRANCH}"

echo "==> [3/7] Creating artifacts directory"
mkdir -p "${ARTIFACTS_DIR}"
mkdir -p "$(dirname "${PR_BODY_PATH}")"

echo "==> [4/7] Building Claude prompt"
PROMPT=$(cat <<EOF
You are Michel, an autonomous coding agent working on GitHub issue #${ISSUE} in repository ${REPO}.

# Issue title
${ISSUE_TITLE}

# Issue description
${ISSUE_BODY}

# Discussion comments
${ISSUE_COMMENTS}

# Your task
Implement the changes described in the issue.

# Constraints
- Working directory: ${WORKDIR}
- Branch: ${BRANCH}
- This is a Bun-native full-stack app (Bun server + React 19 client, SQLite via \`bun:sqlite\`). No bundler, no build step — Bun handles TS/TSX/Tailwind v4 on demand.
- Install deps with \`bun install\`. Run dev server with \`bun run dev\` (hot reload) or \`bun run start\`.
- There is no lint, test, or build script. Typecheck manually with \`bunx tsc --noEmit\`.
- There is no automated test suite. For UI verification, use the configured MCP servers (\`playwright\`, \`chrome-devtools\` in \`.mcp.json\`); Playwright writes recordings to \`./videos\`.
- \`Task\` and \`Status\` types are duplicated in \`src/db.ts\` (server) and \`src/api.ts\` (client) by design — never import \`db.ts\` from client code. If you change the schema, update both copies.
- \`updateTask\`/\`deleteTask\` use optimistic updates with rollback in \`src/App.tsx\` — preserve that pattern for new mutations. \`createTask\` is intentionally non-optimistic.
- All mutation errors must surface via \`setError\` in \`App.tsx\` (red banner) — never throw silently.
- Make atomic, focused commits with clear messages.

# Artifacts (optional)
If you produce evidence of your work (test outputs, logs, generated reports, screenshots, videos),
save them under ${ARTIFACTS_DIR}/ with descriptive filenames.

If the issue requires demonstrating UI behavior (screenshots, screencasts, walkthroughs, before/after visuals, or a recorded demo for the reviewer), use the \`ui-demo-recorder\` skill — it drives the running app via Playwright MCP and produces HD video + per-step screenshots with cursor overlay and narration. Save its output under ${ARTIFACTS_DIR}/ so it gets attached to the PR.

# PR description (REQUIRED)
At the very end of your work, write a complete PR description to:
  ${PR_BODY_PATH}

The PR body MUST include these sections in this exact order.

IMPORTANT formatting rules for the PR body:
- GitHub renders single newlines inside a paragraph as visible line breaks (\`<br>\`).
  So DO NOT hard-wrap paragraph text at 80 columns. Each paragraph must be a SINGLE long line.
  Only insert a newline to start a new paragraph, a new bullet, or a new section.
- Bullet lists: one bullet per line is fine — each bullet itself must be a single line (no mid-bullet wrap).
- Do not indent prose. Do not add trailing two-space hard breaks.

\`\`\`markdown
Closes #${ISSUE}

## Summary
2-4 sentences explaining what was changed and why. Plain language. Write each sentence-paragraph as ONE unwrapped line.

## Changes
Bullet list of the concrete changes you made. Be specific:
- Added \`X\` in \`apps/api/src/...\`
- Modified \`Y\` to support ...
- Created tests in \`...\`

## How to verify
Numbered steps a reviewer can run to validate the change locally.
Include the exact nx commands.

## Testing
Describe what tests you added or modified, and the result of running them.

## Notes for reviewer
Any assumptions you made, trade-offs, or things you couldn't verify.
If everything went smoothly, write "Nothing special to flag."

## Artifacts
(Leave this section as a literal placeholder — the bash script will fill it in.)
<!-- ARTIFACTS_PLACEHOLDER -->
\`\`\`

Write this file as the FINAL action of your task, after all code and commits are done.

# Done criteria
- Code implemented and committed
- Typecheck clean (\`bunx tsc --noEmit\`)
- Dev server boots without errors (\`bun run dev\`)
- UI behavior verified via Playwright or chrome-devtools MCP if changes affect the client
- PR body written to ${PR_BODY_PATH}

Begin.
EOF
)

echo "==> [5/7] Running Claude (this may take several minutes)"
echo "${PROMPT}" | claude \
  --print \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  | jq --unbuffered -r '
      # Collapse newlines + clip long strings so one log line stays one line.
      def oneline: (. // "") | tostring | gsub("\\s+"; " ");
      def clip($n): oneline | if (. | length) > $n then .[0:$n] + "…" else . end;

      # Pull the most useful argument out of a tool_use .input, per tool.
      def tool_args:
        .input as $i
        | if   $i.file_path  then $i.file_path
          elif $i.command    then "$ " + ($i.command | clip(300))
          elif $i.pattern    then "/" + $i.pattern + "/" + (if $i.path then " in " + $i.path elif $i.glob then " glob " + $i.glob else "" end)
          elif $i.query      then ($i.query | clip(200))
          elif $i.url        then $i.url
          elif $i.prompt     then ($i.prompt | clip(200))
          elif $i.description then ($i.description | clip(200))
          else "" end;

      # Render a tool_result content block (string or array of parts) to text.
      def result_text:
        (.content // "")
        | if type == "array" then (map(.text? // (.content? // "") // "") | join(" ")) else . end
        | clip(400);

      if .type == "assistant" then
        (.message.content[]? | select(.type == "text") | .text),
        (.message.content[]? | select(.type == "tool_use")
          | "\n[tool: " + .name + "] " + (tool_args))
      elif .type == "user" then
        (.message.content[]? | select(.type == "tool_result")
          | "[tool_result" + (if .is_error then " ERROR" else "" end) + "] " + (result_text))
      elif .type == "system" and .subtype == "init" then
        "[claude session started]"
      elif .type == "result" then
        "\n[done: " + (.subtype // "ok") + "]"
      else empty end
    '


echo "==> [6/7] Verifying PR body was written"
if [ ! -f "${PR_BODY_PATH}" ]; then
  echo "❌ Claude did not write the PR body to ${PR_BODY_PATH}"
  echo "   Falling back to a minimal body. Review carefully before merging."
  cat > "${PR_BODY_PATH}" <<EOF
Closes #${ISSUE}

## Summary
Automated implementation by Michel for issue #${ISSUE}.

⚠️ Claude did not provide a detailed PR description. Please review the diff carefully.

<!-- ARTIFACTS_PLACEHOLDER -->
EOF
fi

echo "==> [7/7] Committing artifacts, building artifacts section, and creating PR"

# Commit artifacts si présents
if [ -d "${ARTIFACTS_DIR}" ] && [ -n "$(ls -A "${ARTIFACTS_DIR}" 2>/dev/null)" ]; then
  git add "${ARTIFACTS_DIR}"
  git commit -m "chore(agent): add artifacts for issue #${ISSUE}" || true
fi

# Push la branche. --force-with-lease so a retriggered @michel on the same
# issue replaces the prior attempt instead of failing on non-ff.
git push -u origin "${BRANCH}" --force-with-lease

# Construit le bloc Artifacts
ARTIFACTS_BLOCK=""
if [ -d "${ARTIFACTS_DIR}" ] && [ -n "$(ls -A "${ARTIFACTS_DIR}" 2>/dev/null)" ]; then
  ARTIFACTS_BLOCK=$'\n'
  for file in "${ARTIFACTS_DIR}"/*; do
    [ -e "$file" ] || continue
    filename=$(basename "$file")
    raw_url="https://github.com/${REPO}/raw/${BRANCH}/${ARTIFACTS_DIR}/${filename}"
    blob_url="https://github.com/${REPO}/blob/${BRANCH}/${ARTIFACTS_DIR}/${filename}"
    case "$filename" in
      *.png|*.jpg|*.jpeg|*.gif|*.webp)
        ARTIFACTS_BLOCK+="### ${filename}"$'\n'
        ARTIFACTS_BLOCK+="![${filename}](${raw_url})"$'\n\n'
        ;;
      *.mp4|*.webm|*.mov)
        ARTIFACTS_BLOCK+="### ${filename}"$'\n'
        ARTIFACTS_BLOCK+="[▶ ${filename}](${raw_url}) (click to play/download)"$'\n\n'
        ;;
      *)
        ARTIFACTS_BLOCK+="- [\`${filename}\`](${blob_url})"$'\n'
        ;;
    esac
  done
else
  ARTIFACTS_BLOCK="_No artifacts produced._"
fi

# Remplace le placeholder dans le body
PR_BODY_FINAL=$(mktemp)
# Échappe les caractères spéciaux pour sed via une approche awk plus robuste
awk -v block="${ARTIFACTS_BLOCK}" '{
  if ($0 ~ /<!-- ARTIFACTS_PLACEHOLDER -->/) {
    print block
  } else {
    print
  }
}' "${PR_BODY_PATH}" > "${PR_BODY_FINAL}"

# Create or update the PR. If one already exists for this branch (retrigger
# of the same issue), force-push above refreshed the commits; just replace
# the body.
EXISTING_PR=$(gh pr list --repo "${REPO}" --head "${BRANCH}" --state open --json url --jq '.[0].url' || true)
if [ -n "${EXISTING_PR}" ]; then
  gh pr edit "${EXISTING_PR}" --repo "${REPO}" --body-file "${PR_BODY_FINAL}" >/dev/null
  PR_URL="${EXISTING_PR}"
else
  PR_URL=$(gh pr create \
    --repo "${REPO}" \
    --base main \
    --head "${BRANCH}" \
    --title "[Michel] ${ISSUE_TITLE}" \
    --body-file "${PR_BODY_FINAL}" \
    --label "agent-generated")
fi

rm "${PR_BODY_FINAL}"

echo ""
echo "✅ Done. PR opened: ${PR_URL}"