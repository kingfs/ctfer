#!/usr/bin/env python3
"""Preflight checks for the ctfer image build.

Validates, WITHOUT building the image, the things that have historically broken
a 40-minute CI run:

  1. every apt package name exists in the Ubuntu noble index (amd64, and arm64
     on request, so multi-arch breakage shows up before a tag)
  2. every Python requirement set actually resolves
  3. every npm package/version exists
  4. every GitHub release asset pattern still matches an upstream asset, per arch
  5. selftest tokens are covered by the manifest

Usage:
  ./scripts/preflight.py               # amd64 (the released architecture)
  ./scripts/preflight.py --arch both   # amd64 + arm64, list arm64 gaps
"""

from __future__ import annotations

import argparse
import lzma
import os
import re
import subprocess
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCKER = ROOT / "docker"

ARCHIVE = "http://archive.ubuntu.com/ubuntu/dists"        # amd64, i386
PORTS = "http://ports.ubuntu.com/ubuntu-ports/dists"      # arm64, armhf, ...
SUITE = "noble"
SUITES = (SUITE, f"{SUITE}-updates", f"{SUITE}-security")
COMPONENTS = ("main", "universe", "multiverse", "restricted")

# shell words that appear inside the Dockerfile apt lists but are not packages
NON_PACKAGES = {
    "apt-get", "install", "-y", "--no-install-recommends", "||", "&&", "{", "}",
    "true", "fi", "then", "if", "echo",
}

failures: list[str] = []


def fail(msg: str) -> None:
    failures.append(msg)
    print(f"FAIL {msg}")


def ok(msg: str) -> None:
    print(f"ok   {msg}")


def note(msg: str) -> None:
    print(f"note {msg}")


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def pkg_filter(tokens) -> list[str]:
    out = []
    for tok in tokens:
        if tok in NON_PACKAGES:
            continue
        if not re.fullmatch(r"[a-z0-9][a-z0-9+.-]*(:[a-z0-9]+)?", tok):
            continue
        out.append(tok)
    return out


def apt_names_requested() -> dict[str, str]:
    """(package -> core|optional) parsed from the Dockerfile."""
    text = (DOCKER / "Dockerfile").read_text()
    pkgs: dict[str, str] = {}
    m = re.search(r'pkgs="(.*?)"', text, re.S)
    if m:
        for tok in pkg_filter(m.group(1).split()):
            pkgs[tok] = "core"
    for block in re.finditer(
        r"apt-get install -y --no-install-recommends \\\n(.*?)(?:\n\n|\nRUN |\Z)", text, re.S
    ):
        body = block.group(1)
        # skip the python-stage list: it is a build-only toolchain, not the catalog,
        # and it has already been validated by a successful amd64 build.
        if "python3-dev" in body and "pkgs=" not in body:
            continue
        for line in body.splitlines():
            line = line.strip().rstrip("\\").strip()
            if not line or line.startswith("#"):
                continue
            if not re.fullmatch(r"[a-z0-9][a-z0-9+.:-]*(\s+[a-z0-9][a-z0-9+.:-]*)*", line):
                continue  # shell line (echo/repair/brace), not a package list
            for tok in pkg_filter(line.split()):
                pkgs.setdefault(tok, "optional")
    return pkgs


def fetch_index(arch: str, suite: str, comp: str) -> set[str] | None:
    base = PORTS if arch in {"arm64", "armhf", "ppc64el", "riscv64", "s390x"} else ARCHIVE
    url = f"{base}/{suite}/{comp}/binary-{arch}/Packages.xz"
    try:
        with urllib.request.urlopen(url, timeout=120) as resp:
            raw = lzma.decompress(resp.read())
    except Exception as exc:  # noqa: BLE001
        note(f"index fetch failed: {url} ({exc})")
        return None
    return {
        line.split(": ", 1)[1].strip()
        for line in raw.decode("utf-8", "replace").splitlines()
        if line.startswith("Package: ")
    }


