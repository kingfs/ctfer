#!/usr/bin/env bash
# Final runtime wiring: Ruby gems, GDB plugins, Java/Python wrappers,
# Playwright, agent CLIs, and cache cleanup.
set -euo pipefail

TARGETARCH="${TARGETARCH:-amd64}"
WITH_JAVA="${WITH_JAVA:-1}"
WITH_RUBY="${WITH_RUBY:-1}"
WITH_PLAYWRIGHT="${WITH_PLAYWRIGHT:-1}"
WITH_GHIDRA="${WITH_GHIDRA:-1}"
PI_VERSION="${PI_VERSION:-1.5.2}"
CODEX_VERSION="${CODEX_VERSION:-0.170.0}"
DSH_VERSION="${DSH_VERSION:-0.2.2-rc.1}"
PNPM_VERSION="${PNPM_VERSION:-12.21.0}"

warn() { printf 'WARN: %s\n' "$*" >&2; }
log() { printf '\n==> %s\n' "$*"; }

# Debian/Ubuntu rename these binaries.
ln -sf /usr/bin/fdfind /usr/local/bin/fd 2>/dev/null || true
if ! command -v upx >/dev/null 2>&1 && [ -x /usr/bin/upx-ucl ]; then
  ln -sf /usr/bin/upx-ucl /usr/local/bin/upx
fi
# Ubuntu ships Singular with a capital S; provide the conventional lowercase
# command as well.
if [ -x /usr/bin/Singular ]; then
  ln -sf /usr/bin/Singular /usr/local/bin/singular
fi

# ---------------------------------------------------------------------------
# Ruby tools (pwn / forensics / AD)
# ---------------------------------------------------------------------------
if [ "$WITH_RUBY" = "1" ]; then
  log "Ruby gems"
  gem install --no-document one_gadget seccomp-tools zsteg evil-winrm \
    || warn "some Ruby gems failed to install"
  gem cleanup >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# GDB + GEF
# ---------------------------------------------------------------------------
if [ -f /opt/gef.py ]; then
  cat >/usr/local/bin/gdb-gef <<'EOF'
#!/bin/sh
exec gdb -q -ex 'source /opt/gef.py' "$@"
EOF
  chmod 0755 /usr/local/bin/gdb-gef
fi

# ---------------------------------------------------------------------------
# Java tool wrappers
# ---------------------------------------------------------------------------
if [ "$WITH_JAVA" = "1" ]; then
  log "Java wrappers"
  if [ -x /opt/jadx/bin/jadx ]; then
    cat >/usr/local/bin/jadx <<'EOF'
#!/bin/sh
exec /opt/jadx/bin/jadx "$@"
EOF
    chmod 0755 /usr/local/bin/jadx
  fi
  if [ -f /opt/apktool.jar ]; then
    cat >/usr/local/bin/apktool <<'EOF'
#!/bin/sh
exec java -jar /opt/apktool.jar "$@"
EOF
    chmod 0755 /usr/local/bin/apktool
  fi
  if [ -f /opt/ysoserial-all.jar ]; then
    cat >/usr/local/bin/ysoserial <<'EOF'
#!/bin/sh
exec java -jar /opt/ysoserial-all.jar "$@"
EOF
    chmod 0755 /usr/local/bin/ysoserial
  fi
  if [ -x /opt/dex2jar/d2j-dex2jar.sh ]; then
    cat >/usr/local/bin/dex2jar <<'EOF'
#!/bin/sh
exec /opt/dex2jar/d2j-dex2jar.sh "$@"
EOF
    chmod 0755 /usr/local/bin/dex2jar
  fi
fi

# ---------------------------------------------------------------------------
# Python CLI wrappers (source clones)
# ---------------------------------------------------------------------------
if [ -d /opt/RsaCtfTool ]; then
  cat >/usr/local/bin/RsaCtfTool <<'EOF'
#!/bin/sh
if [ -f /opt/RsaCtfTool/src/RsaCtfTool/__main__.py ]; then
  PYTHONPATH=/opt/RsaCtfTool/src${PYTHONPATH:+:$PYTHONPATH} exec python3 -m RsaCtfTool "$@"
fi
exec python3 /opt/RsaCtfTool/RsaCtfTool.py "$@"
EOF
  chmod 0755 /usr/local/bin/RsaCtfTool
fi

wrap_py() {
  local name="$1" script="$2"
  [ -f "$script" ] || return 0
  cat >"/usr/local/bin/${name}" <<EOF
#!/bin/sh
exec python3 "${script}" "\$@"
EOF
  chmod 0755 "/usr/local/bin/${name}"
}

wrap_py xsstrike /opt/XSStrike/xsstrike.py
wrap_py ssrfmap /opt/SSRFmap/ssrfmap.py
wrap_py sstimap /opt/SSTImap/sstimap.py
wrap_py jwt_tool /opt/jwt_tool/jwt_tool.py
wrap_py commix /opt/commix/commix.py
wrap_py enum4linux-ng /opt/enum4linux-ng/enum4linux-ng.py
wrap_py graphw00f /opt/graphw00f/graphw00f.py

if [ -f /opt/phpggc/phpggc ]; then
  chmod 0755 /opt/phpggc/phpggc
  ln -sf /opt/phpggc/phpggc /usr/local/bin/phpggc
fi

