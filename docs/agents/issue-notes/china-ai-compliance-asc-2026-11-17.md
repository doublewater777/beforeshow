# China mainland App Compliance — AI declaration (2026-11-17)

BeforeShow smart timetable recognition calls Bailian `qwen3.7-flash` via CloudBase `recognizeTimetable`. ASC App Compliance for China mainland must declare AI-Generated or Synthetic Content as **Yes**. Security Assessment remains **No** (private schedule structuring; no UGC distribution; no E2E IM).

## ASC fill draft

Path: Apps → 开场前 → General → App Compliance

### AI-Generated or Synthetic Content

- Offers AI-generation / Synthetic services in China mainland: **Yes**
- Filing (LLM):
  - Name: `通义千问大模型`
  - Number: `ZheJiang-TongYiQianWen-20230901`
- Filing (Algo) — prefer if the form asks for Algo:
  - Name: `达摩院交互式多能型合成算法`
  - Number: `网信算备 330110507206401230035 号`
  - Owner: 阿里巴巴达摩院（杭州）科技有限公司
- Verify live at https://beian.cac.gov.cn before upload; save full-page screenshot.
- Third-party authorization: upload Alibaba Cloud cooperation agreement / authorization letter that includes:
  - filing name + number above
  - authorizing entity matching CAC registry owner
  - authorized party = BeforeShow legal entity
  - product name `开场前` / `BeforeShow`
  - use: timetable image recognition → structured schedule JSON
- Source for numbers / agreement request:
  - https://help.aliyun.com/zh/model-studio/model-filing-information-publicity
  - https://help.aliyun.com/zh/model-studio/compliance-and-launch-filing-guide-for-ai-apps-powered-by-the-tongyi-model

### Security Assessment

- Features requiring Security Assessment in China mainland: **No**

## Alibaba agreement request (copy)

主题：申请通义千问 API 应用上架合作协议 / 算法备案授权（开场前 BeforeShow）

正文：

您好，我们通过阿里云百炼 / DashScope 调用通义千问多模态模型（当前 `qwen3.7-flash`）为 iOS App「开场前」（Bundle ID `com.doublewaterapps.beforeshow`）提供音乐节时刻表图片识别能力，仅生成用户私有排期结构化数据，不做公开内容分发。

现需向 Apple App Store Connect（中国大陆 App Compliance）提交第三方技术授权材料，请提供：

1. 应用主体与阿里云主体的合作协议 / 授权书（含算法名称或备案编号、应用产品名称、授权方与被授权方）
2. 通义千问对应算法备案 / 大模型备案信息截图或说明

我方主体名称：【填写】
统一社会信用代码：【填写】
联系人 / 电话 / 邮箱：【填写】
阿里云账号 UID / 实名主体：【填写】

参考文档：https://help.aliyun.com/zh/model-studio/compliance-and-launch-filing-guide-for-ai-apps-powered-by-the-tongyi-model

也可走：https://page.aliyun.com/form/act1311146645/index.htm

## App-side labeling (shipped in code)

- Import entry footer: `智能识别使用 AI，图片仅用于排期整理`
- Recognizing title: `AI 识别中`
- Review banner badge: `AI 识别` + `结果由 AI 生成，请核对后保存`

## Status update 2026-11-17 (later)

- Alibaba self-service application submitted and visible in 我的审核单.
  - 审核单号: `23858`
  - 类型: 模型合作协议备案申请
  - 状态: 审核中
  - 提交账号 UID: `1985707238540662`
  - 提交时间: `2026-11-17 12:36:59`
- Expected Alibaba review: ~6 business days; electronic seal + prior Bailian call history required for approval.
- After stamped PDF arrives: ASC → App Compliance → AI-Generated or Synthetic Content → upload third-party authorization → Save.
- ASC AI fields already drafted: LLM `通义千问大模型` / `ZheJiang-TongYiQianWen-20230901`, third-party Yes.
- Security Assessment already Active = No. ICP `浙ICP备2026041359号-3A` set.
- ASC web session was expired earlier; re-auth before uploading agreement.


## Still blocked on human account work

1. `asc web auth login` (session expired) then fill App Compliance and upload agreement
2. Obtain stamped Alibaba authorization
3. Confirm with local CAC whether app-layer 大模型登记 is required for this feature