def arch_index(arch: str) -> set[str] | None:
    jobs = [(s, c) for s in SUITES for c in COMPONENTS]
    names: set[str] = set()
    failures_seen = 0
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(fetch_index, arch, s, c) for s, c in jobs]
        for fut in futures:
            got = fut.result()
            if got is None:
                failures_seen += 1
                continue
            names |= got
    if failures_seen:
        note(f"{arch}: {failures_seen}/{len(jobs)} index fetches failed")
    return names or None


def check_apt(arches: list[str], strict_secondary: bool) -> None:
    print(f"\n== apt package names (Ubuntu noble: {', '.join(arches)}) ==")
    wanted = apt_names_requested()
    if not wanted:
        fail("no apt packages parsed from the Dockerfile")
        return
    for idx, arch in enumerate(arches):
        pool = arch_index(arch)
        if pool is None:
            fail(f"could not download any Ubuntu {arch} package index")
            continue
        missing: list[str] = []
        for pkg in sorted(wanted):
            base, _, tag = pkg.partition(":")
            if tag and tag != arch:
                # an explicit foreign architecture (wine32:i386 on amd64)
                continue
            if base not in pool:
                missing.append(f"{base}{':' + tag if tag else ''}")
        if missing:
            msg = f"{arch}: {len(missing)} package(s) not available: {', '.join(missing)}"
            if idx == 0 or strict_secondary:
                fail(msg)
            else:
                note(msg)
        else:
            ok(f"{arch}: all {len(wanted)} apt packages available")


def check_python() -> None:
    print("\n== Python requirement resolution ==")
    env = dict(os.environ, UV_CACHE_DIR="/tmp/preflight-uv-cache")
    core = [
        line.split("#", 1)[0].strip()
        for line in (DOCKER / "requirements-tools.txt").read_text().splitlines()
        if line.split("#", 1)[0].strip()
    ]
    extra = [
        line.split("#", 1)[0].strip()
        for line in (DOCKER / "requirements-extra.txt").read_text().splitlines()
        if line.split("#", 1)[0].strip()
    ]
    Path("/tmp/preflight-core.txt").write_text("\n".join(core) + "\n")
    Path("/tmp/preflight-all.txt").write_text(
        "\n".join(core + extra + ["ddddocr", "onnxruntime"]) + "\n"
    )
    for label, path in (("core", "/tmp/preflight-core.txt"), ("all", "/tmp/preflight-all.txt")):
        res = run(
            ["uv", "pip", "compile", path, "--python-version", "3.12",
             "--no-annotate", "--no-header", "--quiet",
             "-o", f"/tmp/preflight-{label}.out"],
            env=env,
        )
        if res.returncode != 0:
            fail(f"python requirements ({label}) do not resolve:\n{res.stderr.strip()[-1200:]}")
        else:
            ok(f"python requirements ({label}) resolve")


def check_npm() -> None:
    print("\n== npm packages ==")
    text = (DOCKER / "Dockerfile").read_text() + (DOCKER / "install-runtime.sh").read_text()
    versions = dict(re.findall(r"ARG ([A-Z_]+_VERSION)=([0-9][^\s]*)", text))
    for arg, default in re.findall(r'([A-Z_]+_VERSION)="\$\{[A-Z_]+:-([^}]+)\}', text):
        versions.setdefault(arg, default)

    specs: set[str] = set()
    for m in re.finditer(r'"(@?[a-z0-9][a-z0-9._/-]*)@(\$\{[A-Z_]+\}|[0-9][^"\s]*)"', text):
        name, ver = m.group(1), m.group(2)
        if ver.startswith("${"):
            arg = ver[2:-1]
            ver = versions.get(arg, "")
            if not ver:
                fail(f"npm spec {name}@{m.group(2)}: no ARG default for {arg}")
                continue
        specs.add(f"{name}@{ver}")
    specs.add("@ast-grep/cli")

    env = dict(os.environ, npm_config_cache="/tmp/preflight-npm-cache", npm_config_fund="false")
    for spec in sorted(specs):
        res = run(["npm", "view", spec, "version"], env=env)
        if res.returncode != 0 or not res.stdout.strip():
            fail(f"npm package not found: {spec}")
        else:
            ok(f"npm {spec}")


