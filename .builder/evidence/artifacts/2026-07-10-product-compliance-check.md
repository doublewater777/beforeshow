# BeforeShow / 开场前上架前合规检查

检查日期：2026-07-10

Product / feature: `开场前` iOS 现场准备工具，包含本地现场记录、相册引用、录音、定位、App Store Pro 订阅、用户主动触发的 AI 候选曲目/往返草稿/现场视频。

Target markets: 中国大陆 App Store；其他 App Store 地区待配置。

Platforms: iOS 17+

Data collected: 现场名称、时间、城市、场馆、艺人等生成所需字段会在用户主动触发时发送到腾讯云后端；定位、相册引用、录音及主要业务数据以设备本地处理/保存为主；反馈可包含用户主动选择的诊断信息。

Payments: App Store 自动续期订阅，月付 `¥12`、年付 `¥68`，无免费试用。

AI / UGC / sensitive domains: 使用豆包，通义千问作为回退；无公开 UGC、社交、票务、医疗、金融或儿童定位。

## Overall risk

中国大陆发布目前为 `Blocker`；其他地区 App Store 发布目前为 `High Risk`，原因是首版资料、构建、隐私和付费协议状态尚未完成或核验。

## Blocking risks

1. `开场前` 尚无独立 APP 备案号。腾讯云当前主体 `浙ICP备2026041359号` 正常，但 APP 列表只有 `PagePilot`（`浙ICP备2026041359号-1A`）。中国大陆发布前需通过接入商提交 `开场前` APP 备案，并把核验通过的 ICP 备案号填入 App Store Connect。
2. App 提供 AI 文本生成。中国大陆上线前需在生成结果或交互界面提供用户可感知的 AI 生成标识，在用户协议中说明标识方式，并准备供分发平台核验的标识材料。
3. 需在显著位置或产品详情页公示实际使用的已备案/已登记生成式 AI 服务名称及备案号。当前项目没有记录豆包、通义千问对应的准确备案/登记号，不能在核实前上线中国大陆 AI 功能。
4. App Store Connect 当前校验为 `33` 个 blocking errors：缺少描述、关键词、支持 URL、审核联系人、构建、可售范围、截图、年龄分级、隐私政策 URL；App Privacy 发布状态还需网页确认。
5. Pro 订阅要求 Account Holder 接受有效的 Paid Apps Agreement，并完成银行与税务信息。2026-07-10 已在 App Store Connect 网页核验：付费 App 协议有效，银行账户状态可用，所需美国税表状态为使用中。

## High risks

1. iOS 正式包当前直接请求腾讯云默认域名 `*.app.tcloudbase.com`，而 APP 备案材料要求填写真实网络接入与域名信息。最终备案信息、实际二进制请求域名和接入商应保持一致；建议在最终构建前切到主体持有并备案的自定义 API 域名。
2. 当前为个人备案主体并销售自动续期数字订阅。是否触及经营性互联网信息服务许可、个人主体业务范围或地方管局口径，需要在提交前向腾讯云备案顾问/属地管局确认；此记录不作法律结论。
3. `现场视频` 使用 Bilibili 第三方公开元数据和站外播放/原站跳转。需继续限制为官方播放器/原页，不下载、不缓存、不自建播放，并保留内容权利说明。

## Watch items

1. App Privacy 与隐私政策应一致披露定位、麦克风、相册选择、本地数据、AI 请求、反馈诊断及第三方处理方；不得把本地处理描述成“完全不收集”而遗漏网络请求。
2. 无 BeforeShow 账号，因此 Apple 的应用内账号删除要求当前不适用；若以后增加账号或云同步需重新检查。
3. 年龄分级应按实际的第三方现场视频内容回答，不能为追求较低分级而错误申报。
4. 若生成结果支持复制、导出或分享，需确认导出内容也保留法规要求的显式标识；如生成文件，还要评估隐式标识要求。

