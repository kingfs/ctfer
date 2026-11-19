# ctfer 内置 CTF 工具集评审报告

- 评审对象：`kingfs/ctfer`，`docker/MANIFEST.yaml`（评审时 v1.0，143 个组件 / 13 个类别；落地后 179 个）
- 对照系：老板 bb 项目（`ctf-harness`、`single-image`）、EnIGMA（ICML 2025）、D-CIPHER（NYU 2025）、NYU CTF Bench、Cybench、InterCode-CTF、Cairn、Strix、CAI、PentestGPT、VulnBot、AutoPenBench、DARPA AIxCC Team Atlanta、XBOW
- 验证方式：本仓库文件逐行阅读；外部项目以 Dockerfile / 配置原文为准（GitHub API 被限流，经 jsDelivr 取原文），二手信息已标注

---

## 1. 结论摘要

1. **总体全面、选型现代**。Web / Pwn / Forensics / Stego / Network 达到一线 CTF 镜像水准，比 bb `single-image` 还多了 Ghidra 12.2 + JDK 25、katana、ffmpeg/ImageMagick、dex2jar、pwninit，以及 manifest 驱动的工具发现（`ctf-manifest`，bb 没有）。**不是"不够充分"，而是有 4 个结构性盲区。**

2. **四个结构性盲区**（不是"少几个小工具"，而是整类能力缺失）：

   | 盲区 | 后果 | 谁有 |
   |---|---|---|
   | **没有 fuzz 能力**（无 AFL++、无 clang/libFuzzer、无 ASan/UBSan） | fuzz 型 pwn/崩溃定位题**完全无法做**；AIxCC 类赛制直接出局 | AIxCC 全部 CRS 的核心 |
   | **不能跑 Windows PE**（无 wine/wine32） | Windows 逆向题只能静态看，无法动态调 | EnIGMA、NYU CTF Bench、D-CIPHER **全部预装 wine** |
   | **Ghidra 只有裸 `ghidra-headless`** | agent 要自己解析 Ghidra 日志；无函数级结构化输出 | EnIGMA/D-CIPHER 都有 `decompile`/`disassemble` → JSON 包装 |
   | **无交互式会话原语** | `gdb`/`nc` 只能靠 tmux 手工糊；无法"主 shell 与调试会话并行" | EnIGMA 的 IAT（debug_*/connect_*）是它 SOTA 的主因 |

3. **rea 与 craft-anything 不是"不适合"，是演化时漏同步**。bb `ctf-harness` 早已把两者做成 opt-in（`WITH_REA=1` / `WITH_CRAFT=1`）。经核查：**rea 应直接内置**（MIT、headless、无 API key、对 dsh/pi/codex 三个 harness 一等支持、深度复用已有 Ghidra/JADX）；**craft-anything 维持 opt-in 观察**（early alpha、旗舰流程依赖 Claude Code、与 rea 重叠）。

4. **相对 bb `single-image` 有约 19 项具体工具缺口 + 2 类知识资产缺口**（fingerprints、playbooks），多数是小体积高收益。

5. **最高性价比的三件事**（都不增加多少体积）：① 搬 HackTricks / PayloadsAllTheThings 知识库落盘；② 补 `decompile`/`disassemble` JSON 包装 + `interactsh-client`；③ 内置 rea。这三项对 agent 解题的边际收益高于再装十个扫描器。

---

## 2. 现有工具集评价

### 2.1 覆盖矩阵（实测）

| 类别 | 组件数 | 覆盖 | 评价 |
|---|---|---|---|
| base | 14 | ✅ 强 | Python 3.12 / Node 24 / Go 1.27 / JDK 25 / Ruby 3.2 / PHP 8.3；gcc-multilib、nasm；**缺 Rust** |
| harness | 3 | ⚠️ | pi / codex / dsh 三个执行体；**缺 agent 工具面（MCP）** |
| web | 26 | ✅ 强 | ffuf/feroxbuster/httpx/nuclei/sqlmap/commix/sstimap/dalfox/xsstrike/jwt_tool/arjun/graphw00f/clairvoyance/ssrfmap/mitmproxy/Playwright/semgrep/subfinder/katana/websocat/grpcurl/phpggc |
| pwn | 17 | ✅ 强 | gdb(+multiarch)+GEF、pwntools、checksec、patchelf、pwninit、ROPgadget/ropper/one_gadget/seccomp-tools、radare2、angr/z3、capstone/keystone/unicorn/lief、qemu-user/system；**缺 fuzz** |
| reverse | 8 | ⚠️ 中上 | Ghidra 12.2 headless、jadx/apktool/dex2jar/androguard/ysoserial/upx；**缺 wine、缺函数级 JSON 包装、缺 .NET 专用（dnSpy 类）** |
| crypto | 8 | ⚠️ 中上 | z3/sympy/gmpy2/fpylll/python-flint、PARI/GP、gmp-ecm、Singular、RsaCtfTool、crypto-attacks、hashcat/john(CPU)；SageMath 刻意排除 |
| forensics | 15 | ✅ 强 | tshark/tcpdump/scapy、volatility3、sleuthkit/ewf、foremost/testdisk、binwalk、exiftool、oletools、qpdf/poppler、yara、ffmpeg/sox、hashdeep/ssdeep |
| stego | 7 | ✅ 强 | steghide/zsteg/stegseek/pngcheck、ImageMagick、zbar/qrencode、sox/ffmpeg |
| network | 19 | ✅ 强 | nmap/masscan、nc/ncat/socat/telnet、DNS/whois、snmp/swaks/sngrep/mosquitto、openvpn/wireguard/proxychains4、chisel/ligolo/suo5 |
| ad | 7 | ⚠️ basics+ | impacket 全家桶、certipy、bloodhound-python、evil-winrm、enum4linux-ng、smbclient/ldap-utils；**缺 netexec/bloodyad/coercer/kerbrute** |
| cloud | 2 | ⚠️ 薄 | 仅 kubectl + aws；**缺 mc（S3/MinIO）** |
| data | 4 | ✅ | 精选 SecLists + gzip rockyou + nuclei-templates + Playwright；**缺知识库** |
| helpers | 3 | ✅ | ctf-manifest / ctf-tools / ctf-selftest；manifest 驱动发现是设计亮点 |