ASSET_RE = re.compile(
    r"(?:fetch_release|install_raw_bin)\s+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)\s+\"([^\"]+)\""
)
ARCH_SUBS = {
    "amd64": {"ARCH": "amd64", "ARCH_X": "x86_64", "BUN_ARCH": "x64",
              "GL_ARCH": "x64", "GRPCURL_ARCH": "x86_64"},
    "arm64": {"ARCH": "arm64", "ARCH_X": "aarch64", "BUN_ARCH": "aarch64",
              "GL_ARCH": "arm64", "GRPCURL_ARCH": "arm64"},
}


def gh_assets(repo: str) -> list[str] | None:
    env = dict(os.environ, XDG_CACHE_HOME="/tmp/preflight-gh")
    res = run(["gh", "api", f"repos/{repo}/releases/latest", "--jq", ".assets[].name"], env=env)
    if res.returncode != 0:
        return None
    return [n for n in res.stdout.splitlines() if n]


def check_assets() -> None:
    print("\n== GitHub release assets (amd64 / arm64) ==")
    text = (DOCKER / "install-assets.sh").read_text()
    seen: set[tuple[str, str]] = set()
    for repo, pattern in ASSET_RE.findall(text):
        if (repo, pattern) in seen:
            continue
        seen.add((repo, pattern))
        assets = gh_assets(repo)
        if assets is None:
            fail(f"cannot list releases for {repo}")
            continue
        result = {}
        for arch, subs in ARCH_SUBS.items():
            raw = pattern.replace("\\\\", "\\")
            for key, value in subs.items():
                raw = raw.replace("${" + key + "}", value)
            try:
                rx = re.compile(raw)
            except re.error as exc:
                fail(f"bad pattern for {repo}: {pattern} ({exc})")
                break
            result[arch] = any(rx.search(a) for a in assets)
        if result.get("amd64") is False:
            fail(f"{repo}: no amd64 asset matches {pattern}")
        elif result.get("arm64") is False:
            note(f"{repo}: no arm64 asset for {pattern} (amd64-only upstream)")
        else:
            ok(f"{repo} ~ {pattern}")


def check_selftest() -> None:
    print("\n== selftest / manifest consistency ==")
    import yaml  # noqa: PLC0415

    manifest = yaml.safe_load((DOCKER / "MANIFEST.yaml").read_text())
    commands: set[str] = set()
    for body in manifest["categories"].values():
        for comp in body["components"]:
            for cmd in comp.get("commands") or []:
                commands.add(cmd.split()[0])

    selftest = (DOCKER / "selftest.sh").read_text()
    tokens: set[str] = set()
    for loop in re.findall(r"for t in (.*?); do", selftest, re.S):
        for tok in loop.split():
            if re.fullmatch(r"[A-Za-z0-9_.+-]+", tok):
                tokens.add(tok)
    missing = sorted(t for t in tokens if t not in commands)
    if missing:
        fail(f"selftest checks tools absent from the manifest: {', '.join(missing)}")
    else:
        ok(f"all {len(tokens)} selftest tokens are in the manifest")


def check_dockerfile_args() -> None:
    """A default on TARGETARCH shadows BuildKit's injected platform value."""
    print("\n== Dockerfile build args ==")
    text = (DOCKER / "Dockerfile").read_text()
    bad = re.findall(r"^ARG (TARGETARCH|TARGETPLATFORM|TARGETOS|TARGETVARIANT)=.+$", text, re.M)
    if bad:
        fail(f"auto platform ARG(s) must be declared without a default: {', '.join(bad)}")
    else:
        ok("platform ARGs are declared without defaults")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--arch", choices=("amd64", "arm64", "both"), default="amd64")
    ap.add_argument("--strict-arm64", action="store_true",
                    help="treat missing arm64 packages as failures")
    args = ap.parse_args()

    arches = ["amd64"] if args.arch == "amd64" else (
        ["arm64"] if args.arch == "arm64" else ["amd64", "arm64"]
    )
    print(f"preflight for {ROOT} (arch: {', '.join(arches)})")

    check_dockerfile_args()
    check_apt(arches, args.strict_arm64)
    check_python()
    check_npm()
    check_assets()
    check_selftest()

    print("\n== summary ==")
    if failures:
        print(f"{len(failures)} failure(s):")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("PREFLIGHT OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
