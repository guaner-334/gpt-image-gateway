#!/usr/bin/env bash
# GPT Image Gateway 健康检查
#
# 用法：
#   ./scripts/healthcheck.sh          轻量检查：GET /v1/models（零成本，适合放 cron）
#   ./scripts/healthcheck.sh --full   完整检查：真实生成一张图（消耗订阅额度，勿放 cron）
#
# 环境变量（均可选）：
#   GATEWAY_BASE_URL   网关地址，默认 http://127.0.0.1:8317
#   GATEWAY_API_KEY    网关 API key；不设置时自动从仓库根目录 config.yaml 读取第一个 api-key
#   IMAGE_MODEL        --full 模式使用的模型，默认 gpt-image-2
#
# 退出码：0 = 健康；非 0 = 异常（cron 可据此告警）。
#
# cron 示例（每 10 分钟一次轻量检查，失败时写日志）：
#   */10 * * * * /opt/gpt-image-gateway/scripts/healthcheck.sh >> /var/log/gateway-health.log 2>&1

set -euo pipefail

BASE_URL="${GATEWAY_BASE_URL:-http://127.0.0.1:8317}"
MODEL="${IMAGE_MODEL:-gpt-image-2}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { log "FAIL: $*"; exit 1; }

# ---- 取 API key：优先环境变量，其次 config.yaml ----
API_KEY="${GATEWAY_API_KEY:-}"
if [[ -z "$API_KEY" && -f "$REPO_ROOT/config.yaml" ]]; then
  API_KEY="$(sed -n '/^api-keys:/,/^[^ #-]/p' "$REPO_ROOT/config.yaml" \
    | grep -m1 -E '^[[:space:]]*-' \
    | sed -E 's/^[[:space:]]*-[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/')"
fi
[[ -n "$API_KEY" ]] || fail "未找到 API key：请设置 GATEWAY_API_KEY 或在仓库根目录准备 config.yaml"

# ---- 轻量检查：/v1/models ----
MODELS_JSON="$(curl -fsS --max-time 15 \
  -H "Authorization: Bearer $API_KEY" \
  "$BASE_URL/v1/models")" || fail "GET $BASE_URL/v1/models 请求失败（网关未启动？key 不对？）"

echo "$MODELS_JSON" | grep -q '"data"' || fail "/v1/models 返回内容异常：$MODELS_JSON"
log "OK: /v1/models 正常（网关存活）"

if [[ "${1:-}" != "--full" ]]; then
  exit 0
fi

# ---- 完整检查：真实生成一张图 ----
log "开始完整检查：调用 /v1/images/generations 生成一张图（模型 $MODEL，消耗订阅额度）..."
mkdir -p "$REPO_ROOT/tmp"
RESP_FILE="$REPO_ROOT/tmp/healthcheck-resp.json"

HTTP_CODE="$(curl -sS --max-time 300 -o "$RESP_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/v1/images/generations" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"model\": \"$MODEL\", \"prompt\": \"A cute orange cat, watercolor style\", \"n\": 1, \"size\": \"1024x1024\"}")"

[[ "$HTTP_CODE" == "200" ]] || fail "图像生成返回 HTTP $HTTP_CODE：$(head -c 500 "$RESP_FILE")"
grep -q 'b64_json\|"url"' "$RESP_FILE" || fail "响应中没有图像数据：$(head -c 500 "$RESP_FILE")"

# 有 python3 就把 base64 解码存成 png，方便人工核验；没有也不影响判定
OUT_PNG="$REPO_ROOT/tmp/healthcheck-$(date +%Y%m%d-%H%M%S).png"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$RESP_FILE" "$OUT_PNG" <<'PYEOF' && log "OK: 图像已保存到 $OUT_PNG" || log "提示：图像解码失败，但接口本身返回正常"
import base64, json, sys
resp = json.load(open(sys.argv[1]))
b64 = resp["data"][0].get("b64_json")
if not b64:
    sys.exit(1)
open(sys.argv[2], "wb").write(base64.b64decode(b64))
PYEOF
else
  log "提示：未安装 python3，跳过图像落盘，仅校验接口返回"
fi

log "OK: 完整检查通过（文生图链路可用）"
