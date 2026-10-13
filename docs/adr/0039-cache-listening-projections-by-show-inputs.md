# Cache listening projections by show inputs

「听」的持久化曲库按 Apple Music artist ID 共享，房间的浏览、合辑、证据和临时热门歌曲属于当前现场。完整 `ArtistCatalogSnapshot` 仍只表示一次成功获取的完整曲库；临时热门歌曲不能作为熟悉度分母，也不写入完整快照。

## 加载与缓存

- `ListeningCatalogStore` 合并同一艺人的完整曲库刷新；成功后在后台 ModelActor 保存，再递增 revision。网络失败保留最后一次完整快照。
- `ListeningCatalogProjection` 拥有当前现场阵容和时间表相关的读上下文、歌曲、专辑及已经组装的艺人展示值。按快照引用的 ID 查询，额外保留热门歌曲所属专辑的发行日期。
- 曲库 revision、相关本地曲库保存或艺人集合变化才重读曲库；热门歌曲增量和时间表修改复用曲库快照。
- 完整曲库按既有 24 小时策略刷新，仍在选中艺人时按需加载。热门歌曲先到先显示，最多四个并发请求，在当前房间内同样受 freshness 检查。
- 普通切页只核对现场输入、意愿、熟悉度和最近播放，不重新组装未变化的唱片。播放器进度刷新从缓存读取艺人展示值。

## 失效与生命周期

| 变化 | 行为 |
| --- | --- |
| 现场切换，包括隐藏页预加载 | 退休旧加载 generation，取消浏览任务，释放旧读上下文、临时歌曲和展示值，绑定新现场 |
| 清空当前现场或删除本地状态 | 解除旧现场绑定，退休加载 generation，取消排队匹配及浏览任务，释放内存投影 |
| 根层切换当前现场 | 在重绑前清除旧现场已装入的唱片及恢复记录；不依赖隐藏页任务和 chrome bootstrap 的执行顺序 |
| 同一现场艺人姓名、ID、链接改变 | 清理不再相关的临时歌曲，退休旧浏览 generation，立即重建本地阵容；有未连接艺人时重新匹配 |
| 头像或嵌套时间表修改 | 比较实际输入值，更新阵容或合辑；不依赖 `Show.updatedAt` |
| 当前页面自己的艺人自动匹配 | 更新输入后继续原加载 generation；不被 SwiftUI 观察回写取消 |
| 完整曲库或精选歌单保存 | revision 使下一次投影读取重新获取持久化数据 |
| 隐藏「听」 | 暂停硬件显示动画、取消精选歌单请求；保持传输与已装入的不可变唱片 |

身份匹配单独记录每个阵容位置已经处理的姓名、ID、链接，曲库完成 key 仅描述曲库加载。外部改名或改链即使晚于曲库请求完成才触发观察回调，也不会被误认为已处理。排队匹配执行前再次核对活跃和加载状态，避免与根层的加载重复。

异步结果发布同时检查取消状态、现场及浏览 generation。旧任务的结束回调只能清理它所属 generation 的任务槽。共享艺人的完整曲库刷新可以完成并保存缓存，但退休的页面任务不能发布其结果到新房间。

## 验证

缓存作用域及本地歌曲更新由房间生命周期测试覆盖；现场隐藏预加载的迟到请求由冷启动测试覆盖；艺人改链和嵌套时间表变化由生命周期测试覆盖；同一艺人的并发完整刷新由缓存模块测试覆盖。`ListeningActivate` / `ListeningRebuild` signpost 提供模拟器和真机上的实际耗时观测。

### 2026-10-14 本地结果

指定模拟器：`beforeshow iphone 18 pro`，iOS 27，Debug 构建。现有数据库为 7,055 首歌曲、1,427 张专辑、76 个艺人快照；当前现场为 24 位艺人的泉州草莓音乐节。

| 主线程区间 | 改造前两次测量 | 改造后两次测量 |
| --- | --- | --- |
| 普通重入的 activation | 886.53 / 500.92 ms | 37.02 / 3.71 ms |
| activation 中的 rebuild | 885.60 / 500.08 ms | 22.40 / 3.12 ms |

原 rebuild 每次读取全库并组装所有相关唱片；改造后的普通重入复用持久化投影，仅核对当前现场及播放证据。Time Profiler 的约 50 秒改造后录制没有报告超过 250 ms 的 hang。以上是主线程区间的 wall time，两次样本不足以估算 P95，也不代表整页完成动画的时间；自动化 AX 截图开销和共享模拟器调度不能作为应用切页耗时。

签名构建已检查 iCloud container entitlement，安装启动后的应用进程存活。93 项相关 XCTest 通过，覆盖缓存、冷启动、浏览、加载、生命周期、当前现场播放状态、删除和本地化；架构 guard 与 `git diff --check` 通过。以下 3 项跨合辑卷播放测试在原 HEAD 已复现相同失败，本轮验证明确跳过：

- `testCompilationPlaybackUsesOneQueueAcrossVisibleVolumes`
- `testCrossingCompilationVolumesKeepsPlayingWithTheRoomOnScreen`
- `testStoppedPreviousAcrossCompilationVolumesLandsOnTheLastTrack`

回归负对照已证明原实现会重复请求完整曲库、保留全库模型、接受退休现场的加载状态和漏掉加载中的改名；清空现场与隐藏页先重绑的回归也在修复前分别触发 6 条和 4 条预期失败。临时热门歌曲使用缓存发行日期的已有行为继续成立。

原始 trace、导出的采样与测试日志保存在 `/tmp/beforeshow-listening-perf-20261013/` 及 `/tmp/beforeshow-listening-*-tests.log`，未加入 Git。
