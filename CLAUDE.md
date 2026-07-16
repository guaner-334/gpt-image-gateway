# CLAUDE.md — gpt-image-gateway 项目规范

## 交流语言

**与用户交流、commit message、文档一律使用中文。**

## 仓库性质

这是一个**运维/部署仓库**，不写业务代码。目标：用 CLIProxyAPI（MIT License，镜像 `eceasy/cli-proxy-api:latest`）把 ChatGPT Plus/Pro 订阅（Codex OAuth 登录）转成 OpenAI 兼容的文生图 API，部署在能直连 OpenAI 的海外 VPS 上，供 `oneis-team/houya` 的文生图功能调用。

与 Houya 主仓同一工程哲学：**仓库 = 唯一真相源**。服务器上的部署状态必须能从本仓 clone 重建，禁止一次性手工操作——任何配置变更先改仓库、再同步到服务器。

## 红线（任何改动不得触碰）

1. **`config.yaml`（含自定义网关 API key）和 `auth/`（ChatGPT 订阅 OAuth 登录态）永不入库**，必须始终在 `.gitignore` 中。
2. **`remote-management.allow-remote` 保持 `false`**。
3. 不在文档、commit、issue 中粘贴真实的 API key、token 或 `auth/` 内容。

## 关键事实

- 图像生成支持需 **CLIProxyAPI ≥ v6.9.30**（v6.9.35 起对所有 Codex 上游请求可用），直接用 `latest` 镜像即可。
- 服务端口 **8317**；OAuth 回调端口 **1455**（仅首次登录时用，需 SSH 端口转发到本地浏览器完成授权）。
- 登录态存在 `auth/` 目录（挂载到容器内 `/root/.cli-proxy-api`），之后 token 自动刷新，无需重复登录。
- 文生图接口：`/v1/images/generations`，底层模型 **gpt-image-2**。
- Houya 侧对接只依赖两个环境变量：`OPENAI_BASE_URL`（网关地址 + `/v1`）和 `OPENAI_API_KEY`（`config.yaml` 里的自定义 key），走标准 OpenAI Images API，随时可切官方 `https://api.openai.com/v1` 回退。
- **ToS 风险**：订阅转 API 违反 OpenAI 服务条款，可能封号。文档中必须保留「用独立订阅账号，勿用主力账号」的提示。

## 文件职责

| 文件 | 职责 |
|---|---|
| `docker-compose.yml` | 网关服务定义（唯一的服务启动方式） |
| `config.example.yaml` | 配置模板；真实配置 `config.yaml` 只存在于服务器上 |
| `scripts/healthcheck.sh` | 健康检查；默认零成本查 `/v1/models`，`--full` 真实生成 |
| `docs/deploy-guide.md` | 完整部署指南；服务器上的一切操作以此为准 |
| `docs/api-usage.md` | API 调用说明；参数以 CLIProxyAPI 源码核实为准，Houya 对接以此为准 |

## Commit 规范

中文 message，格式 `chore: 简短描述`（本仓几乎所有改动都是 chore；文档改动可用 `docs:`）。
