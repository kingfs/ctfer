#!/bin/bash
# disassemble — Ghidra headless disassembly to structured JSON.
#
# Adapted from the NYU CTF / D-CIPHER agent tooling (nyuctf_agents,
# docker/multiagent/ghidra_scripts/), which ships DisassembleToJson.java.
#
# Usage:
#   disassemble <binary>              # JSON with every function's listing
#   disassemble <binary> <function>   # just that function's disassembly
#
# Env: GHIDRA_HOME (default /opt/ghidra)
set -uo pipefail

GHIDRA_HOME="${GHIDRA_HOME:-/opt/ghidra}"
GHIDRA_ANALYZE="${GHIDRA_HOME}/support/analyzeHeadless"
GHIDRA_SCRIPTS="${GHIDRA_HOME}/customScripts"
SCRIPT="DisassembleToJson.java"

usage() {
  echo "Usage: disassemble <binary> [function]" >&2
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

JAVA_HOME="${JAVA_HOME:-/opt/jdk-25}" "${GHIDRA_ANALYZE}" \
  "${tmp}" DummyProj \
  -scriptpath "${GHIDRA_SCRIPTS}" \
  -import "${binary}" \
  -postscript "${SCRIPT}" "${tmp}/output.json" \
  -deleteProject \
  > "${tmp}/run.log" 2>&1

if [ ! -f "${tmp}/output.json" ]; then
  echo "Error: Ghidra did not produce disassembly output." >&2
  echo "--- analyzer log (tail) ---" >&2
  tail -n 40 "${tmp}/run.log" >&2
  exit 1
fi

if [ -z "${want_func}" ]; then
  cat "${tmp}/output.json"
  exit 0
fi

python3 - "${tmp}/output.json" "${want_func}" <<'PY'
import json, sys
path, want = sys.argv[1], sys.argv[2]
data = json.load(open(path))
# DisassembleToJson emits a per-function mapping; tolerate either shape.
funcs = data.get("functions", data)
if isinstance(funcs, dict):
    if want in funcs:
        value = funcs[want]
        print(value if isinstance(value, str) else json.dumps(value, indent=2))
        sys.exit(0)
    print(f"Function {want!r} not found.", file=sys.stderr)
    print("Available functions:", file=sys.stderr)
    for name in sorted(funcs)[:400]:
        print(f"  {name}", file=sys.stderr)
    sys.exit(1)
print(json.dumps(data, indent=2))
PY
