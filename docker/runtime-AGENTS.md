# Agent notes for the ctfer image

You are running inside a CTF workstation container. Most tools are already
installed; **discover before installing**.

## Discover components first

The image ships a machine-readable manifest at `/opt/ctf/MANIFEST.yaml`. Use it
before installing or guessing tool names:

```sh
ctf-manifest                         # categories and counts
ctf-manifest pwn                     # all pwn components, commands and paths
ctf-manifest web                     # web components
ctf-manifest harness                 # pi / codex / dsh / rea
ctf-manifest search jwt              # search names, commands, descriptions
ctf-manifest show gdb                # full manifest entry
ctf-manifest commands ad             # command names as TSV
ctf-manifest json                    # full JSON (pipe to jq)
```

Categories: `base`, `harness`, `web`, `pwn`, `reverse`, `crypto`,
`forensics`, `stego`, `network`, `ad`, `cloud`, `data`, `helpers`.

The human-readable catalog is `ctf-tools`; the manifest is the source of truth
for command names, paths, Python modules and optional/absent tools.

## Layout

| path | contents |
|---|---|
| `/work` | your workspace; persist notes and challenge files here |
| `/work/handouts` | suggested location for downloaded attachments |
| `/opt/ctf/MANIFEST.yaml` | machine-readable component manifest (`ctf-manifest`) |
| `/opt/ctf/TOOLS.md` | human-readable tool catalog (`ctf-tools`) |
| `/opt/ctf/fingerprints.md` | product paths / default credentials (`ctf-fingerprints`) |
| `/opt/ctf/playbooks.md` | per-category playbooks (`ctf-playbooks`) |
| `/opt/knowledge` | HackTricks, PayloadsAllTheThings, InternalAllTheThings (markdown) |
| `/opt/seclists` | wordlists (`$SECLISTS`) |
| `/opt/nuclei-templates` | nuclei templates (`$NUCLEI_TEMPLATES`) |
| `/opt/venv` | Python 3.12 with pwntools/angr/z3/… (first on `PATH`) |
| `/opt/crypto-attacks` | crypto attack library (add to `PYTHONPATH` if needed) |
| `/opt/ghidra` | Ghidra 12.2 (`ghidra-headless`, `decompile`, `disassemble`) |

Search the knowledge bases with `rg` instead of guessing, e.g.
`rg -i 'actuator' /opt/knowledge`. Treat them as hints, never as evidence.

## Operating rules

1. **Evidence first.** A fact must come from a command output, a file, or an
   HTTP response you actually observed. Keep guesses labelled as hypotheses.
   Never "remember" an output you did not produce in this session.
2. **One shell per long-running interaction.** Use `tmux`, a `pwntools` tube,
   or a `pexpect` session for `gdb`, `nc`, servers and shells. Keep at most one
   interactive session alive at a time, and leave the main shell free.
3. **Do not run bare `gdb`, `nc`, `vim` in the foreground** — they block until
   the step times out. Use `gdb-gef -batch -ex ...` for one-shot debugging,
   `tmux`/`pwntools` for sessions, and always bound network calls
   (`nc -w 5`, `curl -m 20`).
4. **Save raw data.** Redirect large scan output to files and grep them; keep
   raw HTTP requests/responses before decoding or replaying. If a command
   produces more than a few hundred lines, write it to `/work/logs/` and read
   the relevant part back with `offset`/`limit`.
5. **Stay in scope.** Only test the challenge target. Do not attack the
   platform, other teams, or infrastructure.
6. **Never bake secrets into files.** API keys and flags belong in environment
   variables or the platform submission tool, not in `/work`.
7. **Prefer the right tool.** Check `ctf-manifest`/`ctf-tools` and
   `command -v` before downloading a replacement. Use `uv tool install`,
   `pipx`, `npm -g`, or `go install` only when something is genuinely missing.
8. **Verify the flag before submitting.** Confirm it matches the announced
   format and that your script reproduces it from scratch; a flag that only
   appeared once is usually a mistake.

## Quick checklists

- **Web**: fingerprint (`whatweb`, `httpx`) → read leaks (`.git`, source maps,
  `ctf-fingerprints`) → content discovery (`ffuf`, `feroxbuster`) →
  parameter/GraphQL discovery → inject (`sqlmap`, `commix`, `sstimap`,
  `dalfox`) → blind channels via `interactsh-client` → browser/DOM (`playwright`).
- **Pwn**: `checksec` → `pwninit`/`patchelf` → `gdb-gef -batch` or `r2` →
  `ROPgadget`/`ropper`/`one_gadget` → `seccomp-tools` → exploit with
  `pwntools`; if a parser is involved, try `afl-fuzz` or a `clang -fsanitize`
  build before hand-reversing.
- **Reverse**: `file`/`readelf`/`strings` → `r2` → `decompile <bin> main` for
  readable C (and `decompile <bin> <func>` for one function) → `angr`/`z3` when
  the check is a pure function; Windows PE: run it under `wine`.
- **Crypto**: identify primitive → check small/public-key/deterministic-nonce
  issues → `RsaCtfTool`, `crypto-attacks`, `fpylll`, `z3`/`sympy`, `chepy`.
- **Forensics**: `file`/`exiftool` → `pcapfix` if the capture is broken →
  `binwalk`/`foremost` → `vol` for memory → `tshark`/`scapy` for PCAP →
  `steghide`/`zsteg`/`stegseek` for stego.
- **AD/network**: `nmap` → `enum4linux-ng`/`smbclient`/`ldap-utils` →
  `nxc`, `impacket-*`, `certipy`, `bloodhound-python`, `kerbrute`,
  `evil-winrm`; escalation with `linpeas.sh`/`winPEASx64.exe`.

## Agents

`pi`, `codex`, and `dsh` are installed. They read API keys from the environment
(`OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, provider-specific variables). DSH can
serve its Web UI:

```sh
# DSH 0.2.2+ rejects wildcard binds; bind the container's interface address.
dsh web --host "$(hostname -i | cut -d" " -f1)" --port 3080 --no-open
```

`rea` (RE A) is an MCP server for reverse engineering; it picks up
`GHIDRA_INSTALL_DIR=/opt/ghidra` automatically and can also be used as a plain
CLI (`rea --help`).
