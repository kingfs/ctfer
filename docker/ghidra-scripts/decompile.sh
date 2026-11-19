#!/bin/bash
# decompile — Ghidra headless decompilation to structured JSON.
#
# Adapted from the NYU CTF / D-CIPHER agent tooling (nyuctf_agents,
# docker/multiagent/ghidra_scripts/), which ships DecompileToJson.java.
# Vendored here so the image exposes an agent-friendly, function-level
# decompiler instead of raw analyzeHeadless logs.
#
# Usage:
#   decompile <binary>              # JSON: {"main":..,"functions":{..},"addresses":{..}}
#   decompile <binary> <function>   # just that function's decompiled C
#
# Env: GHIDRA_HOME (default /opt/ghidra)
set -uo pipefail

GHIDRA_HOME="${GHIDRA_HOME:-/opt/ghidra}"
GHIDRA_ANALYZE="${GHIDRA_HOME}/support/analyzeHeadless"
GHIDRA_SCRIPTS="${GHIDRA_HOME}/customScripts"
SCRIPT="DecompileToJson.java"

usage() {
  echo "Usage: decompile <binary> [function]" >&2
  exit 2
}

[ $# -ge 1 ] || usage
binary="$1"
want_func="${2:-}"

if [ ! -f "${binary}" ]; then
  echo "Error: file not found: ${binary}" >&2
  exit 1
fi
if [ ! -x "${GHIDRA_ANALYZE}" ]; then
  echo "Error: Ghidra not installed at ${GHIDRA_HOME} (rebuild with WITH_GHIDRA=1)" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

# Ghidra is chatty on stdout; keep it out of the JSON.
JAVA_HOME="${JAVA_HOME:-/opt/jdk-25}" "${GHIDRA_ANALYZE}" \
  "${tmp}" DummyProj \
  -scriptpath "${GHIDRA_SCRIPTS}" \
  -import "${binary}" \
  -postscript "${SCRIPT}" "${tmp}/output.json" \
  -deleteProject \
  > "${tmp}/run.log" 2>&1

if [ ! -f "${tmp}/output.json" ]; then
  echo "Error: Ghidra did not produce decompilation output." >&2
  echo "--- analyzer log (tail) ---" >&2
  tail -n 40 "${tmp}/run.log" >&2
  exit 1
fi

if [ -z "${want_func}" ]; then
  cat "${tmp}/output.json"
  exit 0
fi

# Function filter: keeps the common "show me main" request small.
python3 - "${tmp}/output.json" "${want_func}" <<'PY'
import json, sys
path, want = sys.argv[1], sys.argv[2]
data = json.load(open(path))
funcs = data.get("functions", {})
main = data.get("main")
if want in ("main", "_start", "entry") and want not in funcs and main:
    want = main
if want not in funcs:
    print(f"Function {want!r} not found.", file=sys.stderr)
    print("Available functions:", file=sys.stderr)
    for name in sorted(funcs):
        print(f"  {name}", file=sys.stderr)
    sys.exit(1)
print(funcs[want])
PY
