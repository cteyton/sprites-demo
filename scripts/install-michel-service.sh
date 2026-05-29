#!/usr/bin/env bash
# scripts/install-michel-service.sh
#
# One-time setup on the laptop. Uploads the webhook listener to the sprite,
# registers it as a long-lived service, exposes the sprite URL publicly,
# and prints the GitHub webhook config to paste into repo Settings -> Webhooks.
#
# Re-running is idempotent: the service is recreated, secret is preserved.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ENV_FILE=".env.michel"
SERVICE_NAME="michel-webhook"
SPRITE_WORKDIR="/home/sprite/workspace"
REMOTE_SERVER_PATH="${SPRITE_WORKDIR}/scripts/webhook-server.ts"
REMOTE_RUNNER_PATH="${SPRITE_WORKDIR}/scripts/webhook-runner.sh"
REMOTE_ENV_PATH="/home/sprite/.michel.env"

if ! command -v sprite >/dev/null 2>&1; then
  echo "❌ sprite CLI not found. Install: https://docs.sprites.dev/cli/installation/"
  exit 1
fi

# Resolve target sprite. Prefer $SPRITE env, then scripts/.sprite, else fail loudly.
SPRITE_NAME="${SPRITE:-}"
if [ -z "${SPRITE_NAME}" ] && [ -f scripts/.sprite ]; then
  SPRITE_NAME=$(sed -n 's/.*"sprite"[^"]*"\([^"]*\)".*/\1/p' scripts/.sprite | head -1)
fi
if [ -z "${SPRITE_NAME}" ]; then
  echo "❌ Cannot determine sprite name. Set SPRITE=<name> or create scripts/.sprite."
  exit 1
fi
echo "  target sprite: ${SPRITE_NAME}"
SP=(sprite -s "${SPRITE_NAME}")

echo "==> [1/6] Loading or generating ${ENV_FILE}"
if [ ! -f "${ENV_FILE}" ]; then
  echo "  ${ENV_FILE} not found, bootstrapping from .env.michel.example"
  cp .env.michel.example "${ENV_FILE}"
  SECRET=$(openssl rand -hex 32)
  # macOS sed needs '' after -i
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|^WEBHOOK_SECRET=.*|WEBHOOK_SECRET=${SECRET}|" "${ENV_FILE}"
  else
    sed -i "s|^WEBHOOK_SECRET=.*|WEBHOOK_SECRET=${SECRET}|" "${ENV_FILE}"
  fi
  echo "  generated WEBHOOK_SECRET (saved to ${ENV_FILE})"
fi

# Auto-fix the stale example default if still present.
if grep -q '^ALLOWED_REPOS=cedric-teyton/sprites-demo$' "${ENV_FILE}"; then
  echo "  auto-correcting ALLOWED_REPOS owner: cedric-teyton -> cteyton"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' 's|^ALLOWED_REPOS=cedric-teyton/sprites-demo$|ALLOWED_REPOS=cteyton/sprites-demo|' "${ENV_FILE}"
  else
    sed -i 's|^ALLOWED_REPOS=cedric-teyton/sprites-demo$|ALLOWED_REPOS=cteyton/sprites-demo|' "${ENV_FILE}"
  fi
fi

# shellcheck disable=SC1090
set -a; source "${ENV_FILE}"; set +a

: "${WEBHOOK_SECRET:?missing in ${ENV_FILE}}"
: "${ALLOWED_REPOS:?missing in ${ENV_FILE}}"
ALLOWED_ASSOCIATIONS="${ALLOWED_ASSOCIATIONS:-OWNER,MEMBER,COLLABORATOR}"
MICHEL_SCRIPT="${MICHEL_SCRIPT:-${SPRITE_WORKDIR}/scripts/run-michel.sh}"
DISPATCH_SCRIPT="${DISPATCH_SCRIPT:-${SPRITE_WORKDIR}/scripts/dispatch-michel.sh}"
WORKDIR="${WORKDIR:-${SPRITE_WORKDIR}}"
WORKER_SPRITES="${WORKER_SPRITES:-}"
CONTROLLER_ORG="${CONTROLLER_ORG:-}"
: "${WORKER_SPRITES:?missing in ${ENV_FILE} — set the worker pool (csv). Provision with scripts/provision-worker.sh}"

echo "==> [2/6] Uploading scripts + env file to sprite"
"${SP[@]}" exec -- mkdir -p "${SPRITE_WORKDIR}/scripts"

