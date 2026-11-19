# Playbooks — how to work a challenge

Short, tool-aware playbooks. They encode *order of operations*, not answers:
always prefer an observation from the target over a guess from this file.

## Universal loop

```
1. Identify   — what is this? (file type, service banner, source leak)
2. Bound it   — what must be true for the flag to be reachable?
3. Cheapest test first — the test that eliminates the most hypotheses
4. Record     — raw request/response or command output in /work/notes
5. Only then automate
```

If two consecutive attempts produce no new information, stop and re-identify.
See `fingerprints.md` for product-specific paths and default credentials.

## Web

1. Fingerprint: `httpx -td`, `whatweb`, response headers, favicon hash.
2. Read before fuzzing: `robots.txt`, `/.git/`, source maps, `/actuator`,
   `/config` (Gradio), `.env`, backup archives.
3. Map the app with `katana` + a browser (`playwright`), then `ffuf` on
   directories and `arjun` on parameters.
4. Pick the vulnerability class from the *feature*, not from a scanner:
   file upload → traversal / polyglot; template render → SSTI (`sstimap`);
   URL fetch → SSRF (`ssrfmap`, and blind via `interactsh-client`);
   serialized cookie → deserialization (`ysoserial`, `phpggc`, `fickling`).
5. Confirm impact with a minimal, reproducible request. Keep the raw request in
   `/work/notes/`.

## Pwn

1. `checksec` + `file` + `strings`; note libc version if shipped.
2. Run once to learn the I/O contract; then `gdb-gef` or `r2` for the bug.
3. Mitigations drive the technique:
   - no PIE + no canary → classic ret2text/ret2shellcode
   - canary → leak via format string or partial overwrite
   - PIE → need a leak first (format string, heap, stdout)
   - full RELRO → GOT overwrite unavailable; target hooks/exit/malloc
4. Build the exploit with `pwntools`, keeping a `remote()`/`process()` switch.
5. If the input is parsed by a fuzzer-friendly parser, prefer
   `afl-fuzz`/`libFuzzer` over hand-guessing.

## Reverse

1. `file`, `readelf`/`objdump`, `strings`, then `r2 -A` for structure.
2. `decompile <binary> main` (Ghidra JSON) for readable C — cheap and precise.
3. Windows PE: run under `wine`/`wine32` instead of only reading it.
4. Dynamic: `gdb-gef` for native, `Frida`/`objection` for mobile.
5. If the check is a pure function of the input, try `angr` + `z3` before
   reversing the algorithm by hand.

## Crypto

1. Identify the primitive and the *modulus size* first.
2. Check the cheap families in order: small `e`, common modulus, Wiener,
   Fermat/close primes, shared prime, nonce reuse, low-entropy RNG.
3. Automate only after the family is identified (`RsaCtfTool`, `crypto-attacks`).
4. Lattices: `fpylll`; heavy algebra: `pari-gp`, `singular`, `python-flint`.
5. Verify the recovered plaintext is structured (padding OR flag format).

## Forensics

1. `file`, `exiftool`, `binwalk -e`, `strings -el` for quick wins.
2. PCAP: protocol hierarchy (`tshark -q -z io,phs`), then follow streams;
   carve objects (`tshark --export-objects`).
3. Memory: `vol -f <dump> windows.info` / `linux.bash`, then processes,
   network, and file scan in that order.
4. Disk: `mmls` → `fls -r` → `icat` for deleted files; timeline last.
5. Repair broken captures with `pcapfix` before analysing them.

## Stego

1. `pngcheck -v` / `zsteg` / `stegseek` (with the supplied wordlist).
2. Check LSB planes, appended data after EOF, EXIF, and the alpha channel.
3. Audio: spectrogram first (`sox ... spectrogram`), then LSB.
4. Anything that looks like a QR: `zbarimg`, then re-render at higher scale.

## AD / internal (only in authorized AD-style events)

1. `nmap -sV` → `enum4linux-ng` / `smbclient -L` / `ldapsearch` for the domain.
2. Kerberos: enumerate users (`kerbrute`), then AS-REP roasting
   (`impacket-GetNPUsers`), then Kerberoasting (`impacket-GetUserSPNs`).
3. Credentials → `nxc smb <target> -u ... -p ...` for shares and sessions,
   `certipy` for AD CS, `bloodhound-python` for paths.
4. Lateral movement: `impacket-psexec`/`wmiexec`/`evil-winrm`.
5. Privilege escalation on a host: `linpeas.sh` / `winPEASx64.exe`.

## Multi-flag / multi-stage challenges

- Keep a `stages.md` in `/work`: stage id, what proves it, evidence path.
- Never mark a stage done on a guess — attach the command and its output.
- Reuse artifacts across stages; a leak found for stage 1 is usually the key
  for stage 2.
- If a stage looks impossible, record *why* with evidence before pivoting.
