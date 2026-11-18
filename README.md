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

# 三个 agent harness（API key 运行时注入，不打进镜像）
docker run --rm -it -v "$PWD:/work" -e OPENAI_API_KEY kingfs/ctfer:latest pi
docker run --rm -it -v "$PWD:/work" -e OPENAI_API_KEY kingfs/ctfer:latest codex
docker run --rm -it -v "$PWD:/work" -e DEEPSEEK_API_KEY kingfs/ctfer:latest dsh

# DSH Web UI
docker run --rm -p 3080:3080 -e DEEPSEEK_API_KEY \
  kingfs/ctfer:latest dsh web --host 0.0.0.0 --port 3080 --no-open
```

镜像以 `root` 运行，`/work` 是默认工作目录；它只是工具集合，不是安全边界。
请只在获得授权的目标上使用。

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
├── docker/
│   ├── Dockerfile                 # 多阶段构建
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
- 工具版本来自各项目 **latest release**（agent CLI 与 Go 固定版本），
  因此不同时间构建的镜像不是逐字节可复现；如需固定，给 `install-assets.sh`
  增加版本变量即可。
- Ghidra 12 需要 JDK 25；镜像从 Adoptium 下载 Temurin 25（Ubuntu 24.04 只有 21）。
- 镜像不内置任何 API key、flag 或私有 token；所有密钥运行时注入。

## 安全与合规

- 只在授权的 CTF 环境/目标中使用；
- 不要用镜像内的工具扫描或攻击非授权基础设施；
- 平台/比赛若要求提交 flag，请遵循比赛规则；
- 发现镜像构建问题请开 issue 或直接改 `docker/` 后打新 tag。