# Build remote env file from current settings, locally first, then upload.
TMP_ENV=$(mktemp)
trap 'rm -f "${TMP_ENV}"' EXIT
cat > "${TMP_ENV}" <<ENV
WEBHOOK_SECRET=${WEBHOOK_SECRET}
ALLOWED_REPOS=${ALLOWED_REPOS}
ALLOWED_ASSOCIATIONS=${ALLOWED_ASSOCIATIONS}
MICHEL_SCRIPT=${MICHEL_SCRIPT}
DISPATCH_SCRIPT=${DISPATCH_SCRIPT}
WORKDIR=${WORKDIR}
WORKER_SPRITES=${WORKER_SPRITES}
CONTROLLER_ORG=${CONTROLLER_ORG}
PORT=8080
ENV
# Append the per-worker clean-checkpoint ids (WORKER_CLEAN_CKPT_*) verbatim so
# dispatch-michel.sh can map each worker → its reset point.
grep -E '^WORKER_CLEAN_CKPT_' "${ENV_FILE}" >> "${TMP_ENV}" || true

"${SP[@]}" exec \
  --file "scripts/webhook-server.ts:${REMOTE_SERVER_PATH}" \
  --file "scripts/run-michel.sh:${SPRITE_WORKDIR}/scripts/run-michel.sh" \
  --file "scripts/dispatch-michel.sh:${DISPATCH_SCRIPT}" \
  --file "scripts/webhook-runner.sh:${REMOTE_RUNNER_PATH}" \
  --file "${TMP_ENV}:${REMOTE_ENV_PATH}" \
  -- bash -c "chmod +x ${SPRITE_WORKDIR}/scripts/run-michel.sh ${DISPATCH_SCRIPT} ${REMOTE_RUNNER_PATH} && chmod 600 ${REMOTE_ENV_PATH}"

# Give the controller a sprite API token so it can drive worker sprites
# (sprite -s <worker> exec/restore) from inside dispatch-michel.sh.
if [ -n "${SPRITE_TOKEN:-}" ] && [ "${SPRITE_TOKEN}" != "replace-with-sprite-api-token" ]; then
  echo "  setting up sprite auth on the controller"
  "${SP[@]}" exec -- bash -lc "sprite auth setup --token '${SPRITE_TOKEN}'" >/dev/null
else
  echo "  ⚠️  SPRITE_TOKEN not set in ${ENV_FILE} — the controller cannot drive workers until it is."
fi

echo "==> [3/6] Ensuring bun deps installed on sprite"
"${SP[@]}" exec -- bash -c "cd ${SPRITE_WORKDIR} && (bun install || true)"

echo "==> [4/6] (Re)creating sprite-env service '${SERVICE_NAME}'"
# Drop any prior incarnation. Ignore failure (first run, or missing).
"${SP[@]}" exec -- sprite-env services delete "${SERVICE_NAME}" 2>/dev/null || true
# Env vars come from REMOTE_ENV_PATH sourced by the runner; no --env flags here
# because their support is inconsistent across sprite-env versions.
"${SP[@]}" exec -- sprite-env services create "${SERVICE_NAME}" \
  --cmd bash \
  --args "${REMOTE_RUNNER_PATH}"

echo "==> [5/6] Making sprite URL public"
# Note: 'sprite update --url-auth' is the non-deprecated form but does not
# accept '-s <sprite>'; it operates on the active selection. Keep the
# deprecated 'sprite -s NAME url update' since it still works and is
# explicit about the target.
"${SP[@]}" url update --auth public

echo "==> [6/6] Sprite URL & GitHub webhook config"
# 'sprite -s NAME url' prints multi-line:
#   URL: https://...
#   Auth: public
# Extract just the URL line.
SPRITE_URL=$("${SP[@]}" url 2>/dev/null | awk '/^URL:/ {sub(/^URL: */, ""); print; exit}' | tr -d '[:space:]')
WEBHOOK_URL="${SPRITE_URL%/}/github-webhook"

cat <<EOF

✅ Installed. Service: ${SERVICE_NAME}

GitHub webhook config. For each repo in ALLOWED_REPOS (${ALLOWED_REPOS}):
  Open  https://github.com/<owner>/<repo>/settings/hooks  -> Add webhook
  Payload URL:  ${WEBHOOK_URL}
  Content type: application/json
  Secret:       ${WEBHOOK_SECRET}
  SSL:          enabled
  Events:       'Let me select individual events' -> only 'Issue comments'

Smoke check:
  curl -fsS ${SPRITE_URL%/}/healthz   # expect: ok

Service control:
  sprite -s ${SPRITE_NAME} exec -- sprite-env services list
  sprite -s ${SPRITE_NAME} exec -- tail -n 100 /.sprite/logs/services/${SERVICE_NAME}.log
  sprite -s ${SPRITE_NAME} exec -- sprite-env services restart ${SERVICE_NAME}
  sprite -s ${SPRITE_NAME} exec -- sprite-env services stop ${SERVICE_NAME}
  sprite -s ${SPRITE_NAME} exec -- sprite-env services start ${SERVICE_NAME}
EOF
