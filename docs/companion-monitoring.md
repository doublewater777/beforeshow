# 同行监控

使用现有 PostHog。用户关闭「产品数据分析」后，SDK 停止收集这些事件。

## 事件

每次明确操作发送一条 `*_started`，结束发送一条 `*_finished`；`attempt_id` 关联同一次操作，重试产生新 ID。

| 事件前缀 | source | 成功边界 |
| --- | --- | --- |
| `companion_invitation` | `create` / `resend` | 云端邀请数据就绪，创建时本地关联已保存 |
| `companion_share` | `system_sheet` | 系统分享回调 `completed=true` 且无错误；复制链接也算完成 |
| `companion_join` | `onboarding` / `confirmation` | CloudKit 接受成功，且现场导入已保存 |

结束属性：`outcome=succeeded/failed/canceled`、`stage`、`duration_ms`，失败时附 `error_category`。
阶段包括 `validation`、`local_pending`、`cloud_prepare`、`local_link`、`local_recovery`、`cloud_load`、`share_decode`、`presentation`、`system_completion`、`account_check`、`metadata_load`、`cloud_accept`、`local_import`。
分类包括 iCloud 账号不可用、网络失败、权限不足、邀请不存在、数据无效、冲突、接受失败、本地持久化失败，以及系统分享无法打开等。

明确操作中的 CloudKit 请求失败另发 `companion_cloud_request_failed`，使用相同 `attempt_id`、`source`，附 `operation`、请求 `stage`、数值 `cloudkit_error_code` 和去重后的 `cloudkit_partial_error_codes`。
请求阶段包括账号检查、创建/读取 zone、保存邀请、读取 share、修改 share 权限、读取邀请 URL、读取 metadata、接受 share 和读取接受后的根记录。
CloudKit operation 回调显式携带操作上下文；后台请求、已恢复的 zone/accept/root 请求和非必需的昵称保存不会产生此失败事件。

已知会话后附 `session_id`：对随机 CloudKit session record name 加固定命名空间后取 SHA-256。双方使用相同值；不包含 owner identity、姓名、现场详情、邀请 URL/token 或原始错误文本。
开始时尚未知会话的操作，其 `session_id` 只出现在结束事件中。

## PostHog 查看方法

- **技术成功率**：各 `*_finished` 的 succeeded / (succeeded + failed)，按 source 拆分创建、重发、首次加入和已有用户加入。
- **取消分享占比**：`companion_share_finished` 的 canceled / 所有结束事件；单独展示，不归为技术失败。
- **耗时**：成功结束事件的 `duration_ms`，看 p50 / p95；失败按 `stage`、`error_category` 分组。
- **邀请转化**：成功创建/分享的唯一 `session_id`，与成功加入的唯一 `session_id` 关联。双方 distinct ID 不同，不能直接用默认「同一用户」漏斗；可用 HogQL 按 session_id 关联，设置例如 7 天转化窗口，并仅统计窗口已结束的邀请。
- **未结束操作**：按 attempt_id 找有 started、无 finished 的记录。App 退出/崩溃时可能没有结束事件，不自动记为失败。

分享完成表示系统接受了分享操作。朋友真正加入以 `companion_join_finished` 成功为准。
预览、已经加入提示、后台刷新/发现/恢复不生成加入事件；重复打开后明确确认或失败重试各算一次操作。
接受前的返回用户链接加载/预览失败不属于 join attempt；首次引导点击加入后的账号与 metadata 加载失败包含在 join attempt 中。

这是客户端事件采集，关闭分析、离线队列或未运行此版本都会影响覆盖率，不能作为完整云端成员审计。

## 已配置的服务端监控

