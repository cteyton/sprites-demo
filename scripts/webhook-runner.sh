#!/usr/bin/env bash
# Wrapper that sources /home/sprite/.michel.env then execs the webhook
# server. Used because `sprite-env services create --env KEY=VAL` is not
# honored reliably; sourcing an env file from disk is portable.

set -euo pipefail

ENV_FILE="${MICHEL_ENV_FILE:-/home/sprite/.michel.env}"

if [ -f "${ENV_FILE}" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
else
  echo "FATAL: env file not found: ${ENV_FILE}" >&2
  exit 1
fi

exec bun /home/sprite/workspace/scripts/webhook-server.ts
