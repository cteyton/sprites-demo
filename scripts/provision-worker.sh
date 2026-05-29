#!/usr/bin/env bash
# scripts/provision-worker.sh — one-time provisioning of a Michel WORKER sprite.
#
# A worker is a dedicated, isolated sprite where run-michel.sh actually runs.
# Each worker is its own VM (own filesystem + network), so the app it boots
# (bun on :3000, docker compose, …) never collides with another worker's app.
# The controller (test-michel) dispatches one run per worker at a time.
#
# Usage:
#   bash scripts/provision-worker.sh <worker-name>     # e.g. michel-worker-1
#
# What it does (idempotent-ish — safe to re-run):
#   1. create the worker sprite if it doesn't exist
#   2. install docker + compose (Ubuntu 25.10 universe) as a sprite-env service
#   3. install the claude CLI (native installer)
#   4. inject gh + claude credentials  (piped — secrets never hit stdout)
#   5. upload run-michel.sh + dockerd-runner.sh
#   6. take a `clean` checkpoint and record its id into .env.michel
#
# Credential sources (the laptop is the trust anchor):
#   - gh:     `gh auth token` on this laptop (must be logged in as the bot/owner)
#   - claude: the working .credentials.json on the CONTROLLER sprite (test-michel),
#             streamed worker-side without ever printing.
#
# Re-run after a worker rebuild from base image (checkpoints/services are lost).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

WORKER="${1:?usage: $0 <worker-name>  (e.g. michel-worker-1)}"
ENV_FILE=".env.michel"
SPRITE_WORKDIR="/home/sprite/workspace"
CONTROLLER="${CONTROLLER_SPRITE:-test-michel}"

if ! command -v sprite >/dev/null 2>&1; then
  echo "❌ sprite CLI not found. Install: https://docs.sprites.dev/cli/installation/"
  exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "❌ gh CLI not found on this laptop (needed to source the worker's gh token)."
  exit 1
fi

# Resolve org from scripts/.sprite so workers land in the same org as the controller.
ORG=""
if [ -f scripts/.sprite ]; then
  ORG=$(sed -n 's/.*"organization"[^"]*"\([^"]*\)".*/\1/p' scripts/.sprite | head -1)
fi
ORG_FLAG=()
[ -n "${ORG}" ] && ORG_FLAG=(-o "${ORG}")

SP=(sprite "${ORG_FLAG[@]}" -s "${WORKER}")

echo "==> [1/6] Ensuring worker sprite '${WORKER}' exists (org=${ORG:-default})"
if sprite "${ORG_FLAG[@]}" list 2>/dev/null | grep -qw "${WORKER}"; then
  echo "  '${WORKER}' already exists — reusing."
else
  sprite "${ORG_FLAG[@]}" create "${WORKER}" --skip-console
  echo "  created '${WORKER}'."
fi

echo "==> [2/7] Installing Docker + Compose (Ubuntu 25.10 universe)"
"${SP[@]}" exec -- sudo apt-get update -qq
"${SP[@]}" exec -- sudo apt-get install -y docker.io docker-compose-v2 docker-buildx iptables jq
"${SP[@]}" exec -- sudo usermod -aG docker sprite
# dockerd as a sprite-env service (no systemd — PID1 is tini). See scripts/README.md.
"${SP[@]}" exec -- mkdir -p "${SPRITE_WORKDIR}/scripts"
"${SP[@]}" exec --file "scripts/dockerd-runner.sh:${SPRITE_WORKDIR}/scripts/dockerd-runner.sh" \
  -- chmod +x "${SPRITE_WORKDIR}/scripts/dockerd-runner.sh"
"${SP[@]}" exec -- sprite-env services delete dockerd 2>/dev/null || true
"${SP[@]}" exec -- sprite-env services create dockerd \
  --cmd bash --args "${SPRITE_WORKDIR}/scripts/dockerd-runner.sh" --dir "${SPRITE_WORKDIR}"

echo "==> [3/7] Installing Google Chrome + fonts (headless UI verification)"
# run-michel agents verify UI via the playwright / chrome-devtools MCP servers
# (.mcp.json). Playwright MCP uses the 'chrome' channel → it needs a real
# google-chrome at /opt/google/chrome/chrome. The base image ships neither the
# browser nor sans-serif fonts, so screenshots would fail / render in mono.
"${SP[@]}" exec -- bash -lc '
  set -e
  if [ ! -x /opt/google/chrome/chrome ]; then
    tmp=$(mktemp --suffix=.deb)
    curl -fsSL -o "$tmp" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    sudo apt-get install -y "$tmp"
    rm -f "$tmp"
  fi
  # Sans-serif fonts so system-ui/-apple-system fallback renders properly
  # (see scripts/README.md "Headless rendering fonts"). Self-hosted Inter is
  # bundled by the app itself; these cover the fallback chain + Unicode/bold.
  sudo apt-get install -y fonts-liberation fonts-noto-core fonts-dejavu-core
