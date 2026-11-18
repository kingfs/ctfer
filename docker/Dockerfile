# syntax=docker/dockerfile:1.7
#
# ctfer — a batteries-included CTF / AI-agent image.
#
# Multi-stage layout (only the last stage ends up in the image):
#   assets  -> static binaries, JARs, wordlists, nuclei templates, Ghidra
#   golang  -> official Go toolchain
#   python  -> Python 3.12 venv with the CTF Python stack
#   node    -> Node.js 24 runtime copied into the final image
#   runtime -> Ubuntu 24.04 + apt toolchain + the stages above + agent CLIs
#   final   -> sanity check + entrypoint
#
# Build with BuildKit (default in current Docker):
#   docker buildx build --platform linux/amd64 -t kingfs/ctfer:dev docker

ARG UBUNTU_IMAGE=ubuntu:24.04
ARG NODE_IMAGE=node:24-bookworm-slim
ARG GO_VERSION=1.27.4

# ===========================================================================
# 0) small shared base for network downloads
# ===========================================================================
FROM ${UBUNTU_IMAGE} AS download-base

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl wget unzip zip tar xz-utils gzip bzip2 file jq git debconf \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/* \
           /usr/share/doc/* /usr/share/man/* /usr/share/info/* /tmp/*

# ===========================================================================
# 1) assets: third-party release binaries and data files
# ===========================================================================
FROM download-base AS assets

ARG TARGETARCH=amd64
ARG GITHUB_MIRROR=""
ARG WITH_GHIDRA=1
ARG WITH_JAVA=1
ARG WITH_SECLISTS=1
ARG WITH_FULL_SECLISTS=0
ARG WITH_NUCLEI_TEMPLATES=1

COPY install-assets.sh /usr/local/bin/install-assets.sh
RUN chmod 0755 /usr/local/bin/install-assets.sh \
 && TARGETARCH="${TARGETARCH}" \
    GITHUB_MIRROR="${GITHUB_MIRROR}" \
    WITH_GHIDRA="${WITH_GHIDRA}" \
    WITH_JAVA="${WITH_JAVA}" \
    WITH_SECLISTS="${WITH_SECLISTS}" \
    WITH_FULL_SECLISTS="${WITH_FULL_SECLISTS}" \
    WITH_NUCLEI_TEMPLATES="${WITH_NUCLEI_TEMPLATES}" \
    /usr/local/bin/install-assets.sh \
 && rm -f /usr/local/bin/install-assets.sh

# ===========================================================================
# 2) Go toolchain (official tarball, no distribution package lag)
# ===========================================================================
FROM download-base AS golang

ARG TARGETARCH=amd64
ARG GO_VERSION

RUN case "${TARGETARCH}" in \
      amd64) goarch=amd64 ;; \
      arm64) goarch=arm64 ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 900 \
      "https://go.dev/dl/go${GO_VERSION}.linux-${goarch}.tar.gz" -o /tmp/go.tar.gz \
 && tar -xzf /tmp/go.tar.gz -C /usr/local \
 && rm -rf /tmp/go.tar.gz \
           /usr/local/go/test /usr/local/go/api /usr/local/go/doc /usr/local/go/misc

# ===========================================================================
# 3) Python CTF toolchain
# ===========================================================================
FROM download-base AS python

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-dev build-essential pkg-config \
      libffi-dev libssl-dev libgmp-dev libmpfr-dev libmpc-dev \
      libxml2-dev libxslt1-dev zlib1g-dev libmagic-dev libpcap-dev \
      liblzma-dev libyara-dev libjpeg-dev libpng-dev libfreetype6-dev \
      libtiff-dev libwebp-dev libgomp1 \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/* \
           /usr/share/doc/* /usr/share/man/* /usr/share/info/* /tmp/*

COPY requirements-tools.txt /tmp/requirements-tools.txt
RUN python3 -m venv /opt/venv \
 && /opt/venv/bin/pip install --upgrade pip setuptools wheel \
 && /opt/venv/bin/pip install --no-compile -r /tmp/requirements-tools.txt \
 && find /opt/venv -type d -name '__pycache__' -prune -exec rm -rf '{}' + \
 && find /opt/venv -name '*.pyc' -delete \
 && rm -rf /tmp/requirements-tools.txt /root/.cache /root/.cache/pip

# ===========================================================================
# 4) Node.js 24 runtime (required by dsh: node >= 24.9)
# ===========================================================================
FROM ${NODE_IMAGE} AS node

# ===========================================================================
# 5) runtime: Ubuntu toolchain + everything above + agent CLIs
# ===========================================================================
FROM download-base AS runtime

ARG TARGETARCH=amd64
ARG WITH_JAVA=1
ARG WITH_RUBY=1
ARG WITH_PLAYWRIGHT=1
ARG WITH_GHIDRA=1
ARG PI_VERSION=1.5.2
ARG CODEX_VERSION=0.170.0
ARG DSH_VERSION=0.2.2-rc.1
ARG PNPM_VERSION=12.21.0

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC \
    DEBIAN_FRONTEND=noninteractive \
    PATH=/opt/venv/bin:/opt/jdk-25/bin:/usr/local/go/bin:/root/go/bin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin \
    GOROOT=/usr/local/go \
    GOPATH=/root/go \
    GOMODCACHE=/root/go/pkg/mod \
    GOTOOLCHAIN=local \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PLAYWRIGHT_BROWSERS_PATH=/opt/playwright \
    SECLISTS=/opt/seclists \
    WORDLISTS=/opt/seclists \
    NUCLEI_TEMPLATES=/opt/nuclei-templates \
    GHIDRA_HOME=/opt/ghidra \
    JAVA_HOME=/opt/jdk-25 \
    UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    WITH_JAVA="${WITH_JAVA}" \
    WITH_RUBY="${WITH_RUBY}" \
    WITH_PLAYWRIGHT="${WITH_PLAYWRIGHT}" \
    WITH_GHIDRA="${WITH_GHIDRA}"

SHELL ["/bin/bash", "-c"]

# --- apt toolchain ---------------------------------------------------------
# Everything is installed and cleaned in one layer so apt lists/docs never
# survive into the image.
RUN echo "wireshark-common wireshark-common/install-setuid boolean false" \
      | debconf-set-selections \
 && apt-get update \
 && pkgs="ca-certificates curl wget git openssh-client sshpass rsync \
      bash less vim tmux tree procps psmisc lsof htop file debconf \
      jq ripgrep fd-find fzf shellcheck xxd bsdextrautils \
      unzip zip p7zip-full xz-utils zstd bzip2 gzip tar \
      netcat-openbsd ncat socat telnet net-tools dnsutils whois \
      traceroute iproute2 iputils-ping \
      build-essential make cmake pkg-config nasm \
      gcc-multilib g++-multilib libc6-dev-i386 \
      gdb gdb-multiarch gdbserver libc6-dbg strace ltrace \
      binutils patchelf binwalk upx-ucl \
      libssl3t64 libffi8 libgmp10 libmpfr6 libmpc3 libxml2 libxslt1.1 \
      zlib1g libmagic1t64 libpcap0.8t64 libgomp1 libkrb5-dev libsasl2-dev \
      libffi-dev libseccomp-dev zlib1g-dev libyaml-dev libssl-dev \
      libimage-exiftool-perl \
      openssl sqlite3 redis-tools mariadb-client postgresql-client awscli \
      nmap masscan tcpdump tshark \
      openvpn wireguard-tools proxychains4 \
      smbclient ldap-utils snmp swaks sngrep mosquitto-clients \
      yara sleuthkit foremost testdisk ewf-tools hashdeep ssdeep \
      steghide pngcheck sox ffmpeg qpdf poppler-utils \
      imagemagick zbar-tools qrencode \
      radare2 qemu-user qemu-user-static qemu-system-x86 \
      hashcat john pari-gp gmp-ecm singular bc \
      sqlmap nikto whatweb gobuster checksec php-cli" \
 && if [ "${WITH_RUBY}" = "1" ]; then pkgs="$pkgs ruby ruby-dev"; fi \
 && apt-get install -y --no-install-recommends $pkgs \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/* \
           /usr/share/doc/* /usr/share/man/* /usr/share/info/* \
           /usr/share/locale/* /tmp/* /var/tmp/*

# --- copied runtimes and assets -------------------------------------------
COPY --from=python /opt/venv /opt/venv
COPY --from=golang /usr/local/go /usr/local/go
COPY --from=assets /out/bin/ /usr/local/bin/
COPY --from=assets /out/opt/ /opt/
COPY --from=assets /out/seclists/ /opt/seclists/
COPY --from=assets /out/nuclei-templates/ /opt/nuclei-templates/

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/bin/npm /usr/local/bin/npm
COPY --from=node /usr/local/bin/npx /usr/local/bin/npx
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node /usr/local/include/node /usr/local/include/node

# --- agent CLIs, wrappers, Playwright, final cleanup -----------------------
COPY TOOLS.md /opt/ctf/TOOLS.md
COPY runtime-AGENTS.md /opt/ctf/AGENTS.md
COPY selftest.sh /opt/ctf/selftest.sh
COPY entrypoint.sh /usr/local/bin/ctfer-entrypoint
COPY install-runtime.sh /usr/local/bin/install-runtime.sh

RUN chmod 0755 /opt/ctf/selftest.sh /usr/local/bin/ctfer-entrypoint \
              /usr/local/bin/install-runtime.sh \
 && TARGETARCH="${TARGETARCH}" \
    WITH_JAVA="${WITH_JAVA}" \
    WITH_RUBY="${WITH_RUBY}" \
    WITH_PLAYWRIGHT="${WITH_PLAYWRIGHT}" \
    WITH_GHIDRA="${WITH_GHIDRA}" \
    PI_VERSION="${PI_VERSION}" \
    CODEX_VERSION="${CODEX_VERSION}" \
    DSH_VERSION="${DSH_VERSION}" \
    PNPM_VERSION="${PNPM_VERSION}" \
    /usr/local/bin/install-runtime.sh \
 && rm -f /usr/local/bin/install-runtime.sh

WORKDIR /work
RUN mkdir -p /work/handouts /work/.spill /root/.config

# ===========================================================================
# 6) final
# ===========================================================================
FROM runtime AS final

# Never let a build-time proxy leak into the runtime environment.
RUN if env | grep -qiE '^(http|https|all|no)_proxy='; then \
      echo "ERROR: a proxy variable leaked into the image environment" >&2; \
      env | grep -iE '^(http|https|all|no)_proxy=' >&2; \
      exit 1; \
    fi

EXPOSE 3080

ENTRYPOINT ["/usr/local/bin/ctfer-entrypoint"]
CMD ["bash"]
