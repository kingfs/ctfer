# ctfer — tool catalog

Environment:

| variable | value |
|---|---|
| workdir | `/work` |
| wordlists | `$SECLISTS` (`/opt/seclists`) |
| nuclei templates | `$NUCLEI_TEMPLATES` (`/opt/nuclei-templates`) |
| Playwright browsers | `$PLAYWRIGHT_BROWSERS_PATH` (`/opt/playwright`) |
| Python | `/opt/venv/bin/python3` (first on `PATH`) |
| Go | `/usr/local/go/bin/go` |
| Ghidra | `$GHIDRA_HOME` (`/opt/ghidra`) |
| helpers | `ctf-tools` (this file), `ctf-selftest` |

The image runs as root and is a toolkit, not a security boundary. Use it only
against authorized targets.

## Runtime toolchains

| runtime | notes |
|---|---|
| Python 3.12 | venv at `/opt/venv`; `pip`, `uv`, `pipx` on `PATH` |
| Node.js 24 | `node`, `npm`, `npx`, `pnpm`, `bun`; DSH needs Node >= 24.9 |
| Go 1.27 | `go`, `gofmt`; `GOPATH=/root/go` |
| JDK 25 (Temurin) | `java`, `javac`, `jadx`, `apktool`, `ysoserial`, `dex2jar` |
| Ruby 3.2 | `one_gadget`, `seccomp-tools`, `zsteg`, `evil-winrm` |

## Agent harnesses

| command | harness |
|---|---|
| `pi` | Pi coding agent (`@earendil-works/pi-coding-agent`) |
| `codex` | OpenAI Codex CLI (`@openai/codex`) |
| `dsh` | DeepSeek Harness (`@deepseek-ai/dsh`); `dsh web --host 0.0.0.0 --port 3080 --no-open` |

API keys are **not** baked into the image. Pass them at runtime, e.g.
`-e OPENAI_API_KEY=...`, `-e DEEPSEEK_API_KEY=...`, or configure each CLI
interactively. See `/opt/ctf/AGENTS.md` for agent-oriented conventions.

## Web

| tool | use |
|---|---|
| `ffuf`, `feroxbuster`, `gobuster`, `dirsearch` | content/directory discovery |
| `httpx`, `whatweb`, `wafw00f`, `nikto` | probing / fingerprinting / classic checks |
| `nuclei` + `$NUCLEI_TEMPLATES` | template scanning |
| `sqlmap` | SQL injection |
| `commix`, `sstimap`, `dalfox`, `xsstrike` | command injection, SSTI, XSS |
| `jwt_tool` | JWT decode/forge/attack |
| `arjun`, `graphw00f`, `clairvoyance` | parameter / GraphQL discovery |
| `ssrfmap` | SSRF probes |
| `mitmproxy` / `mitmdump` | intercepting proxy |
| `playwright` + headless Chromium | SPA, DOM XSS, cookies, screenshots |
| `curl`, `wget`, `jq`, `yq`, `websocat`, `grpcurl` | raw HTTP / WebSocket / gRPC |
| `semgrep` | source-assisted secret/sink hunting |
| `subfinder`, `katana` | subdomain enumeration / crawling |
| `$SECLISTS` | passwords, directories, DNS, usernames |

## Pwn

| tool | use |
|---|---|
| `gdb-gef`, `gdb`, `gdb-multiarch`, `gdbserver` | debugging |
| `pwntools` (`pwn`) | ELF/ROP/shellcraft/tubes; `pwn checksec` |
| `checksec`, `patchelf`, `ROPgadget`, `ropper`, `one_gadget`, `seccomp-tools` | mitigation / ROP / seccomp |
| `pwninit` | patch challenge binaries with a supplied libc |
| `radare2` / `r2` | disassembly, patching, r2pipe |
| `angr`, `z3` | symbolic execution / constraints |
| `capstone`, `keystone`, `unicorn`, `lief` | disasm / asm / emulation / ELF-PE |
| `qemu-user`, `qemu-user-static`, `qemu-system-x86` | cross-arch and kernel |
| `gcc-multilib`, `g++-multilib`, `nasm` | 32-bit builds / shellcode |
| `strace`, `ltrace`, `binwalk`, `upx` | tracing / firmware / packing |

