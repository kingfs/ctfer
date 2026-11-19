#!/usr/bin/env bash
# Core tool self-test. Optional tools only warn so that a flaky upstream
# download does not make the whole image unusable.
set -u

missing=0

need() {
  if command -v "$1" >/dev/null 2>&1; then
    printf 'ok   %s\n' "$1"
  else
    printf 'MISS %s\n' "$1"
    missing=1
  fi
}

optional() {
  if command -v "$1" >/dev/null 2>&1; then
    printf 'ok   %s\n' "$1"
  else
    printf 'opt  %s (missing)\n' "$1"
  fi
}

echo "== core CLI =="
for t in python3 pip node npm pnpm bun go \
         gdb gdb-multiarch gdbserver nmap masscan tcpdump tshark \
         sqlmap nikto whatweb gobuster ffuf feroxbuster httpx nuclei \
         subfinder katana jq yq rg fd file binwalk patchelf objdump readelf \
         strings socat nc curl git openssl sqlite3 steghide exiftool \
         smbclient rpcclient \
         gcc g++ make nasm r2 hashcat john gp ecm singular \
         checksec ROPgadget vol \
         pwninit chisel websocat grpcurl \
         afl-fuzz clang lld rlwrap hydra pcapfix lftp \
         svmap protoc htpasswd redis-server valgrind \
         pi codex dsh uv pipx semgrep mitmdump dirsearch \
         ctf-tools ctf-manifest ctf-fingerprints ctf-playbooks; do
  need "$t"
done

if [ -f /opt/ctf/MANIFEST.yaml ] && ctf-manifest >/dev/null 2>&1; then
  printf 'ok   /opt/ctf/MANIFEST.yaml (parsed by ctf-manifest)\n'
else
  echo 'MISS /opt/ctf/MANIFEST.yaml or ctf-manifest failed to parse it'
  missing=1
fi

if [ -f /opt/gef.py ]; then
  need gdb-gef
fi

echo "== functional checks =="
if command -v httpx >/dev/null 2>&1; then
  if httpx -version 2>&1 | grep -qi 'projectdiscovery'; then
    printf 'ok   httpx (ProjectDiscovery)\n'
  else
    printf 'MISS httpx resolves to %s, not ProjectDiscovery\n' "$(command -v httpx)"
    missing=1
  fi
fi

if command -v dirsearch >/dev/null 2>&1; then
  if dirsearch --help >/dev/null 2>&1; then
    printf 'ok   dirsearch\n'
  else
    printf 'MISS dirsearch --help failed (pkg_resources missing?)\n'
    missing=1
  fi
fi

if command -v impacket-smbserver >/dev/null 2>&1; then
  if impacket-smbserver -h >/dev/null 2>&1; then
    printf 'ok   impacket-smbserver\n'
  else
    printf 'MISS impacket-smbserver -h failed\n'
    missing=1
  fi
fi

if command -v enum4linux-ng >/dev/null 2>&1; then
  if enum4linux-ng -h 2>&1 | grep -q 'dependend tools are missing'; then
    printf 'MISS enum4linux-ng: missing net/nmblookup (install samba-common-bin)\n'
    missing=1
  else
    printf 'ok   enum4linux-ng deps\n'
  fi
fi

echo "== python modules =="
if ! python3 - <<'PY'
import importlib
mods = [
    "pwn", "angr", "z3", "sympy", "gmpy2", "Crypto", "capstone", "unicorn",
    "keystone", "ropper", "lief", "scapy", "yara", "pefile", "magic",
    "PIL", "qrcode", "androguard", "pexpect", "volatility3", "mitmproxy",
    "impacket", "certipy", "ldap3", "fpylll", "flint",
]
missing = []
for mod in mods:
    try:
        importlib.import_module(mod)
    except Exception as exc:  # noqa: BLE001 - compact report
        missing.append(f"{mod}: {exc}")
if missing:
    print("MISSING python modules:")
    print("\n".join(missing))
    raise SystemExit(1)
print("ok   python core modules")
PY
then
  missing=1
fi

echo "== optional python modules =="
for mod in fickling web3 chepy ddddocr; do
  if python3 -c "import ${mod}" >/dev/null 2>&1; then
    printf 'ok   %s\n' "$mod"
  else
    printf 'opt  %s (missing)\n' "$mod"
  fi
done

echo "== ruby tools =="
if [ "${WITH_RUBY:-1}" = "1" ]; then
  for t in one_gadget seccomp-tools zsteg evil-winrm; do need "$t"; done
else
  echo "skip (WITH_RUBY=0)"
fi

echo "== java tools =="
if [ "${WITH_JAVA:-1}" = "1" ]; then
  for t in java javac jadx apktool ysoserial dex2jar; do need "$t"; done
else
  echo "skip (WITH_JAVA=0)"
fi

echo "== agent runtimes =="
node -v || missing=1
npm -v || missing=1
pnpm -v || missing=1
bun --version || missing=1
go version || missing=1

echo "== optional CLI =="
for t in kubectl aws ligolo-agent ligolo-proxy suo5 stegseek \
         RsaCtfTool xsstrike ssrfmap sstimap jwt_tool commix \
         enum4linux-ng graphw00f phpggc certipy bloodhound-python \
         impacket-smbserver \
         wine wine64 winPEASx64.exe apksigner zipalign ftp \
         interactsh-client mc gitleaks kerbrute linpeas.sh \
         netexec bloodyAD coercer ast-grep js-beautify sshuttle \
         rea rea-agents craft-anything-cli jdwp-shellifier; do
  optional "$t"
done

if [ "${WITH_GHIDRA:-1}" = "1" ]; then
  need ghidra-headless
  # Function-level JSON wrappers are optional: they depend on Ghidra scripts
  # resolving Gson, which can differ between Ghidra releases.
  for t in decompile disassemble; do optional "$t"; done
fi

if [ "${WITH_PLAYWRIGHT:-1}" = "1" ]; then
  echo "== playwright =="
  # Playwright >= 1.50 uses Chrome for Testing's chrome-headless-shell binary.
  if find /opt/playwright -type f \( -name headless_shell -o -name chrome-headless-shell \) 2>/dev/null | grep -q .; then
    printf 'ok   playwright chromium headless shell\n'
  else
    echo 'MISS playwright chromium headless shell'
    missing=1
  fi
fi

echo "== data assets =="
for f in /opt/ctf/MANIFEST.yaml /opt/ctf/TOOLS.md /opt/ctf/fingerprints.md /opt/ctf/playbooks.md; do
  if [ -f "$f" ]; then printf 'ok   %s\n' "$f"; else
    printf 'MISS %s\n' "$f"; missing=1
  fi
done
if [ -d /opt/knowledge ] && [ -n "$(ls -A /opt/knowledge 2>/dev/null)" ]; then
  printf 'ok   /opt/knowledge (%s)\n' \
    "$(find /opt/knowledge -mindepth 1 -maxdepth 1 -printf '%f ' 2>/dev/null)"
else
  echo 'opt  /opt/knowledge (empty or missing)'
fi

if [ "$missing" -eq 0 ]; then
  echo "SELFTEST OK"
else
  echo "SELFTEST FAILED (core tool missing)" >&2
fi
exit "$missing"