### 2.2 选型是否"最优秀"——是

- 目录发现用 ffuf/feroxbuster 而非 dirb/gobuster（保留 gobuster 做 DNS/vhost 合理）；
- ProjectDiscovery 三件套（httpx/nuclei/katana/subfinder）用官方 release，正确；
- mitmproxy 替代容器内 Burp GUI、Playwright 替代 selenium、volatility3 替代 vol2，全部正确；
- semgrep 放独立 uv tool 环境避免与 angr 的 protobuf 冲突——这是踩过坑的成熟工程；
- **没有为了"看起来全"而堆 Kali 元包**，体积控制克制（对比 Cairn 直接吃 `kali-linux-headless`）。

### 2.3 已知短板（README 已声明，合理）

- `john` 是 Ubuntu 1.9.0 非 jumbo：zip/rar/office/keepass 等哈希缺 `*2john` 提取脚本；
- SageMath 排除（~1.5GB）——但注意 **EnIGMA / NYU / D-CIPHER 三个学术环境全都装了 sagemath**；
- Metasploit 排除（体积+许可）——判断正确，CTF Jeopardy 命中率低；
- GPU hashcat 排除、Windows RE 套件排除——正确。

---

## 3. rea / craft-anything 专项

### 3.1 为什么 manifest 里没有？

**不是评估后拒绝，是演化遗漏。** bb `ctf-harness` 的现状（原文）：

| 工具 | bb 参数 | bb 安装方式 | bb 定位 |
|---|---|---|---|
| REA | `WITH_REA=1`（默认 0） | `npm install -g rea-agents` | RE 用 MCP 服务器，覆盖 native/JS/Electron/.NET/APK/PCAP/固件；与 Ghidra/JADX 协作；早期但活跃 |
| Craft Anything | `WITH_CRAFT=1`（默认 0） | release tarball 取 `craft-anything-cli` | 纯 Rust RE 引擎 + CLI/MCP（320 工具）；early alpha |

bb 的实践分层：`核心工具链（常驻）→ Ghidra headless（rev）→ REA/Craft（agent MCP 高层理解）`。
ctfer 从 ctf-harness 演化时保留了核心链与 Ghidra，**这两个 opt-in 层未同步**。

### 3.2 morluto/rea —— 建议直接内置（不再是 opt-in）

| 项 | 事实 |
|---|---|
| 本质 | 面向 agent 的 RE **MCP 服务器 + CLI**（TypeScript），返回带 evidence/局限说明的结构化结果 |
| 运行时 | Node `^22.23.4 \|\| ^24.22.1 \|\| >=26.12.1`；镜像 node:24 满足 |
| headless / key | ✅ 完全 headless；**自身不需要任何 API key**（模型 key 由宿主 harness 自带） |
| License | MIT |
| harness 对接 | **dsh / pi / codex 一等支持**（dist 内含 `DshCordisPatch.js`）；`rea setup --agent dsh --agent pi --agent codex --yes`（落地前需容器内验证 `rea setup --help`） |
| 复用镜像已有 | Ghidra(`GHIDRA_INSTALL_DIR=/opt/ghidra`)、JADX、apktool、binwalk、tshark、pwntools、objdump、procps、Playwright Chromium；可选外部工具中仅 Rizin/unblob/adb 缺 |
| 活跃度 | 468.7k star，2026-04 创建，调研当日仍有 push；release 约每周（6.9.0，2026-11-12） |
| 体积 | npm tarball 42MB，解包约 181MiB（依赖 bundled）；`frida` 为 optionalDependency，失败不阻塞 |

```bash
# Dockerfile: ARG REA_VERSION=6.9.0（与 PI_VERSION 同级）
npm install -g --no-fund --no-audit --loglevel=error "rea-agents@${REA_VERSION}"
# ENV GHIDRA_INSTALL_DIR=/opt/ghidra   (JAVA_HOME 已有)
```

