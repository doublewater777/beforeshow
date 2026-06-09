#!/usr/bin/env bash
# BeforeShow · 腾讯云 Lighthouse/CVM 一键部署
# 在服务器上以 root 或 sudo 运行：
#   curl -fsSL https://raw.githubusercontent.com/doublewater777/beforeshow/main/deploy/setup-server.sh | bash
# 或克隆仓库后：
#   sudo bash deploy/setup-server.sh

set -euo pipefail

APP_DIR="${APP_DIR:-/var/www/beforeshow}"
REPO_URL="${REPO_URL:-https://github.com/doublewater777/beforeshow.git}"
BRANCH="${BRANCH:-main}"
NODE_MAJOR="${NODE_MAJOR:-22}"

echo "→ 安装系统依赖…"
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq git curl nginx
elif command -v yum >/dev/null 2>&1; then
  yum install -y git curl nginx
fi

if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | sed 's/v//' | cut -d. -f1)" -lt "$NODE_MAJOR" ]]; then
  echo "→ 安装 Node.js ${NODE_MAJOR}…"
  curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash -
  apt-get install -y -qq nodejs
fi

if ! command -v pm2 >/dev/null 2>&1; then
  npm install -g pm2
fi

if ! command -v lark-cli >/dev/null 2>&1; then
  npm install -g @larksuite/cli
fi

echo "→ 拉取代码到 ${APP_DIR}…"
mkdir -p "$(dirname "$APP_DIR")"
if [[ -d "$APP_DIR/.git" ]]; then
  git -C "$APP_DIR" fetch origin
  git -C "$APP_DIR" checkout "$BRANCH"
  git -C "$APP_DIR" pull --ff-only origin "$BRANCH"
else
  git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$APP_DIR"
fi

cd "$APP_DIR"
npm ci

echo "→ 构建 fake-door…"
npm run build:fake-door

if [[ ! -f apps/fake-door/.env ]]; then
  echo ""
  echo "⚠  请在服务器创建 apps/fake-door/.env（参考 .env.example）"
  echo "⚠  并确保 ~/.lark-cli/config.json 已配置（在服务器运行 lark-cli config init --new）"
  echo ""
fi

echo "→ 启动 PM2…"
pm2 delete beforeshow-fake-door 2>/dev/null || true
pm2 start apps/fake-door/scripts/production-server.mjs \
  --name beforeshow-fake-door \
  --cwd apps/fake-door \
  --interpreter node
pm2 save

echo ""
echo "✓ 部署完成"
echo "  应用监听: http://127.0.0.1:3000"
echo "  下一步:"
echo "    1. 配置 apps/fake-door/.env"
echo "    2. 配置 lark-cli 授权（lark-cli config init --new && lark-cli auth login --domain base）"
echo "    3. 复制 deploy/nginx-beforeshow.conf 到 Nginx 并绑定域名 SSL"
echo "    4. pm2 restart beforeshow-fake-door"