## Policy evidence

- [Apple：View Mainland China compliance information](https://developer.apple.com/help/app-store-connect/manage-compliance-information/view-mainland-china-compliance-information)
  - 中国大陆组织开发者需确认大陆合规身份信息；App Store 会展示核验信息。
- [Apple：App information reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
  - 中国大陆可用性可能要求有效 ICP 备案号，且 Apple 元数据需与工信部备案信息匹配。
- [腾讯云：APP 备案常见问题](https://cloud.tencent.com/document/product/243/97691)
  - APP 备案材料包括名称、图标、平台、Bundle ID、公钥、iOS 证书 SHA-1、SDK 信息、云资源和服务域名；运营主体与域名注册人应一致。
- [腾讯云：新增/接入服务](https://cloud.tencent.com/document/product/243/97670)
  - 已有主体为新 APP 办理备案时，应在 APP 页签选择“新增/接入服务”。
- [国家网信办：人工智能生成合成内容标识办法](https://www.cac.gov.cn/2025-03/14/c_1743654684782215.htm)
  - 2025-09-01 起施行；要求适用服务提供者落实显式/隐式标识、在用户协议说明标识规范，并由应用分发平台核验 AI 标识材料。
- [国家网信办：生成式人工智能服务已备案信息公告](https://www.cac.gov.cn/2024-04/02/c_1713729983803145.htm)
  - 已上线的生成式 AI 应用或功能应公示所用已备案服务的模型名称及备案号。
- [Apple：Sign and update agreements](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/)
  - 提供 IAP/订阅前，Account Holder 必须签署 Paid Apps Agreement。
- [Apple：Provide tax information](https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information/)
  - 收款需提交银行和税务信息，所有开发者均需完成相应美国税表。

## Required changes

1. 完成腾讯云 `开场前` APP 备案草稿、负责人核验、短信核验和管局审核。
2. 核实豆包/通义千问实际调用模型及备案/登记号；在 App、隐私政策/用户协议和商店说明中加入准确公示。
3. 为 AI 生成页面和可复制/导出内容落实显式标识；按实际导出能力评估隐式标识。
4. 发布隐私政策、支持页和用户协议，并使其与 App Privacy 回答一致。
5. 在 App Store Connect 完成中国大陆合规信息和 App Privacy；Paid Apps Agreement、银行与税务状态已核验通过。
6. 完成首版元数据、截图、年龄分级、可售范围、构建上传和 TestFlight 实机验证。

## Recommended safeguards

- 备案表述保持为“音乐现场准备和本地记录工具”，如实说明 AI 辅助功能，不将产品描述为新闻、网络视听、社交、票务或官方歌单服务。
- 生成结果保留“AI 生成，仅供参考”一类明确标签，并允许用户本地编辑。
- 在正式包中只发送生成必需字段，不上传票务截图、二维码、订单号、身份证号、付款信息、相册原件或录音。

## Recommended review owner

- 产品/开发者：完成 Apple、腾讯云、隐私与 AI 公示材料。
- 腾讯云备案顾问或属地通信管理局：确认个人主体、订阅收费和服务描述口径。
- 如继续面向中国大陆提供 AI 功能：由熟悉生成式 AI 备案/登记与内容标识的合规顾问复核。

## Incomplete checks

- Apple 中国大陆合规信息和 App Privacy 网页状态仍未完成核验；对应页面本次加载为空白。Paid Apps Agreement、银行与税务状态已核验通过。
- 豆包和通义千问当前实际模型版本及其备案/登记号尚未核实。
- 腾讯云新增 APP 备案页面要求重新登录，尚未创建/提交草稿。
- 未确认个人主体在属地管局对订阅收费与 AI 功能的具体受理口径。

Not legal advice: 本检查是发布风险筛查，不构成法律意见；对个人经营性服务与生成式 AI 备案/登记问题应取得主管部门或专业顾问确认。
