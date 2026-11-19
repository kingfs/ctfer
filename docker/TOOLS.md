# ctfer — tool catalog

Environment:

| variable | value |
|---|---|
| workdir | `/work` |
| wordlists | `$SECLISTS` (`/opt/seclists`) |
| nuclei templates | `$NUCLEI_TEMPLATES` (`/opt/nuclei-templates`) |
| Playwright browsers | `$PLAYWRIGHT_BROWSERS_PATH` (`/opt/playwright`) |
| knowledge bases | `/opt/knowledge` (HackTricks, PayloadsAllTheThings, InternalAllTheThings) |
| Python | `/opt/venv/bin/python3` (first on `PATH`) |
| Go | `/usr/local/go/bin/go` |
| Ghidra | `$GHIDRA_HOME` (`/opt/ghidra`), also `$GHIDRA_INSTALL_DIR` |
| helpers | `ctf-tools`, `ctf-manifest`, `ctf-selftest`, `ctf-fingerprints`, `ctf-playbooks` |

The image runs as root and is a toolkit, not a security boundary. Use it only
against authorized targets.

## Component manifest

A machine-readable catalog lives at `/opt/ctf/MANIFEST.yaml`. It groups every
component into categories (`base`, `harness`, `web`, `pwn`, `reverse`,
`crypto`, `forensics`, `stego`, `network`, `ad`, `cloud`, `data`, `helpers`)
and records commands, paths, packages, Python modules and optional flags.

```sh
ctf-manifest                         # category summary
ctf-manifest pwn                     # components in one category
ctf-manifest search angr             # search names/commands/descriptions
ctf-manifest show gdb                # full entry
ctf-manifest commands web            # command names as TSV
ctf-manifest json | jq               # machine-readable
```

Agents should query the manifest before installing a replacement tool.

## Runtime toolchains

| runtime | notes |
|---|---|
| Python 3.12 | venv at `/opt/venv`; `pip`, `uv`, `pipx` on `PATH` |
| Node.js 24 | `node`, `npm`, `npx`, `pnpm`, `bun`; DSH needs Node >= 24.9 |
| Go 1.27 | `go`, `gofmt`; `GOPATH=/root/go` |
| JDK 25 (Temurin) | `java`, `javac`, `jadx`, `apktool`, `ysoserial`, `dex2jar` |
| Ruby 3.2 | `one_gadget`, `seccomp-tools`, `zsteg`, `evil-winrm` |
| C/C++ | `gcc`, `g++`, `make`, `cmake`, `gcc-multilib`, `nasm` |
| Clang/LLVM | `clang`, `clang++`, `llvm-config`, `lld` — libFuzzer + ASan/UBSan |

## Agent harnesses and agent-native tools

| command | what it is |
|---|---|
| `pi` | Pi coding agent (`@earendil-works/pi-coding-agent`) |
| `codex` | OpenAI Codex CLI (`@openai/codex`) |
| `dsh` | DeepSeek Harness (`@deepseek-ai/dsh`); `dsh web --host "$(hostname -i)" --port 3080 --no-open` (0.2.2 rejects `0.0.0.0`) |
| `rea` / `rea-agents` | REA — reverse-engineering MCP server + CLI for native/JS/.NET/APK/firmware/PCAP; reuses Ghidra/JADX/binwalk/tshark |
| `craft-anything-cli` | Craft Anything — pure-Rust RE engine + CLI/MCP (early alpha); complements, does not replace, Ghidra |

API keys are **not** baked into the image. Pass them at runtime, e.g.
`-e OPENAI_API_KEY=...`, `-e DEEPSEEK_API_KEY=...`. See `/opt/ctf/AGENTS.md`.

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
| `ssrfmap`, `interactsh-client` | SSRF probes (blind via out-of-band) |
| `mitmproxy` / `mitmdump` | intercepting proxy |
| `playwright` + headless Chromium | SPA, DOM XSS, cookies, screenshots |
| `curl`, `wget`, `jq`, `yq`, `websocat`, `grpcurl` | raw HTTP / WebSocket / gRPC |
| `semgrep`, `ast-grep` | source-assisted sink hunting |
| `js-beautify` | deobfuscate bundled front-end JS / source maps |
| `gitleaks` | secret scanning in repos and extracted sources |
| `fickling` | Python pickle analysis and exploitation |
| `ddddocr` | captcha / screenshot OCR (optional, onnxruntime backend) |
| `htpasswd`, `ab` | credential files / HTTP load |
| `subfinder`, `katana` | subdomain enumeration / crawling |
| `$SECLISTS` | passwords, directories, DNS, usernames |

## Pwn / fuzz

| tool | use |
|---|---|
| `gdb-gef`, `gdb`, `gdb-multiarch`, `gdbserver` | debugging |
| `pwntools` (`pwn`) | ELF/ROP/shellcraft/tubes; `pwn checksec` |
| `checksec`, `patchelf`, `ROPgadget`, `ropper`, `one_gadget`, `seccomp-tools` | mitigation / ROP / seccomp |
| `pwninit` | patch challenge binaries with a supplied libc |
| `radare2` / `r2` | disassembly, patching, r2pipe |
| `angr`, `z3` | symbolic execution / constraints |
| `afl-fuzz` (`afl++`) | coverage-guided fuzzing |
| `clang`, `clang++` | libFuzzer harnesses, ASan/UBSan builds |
| `capstone`, `keystone`, `unicorn`, `lief` | disasm / asm / emulation / ELF-PE |
| `qemu-user`, `qemu-system-x86` | cross-arch and kernel |
| `gcc-multilib`, `gcc -m32`, `nasm` | 32-bit builds / shellcode |
| `strace`, `ltrace`, `valgrind` | tracing / memory errors |
| `binwalk`, `upx` | firmware / packing |
| `rlwrap` | readline for `nc`, shell upgrades, pwn sessions |

