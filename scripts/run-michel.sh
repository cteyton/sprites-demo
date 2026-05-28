#!/usr/bin/env bash
# ~/run-michel.sh — usage: ./run-michel.sh <repo> <issue-number>

set -euo pipefail

REPO="${1:?usage: $0 <owner/repo> <issue-number>}"
ISSUE="${2:?usage: $0 <owner/repo> <issue-number>}"

WORKDIR="/home/sprite/workspace"
BRANCH="agent/issue-${ISSUE}"
ARTIFACTS_DIR=".agent/artifacts/issue-${ISSUE}"
PR_BODY_PATH=".agent/pr-body-issue-${ISSUE}.md"

echo "==> [1/7] Fetching issue #${ISSUE} from ${REPO}"
ISSUE_JSON=$(gh issue view "${ISSUE}" --repo "${REPO}" --json number,title,body,labels,comments)
ISSUE_TITLE=$(echo "${ISSUE_JSON}" | jq -r '.title')
ISSUE_BODY=$(echo "${ISSUE_JSON}" | jq -r '.body')
ISSUE_COMMENTS=$(echo "${ISSUE_JSON}" | jq -r '.comments[] | "[\(.author.login)]: \(.body)"')

echo "Issue: ${ISSUE_TITLE}"

echo "==> [2/7] Setting up branch ${BRANCH}"
cd "${WORKDIR}"
git fetch origin
git checkout main
git pull
git checkout -b "${BRANCH}" 2>/dev/null || git checkout "${BRANCH}"

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
If you produce evidence of your work (test outputs, logs, generated reports),
save them under ${ARTIFACTS_DIR}/ with descriptive filenames.

# PR description (REQUIRED)
At the very end of your work, write a complete PR description to:
  ${PR_BODY_PATH}

The PR body MUST include these sections in this exact order:

\`\`\`markdown
Closes #${ISSUE}

## Summary
2-4 sentences explaining what was changed and why. Plain language.

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
      if .type == "assistant" then
        (.message.content[]? | select(.type == "text") | .text),
        (.message.content[]? | select(.type == "tool_use") | "\n[tool: " + .name + "]")
      elif .type == "user" then
        (.message.content[]? | select(.type == "tool_result") | "[tool_result]")
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

# Push la branche
git push -u origin "${BRANCH}"

# Construit le bloc Artifacts
ARTIFACTS_BLOCK=""
if [ -d "${ARTIFACTS_DIR}" ] && [ -n "$(ls -A "${ARTIFACTS_DIR}" 2>/dev/null)" ]; then
  ARTIFACTS_BLOCK=$'\n'
  for file in "${ARTIFACTS_DIR}"/*; do
    [ -e "$file" ] || continue
    filename=$(basename "$file")
    case "$filename" in
      *.png|*.jpg|*.jpeg|*.gif|*.webp)
        ARTIFACTS_BLOCK+="### ${filename}"$'\n'
        ARTIFACTS_BLOCK+="![${filename}](../raw/${BRANCH}/${ARTIFACTS_DIR}/${filename})"$'\n\n'
        ;;
      *.mp4|*.webm|*.mov)
        ARTIFACTS_BLOCK+="### ${filename}"$'\n'
        ARTIFACTS_BLOCK+="<video src=\"../raw/${BRANCH}/${ARTIFACTS_DIR}/${filename}\" controls></video>"$'\n\n'
        ;;
      *)
        ARTIFACTS_BLOCK+="- [\`${filename}\`](../blob/${BRANCH}/${ARTIFACTS_DIR}/${filename})"$'\n'
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

# Crée la PR
PR_URL=$(gh pr create \
  --repo "${REPO}" \
  --base main \
  --head "${BRANCH}" \
  --title "[Michel] ${ISSUE_TITLE}" \
  --body-file "${PR_BODY_FINAL}" \
  --label "agent-generated")

rm "${PR_BODY_FINAL}"

echo ""
echo "✅ Done. PR opened: ${PR_URL}"