manifest：主类别 `harness`，`kind: mcp`，`commands: [rea, rea-agents]`，`package: rea-agents`，
`also_in: [reverse, web, forensics]`；selftest 加 `optional rea`。

### 3.3 storytold/craft-anything —— 维持 opt-in（观察）

| 项 | 事实 |
|---|---|
| 本质 | **GUI 桌面应用为主体**（Rust+egui）的"研究→AI 重建→比对"引擎，附 CLI/MCP；检查无需 AI，**重建默认依赖 Claude Code（镜像没有）**，Codex 适配刚起步，不支持 dsh/pi |
| headless | ✅ CLI/MCP 可用（X11/Vulkan 全 dlopen）；release tarball 内含 CLI，免 Rust 工具链 |
| License | MIT OR Apache-2.0 |
| 成熟度 | **early alpha**：2026-10-31 创建（约 3 周），部分引擎"仅对 stand-in 测试过" |
| 体积 | tarball 64MB，解包预计 150–250MB（含无用的 GUI 本体） |
| 重叠 | 与 rea + 现有 Ghidra/JADX/tshark **大面积重叠** |

结论：加 `ARG WITH_CRAFT=0` + release 安装分支（照抄 bb 的 `install-assets.sh` 写法），
校验 SHA256SUMS，只取 `craft-anything-cli`。等其到 stable 再考虑默认开。

---

## 4. 结构性盲区详解（本次最有价值的发现）

### 4.1 fuzz 能力完全缺失

ctfer 有 angr/z3（符号执行）但**没有任何 fuzz 工具**。AIxCC 全部 CRS（含冠军 ATLANTIS）的工具栈核心就是：
`OSS-Fuzz harness + libFuzzer 覆盖率 fuzz`、**Jazzer**（Java，GONDAR 论文称其贡献了 Team Atlanta 最多的 Java 漏洞）、
**SymCC 系 concolic**、**ASan/UBSan**。对 CTF 而言，fuzz 型题目（Google CTF 常见、pwn 找 crash）目前是硬缺口。

```bash
# apt：AFL++ + clang/LLVM（libFuzzer、ASan/UBSan 都在 clang 里）
afl++ clang llvm lld
```

体积约 +400MB（clang/llvm 较大）。建议默认装 `afl++` + `clang`，`llvm` 全套可裁剪。

### 4.2 不能跑 Windows PE

**EnIGMA、NYU CTF Bench、D-CIPHER 三个学术环境全部预装 `wine` + `wine32`**——因为 CSAW/HTB 的 rev 题大量是 PE。
ctfer 目前只能静态分析。

```bash
dpkg --add-architecture i386
apt-get install -y --no-install-recommends wine wine32:i386 wine64
```

体积约 +500MB（i386 架构会连带若干 32 位库）。这是**收益/体积比最高的 rev 补齐项**。

### 4.3 Ghidra 只有裸 headless

EnIGMA 与 D-CIPHER 都有函数级包装：`decompile <binary> [--function_name main]` /
`disassemble <binary> [--function_name main]`，输出**结构化 JSON**（`DecompileToJson.java` /
`DisassembleToJson.java`，D-CIPHER 里后者 11KB，含 `__libc_start_main` 反查 main 等启发式）。

ctfer 的 `ghidra-headless` 要求 agent 自己拼 `-postscript`、自己解析日志——对 LLM 极不友好。
**把 D-CIPHER 的 4 个文件（两个 .java + 两个 .sh）搬过来**，包成 `decompile` / `disassemble` 命令，
成本几乎为零、收益极高（MIT/学术开源，注意保留出处）。

### 4.4 无交互会话原语（EnIGMA 的 IAT）

EnIGMA 的核心贡献不是工具，是**让 agent 能嵌套 REPL**：

| 工具 | 动词 | 实现要点（原文） |
|---|---|---|
| `debug_*` | `debug_start <binary> [args]` / `debug_add_breakpoint` / `debug_step` / `debug_continue` / `debug_exec` / `debug_stop` | gdb 长驻会话，`starti` 起步，`debug_exec` 可跑任意 gdb 命令 |
| `connect_*` | `connect_start <host> <port>` / `connect_sendline` / `connect_exec` / `connect_stop` | pwntools `remote()` 封装，`sendline` 支持 `\xhh` |
| 其它 | `decompile` / `disassemble` / `check_flag` / `submit` / `give_up` | |

配套机制（比工具本身更重要）：

1. **全局只允许 1 个交互会话**（`INTERACTIVE_SESSION`），避免状态爆炸；
2. **主 shell 与交互会话并行**——这才是"专业选手"的工作方式；
3. **blocklist 拦截裸 `gdb`/`vim`/`nohup`**，返回"请用 debug_start/connect_start"，防止模型阻塞到超时或**自造观察**（soliloquizing）；
4. **输出预算**：超阈值落盘 + 返回分页/搜索句柄；`hexdump/xxd/strings` 不摘要，只对反编译类做 LM 摘要；
5. **无输出超时**：超时前已产生的 stdout 必须随错误一并回传（否则爆破脚本永远拿不到中间结果）。

