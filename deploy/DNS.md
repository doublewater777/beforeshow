# BeforeShow · Cloudflare Pages + 腾讯云 DNS 配置

目标域名：`beforeshow.doublewaterapps.com`

## 1. Cloudflare Pages 部署

项目：`beforeshow`

```bash
npm run build:fake-door
cd apps/fake-door
npm run deploy:pages
```

生产环境变量：

```env
FEISHU_WEBHOOK_URL=https://www.feishu.cn/flow/api/trigger-webhook/xxxxxxxx
```

> Cloudflare Pages Function 运行在 edge 环境，不能使用依赖 `lark-cli` 的 `FEISHU_LEAD_MODE=bitable` 模式。生产环境请使用飞书自动化 webhook。

## 2. Cloudflare Pages 自定义域名

在 Cloudflare Dashboard：

1. 进入 Workers & Pages
2. 选择 Pages 项目 `beforeshow`
3. 打开 Custom domains
4. 添加 `beforeshow.doublewaterapps.com`
5. 等待 Cloudflare 显示需要配置的 CNAME 目标，通常是 `beforeshow.pages.dev`

> 必须先在 Pages 项目里添加自定义域名，再去 DNSPod 增加 CNAME。只在 DNSPod 手动指向 `*.pages.dev` 可能会得到 522。

## 3. 腾讯云 DNS 解析（DNSPod / 腾讯云域名控制台）

登录 [腾讯云 DNS 解析](https://console.cloud.tencent.com/cns)，选择 `doublewaterapps.com`，添加或修改记录：

| 主机记录 | 记录类型 | 记录值 | TTL |
|---------|---------|--------|-----|
| `beforeshow` | CNAME | `beforeshow.pages.dev` | 600 |

如果 Cloudflare Dashboard 给出的 Pages 子域名不是 `beforeshow.pages.dev`，以 Dashboard 显示的值为准。

验证：

```bash
dig +short beforeshow.doublewaterapps.com
# 应返回 beforeshow.pages.dev 或 Cloudflare 解析结果
```

## 4. 验证上线

```bash
curl -I https://beforeshow.doublewaterapps.com/
curl -X POST https://beforeshow.doublewaterapps.com/api/leads \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","show":"上线测试"}'
```
