#!/usr/bin/env bash
# BeforeShow · 飞书多维表格一键初始化（lark-cli）
#
# 前置：先完成 lark-cli 登录
#   lark-cli config init --new
#
# 用法：
#   cd apps/fake-door
#   bash scripts/setup-feishu-bitable.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$ROOT_DIR/.feishu-beforeshow.json"
ENV_FILE="$ROOT_DIR/.env"

if ! command -v lark-cli >/dev/null 2>&1; then
  echo "未找到 lark-cli，请先安装：npm install -g @larksuite/cli"
  exit 1
fi

if ! lark-cli doctor 2>/dev/null | rg -q '"ok": true'; then
  echo "lark-cli 尚未完成配置。请在新终端运行："
  echo "  lark-cli config init --new"
  echo "然后在浏览器打开输出的链接完成授权。"
  exit 1
fi

IDENTITY="${FEISHU_IDENTITY:-user}"
AS_FLAG=(--as "$IDENTITY")

echo "→ 创建多维表格 BeforeShow 内测（identity: $IDENTITY）…"
BASE_JSON="$(lark-cli base +base-create \
  "${AS_FLAG[@]}" \
  --name "BeforeShow 内测" \
  --time-zone "Asia/Shanghai" \
  --format json)"

BASE_TOKEN="$(echo "$BASE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('app_token') or d.get('app_token') or '')")"

if [[ -z "$BASE_TOKEN" ]]; then
  echo "创建 Base 失败，原始返回："
  echo "$BASE_JSON"
  exit 1
fi

echo "  app_token = $BASE_TOKEN"

FIELDS='[
  {"type":"text","name":"邮箱"},
  {"type":"text","name":"演出"},
  {"type":"text","name":"会话ID"},
  {"type":"text","name":"提交时间"},
  {"type":"text","name":"来源"}
]'

echo "→ 创建数据表 waitlist…"
TABLE_JSON="$(lark-cli base +table-create \
  "${AS_FLAG[@]}" \
  --base-token "$BASE_TOKEN" \
  --name "waitlist" \
  --fields "$FIELDS" \
  --format json)"

TABLE_ID="$(echo "$TABLE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('table_id') or d.get('table_id') or '')")"

if [[ -z "$TABLE_ID" ]]; then
  echo "创建数据表失败，原始返回："
  echo "$TABLE_JSON"
  exit 1
fi

echo "  table_id = $TABLE_ID"

cat > "$CONFIG_FILE" <<EOF
{
  "base_token": "$BASE_TOKEN",
  "table_id": "$TABLE_ID",
  "table_name": "waitlist",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "mode": "lark-cli-record-upsert"
}
EOF

echo "→ 写入 $CONFIG_FILE"

if [[ -f "$ENV_FILE" ]]; then
  python3 - <<PY
from pathlib import Path
import re

env = Path("$ENV_FILE").read_text()
updates = {
    "FEISHU_BASE_TOKEN": "$BASE_TOKEN",
    "FEISHU_TABLE_ID": "$TABLE_ID",
    "FEISHU_LEAD_MODE": "bitable",
    "FEISHU_IDENTITY": "$IDENTITY",
}
for key, val in updates.items():
    line = f"{key}={val}"
    if re.search(rf"^{key}=", env, re.M):
        env = re.sub(rf"^{key}=.*$", line, env, flags=re.M)
    else:
        env += ("\n" if env and not env.endswith("\n") else "") + line + "\n"
Path("$ENV_FILE").write_text(env)
print(f"→ 已更新 $ENV_FILE")
PY
else
  cat > "$ENV_FILE" <<EOF
FEISHU_LEAD_MODE=bitable
FEISHU_BASE_TOKEN=$BASE_TOKEN
FEISHU_TABLE_ID=$TABLE_ID
FEISHU_IDENTITY=$IDENTITY
EOF
  echo "→ 已创建 $ENV_FILE"
fi

echo ""
echo "✓ 飞书多维表格已就绪"
echo ""
echo "测试写入一条记录："
echo "  lark-cli base +record-upsert \\"
echo "    --base-token $BASE_TOKEN \\"
echo "    --table-id $TABLE_ID \\"
echo "    --json '{\"邮箱\":\"test@example.com\",\"演出\":\"五月天上海\",\"会话ID\":\"demo\",\"提交时间\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"来源\":\"setup-script\"}'"
echo ""
echo "启动 fake-door："
echo "  npm run dev"
echo ""
echo "说明：lark-cli 的 workflow API 目前不支持 Webhook 触发器，"
echo "已改用 bitable 直写模式（更稳、可完全 CLI 化）。"