#!/usr/bin/env bash
# Smoke-test an already built image.
set -euo pipefail

image="${1:-kingfs/ctfer:latest}"
shift || true

echo "== image =="
docker image inspect "${image}" --format 'size: {{.Size}} bytes'

echo "== ctf-selftest =="
docker run --rm "${image}" ctf-selftest

echo "== runtimes and agents =="
docker run --rm "${image}" bash -lc '
  set -e
  node -v
  npm -v
  pnpm -v
  bun --version
  go version
  python3 -V
  uv --version
  pi --version
  codex --version
  dsh --version
'
