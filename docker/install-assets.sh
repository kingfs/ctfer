#!/usr/bin/env bash
# Download release binaries, JARs, wordlists and templates for the ctfer image.
#
# Runs in the `assets` build stage; only /out is copied into the final image.
# GitHub API is intentionally avoided (shared CI IPs are rate-limited); release
# tags come from the /releases/latest redirect and asset names are scraped from
# the expanded-assets HTML.
#
# The `fetch && install || warn` chains below are intentional: the fallback
# only fires when the fetch/extract chain fails, so SC2015 is disabled.
# shellcheck disable=SC2015
#
# Optional:
#   GITHUB_MIRROR=https://ghproxy.example/   prefix for github.com URLs
set -euo pipefail

OUT="${OUT:-/out}"
TARGETARCH="${TARGETARCH:-amd64}"
GITHUB_MIRROR="${GITHUB_MIRROR:-}"
WITH_GHIDRA="${WITH_GHIDRA:-1}"
WITH_JAVA="${WITH_JAVA:-1}"
WITH_SECLISTS="${WITH_SECLISTS:-1}"
WITH_FULL_SECLISTS="${WITH_FULL_SECLISTS:-0}"
WITH_NUCLEI_TEMPLATES="${WITH_NUCLEI_TEMPLATES:-1}"

case "$TARGETARCH" in
  amd64) ARCH=amd64; ARCH_X=x86_64; BUN_ARCH=x64; JDK_ARCH=x64 ;;
  arm64) ARCH=arm64; ARCH_X=aarch64; BUN_ARCH=aarch64; JDK_ARCH=aarch64 ;;
  *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;;
esac

log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

mkdir -p "$OUT/bin" "$OUT/opt" "$OUT/seclists" "$OUT/nuclei-templates"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mirror_url() {
  case "$1" in
    https://github.com/* | https://codeload.github.com/* | https://raw.githubusercontent.com/*)
      printf '%s%s' "$GITHUB_MIRROR" "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

fetch() {
  local url="$1" dest="$2"
  echo "  -> $url"
  curl -fL --retry 8 --retry-all-errors --retry-delay 3 \
    --connect-timeout 30 --max-time 1800 -o "$dest" "$(mirror_url "$url")"
}

latest_tag() {
  local repo="$1" tag
  tag="$(curl -sSIL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 60 \
    "https://github.com/${repo}/releases/latest" 2>/dev/null \
    | tr -d '\r' \
    | awk 'tolower($1)=="location:"{u=$2} END{sub(/.*\/tag\//,"",u); print u}')"
  if [ -z "$tag" ]; then
    tag="$(curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 60 \
      "https://github.com/${repo}/releases.atom" 2>/dev/null \
      | grep -o '<title>[^<]*</title>' | sed -n '2p' | sed 's#</\?title>##g')"
  fi
  printf '%s' "$tag"
}

asset_url() {
  local repo="$1" pattern="$2" tag
  tag="$(latest_tag "$repo")"
  [ -n "$tag" ] || return 1
  curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 60 \
    "https://github.com/${repo}/releases/expanded_assets/${tag}" 2>/dev/null \
    | grep -oE 'href="[^"]*/releases/download/[^"]*"' \
    | sed 's/^href="//;s/"$//' \
    | grep -E "$pattern" | head -n1 \
    | sed 's#^#https://github.com#'
}

fetch_release() {
  local repo="$1" pattern="$2" dest="$3" url
  url="$(asset_url "$repo" "$pattern")" || { warn "no asset: $repo / $pattern"; return 1; }
  fetch "$url" "$dest"
}

# Download a repository tarball without git (git ls-remote is often blocked).
fetch_repo() {
  local repo="$1" dest="$2" branch t
  for branch in main master; do
    t="$(mktemp -d)"
    if curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 900 \
        "$(mirror_url "https://codeload.github.com/${repo}/tar.gz/refs/heads/${branch}")" 2>/dev/null \
        | tar -xz -C "$t" --strip-components=1 2>/dev/null; then
      mkdir -p "$dest"
      cp -a "$t/." "$dest/"
      rm -rf "$t"
      return 0
    fi
    rm -rf "$t"
  done
  warn "cannot fetch repo: $repo"
  return 1
}