## Reverse / mobile

| tool | use |
|---|---|
| `radare2`, `objdump`, `readelf`, `nm`, `strings` | static analysis |
| `angr`, `z3`, `lief` | symbolic / constraint-assisted / binary parsing |
| `ghidra-headless` | headless decompiler/analyzer |
| `jadx`, `apktool`, `dex2jar` | Java/APK decompilation and rebuilding |
| `androguard` | APK / Manifest / DEX analysis |
| `ysoserial` | Java deserialization payloads |
| `ctf-selftest` | verify the toolchain |

## Crypto

| tool | use |
|---|---|
| `python3` + `z3`, `sympy`, `gmpy2`, `fpylll`, `python-flint` | math / SMT / lattices |
| `pari-gp` (`gp`), `gmp-ecm` (`ecm`), `singular` | number theory / factoring |
| `RsaCtfTool` | RSA attack automation |
| `crypto-attacks` | attack library at `/opt/crypto-attacks` |
| `primefac`, `factordb-pycli`, `pycryptodome`, `pyjwt`, `cryptography` | primitives / helpers |
| `openssl`, `xxd`, `bc` | encodings / inspection |
| `hashcat`, `john` | hash cracking (CPU) |

## Forensics / stego

| tool | use |
|---|---|
| `tshark`, `dumpcap`, `tcpdump`, `scapy` | packet capture/analysis |
| `volatility3` (`vol`) | memory forensics |
| `sleuthkit` (`fls`, `icat`, `mmls`, `fsstat`), `ewf-tools` | disk / E01 images |
| `foremost`, `testdisk`/`photorec`, `binwalk` | carving / recovery / firmware |
| `steghide`, `zsteg`, `stegseek`, `pngcheck` | image stego |
| `convert`/`identify`, `zbarimg`, `qrencode` | image/QR manipulation |
| `sox`, `ffmpeg` | audio/video stego and spectrograms |
| `exiftool`, `file`, `hashdeep`, `ssdeep` | metadata / hashing |
| `oletools`, `qpdf`, `pdftotext`, `poppler-utils` | Office / PDF |
| `yara` | rule scanning |

## Network / AD / cloud

| tool | use |
|---|---|
| `nmap` (+NSE), `masscan`, `tcpdump`, `tshark` | discovery / scanning |
| `nc`/`ncat`, `socat`, `telnet` | raw connections / relays |
| `snmpwalk`, `swaks`, `sngrep`, `mosquitto_pub` | SNMP / mail / SIP / MQTT |
| `openvpn`, `wg`, `proxychains4` | VPN / pivoting |
| `chisel`, `ligolo-agent`/`ligolo-proxy`, `suo5` | tunnels |
| `impacket-*` | SMB / WinRM / Kerberos / AD |
| `certipy`, `bloodhound-python`, `evil-winrm`, `smbclient`, `ldap-utils` | AD |
| `enum4linux-ng` | SMB / AD enumeration |
| `kubectl`, `aws` | Kubernetes / cloud APIs |

## Useful wrappers

| command | what it does |
|---|---|
| `ctf-tools` | print this catalog |
| `ctf-selftest` | verify the toolchain |
| `gdb-gef` | GDB + GEF |
| `ghidra-headless` | Ghidra `analyzeHeadless` |
| `RsaCtfTool` | RSA attack CLI |
| `xsstrike`, `ssrfmap`, `sstimap`, `jwt_tool`, `commix`, `enum4linux-ng`, `graphw00f`, `phpggc` | tool wrappers |

SageMath, Metasploit, GPU hashcat and Windows reverse-engineering suites are
intentionally **not** included (size / licensing). Install them on demand with
`uv`, `pipx`, `npm` or `go install` if a challenge needs them.
