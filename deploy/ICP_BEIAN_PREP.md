# BeforeShow ICP / APP 备案准备清单

目标服务：开场前 BeforeShow
目标域名：beforeshow.doublewaterapps.com
备案服务域名：doublewaterapps.com / beforeshow.doublewaterapps.com

## 当前核验结果

- 腾讯云账号已实名认证。
- 域名 `doublewaterapps.com` 已在腾讯云当前账号下，注册日期 `2026-06-08`，到期日期 `2028-06-08`。
- DNS 使用 DNSPod：`cricket.dnspod.net`、`sagittarius.dnspod.net`。
- 当前解析：`beforeshow.doublewaterapps.com` CNAME 到 `beforeshow.pages.dev`，实际托管在 Cloudflare Pages。
- 当前腾讯云可用备案资源：轻量应用服务器 `lhins-1fguk4yo`，上海五区，公网 IP `124.222.189.17`，到期 `2027-06-08`。
- 轻量服务器防火墙目前只放通 `22/tcp` 和 `ICMP`，尚未放通 `80/tcp`、`443/tcp`。

## 备案路径判断

如果继续使用 Cloudflare Pages 作为实际源站，腾讯云通常不能作为接入服务商完成该域名的大陆 ICP 接入备案。

建议路径：

1. 先用腾讯云备案小程序/控制台提交 `APP` 或 `网站/APP` 备案。
2. 云服务资源选择上海轻量应用服务器 `lhins-1fguk4yo`。
3. 备案审核通过后，把 `beforeshow.doublewaterapps.com` 从 Cloudflare Pages 迁到腾讯云轻量服务器公网 IP `124.222.189.17`。
4. 备案通过并开通访问后，在页面底部添加 ICP 备案号，并在开通后 30 日内做公安备案。

## 腾讯云官方入口

- ICP 备案文档：https://cloud.tencent.com/document/product/243
- 快速备案网站或 APP：https://cloud.tencent.com/document/product/243/39038
- 备案域名要求：https://cloud.tencent.com/document/product/243/18905
- 备案云资源要求：https://cloud.tencent.com/document/product/243/18908
- 备案材料清单：https://cloud.tencent.com/document/product/243/18914
- 小程序端首次备案：https://cloud.tencent.com/document/product/243/37402
- PC 端首次备案：https://cloud.tencent.com/document/product/243/18958
- 短信核验说明：https://cloud.tencent.com/document/product/243/13435
- 公安备案流程：https://cloud.tencent.com/document/product/243/19142

## APP 备案建议填写项

- APP 名称：开场前
- 英文名/别名：BeforeShow
- 服务内容：音乐现场开场前准备工具，提供现场倒计时、候选曲目、现场回顾、往返计划、现场准备和本地现场碎片记录。
- 服务域名：`beforeshow.doublewaterapps.com`
- 备案主体：使用腾讯云账号实名主体，需与域名实名认证主体一致
- 云资源：轻量应用服务器 `lhins-1fguk4yo`
- 运行平台：iOS
- iOS Bundle ID：`com.doublewaterapps.beforeshow`
- App Store Connect App ID：`6780078298`
- App Store URL：`https://apps.apple.com/us/app/id6780078298`
- App Store Connect Bundle ID 资源 ID：`5NWJ7ZT3UH`
- App Store Version ID：`09ededb4-02b4-4e84-9a4a-874ee21cbda3`
- App Store App Info ID：`affd6168-3d9a-4a61-9abd-b9cd8b428b77`
- Team ID / Seed ID：`29C8MS76CZ`
- App Store SKU：`beforeshow-ios`
- App Store 主分类：Music
- App Store 副分类：Lifestyle
- App Store 副标题：开场之前，先进入状态
- 品牌氛围句：灯亮之前，先进入状态
- iOS Distribution 证书 ID：`XCJMLU87V5`
- iOS Distribution 证书名称：`iOS Distribution: Yang Pan`
- iOS Distribution 证书过期时间：`2027-05-05T01:37:20.000+00:00`
- iOS Distribution 证书 SHA-1：`DC:56:8C:69:9D:63:FE:18:CE:04:86:27:D8:35:15:E2:64:5D:C2:9F`
- iOS 证书公钥：

