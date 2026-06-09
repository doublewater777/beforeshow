#!/usr/bin/env bash
# 在 Lighthouse 服务器上运行
# 用法：bash one-shot-deploy.sh

set -euo pipefail

APP_DIR="${APP_DIR:-/var/www/beforeshow}"
REPO="https://github.com/doublewater777/beforeshow.git"

echo "→ 拉取代码…"
sudo mkdir -p "$(dirname "$APP_DIR")"
if [[ -d "$APP_DIR/.git" ]]; then
  sudo git -C "$APP_DIR" pull --ff-only origin main
else
  sudo git clone --depth 1 "$REPO" "$APP_DIR"
fi

cd "$APP_DIR"
sudo bash deploy/setup-server.sh

if [[ ! -f apps/fake-door/.env ]]; then
  echo ""
  echo "⚠  请创建 apps/fake-door/.env（参考 .env.example）"
  echo "    然后运行：pm2 restart beforeshow-fake-door"
  echo ""
fi

echo "✓ 部署脚本执行完毕"