install_tar_bin() {
  local archive="$1" name="$2" outname="${3:-$2}" t f
  t="$(mktemp -d)"
  tar -xzf "$archive" -C "$t"
  f="$(find "$t" -type f -name "$name" | head -n1)"
  if [ -z "$f" ]; then
    warn "$name not found in $archive"
    rm -rf "$t"
    return 1
  fi
  install -m 0755 "$f" "$OUT/bin/$outname"
  rm -rf "$t"
}

install_zip_bin() {
  local archive="$1" name="$2" outname="${3:-$2}" p
  p="$(unzip -Z1 "$archive" 2>/dev/null | grep -E "(^|/)${name}$" | head -n1 || true)"
  [ -n "$p" ] || p="$name"
  if ! unzip -p "$archive" "$p" > "$OUT/bin/$outname" 2>/dev/null; then
    warn "$name not found in $archive"
    rm -f "$OUT/bin/$outname"
    return 1
  fi
  chmod 0755 "$OUT/bin/$outname"
}

install_raw_bin() {
  local repo="$1" pattern="$2" outname="$3"
  if fetch_release "$repo" "$pattern" "$OUT/bin/$outname"; then
    chmod 0755 "$OUT/bin/$outname"
  else
    rm -f "$OUT/bin/$outname"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Go/Rust single-binary tools
# ---------------------------------------------------------------------------
log "nuclei / httpx / subfinder / katana"
fetch_release projectdiscovery/nuclei "linux_${ARCH}\\.zip$" "$tmp/nuclei.zip" \
  && install_zip_bin "$tmp/nuclei.zip" nuclei || die "nuclei download failed"
fetch_release projectdiscovery/httpx "linux_${ARCH}\\.zip$" "$tmp/httpx.zip" \
  && install_zip_bin "$tmp/httpx.zip" httpx || die "httpx download failed"
fetch_release projectdiscovery/subfinder "linux_${ARCH}\\.zip$" "$tmp/subfinder.zip" \
  && install_zip_bin "$tmp/subfinder.zip" subfinder || warn "subfinder skipped"
fetch_release projectdiscovery/katana "linux_${ARCH}\\.zip$" "$tmp/katana.zip" \
  && install_zip_bin "$tmp/katana.zip" katana || warn "katana skipped"

log "ffuf / feroxbuster / dalfox"
fetch_release ffuf/ffuf "linux_${ARCH}\\.tar\\.gz$" "$tmp/ffuf.tar.gz" \
  && install_tar_bin "$tmp/ffuf.tar.gz" ffuf || die "ffuf download failed"
if fetch_release epi052/feroxbuster "${ARCH_X}-linux-feroxbuster\\.tar\\.gz$" "$tmp/ferox.tar.gz"; then
  install_tar_bin "$tmp/ferox.tar.gz" feroxbuster || die "feroxbuster extract failed"
elif fetch_release epi052/feroxbuster "${ARCH_X}-linux-feroxbuster\\.zip$" "$tmp/ferox.zip"; then
  install_zip_bin "$tmp/ferox.zip" feroxbuster || die "feroxbuster extract failed"
else
  die "feroxbuster download failed"
fi
if fetch_release hahwul/dalfox "linux-${ARCH_X}\\.tar\\.gz$" "$tmp/dalfox.tar.gz"; then
  install_tar_bin "$tmp/dalfox.tar.gz" dalfox || warn "dalfox extract failed"
else
  warn "dalfox skipped"
fi

log "chisel / ligolo-ng / suo5 / websocat / grpcurl"
fetch_release jpillora/chisel "linux_${ARCH}\\.gz$" "$tmp/chisel.gz" \
  && gunzip -c "$tmp/chisel.gz" > "$OUT/bin/chisel" \
  && chmod 0755 "$OUT/bin/chisel" || warn "chisel skipped"
fetch_release nicocha30/ligolo-ng "agent_.*linux_${ARCH}\\.tar\\.gz$" "$tmp/ligolo-agent.tar.gz" \
  && install_tar_bin "$tmp/ligolo-agent.tar.gz" agent ligolo-agent || warn "ligolo-agent skipped"
fetch_release nicocha30/ligolo-ng "proxy_.*linux_${ARCH}\\.tar\\.gz$" "$tmp/ligolo-proxy.tar.gz" \
  && install_tar_bin "$tmp/ligolo-proxy.tar.gz" proxy ligolo-proxy || warn "ligolo-proxy skipped"
install_raw_bin zema1/suo5 "suo5-linux-${ARCH}$" suo5 || warn "suo5 skipped"
install_raw_bin vi/websocat "websocat\\.${ARCH_X}-unknown-linux-musl$" websocat || warn "websocat skipped"
fetch_release fullstorydev/grpcurl "linux_${ARCH_X}\\.tar\\.gz$" "$tmp/grpcurl.tar.gz" \
  && install_tar_bin "$tmp/grpcurl.tar.gz" grpcurl || warn "grpcurl skipped"

log "pwninit / yq / kubectl"
install_raw_bin io12/pwninit "(^|/)pwninit$" pwninit || warn "pwninit skipped"
install_raw_bin mikefarah/yq "yq_linux_${ARCH}$" yq || warn "yq skipped"
kver="$(curl -fsSL --retry 5 --connect-timeout 20 --max-time 30 https://dl.k8s.io/release/stable.txt 2>/dev/null || true)"
if [ -n "$kver" ]; then
  fetch "https://dl.k8s.io/release/${kver}/bin/linux/${ARCH}/kubectl" "$OUT/bin/kubectl" \
    && chmod 0755 "$OUT/bin/kubectl" || warn "kubectl skipped"
else
  warn "kubectl version lookup failed"
fi

log "bun"
fetch_release oven-sh/bun "bun-linux-${BUN_ARCH}\\.zip$" "$tmp/bun.zip" \
  && install_zip_bin "$tmp/bun.zip" bun || warn "bun skipped"

# stegseek ships an amd64-only Debian package and needs no JVM.
if [ "$TARGETARCH" = "amd64" ]; then
  log "stegseek"
  if fetch_release RickdeJager/stegseek "stegseek_.*\\.deb$" "$tmp/stegseek.deb"; then
    mkdir -p "$tmp/stegseek"
    dpkg-deb -x "$tmp/stegseek.deb" "$tmp/stegseek"
    install -m 0755 "$tmp/stegseek/usr/bin/stegseek" "$OUT/bin/stegseek" \
      || warn "stegseek extract failed"
  else
    warn "stegseek skipped"
  fi
fi

# ---------------------------------------------------------------------------
# Java tools (arch-independent)
# ---------------------------------------------------------------------------
log "jadx / apktool / ysoserial / dex2jar"
if fetch_release skylot/jadx "jadx-.*\\.zip$" "$tmp/jadx.zip"; then
  mkdir -p "$tmp/jadx"
  unzip -q "$tmp/jadx.zip" -d "$tmp/jadx"
  if [ -x "$tmp/jadx/bin/jadx" ]; then
    mv "$tmp/jadx" "$OUT/opt/jadx"
    chmod 0755 "$OUT/opt/jadx/bin/jadx"
  else
    warn "jadx layout unexpected"
  fi
else
  warn "jadx skipped"
fi
fetch_release iBotPeaches/Apktool "apktool_.*\\.jar$" "$OUT/opt/apktool.jar" \
  || warn "apktool skipped"
fetch_release frohoff/ysoserial "ysoserial-all\\.jar$" "$OUT/opt/ysoserial-all.jar" \
  || warn "ysoserial skipped"
if fetch_release pxb1988/dex2jar "dex-tools-v.*\\.zip$" "$tmp/dex2jar.zip"; then
  mkdir -p "$tmp/dex2jar"
  unzip -q "$tmp/dex2jar.zip" -d "$tmp/dex2jar"
  d="$(find "$tmp/dex2jar" -maxdepth 1 -mindepth 1 -type d | head -n1)"
  if [ -n "$d" ]; then
    mv "$d" "$OUT/opt/dex2jar"
    chmod 0755 "$OUT/opt/dex2jar"/*.sh 2>/dev/null || true
  else
    warn "dex2jar layout unexpected"
  fi
else
  warn "dex2jar skipped"
fi

# ---------------------------------------------------------------------------
# GDB + GEF
# ---------------------------------------------------------------------------
log "gef"
mkdir -p "$tmp/gef"
if curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 300 \
     "$(mirror_url "https://codeload.github.com/hugsy/gef/tar.gz/refs/heads/main")" \
     | tar -xz -C "$tmp/gef" --strip-components=1 2>/dev/null; then
  if [ -f "$tmp/gef/gef.py" ]; then
    install -m 0644 "$tmp/gef/gef.py" "$OUT/opt/gef.py"
  else
    warn "gef.py missing from tarball"
  fi
else
  fetch "https://raw.githubusercontent.com/hugsy/gef/main/gef.py" "$OUT/opt/gef.py" \
    && chmod 0644 "$OUT/opt/gef.py" || warn "gef skipped"
fi

# ---------------------------------------------------------------------------
# Temurin JDK 25 (Ghidra 12 requires Java 25; Ubuntu 24.04 only ships 21)
# ---------------------------------------------------------------------------
if [ "$WITH_JAVA" = "1" ] || [ "$WITH_GHIDRA" = "1" ]; then
  log "Temurin JDK 25"
  if curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 900 \
      "https://api.adoptium.net/v3/binary/latest/25/ga/linux/${JDK_ARCH}/jdk/hotspot/normal/eclipse" \
      -o "$tmp/jdk.tar.gz"; then
    mkdir -p "$OUT/opt/jdk-25"
    tar -xzf "$tmp/jdk.tar.gz" -C "$OUT/opt/jdk-25" --strip-components=1
    chmod 0755 "$OUT/opt/jdk-25/bin/java" "$OUT/opt/jdk-25/bin/javac"
    rm -rf "$OUT/opt/jdk-25/lib/src.zip" "$OUT/opt/jdk-25/jmods" \
           "$OUT/opt/jdk-25/man" "$OUT/opt/jdk-25/demo"
  else
    die "Temurin JDK 25 download failed"
  fi
fi

# ---------------------------------------------------------------------------
# Optional: Ghidra (the headless decompiler is the main reverse tool)
# ---------------------------------------------------------------------------
if [ "$WITH_GHIDRA" = "1" ]; then
  log "Ghidra"
  fetch_release NationalSecurityAgency/ghidra "_PUBLIC_.*\\.zip$" "$tmp/ghidra.zip" \
    || die "ghidra download failed"
  mkdir -p "$tmp/ghidra"
  unzip -q "$tmp/ghidra.zip" -d "$tmp/ghidra"
  gpath="$(find "$tmp/ghidra" -type f -name analyzeHeadless | head -n1)"
  [ -n "$gpath" ] || die "ghidra analyzeHeadless not found"
  gdir="$(dirname "$(dirname "$gpath")")"
  mv "$gdir" "$OUT/opt/ghidra"
  chmod 0755 "$OUT/opt/ghidra/support/analyzeHeadless"
  chmod 0755 "$OUT/opt/ghidra/support/"*.sh "$OUT/opt/ghidra/ghidraRun" 2>/dev/null || true
  # Docs/API sources are large and never used at runtime.
  rm -rf "$OUT/opt/ghidra/docs" "$OUT/opt/ghidra/Ghidra/Features"/*/src 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Python/source tools
# ---------------------------------------------------------------------------
log "Python CTF tools (git clones)"
fetch_repo RsaCtfTool/RsaCtfTool "$OUT/opt/RsaCtfTool" || true
fetch_repo s0md3v/XSStrike "$OUT/opt/XSStrike" || true
fetch_repo swisskyrepo/SSRFmap "$OUT/opt/SSRFmap" || true
fetch_repo vladko312/SSTImap "$OUT/opt/SSTImap" || true
fetch_repo ticarpi/jwt_tool "$OUT/opt/jwt_tool" || true
fetch_repo commixproject/commix "$OUT/opt/commix" || true
fetch_repo ldsec/Enum4linux-ng "$OUT/opt/enum4linux-ng" || true
fetch_repo dolevf/graphw00f "$OUT/opt/graphw00f" || true
fetch_repo ambionics/phpggc "$OUT/opt/phpggc" || true
fetch_repo jvdsn/crypto-attacks "$OUT/opt/crypto-attacks" || true

# Trim repo docs/tests that are never used at runtime.
for d in RsaCtfTool XSStrike SSRFmap SSTImap jwt_tool commix enum4linux-ng \
         graphw00f phpggc crypto-attacks; do
  rm -rf "$OUT/opt/$d/.git" "$OUT/opt/$d/.github" "$OUT/opt/$d/docs" \
         "$OUT/opt/$d/test" "$OUT/opt/$d/tests" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# Wordlists and nuclei templates
# ---------------------------------------------------------------------------
if [ "$WITH_SECLISTS" = "1" ]; then
  log "SecLists (selected)"
  SECLISTS_BASE="${SECLISTS_BASE:-https://raw.githubusercontent.com/danielmiessler/SecLists/master}"
  if [ "$WITH_FULL_SECLISTS" = "1" ]; then
    fetch_repo danielmiessler/SecLists "$OUT/seclists" || warn "full SecLists failed"
  else
    for p in \
      "Passwords/Common-Credentials/Pwdb_top-1000.txt" \
      "Passwords/Common-Credentials/Pwdb_top-10000.txt" \
      "Passwords/Common-Credentials/10k-most-common.txt" \
      "Discovery/Web-Content/common.txt" \
      "Discovery/Web-Content/big.txt" \
      "Discovery/Web-Content/raft-medium-directories.txt" \
      "Discovery/Web-Content/raft-medium-files.txt" \
      "Discovery/Web-Content/DirBuster-2007_directory-list-2.3-medium.txt" \
      "Discovery/DNS/subdomains-top1million-5000.txt" \
      "Discovery/DNS/subdomains-top1million-20000.txt" \
      "Usernames/Names/names.txt"; do
      mkdir -p "$OUT/seclists/$(dirname "$p")"
      curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 180 \
        "${SECLISTS_BASE}/${p}" -o "$OUT/seclists/$p" 2>/dev/null \
        || warn "SecLists file skipped: $p"
    done
    # rockyou is ~134 MB raw; ship it gzipped and let the agent gunzip on demand.
    if curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 900 \
        "${SECLISTS_BASE}/Passwords/Leaked-Databases/rockyou.txt.tar.gz" -o "$tmp/rockyou.tar.gz"; then
      mkdir -p "$OUT/seclists/Passwords/Leaked-Databases"
      tar -xzf "$tmp/rockyou.tar.gz" -C "$OUT/seclists/Passwords/Leaked-Databases" 2>/dev/null || true
      if [ -f "$OUT/seclists/Passwords/Leaked-Databases/rockyou.txt" ]; then
        gzip -9 "$OUT/seclists/Passwords/Leaked-Databases/rockyou.txt"
      fi
    else
      warn "rockyou skipped"
    fi
  fi
fi

if [ "$WITH_NUCLEI_TEMPLATES" = "1" ]; then
  log "nuclei-templates"
  fetch_repo projectdiscovery/nuclei-templates "$OUT/nuclei-templates" \
    || warn "nuclei-templates skipped"
  rm -rf "$OUT/nuclei-templates/.git" "$OUT/nuclei-templates/.github" \
         "$OUT/nuclei-templates/docs" 2>/dev/null || true
fi

log "done"
du -sh "$OUT/bin" "$OUT/opt" "$OUT/seclists" "$OUT/nuclei-templates" 2>/dev/null || true
