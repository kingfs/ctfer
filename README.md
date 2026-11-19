# ctfer

一个用于 CTF 比赛与 AI agent 实战的「开箱即用」Docker 镜像：

- **开发运行时**：Python 3.12、Node.js 24（npm / pnpm / bun）、Go 1.27、JDK 25（Temurin）、Ruby 3.2
- **Agent harness**：[Pi](https://pi.dev)、[OpenAI Codex CLI](https://github.com/openai/codex)、[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`pi` / `codex` / `dsh`）
- **CTF 工具链**：Web、Pwn、Reverse、Crypto、Forensics/Stego、Network/AD、云原生等常用工具
- **数据**：精选 SecLists、rockyou（gzip）、nuclei-templates、Ghidra、Playwright Chromium

镜像发布在 Docker Hub：[`kingfs/ctfer`](https://hub.docker.com/r/kingfs/ctfer)。
打 `v*` tag 后由 GitHub Actions 自动构建 `linux/amd64` 镜像、跑烟测并推送。

## 快速使用

```bash
# 交互式 shell，当前目录挂载到 /work
docker run --rm -it -v "$PWD:/work" kingfs/ctfer:latest

# 工具目录 / 自检
docker run --rm kingfs/ctfer:latest ctf-tools
docker run --rm kingfs/ctfer:latest ctf-selftest
# 机器可读组件清单（v0.1.2+）
docker run --rm kingfs/ctfer:latest ctf-manifest pwn

# 三个 agent harness（API key 运行时注入，不打进镜像）
docker run --rm -it -v "$PWD:/work" -e OPENAI_API_KEY kingfs/ctfer:latest pi
docker run --rm -it -v "$PWD:/work" -e OPENAI_API_KEY kingfs/ctfer:latest codex
docker run --rm -it -v "$PWD:/work" -e DEEPSEEK_API_KEY kingfs/ctfer:latest dsh

# DSH Web UI（DSH 0.2.2 拒绝 0.0.0.0，需绑定容器 eth0 地址后再用 -p 发布）
docker run --rm -p 3080:3080 -e DEEPSEEK_API_KEY \
  kingfs/ctfer:latest \
  bash -lc 'exec dsh web --host "$(hostname -i | cut -d" " -f1)" --port 3080 --no-open --public-url http://127.0.0.1:3080'
# 然后打开日志中打印的 http://127.0.0.1:3080/?token=... 链接
```

镜像以 `root` 运行，`/work` 是默认工作目录；它只是工具集合，不是安全边界。
请只在获得授权的目标上使用。

## 组件清单（manifest）

镜像内维护一份按功能分类的机器可读清单 `/opt/ctf/MANIFEST.yaml`，并提供
`ctf-manifest` 查询命令：

```bash
ctf-manifest                         # 分类与数量
ctf-manifest pwn                     # 某一类的组件、命令、路径
ctf-manifest search jwt              # 按名称/命令/描述搜索
ctf-manifest show gdb                # 查看完整条目
ctf-manifest commands ad             # 只列命令名（TSV）
ctf-manifest json | jq               # 机器可读 JSON
```

| 分类 | 内容 |
|---|---|
| `base` | OS、Python/Node/Go/JDK/Ruby、编译链、常用 CLI |
| `harness` | `pi`、`codex`、`dsh` |
| `web` | 目录/参数发现、注入、JWT、GraphQL、浏览器、源码审计 |
| `pwn` | 调试、ELF/ROP、符号执行、qemu、32 位编译 |
| `reverse` | Ghidra、jadx、apktool、dex2jar、androguard、ysoserial |
| `crypto` | z3/sympy/gmpy2/fpylll、PARI/GP、RsaCtfTool、hashcat/john |
| `forensics` | 流量、内存、磁盘、文档、固件 |
| `stego` | 图片/音频/二维码隐写 |
| `network` | 扫描、连接、VPN、代理、隧道 |
| `ad` | impacket、certipy、bloodhound、evil-winrm、SMB/LDAP |
| `cloud` | kubectl、aws |
| `data` | SecLists、rockyou、nuclei 模板、Playwright 浏览器 |
| `helpers` | `ctf-manifest`、`ctf-tools`、`ctf-selftest` |

> 说明：manifest 与 `ctf-manifest` 自 `v0.1.2` 起随镜像发布；更早的 `v0.1.1`
> 只有 `ctf-tools` / `ctf-selftest`。不重建镜像时，也可以直接阅读仓库里的
> [`docker/MANIFEST.yaml`](docker/MANIFEST.yaml)。

## 发布流程

```bash
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actions 会：

1. `lint`：ShellCheck 检查所有脚本；
2. 构建 `linux/amd64` 镜像（BuildKit + GitHub Actions 层缓存）；
3. 在 runner 内加载镜像并执行 `ctf-selftest`、Python 模块导入、Node/Go/Agent 版本检查；
4. 推送以下 tag 到 Docker Hub：
   - `v0.1.0`、`0.1.0`、`0.1`、`0`、`latest`
   - `sha-<短 commit>`（每次构建都有）

也可以在 Actions 页面手动 `workflow_dispatch`：默认只构建 + 烟测、不推送；
勾选 `push_image` 才会推送（tag 使用 `image_tag` 输入，默认 `test`）。

### 仓库 Secrets

在 GitHub 仓库 `Settings → Secrets and variables → Actions` 配置：

| Secret | 说明 |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub 用户名（`kingfs`） |
| `DOCKERHUB_TOKEN` | Docker Hub Access Token（Read & Write 即可） |

## 构建

CI 只构建 `linux/amd64`。本地构建：

```bash
# 推荐：在 amd64 机器上构建
docker buildx build --platform linux/amd64 --load -t kingfs/ctfer:dev docker

# 或者直接用仓库里的封装（默认 linux/amd64）
./scripts/build.sh
```

> arm64 主机上的 `--platform linux/amd64` 会走 QEMU，apt/pip/npm 全部模拟执行，
> 可能耗时数小时；日常请交给 GitHub Actions。

### 构建参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `GO_VERSION` | `1.27.4` | Go 官方 tarball 版本 |
| `WITH_GHIDRA` | `1` | Ghidra headless（约 1 GB 级） |
| `WITH_PLAYWRIGHT` | `1` | Playwright headless Chromium |
| `WITH_JAVA` | `1` | Temurin JDK 25 + jadx/apktool/ysoserial/dex2jar |
| `WITH_RUBY` | `1` | one_gadget/seccomp-tools/zsteg/evil-winrm |
| `WITH_SECLISTS` | `1` | 精选 SecLists + gzip rockyou |
| `WITH_FULL_SECLISTS` | `0` | 完整 SecLists（很大，不建议） |
| `WITH_NUCLEI_TEMPLATES` | `1` | nuclei 模板 |
| `PI_VERSION` / `CODEX_VERSION` / `DSH_VERSION` / `PNPM_VERSION` | 见 Dockerfile | agent harness / pnpm 版本 |

示例：不要 Ghidra，缩小体积：

```bash
docker buildx build --platform linux/amd64 \
  --build-arg WITH_GHIDRA=0 -t kingfs/ctfer:slim docker
```

## 体积与缓存

镜像刻意做了这些清理：

- 多阶段构建：下载/编译产物只在最终镜像保留必要文件；
- apt：`--no-install-recommends`，删除 `/var/lib/apt/lists`、`/var/cache/apt`、文档、man、locale；
- Python：`PIP_NO_CACHE_DIR=1 --no-compile`，删除 `__pycache__`/`*.pyc`；
- Node：`npm cache clean --force`，删除 `~/.npm`；
- Ruby：`gem cleanup`，删除 gem cache；
- Go：删除 `test/`、`api/`、`doc/`、`misc/`；
- Ghidra：删除 docs 与 Features 下的 `src`；
- 所有临时文件在同一层内删除，避免“删了但还在下层”的体积浪费。

CI 会打印镜像未压缩大小；Docker Hub 拉取时传输的是压缩层。

## 目录

```text
.
├── .github/workflows/docker.yml   # tag -> 构建 -> 烟测 -> 推送
├── AGENTS.md                      # 仓库维护 agent 指南
├── docker/
│   ├── Dockerfile                 # 多阶段构建
│   ├── MANIFEST.yaml              # 机器可读组件清单（source of truth）
│   ├── ctf-manifest               # 清单查询 CLI（ctf-manifest）
│   ├── install-assets.sh          # GitHub Releases / 数据文件
│   ├── install-runtime.sh         # gem、wrapper、Playwright、agent CLI
│   ├── requirements-tools.txt     # Python CTF 工具链
│   ├── TOOLS.md                   # 镜像内工具目录（ctf-tools）
│   ├── runtime-AGENTS.md          # 镜像内 agent 约定（/opt/ctf/AGENTS.md）
│   ├── selftest.sh                # ctf-selftest
│   └── entrypoint.sh
├── scripts/
│   ├── build.sh                   # 本地构建封装
│   └── smoke-test.sh              # 本地烟测
└── README.md
```

## 已知限制

- **仅 amd64**：CTF 平台、大多数 pwn 题和 `gcc-multilib`/`qemu-system-x86` 都是 amd64 生态。
- 不包含 SageMath、Metasploit、GPU hashcat、Windows RE 套件（体积/许可/驱动原因）。
  需要时在容器内用 `uv` / `pipx` / `npm` / `go install` 临时安装。
- `john` 使用 Ubuntu 自带的 1.9.0（非 jumbo），仅支持 crypt(3) 类哈希；更多哈希格式
  请用 `hashcat`，或在容器内自行安装 jumbo 版。
- 工具版本来自各项目 **latest release**（agent CLI 与 Go 固定版本），
  因此不同时间构建的镜像不是逐字节可复现；如需固定，给 `install-assets.sh`
  增加版本变量即可。
- Ghidra 12 需要 JDK 25；镜像从 Adoptium 下载 Temurin 25（Ubuntu 24.04 只有 21）。
- 镜像不内置任何 API key、flag 或私有 token；所有密钥运行时注入。
- `ctf-manifest` / `MANIFEST.yaml` 自 `v0.1.2` 起可用；`v0.1.1` 及更早镜像
  没有这两个文件。
- 少数 source-clone 工具（如 `graphw00f`）属于 optional，缺失不影响核心自检。

## 安全与合规

- 只在授权的 CTF 环境/目标中使用；
- 不要用镜像内的工具扫描或攻击非授权基础设施；
- 平台/比赛若要求提交 flag，请遵循比赛规则；
- 发现镜像构建问题请开 issue 或直接改 `docker/` 后打新 tag。