ctfer 已有 `tmux` + `pwntools` + `pexpect`，`runtime-AGENTS.md` 也写了"一个长驻会话"，但**没有工具化**。
建议做一层薄封装（`ctf-session` 或直接写进 AGENTS.md 的强约定），不必上 SWE-agent 整套 ACI。

---

## 5. 增补清单（全部经 MANIFEST 逐项核对）

> 说明：调研子代理多处误报"ctfer 缺失"，本表已用脚本对 `MANIFEST.yaml` 的
> `commands`/`package`/`python_modules` 逐项核对。已确认**已有**、不必重复的包括：
> katana、arjun、jwt_tool、dalfox、ysoserial、dirsearch、nikto、wafw00f、subfinder、
> sshpass、RsaCtfTool、pycryptodome、gmpy2、libc6-dbg、gcc-multilib、gcc-multilib 的 i386 支持。

### P0 — 不做就会丢分（建议默认内置）

| 工具 | 用途 | 类别 | 安装 | 体积 |
|---|---|---|---|---|
| `wine` + `wine32:i386` | 动态跑 Windows PE rev 题 | reverse | apt + `dpkg --add-architecture i386` | ~500MB |
| `afl++` (`afl-fuzz`) | 覆盖率 fuzz / 找 crash | pwn | apt | ~80MB |
| `clang`(+`llvm`) | libFuzzer、ASan/UBSan、编译 harness | pwn/base | apt | ~400MB |
| **Ghidra JSON 包装** `decompile`/`disassemble` | 函数级结构化反编译，LLM 友好 | reverse/helpers | 搬 D-CIPHER 的 4 个文件 | ~0 |
| `interactsh-client` | OOB 带外（盲 SSRF/XSS/命令注入） | web | release（同 PD 三件套） | ~20MB |
| `hydra` | 在线口令爆破（ssh/ftp/http-form/rdp） | network | apt | ~5MB |
| `ddddocr` + `onnxruntime` | 验证码/截图 OCR（web 题刚需） | web | pip，设 `OMP_NUM_THREADS=4` | ~100MB |
| `fickling` | Python pickle 反序列化分析/利用 | web/reverse | pip | ~1MB |
| `rlwrap` | 交互壳升级（nc 反弹 shell、pwn 调试） | pwn/network | apt | ~0.3MB |
| `mc` | S3/MinIO 云存储题 | cloud | release | ~25MB |
| **suo5 服务端资产** | JSP/PHP/ASP.NET/Node endpoint（现有客户端无资产，隧道不闭环） | network | 从 suo5 repo 取 assets | ~1MB |
| `rea` | agent RE MCP 工具面 | harness | npm `rea-agents@6.9.0` | ~181MiB |

### P1 — 高频增益

| 工具 | 用途 | 类别 | 安装 |
|---|---|---|---|
| `chepy` | Python 版 CyberChef（编码/加密/取证链式操作） | crypto/forensics | pip（**D-CIPHER 预装**） |
| `netexec`(nxc) | AD 瑞士军刀（crackmapexec 继任） | ad | uv tool 独立环境 |
| `bloodyad` / `coercer` | AD 写操作 / 强制认证 | ad | pipx |
| `kerbrute` | Kerberos 用户枚举/喷洒 | ad | release |
| `searchsploit`(exploitdb) | 离线 CVE/exp 检索 | web/network | apt |
| `linpeas` / `winpeas` | 提权枚举（A&D/内网题高频） | ad | 单文件 release |
| `apksigner` / `zipalign` | APK 重打包签名/对齐 | reverse | apt |
| `protoc` | protobuf 序列化/逆向 | reverse | apt |
| `web3` | 区块链题 | crypto | pip（bb 钉 8.0.0） |
| `sipvicious`(svmap/svcrack/svwar) | SIP 扫描/爆破（sngrep 只覆盖分析） | network | apt |
| `pcapfix` | 损坏 pcap 修复 | forensics | apt |
| `sshuttle` | 透明代理隧道 | network | apt/pip |
| `lftp` / `ftp` | FTP 客户端 | network | apt |
| `redis-server` | 本地起 Redis 复现 SSRF/gopher 题 | network | apt |
| `apache2-utils`(`htpasswd`,`ab`) | htpasswd 解析、压测 | web | apt |
| `js-beautify` / `ast-grep` | 前端 JS 还原/挖接口（Strix 有） | web | npm/pip |
| `gitleaks` | 源码密钥扫描 | web/forensics | release |
| `pyecm` | 纯 Python ECM（gmp-ecm 已有，冗余度高） | crypto | pip |
| `frida-tools` + `objection` | 移动动态插桩（bb `WITH_MOBILE=1`） | reverse | pip，opt-in |
| `valgrind` | 内存调试 | pwn | apt，opt-in |
| `craft-anything-cli` | 纯 Rust RE 引擎（alpha） | reverse | release，opt-in |

### P1 — 知识资产（零风险、最高性价比）