'
# Pre-warm Playwright browser + ffmpeg into ~/.cache/ms-playwright so the first
# MCP screenshot/video during a run does not race a cold download.
"${SP[@]}" exec -- bash -lc 'npx -y playwright@latest install chromium ffmpeg >/dev/null 2>&1 || true'

echo "==> [4/7] Installing the claude CLI (native installer)"
# bun ships in the base image (/.sprite/bin/bun); only claude needs installing.
"${SP[@]}" exec -- bash -lc 'command -v claude >/dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash'

echo "==> [5/7] Injecting credentials (values never printed)"
# --- gh: stream this laptop's token straight into the worker's gh login ---
if gh auth token >/dev/null 2>&1; then
  gh auth token | "${SP[@]}" exec -- bash -lc 'gh auth login --with-token >/dev/null 2>&1 && gh auth setup-git'
  echo "  gh token injected from laptop."
else
  echo "  ⚠️  laptop gh not logged in — run 'gh auth login' then re-run, or inject manually."
fi
# --- claude: stream the controller's working creds into the worker, no stdout dump ---
#     sprite→sprite relayed through this shell as a pipe; nothing is echoed.
if sprite "${ORG_FLAG[@]}" -s "${CONTROLLER}" exec -- test -f /home/sprite/.claude/.credentials.json 2>/dev/null; then
  sprite "${ORG_FLAG[@]}" -s "${CONTROLLER}" exec -- cat /home/sprite/.claude/.credentials.json \
    | "${SP[@]}" exec -- bash -lc 'mkdir -p ~/.claude && cat > ~/.claude/.credentials.json && chmod 600 ~/.claude/.credentials.json'
  echo "  claude credentials copied from controller '${CONTROLLER}'."
else
  echo "  ⚠️  controller has no ~/.claude/.credentials.json — authenticate claude on a sprite first."
fi

echo "==> [6/7] Uploading run-michel.sh + installing deps"
"${SP[@]}" exec --file "scripts/run-michel.sh:${SPRITE_WORKDIR}/scripts/run-michel.sh" \
  -- chmod +x "${SPRITE_WORKDIR}/scripts/run-michel.sh"

echo "==> [7/7] Taking 'clean' checkpoint"
CKPT_OUT=$("${SP[@]}" checkpoint create --comment "clean: provisioned worker" 2>&1)
echo "${CKPT_OUT}"
# Extract a version id like v1/v2 from the command output.
CKPT_ID=$(echo "${CKPT_OUT}" | grep -oE '\bv[0-9]+\b' | head -1)
if [ -z "${CKPT_ID}" ]; then
  echo "  ⚠️  Could not auto-detect checkpoint id. Run 'sprite -s ${WORKER} checkpoint list' and"
  echo "      set WORKER_CLEAN_CKPT_${WORKER//-/_}=<id> in ${ENV_FILE} manually."
else
  KEY="WORKER_CLEAN_CKPT_${WORKER//-/_}"
  touch "${ENV_FILE}"
  # Ensure the file ends with a newline, else the appended key glues onto the
  # last line (e.g. onto a secret value) and won't be parsed as its own var.
  if [ -s "${ENV_FILE}" ] && [ -n "$(tail -c1 "${ENV_FILE}")" ]; then
    printf '\n' >> "${ENV_FILE}"
  fi
  if grep -q "^${KEY}=" "${ENV_FILE}"; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s|^${KEY}=.*|${KEY}=${CKPT_ID}|" "${ENV_FILE}"
    else
      sed -i "s|^${KEY}=.*|${KEY}=${CKPT_ID}|" "${ENV_FILE}"
    fi
  else
    printf '%s=%s\n' "${KEY}" "${CKPT_ID}" >> "${ENV_FILE}"
  fi
  echo "  recorded ${KEY}=${CKPT_ID} in ${ENV_FILE}"
fi

cat <<EOF

✅ Worker '${WORKER}' provisioned.

Next:
  # smoke-test the worker directly (replace 1 with a real test issue number):
  sprite ${ORG:+-o ${ORG} }-s ${WORKER} exec -- ${SPRITE_WORKDIR}/scripts/run-michel.sh cteyton/sprites-demo 1

  # then wire the controller's dispatcher (see scripts/install-michel-service.sh).
EOF
