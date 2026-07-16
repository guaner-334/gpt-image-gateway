# 部署指南

在一台**能直连 OpenAI 的海外 VPS** 上，从零把文生图网关部署到可供 Houya 调用的状态。全程只依赖本仓库——服务器上的部署状态必须能从本仓 clone 重建，禁止一次性手工操作。

## 0. 前置要求

- 一台海外 VPS（能直连 `chatgpt.com` / `auth.openai.com`），Debian/Ubuntu 均可；
- 已安装 Docker 与 Docker Compose 插件（`docker compose version` 能跑通）;
- 一个 **ChatGPT Plus 或 Pro 订阅账号**——⚠️ **用独立订阅账号，勿用主力账号**（订阅转 API 违反 OpenAI ToS，可能封号）；
- 本地机器能 SSH 到 VPS（首次 OAuth 登录需要 SSH 端口转发）。

## 1. Clone 本仓

```bash
# 推荐部署到 /opt 下，后文 cron 示例以此路径为准
sudo git clone https://github.com/guaner-334/gpt-image-gateway.git /opt/gpt-image-gateway
cd /opt/gpt-image-gateway
```

## 2. 填配置

```bash
cp config.example.yaml config.yaml
# 生成一个随机 key，填进 config.yaml 的 api-keys
openssl rand -hex 32
vim config.yaml
```

只需要改一处：把 `api-keys` 里的占位符换成刚生成的随机 key。**这个 key 就是之后交付给 Houya 的 `OPENAI_API_KEY`。**

其余字段保持默认：`port: 8317`、`auth-dir: "~/.cli-proxy-api"`、`disable-image-generation: false`、`remote-management.allow-remote: false`（红线，不得改 true）。

> `config.yaml` 已被 `.gitignore` 忽略，永不入库。它只存在于服务器上。

## 3. 启动网关

```bash
docker compose up -d
docker compose logs -f gateway   # 确认无报错后 Ctrl+C 退出
```

镜像 `eceasy/cli-proxy-api:latest` 已满足图像生成的版本要求（需 ≥ v6.9.30，v6.9.35 起对所有 Codex 上游请求可用）。

## 4. Codex OAuth 登录（仅首次）

登录流程会在 VPS 的 **1455 端口**起一个 OAuth 回调服务，而授权要在**你本地的浏览器**里完成，所以需要 SSH 端口转发把回调接回来。

**本地机器**另开一个终端，保持运行：

```bash
ssh -L 1455:127.0.0.1:1455 <user>@<VPS_IP>
```

**VPS 上**（原终端）发起登录：

```bash
cd /opt/gpt-image-gateway
docker compose exec gateway ./CLIProxyAPI --codex-login
```

终端会打印一个 `https://auth.openai.com/...` 的授权链接。**复制到本地浏览器打开**，用独立订阅账号登录并授权。授权完成后浏览器会跳转到 `localhost:1455`，经 SSH 转发回到容器，终端提示登录成功。

登录态（token）保存在宿主机 `./auth/` 目录（容器内 `/root/.cli-proxy-api`），之后自动刷新，**无需重复登录**。此时可以关掉本地的 SSH 转发终端。

> 替代方案：如果端口转发不方便，可用设备码登录，无需回调端口：
> `docker compose exec gateway ./CLIProxyAPI --codex-device-login`
> 按提示在任意浏览器打开链接并输入设备码即可。

> `auth/` 已被 `.gitignore` 忽略，和 `config.yaml` 一样永不入库。

## 5. 验证

```bash
# 零成本检查：网关存活、key 正确、/v1/models 可用
./scripts/healthcheck.sh

# 完整检查：真实生成一张图（消耗订阅额度），成功后图片在 tmp/ 下
./scripts/healthcheck.sh --full
```

也可以手工模拟 Houya 的调用：

```bash
curl -X POST http://127.0.0.1:8317/v1/images/generations \
  -H "Authorization: Bearer <config.yaml 里的 key>" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-image-2", "prompt": "一只戴帽子的橘猫", "size": "1024x1024"}'
```

## 6. 交付给 Houya

到这一步网关已可用。交付两个值：

| Houya 环境变量 | 取值 |
|---|---|
| `OPENAI_BASE_URL` | `https://<域名>/v1`（第 7 步 nginx 反代就绪后的正式地址） |
| `OPENAI_API_KEY` | `config.yaml` 里 `api-keys` 的值 |

> 8317 默认只绑本机回环（见 docker-compose.yml），对外必须走第 7 步的 nginx 443。
> 如需在 nginx 就绪前用 `http://<VPS_IP>:8317/v1` 公网直连联调：临时把 compose 里的映射改回
> `"8317:8317"`、安全组按来源 IP 放行 8317，联调完改回来。

Houya 走标准 OpenAI Images API，随时可把这两个值切回官方 `https://api.openai.com/v1` + 官方 key 回退，代码零改动。