| 资产 | 内容 | 落地 | 说明 |
|---|---|---|---|
| **HackTricks** + **hacktricks-cloud** | 全品类攻防手册 | `/opt/ctf/knowledge/` | Cairn/Strix 都落盘；**agent 用 `rg` 检索的收益高于再装十个扫描器** |
| **PayloadsAllTheThings** + **InternalAllTheThings** | payload / 内网技巧全集 | 同上 | 同上 |
| `fingerprints.md` | 产品默认路径/默认凭据（Tomcat/Actuator/Gradio/Next.js…） | `/opt/ctf/fingerprints.md` | 从 bb `single-image/` 移植（内容通用，需检查无私有数据） |
| `playbooks/` | 分题型方法论 + 多 flag/多阶段打法 | `/opt/ctf/playbooks/` | 从 bb 移植并**剔除 bb 平台专属 API 内容** |

体积注意：HackTricks 仓库较大（含图片），建议只取 `src/` 的 markdown，删图片与 git 历史。

### P2 / 维持不装（有明确理由）

| 工具 | 判断 |
|---|---|
| `sagemath` | EnIGMA/NYU/D-CIPHER 都装，但 ~1.5GB。现有 `fpylll`+`flint`+`crypto-attacks`+`pari-gp`+`singular` 已覆盖多数；**建议做成 `WITH_SAGE=1` opt-in**（格密码重题再开） |
| `metasploit` | 维持排除：体积大、EULA 麻烦、Jeopardy 命中率低；PT 类比赛另开镜像 |
| `rustc`/`cargo` | D-CIPHER 装了。ctfer 无 Rust，`cargo install` 用不了。建议 `WITH_RUST=1` opt-in（或文档说明用 rustup 现装）；**rea/craft 都是预编译，不刚需** |
| `trivy`/`opengrep`/`bandit`/`govulncheck`/`retire.js` | Strix 的 SCA/SAST 流水线，真实产品向，CTF 收益低 |
| `cloudfox` + 三家云 CLI | Cairn 有，CTF 基本用不上 |
| `vulhub`/`exphub`/`Awesome-POC` | 靶场复现用，与大仓库体积不成比例 |
| `naabu` | masscan+nmap 已覆盖 |
| `gospider` | katana 已覆盖 |
| `dirb`/`wfuzz`/`wapiti` | ffuf/feroxbuster/nuclei 已覆盖 |
| `Kali 元包`（`kali-linux-headless`） | **坚决不学 Cairn**：一次拉几百个包，镜像膨胀且版本不可控 |

---

## 6. 建议的实施顺序

**第一批（低风险、高收益，可下一个 tag 就发）**
1. 知识资产：HackTricks/PayloadsAllTheThings 落盘 + `fingerprints.md` + `playbooks/`（manifest `data` 类登记）
2. rea 内置（`ARG REA_VERSION`，manifest `harness` + `also_in`）
3. Ghidra JSON 包装：`decompile` / `disassemble`（搬 D-CIPHER 脚本，manifest `reverse`）
4. 小件补齐：`rlwrap`、`hydra`、`pcapfix`、`lftp`、`htpasswd`、`suo5` 资产、`mc`、`interactsh-client`

**第二批（改变能力边界）**
5. `wine` + `wine32:i386`
6. `afl++` + `clang`（fuzz 能力）
7. `chepy`、`ddddocr`+`onnxruntime`、`fickling`、`web3`、`protoc`
8. AD：`netexec`（独立 uv 环境）、`bloodyad`、`coercer`、`kerbrute`

**第三批（opt-in 构建参数）**
9. `WITH_SAGE=1`、`WITH_RUST=1`、`WITH_MOBILE=1`（frida/objection）、`WITH_CRAFT=1`、`WITH_VALGRIND=1`

**机制层（不装包，改文档/包装）**
10. 在 `runtime-AGENTS.md` 固化：主 shell 与调试/连接会话并行、全局单会话、禁止裸 `gdb`/`nc` 阻塞、
    大输出落盘分页、超时保留部分 stdout、`check_flag` 式提交前自校验

每批需同步：`Dockerfile`/`install-*.sh` → `MANIFEST.yaml` → `TOOLS.md` → `selftest.sh` → `README.md`（用户可见时）。

---

## 7. 落地注意事项

- 遵循 `AGENTS.md`：manifest 类别固定，一个主类别 + `also_in`；不要本地全量构建（arm64 QEMU 慢），改完打 tag 走 CI。
- **Python 依赖冲突是历史坑**：`semgrep`/`awscli` 已走独立 uv tool。新增大依赖（`netexec`、`sagemath`、`ddddocr`）
  建议同样隔离，避免破坏 angr/pwntools 的 protobuf/urllib3 约束。
- `wine` 需要 `dpkg --add-architecture i386`，会让 apt 层变大；建议单独一个 `RUN` 层并清理。
- `ddddocr`/`onnxruntime`：按 bb 经验设 `OMP_NUM_THREADS` 上限，否则在宿主机上会按 CPU 核数爆线程。
- 知识库落盘前确认 license 与体积，剔除 git 历史与图片。
- `rea` 迭代快：钉版本，CI 定期升级时跑一次 `rea --version` 与 `ctf-selftest`。
- 学术项目脚本（Ghidra JSON 包装）移植时保留出处与 license 声明。