## Reverse / mobile

| tool | use |
|---|---|
| `radare2`, `objdump`, `readelf`, `nm`, `strings` | static analysis |
| `angr`, `z3`, `lief` | symbolic / constraint-assisted / binary parsing |
| `ghidra-headless` | raw Ghidra `analyzeHeadless` |
| `decompile <bin> [func]` | Ghidra function-level decompilation → JSON (or just one function's C) |
| `disassemble <bin> [func]` | Ghidra function-level disassembly → JSON |
| `rea` | agent-native RE over MCP (pseudocode, xrefs, call graphs) |
| `craft-anything-cli` | pure-Rust RE engine (early alpha) |
| `wine` | run/debug Windows PE binaries (32- and 64-bit via wine/wine32) |
| `jadx`, `apktool`, `dex2jar`, `apksigner`, `zipalign` | Java/APK decompile, rebuild, sign |
| `androguard` | APK / Manifest / DEX analysis |
| `ysoserial` | Java deserialization payloads |

## Crypto

| tool | use |
|---|---|
| `python3` + `z3`, `sympy`, `gmpy2`, `fpylll`, `python-flint` | math / SMT / lattices |
| `pari-gp` (`gp`), `gmp-ecm` (`ecm`), `pyecm`, `singular` | number theory / factoring |
| `RsaCtfTool` | RSA attack automation |
| `crypto-attacks` | attack library at `/opt/crypto-attacks` |
| `chepy` | CyberChef-style chained encode/decode/crypto operations |
| `web3` | EVM / blockchain interaction |
| `primefac`, `factordb-pycli`, `pycryptodome`, `pyjwt`, `cryptography` | primitives / helpers |
| `openssl`, `xxd`, `bc` | encodings / inspection |
| `hashcat`, `john` | hash cracking (CPU) |

## Forensics / stego

| tool | use |
|---|---|
| `tshark`, `dumpcap`, `tcpdump`, `scapy`, `pcapfix` | capture / analysis / repair |
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
| `nc`/`ncat`, `socat`, `telnet`, `rlwrap` | raw connections / relays / shell upgrades |
| `hydra` | online password brute force |
| `lftp`, `ftp` | FTP/FTPS/SFTP transfers |
| `snmpwalk`, `swaks`, `sngrep`, `mosquitto_pub` | SNMP / mail / SIP / MQTT |
| `svmap`, `svwar`, `svcrack` | SIP discovery / enumeration / cracking |
| `openvpn`, `wg`, `proxychains4`, `sshuttle` | VPN / pivoting |
| `chisel`, `ligolo-agent`/`ligolo-proxy`, `suo5` (+ assets in `/opt/suo5`) | tunnels |
| `impacket-*` | SMB / WinRM / Kerberos / AD |
| `nxc` (netexec), `bloodyAD`, `coercer`, `kerbrute` | AD enumeration / abuse / coercion |
| `certipy`, `bloodhound-python`, `evil-winrm`, `smbclient`, `ldap-utils` | AD |
| `enum4linux-ng` | SMB / AD enumeration |
| `linpeas.sh`, `winPEASx64.exe` | local privilege-escalation enumeration |
| `kubectl`, `aws`, `mc` | Kubernetes / AWS / S3-compatible storage |
| `redis-server` | local Redis to reproduce SSRF/gopher chains |

## Knowledge assets

| path | contents |
|---|---|
| `ctf-fingerprints` → `/opt/ctf/fingerprints.md` | product default paths, default credentials, leak files, cloud metadata |
| `ctf-playbooks` → `/opt/ctf/playbooks.md` | per-category order-of-operations playbooks |
| `/opt/knowledge/hacktricks` | HackTricks (markdown, images stripped) |
| `/opt/knowledge/PayloadsAllTheThings` | payload cheat sheets |
| `/opt/knowledge/InternalAllTheThings` | internal/AD cheat sheets |

Search them with `rg`, e.g. `rg -i 'gopher' /opt/knowledge`.

## Useful wrappers

| command | what it does |
|---|---|
| `ctf-tools` | print this catalog |
| `ctf-manifest` | query the machine-readable component manifest |
| `ctf-selftest` | verify the toolchain |
| `ctf-fingerprints` | print the fingerprint/default-credential notes |
| `ctf-playbooks` | print the methodology playbooks |
| `gdb-gef` | GDB + GEF |
| `ghidra-headless` | Ghidra `analyzeHeadless` |
| `decompile`, `disassemble` | Ghidra function-level JSON wrappers |
| `RsaCtfTool` | RSA attack CLI |
| `xsstrike`, `ssrfmap`, `sstimap`, `jwt_tool`, `commix`, `enum4linux-ng`, `graphw00f`, `phpggc` | tool wrappers |

SageMath, Metasploit and GPU hashcat are intentionally **not** included (size /
licensing / drivers). Install them on demand with `uv`, `pipx`, `npm` or
`go install` if a challenge needs them.
