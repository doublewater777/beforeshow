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
PostHog 仪表盘和自动告警需在服务端配置；本次没有建立仪表盘或告警规则。