---

## 8. 九个参照项目逐项映射（他们给 agent 什么工具 / 我们能吸收什么）

> 用途：直接回答"顶级开源项目会让 agent 用哪些厉害工具，我们缺不缺"。
> "镜像已有"列按 `MANIFEST.yaml` 实测；"BB 可借鉴"列针对老板的 bb（非本镜像）。

| 项目 | agent 实际拿到的工具 | 镜像已有 | 建议内置 | BB 可借鉴的机制 |
|---|---|---|---|---|
| **EnIGMA**（ICML25） | gdb（`debug_start/add_breakpoint/step/continue/exec/stop`）、pwntools `remote()` 封装（`connect_start/sendline/exec`）、Ghidra `decompile`/`disassemble`→JSON、`check_flag`/`submit`/`give_up`；预装 wine、sagemath、RsaCtfTool、tshark、binwalk | gdb/GEF ✅、pwntools ✅、Ghidra 裸 headless ⚠️、其余 ❌ | **wine**、**Ghidra JSON 包装**、**交互原语** | **工具质量 > agent 数量**的最强证据；blocklist 拦裸 `gdb`/`vim` 防"自造观察"（soliloquizing）；全局单交互会话 |
| **D-CIPHER**（NYU25） | `run_command`、`python`、Ghidra `decompile`/`disassemble`、文件编辑、executor↔executor 互问 | 大部分 ✅ | **chepy**、**Ghidra JSON 包装**（源文件就在这类仓库） | Planner-Executor 职责切分；Auto-prompter 降低初始 prompt 方差 |
| **Cairn** | Kali 元包 + netexec/bloodyad/coercer/kerbrute/pwncat/jdwp-shellifier/cloudfox；**HackTricks/PayloadsAllTheThings/InternalAllTheThings 落盘** | 部分 ✅，知识库 ❌ | **知识库落盘**（最高性价比）、netexec、bloodyad、coercer、kerbrute、jdwp-shellifier | 三原语（Fact/Intent/Hint）证明"边缘规划"能打赢；Reason 任务可并行 |
| **AIxCC / ATLANTIS** | OSS-Fuzz harness、**AFL++/libFuzzer**、**Jazzer**(Java)、**SymCC**、**ASan/UBSan**、GONDAR(Java SAST) | 全部 ❌ | **afl++ + clang**（结构性盲区） | N-versioning / 正交冗余；确定性工具与 LLM 分工；**补丁必须过测试**的硬验证 |
| **XBOW** | 无公开清单；headless browser + 截图 imagehash 视觉去重 + SimHash 文本去重 + LLM validator | playwright ✅、mitmproxy ✅ | —（方法论为主） | **"可复现 exploit"作为一等验收标准**，而非"报告了一个漏洞" |
| **Strix** | nmap/sqlmap/nuclei/subfinder/naabu/ffuf/httpx/katana/gospider/interactsh-client/wapiti/arjun；caido-cli、chromium、agent-browser；js-beautify/ast-grep/tree-sitter；opengrep/bandit/gitleaks/trufflehog/trivy | 多数 ✅ | **interactsh-client**、js-beautify/ast-grep、gitleaks | 运行中干预（mid-run steering）、live agent graph、开箱即用报告 |
| **PentestGPT** | 无固定清单：驱动 Claude Code/Codex 跑任意 shell（能力=宿主镜像） | — | — | 固定流水线会僵化，是反面教材 |
| **VulnBot** | Nmap、Dirb、Nikto、WPScan、Metasploit、Hydra（论文点名） | namp/nikto ✅，其余 ❌ | **hydra**；Metasploit/WPScan/Dirb 维持不装 | 任务分解与工具编排的工程经验 |
| **AutoPenBench** | Kali 全套 + Metasploit/Hydra/Nmap；33 个 Docker 任务（含 ARP 投毒、SNMP、11 个真实 CVE） | 部分 ✅ | **hydra** | 基准化回归题单 |
| **NYU CTF / Cybench / InterCode** | NYU：pwntools/radare2/**wine**/pycryptodome/**sagemath**/gmpy2/RsaCtfTool/tshark/binwalk/sqlmap/nikto；Cybench：吃 Kali 默认工具 + Python3.9 + docker.io | 多数 ✅ | **wine**；sagemath 建议 opt-in | **BB 缺的"标尺"**：直接用作回归与消融题单 |

### 8.1 对 BB 的机制层建议（不是给镜像装包）

1. **交互原语标准化**：`<tool>_start / <tool>_send / <tool>_exec / <tool>_stop` 四动词 + 一个 `*_exec` 逃生口，
   全局只允许 1 个交互会话——这是 EnIGMA 拿 SOTA 的直接原因，成本极低。
2. **反 soliloquizing**：对裸 `gdb`/`nc`/`vim` 做 blocklist 并回提示，禁止模型自造观察；
   bb 现有的"证据阶梯"应再加一条"交互输出必须来自真实会话"。
