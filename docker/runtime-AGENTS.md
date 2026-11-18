# Agent notes for the ctfer image

You are running inside a CTF workstation container. Most tools are already
installed; **discover before installing**.

## Layout

| path | contents |
|---|---|
| `/work` | your workspace; persist notes and challenge files here |
| `/work/handouts` | suggested location for downloaded attachments |
| `/opt/ctf/TOOLS.md` | full tool catalog (`ctf-tools`) |
| `/opt/seclists` | wordlists (`$SECLISTS`) |
| `/opt/nuclei-templates` | nuclei templates (`$NUCLEI_TEMPLATES`) |
| `/opt/venv` | Python 3.12 with pwntools/angr/z3/… (first on `PATH`) |
| `/opt/crypto-attacks` | crypto attack library (add to `PYTHONPATH` if needed) |

## Operating rules

1. **Evidence first.** A fact must come from a command output, a file, or an
   HTTP response you actually observed. Keep guesses labelled as hypotheses.
2. **One shell per long-running interaction.** Use `tmux`, or a Python
   `pwntools` tube / `pexpect` session, for `gdb`, `nc`, servers, and shells.
   Do not block the main shell on an interactive process.
3. **Save raw data.** Redirect large scan output to files and grep them; keep
   raw HTTP requests/responses before decoding or replaying.
4. **Stay in scope.** Only test the challenge target. Do not attack the
   platform, other teams, or infrastructure.
5. **Never bake secrets into files.** API keys and flags belong in environment
   variables or the platform submission tool, not in `/work`.
6. **Prefer the right tool.** Check `ctf-tools` and `command -v` before
   downloading a replacement. Use `uv tool install`, `pipx`, `npm -g`, or
   `go install` only when something is genuinely missing.

## Quick checklists

- **Web**: fingerprint (`whatweb`, `httpx`) → content discovery (`ffuf`,
  `feroxbuster`, `dirsearch`) → parameter/GraphQL discovery → inject
  (`sqlmap`, `commix`, `sstimap`, `dalfox`) → source audit (`semgrep`) →
  browser/DOM (`playwright`).
- **Pwn**: `checksec` → `pwninit`/`patchelf` → `gdb-gef` or `r2` →
  `ROPgadget`/`ropper`/`one_gadget` → `seccomp-tools` → exploit with
  `pwntools`.
- **Reverse**: `file`/`readelf`/`strings` → `r2` → `ghidra-headless` for
  decompilation → `angr`/`z3` for automated paths.
- **Crypto**: identify primitive → check small/public-key/deterministic-nonce
  issues → `RsaCtfTool`, `crypto-attacks`, `fpylll`, `z3`/`sympy`.
- **Forensics**: `file`/`exiftool` → `binwalk`/`foremost` → `vol` for memory
  → `tshark`/`scapy` for PCAP → `steghide`/`zsteg`/`stegseek` for stego.
- **AD/network**: `nmap` → `enum4linux-ng`/`smbclient`/`ldap-utils` →
  `impacket-*`, `certipy`, `bloodhound-python`, `evil-winrm`.

## Agents

`pi`, `codex`, and `dsh` are installed. They read API keys from the environment
(`OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, provider-specific variables). DSH can
serve its Web UI:

```sh
dsh web --host 0.0.0.0 --port 3080 --no-open
```