```text
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsT/Et1yLAiY4sa9DO81P
zWA3/9FlFJwhlGHHOhkgkG+SRDn2nCexuYTWI73aRw7pCdpfDHW+TtfNI0fd9Q9l
uHwGpCNhbSCa1wd/BS8FCwlVMO5AhFNHGQdAjJHNw9Mfw6EiDhWlAId98iMcnEHo
2IN7jCzYStMHC3fgsSodw/OZj/5ENsyP4IUq83kHXzfIhJUEABwUKeDV2//47nOC
xxApV+OOpalMhU6qmAoHJ9tTQbXymjYpr271eAhiToNmVRlemxJbUwxldENfCevE
Lr2MrZRB5px3Z+GMGj0nyt634Y8+w8nyioaEDekX+ELb3VJwWNMvhnxRA/w+LpbY
KwIDAQAB
-----END PUBLIC KEY-----
```

还需要等原生应用确定后补齐：

- APP 图标、截图、隐私政策、用户协议
- 隐私政策 URL、用户协议 URL、客服/反馈联系方式
- 若包含 AI 生成、B 站现场回顾、音乐平台跳转等能力，备案描述里避免写成新闻、出版、网络游戏、网络视听节目、票务交易、社交社区等需要额外资质或改变业务性质的类别。

不支持 Android，因此不需要 Android 包名或 Android 签名证书摘要。

## App Store Connect 当前状态

- 已完成：Bundle ID `com.doublewaterapps.beforeshow`。
- 已完成：App Store Connect App 记录，App ID `6780078298`，版本 `1.0` 处于 `PREPARE_FOR_SUBMISSION`。
- 已完成：App Store 分类 Music / Lifestyle。
- 已完成：内容权利声明 `USES_THIRD_PARTY_CONTENT`，因为 V2.1 的现场回顾会使用 B 站官方站外播放器或跳转原站展示第三方公开内容。

## 备案前技术准备

放通轻量服务器 HTTP/HTTPS：

```bash
tccli lighthouse CreateFirewallRules \
  --region ap-shanghai \
  --InstanceId lhins-1fguk4yo \
  --FirewallRules '[{"Protocol":"TCP","Port":"80","CidrBlock":"0.0.0.0/0","Action":"ACCEPT","FirewallRuleDescription":"HTTP"},{"Protocol":"TCP","Port":"443","CidrBlock":"0.0.0.0/0","Action":"ACCEPT","FirewallRuleDescription":"HTTPS"}]'
```

备案通过后再修改 DNS：

```bash
tccli dnspod ModifyRecord \
  --Domain doublewaterapps.com \
  --RecordId 2311285262 \
  --SubDomain beforeshow \
  --RecordType A \
  --RecordLine 默认 \
  --Value 124.222.189.17 \
  --TTL 600
```

验证：

```bash
dig +short beforeshow.doublewaterapps.com
curl -I http://beforeshow.doublewaterapps.com/
curl -I https://beforeshow.doublewaterapps.com/
```

## 注意事项

- 域名刚在 `2026-06-08` 注册并实名，腾讯云文档提示实名认证信息同步到工信部通常建议至少等待三天后再提交备案。
- 网站备案通常只需要备案主域名 `doublewaterapps.com`，备案通过后三级域名 `beforeshow.doublewaterapps.com` 可使用；APP 备案可以填写 APP 运行平台使用的域名，支持填写到四级域名。
- 管局短信核验一般需要在收到短信后 24 小时内到工信部系统完成。
- 腾讯云初审通常会先反馈，提交管局后按官方说明可能在 20 个工作日内审核。
- 备案审核通过前，不建议把域名直接切到未备案的腾讯云大陆源站并开放正式服务。