3. **输出预算治理**：超阈值落盘 + 返回分页/搜索句柄；`hexdump/xxd/strings` 不摘要，只对反编译类做 LM 摘要。
   （bb 已有 2000 行/50KB 上限，可再加"无输出超时 + 超时回传部分 stdout"。）
4. **可复现验收**：借鉴 XBOW——flag 之外的 evidence stage 应要求"重跑脚本仍得同一结果"，而非仅贴输出片段。
5. **回归标尺**：把 NYU CTF Bench / Cybench 作为 bb 的固定回归题单（你表格里已点出 bb 缺标尺，这是最该补的工程能力）。

---

## 附录 A：学术/工业项目工具对照（证据）

| 项目 | 环境 | 明确工具/机制（原文证据） |
|---|---|---|
| **EnIGMA** | SWE-agent v0.7 Docker | `config/default_ctf.yaml` 声明预装：pwntools、radare2、**wine/wine32**、gmpy2、**sagemath**、pycryptodome、sympy、RsaCtfTool、tshark、sqlmap、nikto；命令：`decompile`/`disassemble`/`debug_*`/`connect_*`/`check_flag`/`submit`/`give_up`；blocklist：`vim/vi/emacs/nano/nohup/gdb` |
| **D-CIPHER** | `docker/multiagent/Dockerfile`（ubuntu 22.04） | apt：gdb/gdbserver、**sagemath**、sqlmap、nikto、apktool、`libc6-i386`+`libc6-dev:i386`+`gcc-multilib`、rustc/cargo、sleuthkit、openjdk-17、p11-kit；radare2 5.8.8 deb；Ghidra 11.0.1 + `DecompileToJson`/`DisassembleToJson`；pip：pwntools、gmpy2、angr、**chepy** |
| **NYU CTF Bench** | 每题一个 Docker 容器 | 论文明列：pwntools、radare2、wine、pycryptodome、sagemath、gmpy2、RsaCtfTool、tshark、binwalk、sqlmap、nikto |
| **Cybench** | `cybench/kali-linux`（Kali 基镜像） | 不自建工具集，吃 Kali 默认工具；Dockerfile 只补 Python 3.9 编译链 + docker.io + docker-compose |
| **InterCode-CTF** | `docker/ctf.Dockerfile` | 未能取到正文；仅确认 Ubuntu + 安全/取证工具 + picoCTF 题 |
| **Cairn** | Kali rolling（`kali-linux-headless` 元包） | netexec、bloodyad、coercer、enum4linux-ng、krb5-user、kerbrute、pwncat、chisel、dirsearch、nikto、naabu、katana、nuclei+templates、dalfox、cloudfox、awscli、tccli、ysoserial-all、jwt_tool、jdwp-shellifier、gitleaks、截获 Playwright/adb；**知识库落盘**：PayloadsAllTheThings/InternalAllTheThings/HackTricks/hacktricks-cloud/vulhub/Awesome-POC |
| **Strix** | Kali rolling sandbox | nmap(setcap)、sqlmap、nuclei、subfinder、naabu、ffuf、httpx、katana、gospider、interactsh-client、wapiti、arjun、dirsearch、wafw00f、caido-cli、chromium、agent-browser、libnss3-tools、js-beautify、eslint、ast-grep、tree-sitter、retire.js、opengrep、bandit、gitleaks、trufflehog、trivy、govulncheck、gdb |
| **CAI** | 无容器，纯 Python 框架 | 不预装安全 CLI；工具是 function-call 包装器 + `generic_linux_command`，实际复用宿主工具 |
| **PentestGPT** | 宿主镜像 | v1.0 无固定清单，驱动 Claude Code/Codex 执行任意 shell；能力面取决于镜像 |
| **VulnBot** | — | 论文 §3.2 点名：Nmap、Dirb、Nikto、WPScan、Metasploit、Hydra |
| **AutoPenBench** | Kali 工作站 | 点名 Metasploit、Hydra、Nmap；33 个 Docker 任务（含 ARP 投毒、SNMP 发现、11 个真实 CVE） |
| **AIxCC / ATLANTIS** | 多 VM CRS | OSS-Fuzz harness + 覆盖率 fuzz、**Jazzer**（Java）、**SymCC** concolic（C）、ASan/UBSan、GONDAR（Java sink SAST）、SARIF；**公开材料未见 angr/KLEE 使用证据** |
| **XBOW** | 闭源服务 | 无公开工具清单；方法论：headless browser 截图 + imagehash 视觉去重、SimHash 文本去重、LLM validator + 程序化验证（"可复现 exploit"为验收标准） |

## 附录 B：本次评审未采纳的建议及原因

