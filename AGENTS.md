# Repository agent guide

This repository builds `kingfs/ctfer`, a CTF + AI-agent Docker image, and
publishes it to Docker Hub from GitHub Actions.

## Layout

| path | purpose |
|---|---|
| `docker/Dockerfile` | multi-stage image build |
| `docker/MANIFEST.yaml` | machine-readable component manifest (source of truth) |
| `docker/ctf-manifest` | manifest query CLI (installed as `ctf-manifest`) |
| `docker/TOOLS.md` | human-readable catalog (`ctf-tools`) |
| `docker/runtime-AGENTS.md` | agent notes copied to `/opt/ctf/AGENTS.md` in the image |
| `docker/install-assets.sh` | GitHub Releases / Ghidra / JDK / wordlists |
| `docker/install-runtime.sh` | gems, wrappers, Playwright, agent CLIs |
| `docker/selftest.sh` | `ctf-selftest` |
| `.github/workflows/docker.yml` | tag -> preflight -> build amd64+arm64 -> smoke test -> multi-arch push |

## Release

Do **not** build the amd64 image on an arm64 host (it goes through QEMU and is
far slower than CI). An **arm64 build is native** there and is the fast way to
validate a change. Otherwise push a semver tag and let GitHub Actions build,
smoke-test and push:

```bash
git push origin main
git tag v0.1.2
git push origin v0.1.2
```

Required repository secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`.
Tag builds push `vX.Y.Z`, `X.Y.Z`, `X.Y`, `X`, `latest`, and `sha-<short>`.
The workflow can be run manually with `push_image=true` to test a push.

## Adding or removing a component

Keep these files consistent:

1. `docker/Dockerfile` / `docker/install-*.sh` — actually install the tool.
2. `docker/MANIFEST.yaml` — category, name, kind, commands, path, package,
   Python modules, optional flag, short description.
3. `docker/TOOLS.md` — add it to the human-readable catalog if it is a
   user-facing tool; update the helpers/wrappers table if needed.
4. `docker/selftest.sh` — add a `need` check for core tools, or leave it
   optional for flaky/source-clone tools.
5. `README.md` — update the image contents/limitations only when the change is
   user-visible.

Manifest categories are fixed: `base`, `harness`, `web`, `pwn`, `reverse`,
`crypto`, `forensics`, `stego`, `network`, `ad`, `cloud`, `data`, `helpers`.
Prefer one primary category; use `also_in` for cross-category tools.

Validate and try the query CLI locally:

```bash
python3 -c 'import yaml; yaml.safe_load(open("docker/MANIFEST.yaml"))'
CTF_MANIFEST=docker/MANIFEST.yaml ./docker/ctf-manifest
CTF_MANIFEST=docker/MANIFEST.yaml ./docker/ctf-manifest search python
CTF_MANIFEST=docker/MANIFEST.yaml ./docker/ctf-manifest show gdb
```

There is no image rebuild required for a manifest/documentation-only change,
but those files only reach the published image on the next tag.

## Rules

- Never commit `.env`, API keys, Docker Hub tokens, flags, or private challenge
  data.
- Only run the shipped tools against authorized targets.
- The image is multi-arch (`linux/amd64`, `linux/arm64`). amd64 is the full
  target; the 32-bit x86 chain (`gcc-multilib`, `libc6-dev-i386`, `wine32`) and
  `pwninit`/`kerbrute`/`craft-anything`/`stegseek` are amd64-only. Gate new
  architecture-specific pieces on `${TARGETARCH}`.
- Run `./scripts/preflight.py --arch both` before tagging: it checks package
  names, Python/npm versions, release assets and manifest drift in ~2 minutes.
- Prefer source-of-truth edits over duplicating package lists in docs.
