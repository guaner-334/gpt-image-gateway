# gpt-image-gateway

用 [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)（MIT License，镜像 `eceasy/cli-proxy-api:latest`）把 **ChatGPT Plus/Pro 订阅**（Codex OAuth 登录）转成 **OpenAI 兼容的文生图 API**（`/v1/images/generations`，底层 gpt-image-2），部署在能直连 OpenAI 的海外 VPS 上，供 [oneis-team/houya](https://github.com/oneis-team/houya) 的文生图功能调用。

这是一个**运维/部署仓库**，不写业务代码。仓库即唯一真相源：服务器上的部署状态必须能从本仓 clone 重建。

```
Houya (OPENAI_BASE_URL / OPENAI_API_KEY)
   │  标准 OpenAI Images API
   ▼
海外 VPS :8317 ── CLIProxyAPI（本仓部署）
   │  Codex OAuth（登录态在 auth/，token 自动刷新）
   ▼
OpenAI 上游（gpt-image-2，走 ChatGPT 订阅额度）
```

## 快速开始

完整步骤（含 OAuth 登录、nginx/防火墙加固、运维备忘）见 **[docs/deploy-guide.md](docs/deploy-guide.md)**，概要如下：

```bash
# 1. 在海外 VPS 上 clone 本仓
git clone https://github.com/guaner-334/gpt-image-gateway.git && cd gpt-image-gateway

# 2. 生成配置，改 api-keys 为随机 key（openssl rand -hex 32）
cp config.example.yaml config.yaml && vim config.yaml

# 3. 启动网关
docker compose up -d

# 4. Codex OAuth 登录（仅首次；需另开本地终端做 SSH 端口转发，见部署指南第 4 步）
docker compose exec gateway ./CLIProxyAPI --codex-login

# 5. 验证
./scripts/healthcheck.sh          # 零成本：查 /v1/models
./scripts/healthcheck.sh --full   # 真实生成一张图（消耗订阅额度）
```

## 交付给 Houya 的两个环境变量

Houya 侧对接只依赖这两个值，走标准 OpenAI Images API：

| 环境变量 | 取值 |
|---|---|
| `OPENAI_BASE_URL` | 网关地址 + `/v1`，如 `http://<VPS_IP>:8317/v1`（上 nginx 后为 `https://<域名>/v1`） |
| `OPENAI_API_KEY` | `config.yaml` 里 `api-keys` 配置的自定义 key |

随时可以把这两个值切回官方 `https://api.openai.com/v1` + 官方 API key 回退，Houya 侧代码零改动。

## 红线（务必遵守）

- **`config.yaml`（含网关 API key）和 `auth/`（ChatGPT 订阅 OAuth 登录态）永不入库**，`.gitignore` 已覆盖，任何情况下不得移出。
- `remote-management.allow-remote` 保持 `false`。

## ⚠️ 风险声明

把 ChatGPT 订阅转成 API 使用**违反 OpenAI 服务条款**，存在账号被封的风险。请：

- **使用独立的订阅账号，勿用主力账号**；
- 控制调用频率，不要把网关暴露给不受信任的调用方；
- 接受账号可能随时被封的现实，Houya 侧保留切回官方 API 的回退路径。

## 目录结构

```
├── README.md               本文件
├── docker-compose.yml      网关服务定义（端口 8317 + 1455）
├── config.example.yaml     配置模板（复制为 config.yaml 使用）
├── .gitignore              忽略 config.yaml / auth/ 等凭证与产物
├── scripts/
│   └── healthcheck.sh      健康检查（默认零成本，--full 真实生成）
├── docs/
│   └── deploy-guide.md     完整部署指南
└── CLAUDE.md               本仓项目规范
```
