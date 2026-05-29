#!/usr/bin/env bash
set -euo pipefail
# Launched by the `dockerd` sprite-env service. The sprite has no systemd
# (PID1 is tini), so dockerd cannot be managed by `systemctl` — this wrapper
# runs it directly as the long-lived service process.
#
# dockerd needs root; the service launches this as the `sprite` user, so we
# re-exec under (passwordless) sudo. If services already run as root, the
# sudo is a harmless no-op.
#
# No --containerd flag: there is no systemd to manage a standalone containerd,
# so we let dockerd start and supervise its own containerd instance.
exec sudo dockerd \
  --host=unix:///var/run/docker.sock
