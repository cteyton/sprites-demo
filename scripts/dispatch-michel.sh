#!/usr/bin/env bash
# scripts/dispatch-michel.sh — runs on the CONTROLLER sprite.
#
# Replaces the old "run run-michel.sh locally" behaviour. Instead it:
#   1. claims a FREE worker sprite (one run per worker — anti-collision lock)
#   2. runs run-michel.sh INSIDE that worker (sprite exec, blocking)
#   3. restores the worker's `clean` checkpoint (reset the dirty overlay)
#   4. releases the worker so the next queued job can use it
#
# Concurrency model:
#   - Real parallelism = number of workers in WORKER_SPRITES. 3 workers ⇒ 3
#     issues run truly in parallel (separate VMs, no port :3000 collision).
#   - When all workers are busy, this process waits (flock-based queue) until
#     one frees up — no mention is dropped.
#
# Usage (the webhook server spawns this):
#   dispatch-michel.sh <owner/repo> <issue-number>
#
# Env (sourced from /home/sprite/.michel.env, written by install-michel-service.sh):
#   WORKER_SPRITES=michel-worker-1,michel-worker-2,michel-worker-3
#   WORKER_CLEAN_CKPT_michel_worker_1=v1   (per-worker checkpoint id; '-'→'_')
#   CONTROLLER_ORG=cedric-teyton           (optional; -o flag for sprite calls)

set -euo pipefail

REPO="${1:?usage: $0 <owner/repo> <issue-number>}"
ISSUE="${2:?usage: $0 <owner/repo> <issue-number>}"

ENV_FILE="${MICHEL_ENV_FILE:-/home/sprite/.michel.env}"
# shellcheck disable=SC1090
[ -f "${ENV_FILE}" ] && { set -a; source "${ENV_FILE}"; set +a; }

: "${WORKER_SPRITES:?WORKER_SPRITES missing (csv of worker sprite names)}"

ORG_FLAG=()
[ -n "${CONTROLLER_ORG:-}" ] && ORG_FLAG=(-o "${CONTROLLER_ORG}")

# Lock dir: /var/michel/locks if writable, else /tmp (service user perms vary).
LOCK_DIR="/var/michel/locks"
mkdir -p "${LOCK_DIR}" 2>/dev/null || LOCK_DIR="/tmp/michel/locks"
mkdir -p "${LOCK_DIR}"

IFS=',' read -ra WORKERS <<< "${WORKER_SPRITES}"

log() { echo "[$(date -Is)] dispatch issue=${ISSUE} $*"; }

# Look up the clean-checkpoint id for a worker (key: name with '-'→'_').
ckpt_for() {
  local w="$1" key val
  key="WORKER_CLEAN_CKPT_${w//-/_}"
  val="${!key:-}"
  echo "${val}"
}

# Claim the first free worker. Holds an flock on its lock fd for the whole run;
# the lock auto-releases if this process dies (no orphan locks). Returns via the
# globals WORKER and LOCK_FD. Waits (queue) when every worker is busy.
WORKER=""
LOCK_FD=""
claim_worker() {
  local waited=0
  while :; do
    local w fd
    for w in "${WORKERS[@]}"; do
      exec {fd}>"${LOCK_DIR}/${w}.lock"
      if flock -n "${fd}"; then
        WORKER="${w}"; LOCK_FD="${fd}"
        return 0
      fi
      exec {fd}>&-   # not free — close and try next
    done
    [ "${waited}" -eq 0 ] && log "all workers busy — queuing"
    waited=1
    sleep 3
  done
}

release_worker() {
  [ -n "${LOCK_FD}" ] && exec {LOCK_FD}>&- 2>/dev/null || true
}

# Wait until the worker is reachable again after the async restore restart.
wait_worker_up() {
  local w="$1" tries=0
  until sprite "${ORG_FLAG[@]}" -s "${w}" exec -- true >/dev/null 2>&1; do
    tries=$((tries+1))
    if [ "${tries}" -ge 60 ]; then
      log "worker ${w} did not come back after restore (60 tries)"; return 1
    fi
    sleep 2
  done
}

claim_worker
log "claimed worker=${WORKER}"

CKPT="$(ckpt_for "${WORKER}")"

# Always reset + release the worker, even on failure.
cleanup() {
  local rc=$?
  # run-michel.sh works in /tmp/michel-runs and KEEPS the workspace on failure.
  # /tmp is tmpfs (outside the checkpoint overlay), so `restore` does NOT clean
  # it — wipe it explicitly so dirty clones never accumulate across dispatches.
  sprite "${ORG_FLAG[@]}" -s "${WORKER}" exec -- rm -rf /tmp/michel-runs >/dev/null 2>&1 || true
  if [ -n "${CKPT}" ]; then
    # restore resets the home overlay (~/.claude history/cache, ~/.config, git
    # config) so per-run state never drifts. Baked packages (chrome/fonts/claude)
    # live in the checkpoint and survive.
    log "restoring ${WORKER} to clean checkpoint ${CKPT}"
    sprite "${ORG_FLAG[@]}" -s "${WORKER}" restore "${CKPT}" >/dev/null 2>&1 || log "restore failed (rc continues)"
    wait_worker_up "${WORKER}" || true
  else
    log "⚠️ no clean checkpoint configured for ${WORKER} — skipping reset (state will accumulate)"
  fi
  release_worker
  log "released ${WORKER} (run rc=${rc})"
}
trap cleanup EXIT

log "running run-michel.sh in ${WORKER} for ${REPO}#${ISSUE}"
sprite "${ORG_FLAG[@]}" -s "${WORKER}" exec -- \
  /home/sprite/workspace/scripts/run-michel.sh "${REPO}" "${ISSUE}"
log "run-michel.sh finished in ${WORKER}"
