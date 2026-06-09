# BeforeShow · 腾讯云 DNS 配置

目标域名：`beforeshow.doublewaterapps.com`

## 1. DNS 解析（DNSPod / 腾讯云域名控制台）

登录 [腾讯云 DNS 解析](https://console.cloud.tencent.com/cns)，选择 `doublewaterapps.com`，添加记录：

| 主机记录 | 记录类型 | 记录值 | TTL |
|---------|---------|--------|-----|
| `beforeshow` | A | `<你的 Lighthouse 公网 IP>` | 600 |

> 若 Lighthouse 只提供 IPv6，改用 AAAA 记录。

验证：

```bash
dig +short beforeshow.doublewaterapps.com
# 应返回服务器公网 IP
```

## 2. Lighthouse 部署

SSH 登录服务器后：

```bash
# 克隆并部署
export APP_DIR=/var/www/beforeshow
sudo git clone https://github.com/doublewater777/beforeshow.git "$APP_DIR"
cd "$APP_DIR"
sudo bash deploy/setup-server.sh
```

创建 `apps/fake-door/.env`（勿提交 git）：

```env
FEISHU_LEAD_MODE=bitable
FEISHU_BASE_TOKEN=<你的 token>
FEISHU_TABLE_ID=<你的 table id>
FEISHU_IDENTITY=user
```

在服务器完成 lark-cli 授权：

```bash
lark-cli config init --new
lark-cli auth login --domain base
```

重启应用：

```bash
pm2 restart beforeshow-fake-door
```

## 3. HTTPS（Nginx + 腾讯云免费证书）

1. [SSL 证书控制台](https://console.cloud.tencent.com/ssl) 申请免费证书，域名填 `beforeshow.doublewaterapps.com`
2. 下载 Nginx 格式证书，上传到服务器 `/etc/nginx/ssl/`
3. 复制 `deploy/nginx-beforeshow.conf`，修改证书路径
4. `sudo nginx -t && sudo systemctl reload nginx`

## 4. 验证上线

```bash
curl -I https://beforeshow.doublewaterapps.com/
curl -X POST https://beforeshow.doublewaterapps.com/api/leads \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","show":"上线测试"}'
```