[BeforeShow · 同行与稳定性监控](https://us.posthog.com/project/461647/dashboard/2165165)

10 个看板指标：技术成功率、失败阶段/原因、最近失败明细、成功耗时、7 天邀请转化、15 分钟未结束操作、各构建埋点覆盖、最近一小时邀请失败/加入失败/崩溃。
仅统计 bundle `com.doublewaterapps.beforeshow` 且 `$is_emulator=false`、`$is_sideloaded=false` 的真机 App Store / TestFlight 数据。

已启用 3 个每小时检查的告警：邀请准备失败、加入失败、真机崩溃；最近一小时数量大于 0 时触发，订阅者为配置时登录的项目用户。
告警已保存并启用，尚未验证实际通知送达。关闭分析、网络阻断或旧版本没有事件时，告警不能检测失败。
SQL、指标与告警 ID 存在 [companion-posthog.json](observability/companion-posthog.json)，不包含访问凭证。

## 崩溃符号

Release 真机归档的最后一个 build phase 调用 PostHog SDK 官方 `upload-symbols.sh`，上传 dSYM 并关联 bundle/version/build；上传失败会阻止归档完成。
安装 `posthog-cli` 后执行 `posthog-cli login`，选择 US 项目 461647 与 Error tracking 权限。凭证保存在本机 `~/.posthog/credentials.json`，不进 Git。CI 使用外部 secret `POSTHOG_CLI_API_KEY`。
Debug 与模拟器构建跳过上传；不上传源代码片段。

22、26 的 App 与 Widget dSYM 已补传，并核对了服务端 UUID 与上传状态。

已有归档可手动补传，例如（在仓库外执行，避免 CLI 为历史归档附上当前 Git 提交）：

```bash
companion_archive="$PWD/.asc/artifacts/BeforeShow-1.0.2-26.xcarchive"
(cd /tmp && POSTHOG_CLI_PROJECT_ID=461647 ~/.posthog/posthog-cli dsym upload \
  --directory "$companion_archive/dSYMs" \
  --info-plist "$companion_archive/Products/Applications/BeforeShow.app/Info.plist" \
  --main-dsym BeforeShow.app.dSYM)
```

## TestFlight 覆盖限制

2026-10-03 早上的 1.0.2（26）早于邀请重试修复与本页的同行事件，不能通过新事件追溯它之前的邀请失败。
开发签名用 CloudKit Development，TestFlight 用 Production；开发环境成功不能替代 Production schema 验证。
同一台已登录 iCloud 的 iPhone 17 模拟器在 Production 签名下复现邀请保存失败，PostHog 服务端已收到 `invitation_save` 阶段的 CloudKit 错误码 12（`serverRejectedRequest`）。
本地临时诊断确认具体原因：`Cannot create or modify field 'showSnapshotV1' in record 'CompanionSession' in production schema`。
26 的代码也会保存此字段。2026-10-03 13:03（Asia/Taipei）已将 Development 的同行字段与 11 个新增索引发布到 Production，控制台返回 `Changes Deployed`：

| 字段 | 类型 | 索引 |
| --- | --- | --- |
| `showSnapshotV1` | Bytes | Queryable、Sortable |
| `ownerDisplayName` | String | Queryable、Searchable、Sortable |
| `participantDisplayName` | String | Queryable、Searchable、Sortable |
| `participantNicknamesJSON` | String | Queryable、Searchable、Sortable |

撤销实测还发现状态时间字段未定义。13:09 补充发布 `acceptedAt`、`canceledAt`（Date/Time，无索引）；两次发布均只新增同行字段，不修改安全角色或删除数据。

同一台 iPhone 17 使用 Release 构建、Production iCloud entitlements 验证：

- 13:04 创建邀请成功，系统分享面板正常打开，复制链接成功。
- 13:05 再次分享成功，重新读取云端邀请后打开系统分享面板，复制链接成功。
- PostHog 收到两次 `companion_invitation_finished`（`create` / `resend`）和两次 `companion_share_finished`，均为 `outcome=succeeded`。
- 补齐时间字段后撤销测试邀请成功，页面回到「添加同行」；未向他人发送邀请。

当前 26 的 schema 保存阻碍已解除，可以直接重试邀请。上述运行验证使用本地最新客户端；尚未在用户的真机 26 或第二个 iCloud 账号上验证加入。
新客户端事件仍需下一次 TestFlight 更新才会覆盖真机；本次模拟器事件被生产看板过滤，不会触发真机告警。

CloudKit 保存现已改用原生异步结果并逐条检查成功/失败，避免 operation 成功但记录失败时丢失底层错误。
这次真机录像缺少初始 snapshot，播放器无法播放，因此邀请诊断以操作事件和错误码为主。