# impacket 0.13.x installs its example CLIs as standalone .py files in
# /opt/venv/bin instead of importable impacket.examples.<name> modules. Prefer
# those scripts and fall back to nothing if an example is not shipped.
if python3 -c 'import impacket' >/dev/null 2>&1; then
  while read -r script bin; do
    [ -n "$script" ] || continue
    if [ ! -f "/opt/venv/bin/${script}" ]; then
      warn "impacket example ${script} not found; skipping ${bin}"
      continue
    fi
    cat >"/usr/local/bin/${bin}" <<EOF
#!/bin/sh
exec /opt/venv/bin/python3 "/opt/venv/bin/${script}" "\$@"
EOF
    chmod 0755 "/usr/local/bin/${bin}"
  done <<'IMPACKET'
smbserver.py impacket-smbserver
secretsdump.py impacket-secretsdump
psexec.py impacket-psexec
wmiexec.py impacket-wmiexec
smbexec.py impacket-smbexec
atexec.py impacket-atexec
dcomexec.py impacket-dcomexec
smbclient.py impacket-smbclient
rpcdump.py impacket-rpcdump
samrdump.py impacket-samrdump
lookupsid.py impacket-lookupsid
GetNPUsers.py impacket-GetNPUsers
GetUserSPNs.py impacket-GetUserSPNs
ntlmrelayx.py impacket-ntlmrelayx
ticketer.py impacket-ticketer
goldenPac.py impacket-goldenPac
raiseChild.py impacket-raiseChild
mssqlclient.py impacket-mssqlclient
mssqlinstance.py impacket-mssqlinstance
dpapi.py impacket-dpapi
netview.py impacket-netview
regsecrets.py impacket-regsecrets
services.py impacket-services
ping.py impacket-ping
karmaSMB.py impacket-karmaSMB
ntfs-read.py impacket-ntfsread
IMPACKET
fi

# dirsearch normally ships a console script; fall back to the module entry.
if ! command -v dirsearch >/dev/null 2>&1; then
  cat >/usr/local/bin/dirsearch <<'EOF'
#!/bin/sh
exec python3 -m dirsearch "$@"
EOF
  chmod 0755 /usr/local/bin/dirsearch
fi

# ---------------------------------------------------------------------------
# Ghidra headless
# ---------------------------------------------------------------------------
if [ "$WITH_GHIDRA" = "1" ] && [ -x /opt/ghidra/support/analyzeHeadless ]; then
  cat >/usr/local/bin/ghidra-headless <<'EOF'
#!/bin/sh
JAVA_HOME="${JAVA_HOME:-/opt/jdk-25}"
export JAVA_HOME
exec /opt/ghidra/support/analyzeHeadless "$@"
EOF
  chmod 0755 /usr/local/bin/ghidra-headless
fi

# ---------------------------------------------------------------------------
# Playwright headless Chromium (SPA / DOM XSS / screenshots)
# ---------------------------------------------------------------------------
if [ "$WITH_PLAYWRIGHT" = "1" ]; then
  log "Playwright"
  mkdir -p /opt/playwright
  playwright_ok=0
  for attempt in 1 2 3; do
    if PLAYWRIGHT_BROWSERS_PATH=/opt/playwright \
        /opt/venv/bin/playwright install --with-deps --only-shell chromium; then
      playwright_ok=1
      break
    fi
    warn "playwright install attempt ${attempt} failed"
  done
  if [ "$playwright_ok" != "1" ]; then
    warn "playwright browser install failed; ctf-selftest will report it"
  fi
  rm -rf /var/lib/apt/lists/* /var/cache/apt/* 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Agent harnesses: pi, Codex CLI, DeepSeek Harness, plus pnpm
# ---------------------------------------------------------------------------
log "Agent harnesses"
npm install -g --no-fund --no-audit --loglevel=error \
  "@earendil-works/pi-coding-agent@${PI_VERSION}" \
  "@openai/codex@${CODEX_VERSION}" \
  "@deepseek-ai/dsh@${DSH_VERSION}" \
  "pnpm@${PNPM_VERSION}"
npm cache clean --force >/dev/null 2>&1 || true

# AWS CLI and semgrep are installed in isolated uv tool environments: their
# pinned protobuf/urllib3 versions would otherwise break angr and the main venv.
if command -v uv >/dev/null 2>&1; then
  uv tool install --python /usr/bin/python3 awscli || warn "awscli install failed"
  uv tool install --python /usr/bin/python3 semgrep || warn "semgrep install failed"
fi

# ---------------------------------------------------------------------------
# Discovery helpers
# ---------------------------------------------------------------------------
cat >/usr/local/bin/ctf-tools <<'EOF'
#!/bin/sh
exec cat /opt/ctf/TOOLS.md
EOF
chmod 0755 /usr/local/bin/ctf-tools

cat >/usr/local/bin/ctf-selftest <<'EOF'
#!/bin/sh
exec bash /opt/ctf/selftest.sh "$@"
EOF
chmod 0755 /usr/local/bin/ctf-selftest

# ---------------------------------------------------------------------------
# Cleanup: caches must be removed in the same layer that created them.
# ---------------------------------------------------------------------------
log "Cleanup"
rm -rf /tmp/* /var/tmp/* \
       /root/.cache /root/.npm /root/.gem /root/.config/pip \
       /var/lib/gems/*/cache /usr/lib/ruby/gems/*/cache 2>/dev/null || true
rm -rf /var/lib/apt/lists/* /var/cache/apt/* 2>/dev/null || true
find /opt/venv -type d -name '__pycache__' -prune -exec rm -rf '{}' + 2>/dev/null || true
find /opt/venv -name '*.pyc' -delete 2>/dev/null || true

log "Runtime toolchain ready"
python3 -V
node -v
go version
