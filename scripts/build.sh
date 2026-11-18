#!/usr/bin/env bash
# Build the ctfer image locally. On arm64 hosts this goes through QEMU and is
# very slow; prefer the GitHub Actions workflow for full builds.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${IMAGE:-kingfs/ctfer:dev}"
platform="${PLATFORM:-linux/amd64}"

exec docker buildx build \
  --platform "${platform}" \
  --load \
  --tag "${image}" \
  "${root}/docker" \
  "$@"