- **不要照搬 Kali 元包**：Cairn/Strix/AutoPenBench 都基于 `kali-rolling`，但那是"产品镜像"取舍；ctfer 的 Ubuntu + 精确包清单在体积/可复现性上更优，且已覆盖同等能力。
- **不建议上 SWE-agent ACI 全套**：EnIGMA 的价值在"交互原语 + 输出治理"这两点，ctfer 已有 dsh/pi/codex 三个成熟 harness，只需补约定与薄封装，不必换框架。
- **不建议装 CloudFox / 三家云 CLI / trivy 系**：真实渗透产品向，CTF 收益低、体积与依赖成本高。
- **不建议装 Metasploit**：维持现有排除决策。

---

## 附录 C：本次落地记录（v0.3.3）

评审结论已全部实施，镜像由 GitHub Actions 构建（本地不构建）。

发布状态：`v0.3.3` 为第一个 **多架构** 发布（`linux/amd64` + `linux/arm64` 同一 manifest，
两端 `ctf-selftest` 均通过，registry 层大小 amd64 4.33 GB / arm64 3.72 GB）。
`v0.2.1` 是第一个构建+烟测+推送全部通过的版本；
`v0.2.0` 构建成功但烟测失败（Playwright 缺失，根因是清理 man 目录导致 dpkg 半配置），
保留该 tag 作为失败记录；`v0.2.2` 修掉 NetExec 的包源与 winPEAS 的自检路径；`v0.3.x` 引入双架构、构建前预检
（`scripts/preflight.py`）与 apt 镜像回退。

### C.1 多架构结论

| 能力 | amd64 | arm64 | 说明 |
|---|---|---|---|
| Web / Pwn / Crypto / Forensics / Stego 主体 | ✅ | ✅ | 纯 Python/Java 或多架构二进制 |
| ProjectDiscovery 全家桶、ffuf、chisel、ligolo、mc、yq、bun、suo5、dalfox | ✅ | ✅ | 上游有 arm64 资产 |
| Ghidra / JDK / jadx / apktool / ysoserial | ✅ | ✅ | 纯 Java |
| `gcc-multilib`、`g++-multilib`、`libc6-dev-i386` | ✅ | ❌ | i386 multilib 只存在于 amd64（32 位 x86 pwn 编译） |
| `wine32:i386`（32 位 PE） | ✅ | ❌ | arm64 有 wine/wine64，但没有 i386 用户态 |
| `pwninit`、`kerbrute`、`craft-anything`、`stegseek` | ✅ | ❌ | 上游只发 amd64 |
| `keystone-engine`、`cysignals` | ✅ | ⚠️ 源码编译 | PyPI 无 aarch64 wheel（已加 cmake） |

CI 用 native runner 双跑（`ubuntu-latest` + `ubuntu-24.04-arm`），再用
`docker buildx imagetools create` 合并为一个多架构 manifest，全程不经过 QEMU。

| 类别 | 新增内容 | 构建参数 |
|---|---|---|
| fuzz | `afl++`（`afl-fuzz`）、`clang`/`llvm`/`lld`（libFuzzer、ASan/UBSan） | 默认开 |
| Windows PE | `wine`、`wine64`、`wine32:i386`（启用 i386 架构） | 默认开，best-effort |
| Ghidra | `decompile` / `disassemble` 函数级 JSON 包装（`docker/ghidra-scripts/`） | 依赖 `WITH_GHIDRA=1` |
| Agent 逆向 | `rea`（`rea-agents@6.9.0`，构建期注册 dsh/pi/codex）、`craft-anything-cli@0.6.1` | `WITH_REA` / `WITH_CRAFT` |
| Web/OOB | `interactsh-client`、`fickling`、`ast-grep`、`js-beautify`、`gitleaks`、`ddddocr`、`htpasswd`/`ab` | 默认开 |
| AD/内网 | `nxc`、`bloodyAD`、`coercer`、`kerbrute`、`hydra`、`lftp`、`sipvicious`、`redis-server`、`sshuttle`、`linpeas`/`winPEAS`、`rlwrap` | 默认开 |
| Forensics/其他 | `pcapfix`、`valgrind`、`mc`（S3/MinIO）、suo5 端点资产、`jdwp-shellifier` | 默认开 |
| Crypto | `chepy`、`web3`、`pyecm` | 默认开 |
| 知识资产 | `/opt/knowledge`（HackTricks / PayloadsAllTheThings / InternalAllTheThings）、`ctf-fingerprints`、`ctf-playbooks` | `WITH_KNOWLEDGE=1` |

Manifest：143 → 179 个组件。

**设计原则**（避免"加一个工具炸一次构建"）：
- 核心工具用严格 apt/pip；不确定或需联网的工具走 `|| warn`，缺失由 `ctf-selftest` 报 optional。
- 额外 Python 依赖逐包安装：一个版本 pin 失败不会连坐其他包（`pyecm` 只有 0.0.x，曾差点拖垮整组）。
- `netexec`/`bloodyAD`/`coercer` 走独立 uv tool 环境，避免污染 angr/pwntools 的依赖。
- `rea setup` 与 npm 安装均加 `timeout` + `</dev/null`，防止交互式提示挂死构建。

**仍未内置（维持评审结论）**：SageMath（~1.5GB）、Metasploit、GPU hashcat、Windows RE 套件、trivy/opengrep 等产品向扫描器。