## 7. 加固（nginx 反代 + 防火墙，强烈建议）

裸 HTTP + IP 直连仅适合联调。生产建议套一层 nginx 做 HTTPS，并用防火墙关掉直连。

### 7.1 nginx 反代

```nginx
# /etc/nginx/sites-available/gateway.conf
server {
    listen 443 ssl;
    server_name gateway.example.com;   # 换成你的域名

    ssl_certificate     /etc/letsencrypt/live/gateway.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/gateway.example.com/privkey.pem;

    location / {
        # 可选：来源 IP 白名单（服务器上还有其他站点共用 443 时，安全组不能收紧，
        # 就在这里做只针对本站点的访问控制；IP 以调用方实测出口 IP 为准）
        # allow <调用方出口IP>;
        # deny all;

        proxy_pass http://127.0.0.1:8317;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        # 图像生成耗时较长，放宽超时
        proxy_read_timeout 300s;
        # 响应里带 base64 图片，别限制太小
        client_max_body_size 20m;
        proxy_buffering off;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/gateway.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
# 证书用 certbot 签发：sudo certbot --nginx -d gateway.example.com
```

之后交付给 Houya 的 `OPENAI_BASE_URL` 改为 `https://gateway.example.com/v1`。

### 7.2 访问控制（来源 IP 白名单）

**⚠️ 不要用 ufw 去挡 8317**：8317 是 Docker 发布的端口，Docker 会直接写 iptables（DOCKER 链），流量不经过 ufw 的常规规则——`ufw deny 8317` 看似生效，实际拦不住，是假安全感。

正确做法，按优先级：

1. **云安全组（推荐）**：在云控制台把 8317 入方向规则的源地址从 `0.0.0.0/0` 收紧为调用方的出口 IP（`x.x.x.x/32`）。拦截发生在云的网络层，Docker 绕不过去。
   > 调用方的真实出口 IP 以在调用方服务器上执行 `curl -s ifconfig.me` 的结果为准——出网经过 NAT/代理时，出口 IP 和机器自身 IP 不一致，填错会把自己挡在外面。
2. **配好 nginx 后收口**：把 docker-compose.yml 里 8317 的映射改成 `"127.0.0.1:8317:8317"`（先改仓库、再同步到服务器，勿手改），`docker compose up -d` 重建后 8317 彻底不对公网暴露，只剩 443 经 nginx 进来，安全组也只放行 443。
3. 如果一定要在主机层做防火墙，规则必须写进 iptables 的 `DOCKER-USER` 链才对 Docker 端口生效，ufw 常规命令无效。

SSH 防护照旧走 ufw 或安全组：`sudo ufw allow OpenSSH && sudo ufw enable`。

> 1455 端口在 docker-compose.yml 里只绑定了 `127.0.0.1`，公网本来就摸不到，无需处理。

## 8. 运维备忘

- **更新镜像**：`docker compose pull && docker compose up -d`（登录态在 `auth/`，更新不丢）。
- **看日志**：`docker compose logs -f gateway`；文件日志在 `./logs/`。
- **重启 / 重建**：`docker compose restart`；服务器重装时，clone 本仓 → 恢复 `config.yaml` 和 `auth/`（或重新登录）→ `docker compose up -d`，即可完整重建。
- **备份**：`config.yaml` 和 `auth/` 是仅有的两样不在仓库里的东西，妥善离线备份（它们是凭证，勿放任何公开位置）。
- **健康监控**：把轻量检查放 cron：
  ```
  */10 * * * * /opt/gpt-image-gateway/scripts/healthcheck.sh >> /var/log/gateway-health.log 2>&1
  ```
  `--full` 会真实消耗订阅额度，只用于手工排查，勿放 cron。
- **登录态失效**（日志出现 401/token 刷新失败）：重跑第 4 步登录即可。
- **⚠️ 封号风险**：订阅转 API 违反 OpenAI ToS。用独立订阅账号；控制调用量；账号被封时 Houya 侧把两个环境变量切回官方 API 即可无缝回退，之后换账号重新登录网关。

## 9. 故障排查

| 现象 | 排查 |
|---|---|
| `healthcheck.sh` 连不上 | `docker compose ps` 看容器是否在跑；`docker compose logs gateway` 看报错 |
| `/v1/models` 返回 401 | 请求头里的 key 与 `config.yaml` 的 `api-keys` 不一致 |
| 生成接口返回 404 | 检查 `config.yaml` 里 `disable-image-generation` 是否还是 `false`；镜像是否过旧（`docker compose pull`） |
| 生成接口返回 401/403 | 登录态失效或账号异常，重跑第 4 步；确认账号未被封 |
| OAuth 回调打不开 | 本地 SSH 转发是否还挂着；或改用 `--codex-device-login` |
| 生成很慢 / 超时 | 属正常现象（数十秒级）；调用方超时设 ≥ 300s；nginx 已配 `proxy_read_timeout 300s` |
