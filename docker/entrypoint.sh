#!/bin/sh
set -e

if [ "$#" -eq 0 ]; then
  printf '%s\n' "ctfer image — 'ctf-tools' prints the catalog, 'ctf-selftest' verifies the toolchain."
  exec bash
fi

exec "$@"
