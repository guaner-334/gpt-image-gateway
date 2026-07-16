# API 调用说明（Houya 对接用）

网关暴露标准 **OpenAI Images API**，任何 OpenAI SDK / HTTP 客户端都能直接用。本文列出的参数已对照 CLIProxyAPI 源码（v7.2.80）逐一核实，是 `gpt-image-2` 路径**真实生效**的字段，不是照抄 OpenAI 官方文档。

## 基本信息

| 项 | 值 |
|---|---|
| 接口 | `POST {OPENAI_BASE_URL}/images/generations` |
| 认证 | 请求头 `Authorization: Bearer {OPENAI_API_KEY}` |
| Content-Type | `application/json` |
| 模型 | `gpt-image-2`（另支持 `gpt-image-1.5`） |
| 耗时 | 实测约 80 秒/张，**客户端超时务必 ≥ 300 秒** |

## 最简调用

```bash
curl -m 300 -X POST "$OPENAI_BASE_URL/images/generations" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-image-2", "prompt": "一只戴帽子的橘猫，水彩风格"}'
```

## 请求参数

| 参数 | 类型 | 必填 | 可选值 / 说明 |
|---|---|---|---|
| `model` | string | 否 | `gpt-image-2`（缺省即此值）、`gpt-image-1.5` |
| `prompt` | string | **是** | 图片描述；缺失直接返回 400 |
| `size` | string | 否 | `1024x1024`（方）、`1536x1024`（横）、`1024x1536`（竖）、`auto`（默认，由模型自行决定） |
| `quality` | string | 否 | `low` / `medium` / `high` / `auto`（默认）。越高越慢、耗额度越多 |
| `background` | string | 否 | `transparent`（透明底，需配 png/webp）/ `opaque` / `auto`（默认） |
| `output_format` | string | 否 | `png`（默认）/ `jpeg` / `webp` |
| `output_compression` | number | 否 | 0–100，仅对 jpeg/webp 生效的压缩率 |
| `moderation` | string | 否 | `auto`（默认）/ `low`（放宽内容审核） |
| `response_format` | string | 否 | `b64_json`（默认，**建议保持**）/ `url`（见下方注意事项） |
| `stream` | bool | 否 | `true` 时走 SSE 流式返回中途预览图（配 `partial_images`: 0–3）；Houya 场景用不上，保持默认即可 |

**不支持 `n` 参数**：网关的 Codex 路径不转发 `n`，一次请求固定返回 1 张图。要多张就并发/循环发多次请求（每张都独立消耗订阅额度）。

## 响应格式

```json
{
  "created": 1768888888,
  "data": [
    {
      "b64_json": "iVBORw0KGgo...（图片的 base64 编码）",
      "revised_prompt": "（模型改写后的提示词，可能没有）"
    }
  ],
  "usage": { "...": "token 用量统计" }
}
```

注意事项：

- **图片以 base64 内嵌返回**（`b64_json`），解码后即为图片文件，需要自己落盘或转存对象存储。
- `response_format: "url"` **拿不到真正的托管链接**——上游只回 base64，网关会把它包装成 `data:image/png;base64,...` 形式的 data URL 塞进 `url` 字段。所以老实用默认的 `b64_json` 最省事。
- 官方 `api.openai.com` 的 gpt-image 系列同样只回 `b64_json`，因此 Houya 按 base64 处理，将来切回官方 API 也不用改。

## Python 示例（OpenAI SDK）

```python
import base64, os
from openai import OpenAI

client = OpenAI(
    base_url=os.environ["OPENAI_BASE_URL"],  # 例: http://<网关IP>:8317/v1
    api_key=os.environ["OPENAI_API_KEY"],
    timeout=300,
)

resp = client.images.generate(
    model="gpt-image-2",
    prompt="一只戴帽子的橘猫，水彩风格",
    size="1024x1024",
    quality="high",
)
with open("out.png", "wb") as f:
    f.write(base64.b64decode(resp.data[0].b64_json))
```

## 错误速查

| HTTP 状态 | 含义 | 处理 |
|---|---|---|
| 400 | 缺 `prompt`，或 `model` 不在支持列表 | 检查请求体 |
| 401 | key 不对 | 与服务器 `config.yaml` 的 `api-keys` 核对 |
| 404 | 服务器把 `disable-image-generation` 改成了 true | 恢复为 `false` 并重启 |
| 5xx / 超时 | 上游波动或登录态异常 | 服务器上跑 `scripts/healthcheck.sh` 定位；登录态失效则重新登录 |

## 图生图 / 改图（备用）

网关同时支持 `POST /images/edits`（传原图 + 提示词改图，multipart 或 JSON，额外支持 `input_fidelity` 参数控制与原图的贴合度）。Houya 现阶段用不到，需要时再查上游文档：https://help.router-for.me/
