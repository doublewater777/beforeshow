# Issue #364 实际验证执行计划

给执行模型：按顺序执行，逐项记录，不修改产品代码来让验证通过。本文是验证计划，不是已经完成的验证报告。

需求：<https://github.com/doublewater777/beforeshow/issues/364>

工作目录：`/Users/water/Desktop/dev/beforeshow`。

## 1. 任务、权限和最终产物

你的任务是验证当前工作区中 #364 的实现，并提交本地验证报告。你不负责继续开发、提交、推送或发布。

必须验证三类事实，分别给结论：

1. **规则**：频率、队列、时区、收听证据、降频、旧载荷兼容。
2. **系统边界**：生产 App 确实把请求交给系统；系统确实投递；点正文和点「播放」经过真正的通知 delegate。
3. **最终用户结果**：打开对应唱片、不误播放；播放入口实际播放可播放曲目；失效目标安全回退；没有额外权限弹窗或 presentation 接力。

以下行为在本次任务内允许：读代码、构建、运行已有测试、安装覆盖同 bundle 的 Debug 构建、在指定模拟器观察操作、创建名称以 `QA364-` 开头的测试现场、临时提前一条属于该测试现场的既有系统通知请求。

以下行为需要另行取得用户授权：卸载 App、擦除模拟器、清空数据库、重置系统权限、修改 Apple ID/订阅、接管他人占用的调试或设备会话、删除既有用户数据。通知或音乐系统权限尚未决定时，让用户完成系统选择；不要擅自重置成方便测试的状态。

禁止：

- `git reset`、`git clean`、`git stash`、覆盖他人改动、批量删除通知。
- 建一个只含 HEAD 的新 worktree 后声称验证了本实现：当前实现尚未提交。
- 用新增测试专用按钮、UserDefaults key、生产开关或 mock 来绕过实际流程。
- 为了让用例通过而改系统日期、修改生产持久化记录或伪造实际收听证据。
- 把「读了实现」「单测通过」「打开深链成功」「点击动作成功」「真实有音频」当成同一证据。
- 提交截图、临时日志、账号信息、密钥。报告中的用户现场和账号信息须脱敏。

最终交付：一个本地报告文件、每个用例状态及证据路径、发现的问题及最短复现步骤、未验证项和具体阻塞原因。证据放系统临时目录，不进 git。

## 2. 执行前读这些资料

按顺序读取：

1. 仓库根目录 `AGENTS.md`。
2. `apps/ios/ARCHITECTURE.md`。
3. `.agents/skills/test-audit/SKILL.md`。
4. `/Users/water/.agents/skills/test-app/SKILL.md`。
5. `/Users/water/.agents/skills/device-hub/SKILL.md`。
6. `docs/adr/0045-schedule-current-show-listening-reminders.md`。
7. issue #364：使用 `gh issue view 364 --repo doublewater777/beforeshow --comments`。

如果资料与本文的某个操作冲突，先按用户明确要求和仓库约束处理，并在报告记录冲突。已明确的需求决定：**沿用现有系统通知权限，没有独立「准备」开关，不新增设置或 UserDefaults key。** 不要把缺少该开关报成 bug。

## 3. 固定环境与源码指纹

指定设备：

- 名称：`beforeshow iphone 18 pro`。
- UDID：`09A7C382-C1EB-41F6-BAEB-3B6B922D4B74`。
- Bundle：`com.doublewaterapps.beforeshow`。
- Scheme：`BeforeShow`。
- Development Team：`29C8MS76CZ`。

不要选择另一个仅名为 `iPhone 18 Pro` 的模拟器。先列出设备核对 UDID；如果设备不存在，停止设备相关步骤并报告 BLOCKED，规则测试仍可记录其环境问题，不要静默换设备。

在 shell 一次执行以下初始化；之后每次新 shell 均须重新设置 `QA364_DIR` 为这里打印出的真实路径，不能重新 mktemp 后丢掉旧证据。

```bash
cd /Users/water/Desktop/dev/beforeshow
QA364_DIR="$(mktemp -d /tmp/beforeshow-364-qa.XXXXXX)"
printf '%s\n' "$QA364_DIR"
git rev-parse HEAD > "$QA364_DIR/head.txt"
git status --short > "$QA364_DIR/status-before.txt"
xcodebuild -version > "$QA364_DIR/xcode-version.txt"
xcrun simctl list devices available > "$QA364_DIR/devices.txt"
python3 - "$QA364_DIR" <<'PY'
import hashlib, pathlib, subprocess, sys
root = pathlib.Path.cwd()
names = subprocess.check_output([
    'git', 'ls-files', '-m', '-o', '--exclude-standard', '-z', '--',
    'apps/ios', 'docs/adr/0037-recommend-unused-features-through-notifications-and-countdown-card.md',
    'docs/adr/0045-schedule-current-show-listening-reminders.md'
]).decode().split('\0')
rows = []
for name in sorted(set(filter(None, names))):
    p = root / name
    rows.append(('DELETED' if not p.is_file() else hashlib.sha256(p.read_bytes()).hexdigest()) + '  ' + name)
(pathlib.Path(sys.argv[1]) / 'source-fingerprint-before.txt').write_text('\n'.join(rows) + '\n')
PY
```

当前实现基线 HEAD 曾是 `ce4727f7d5e77def318f9a934e46126ae790ac5a`，但以本次实际输出为准。HEAD 相同不代表工作区相同，必须保留未提交文件指纹。

注意已有其他任务的改动，至少包括以下两个文件；它们不属于本任务，不修改、不回滚、不暂存：

- `apps/cloudbase-functions/src/functions/parseShowLink/platformDetector.js`
- `apps/cloudbase-functions/test/parseShowLink.test.js`

验证结束再运行同一指纹脚本，输出到 `source-fingerprint-after.txt`，对比前后。除本地报告外，验证不应产生产品源码改动；若执行中别人更新源码，记录时间并对受影响用例重跑，不能混合两版结果。

## 4. 第一阶段：静态约束、签名构建、启动

### A01 基本检查

```bash
cd /Users/water/Desktop/dev/beforeshow
git diff --check
python3 apps/ios/scripts/check_architecture.py
```

分别保存命令、退出码和输出。已有超大文件的受控基线以脚本结果为准；不要自行修改基线来通过。

### A02 独立构建

`QA364_DIR` 必须是第 3 节创建的真实目录。命令中的 `DEVELOPMENT_TEAM` 不得省略。

```bash
cd /Users/water/Desktop/dev/beforeshow/apps/ios
set -o pipefail
xcodebuild -project BeforeShow.xcodeproj -scheme BeforeShow \
  -destination 'platform=iOS Simulator,id=09A7C382-C1EB-41F6-BAEB-3B6B922D4B74' \
  -derivedDataPath "$QA364_DIR/DerivedData" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=29C8MS76CZ \
  build 2>&1 | tee "$QA364_DIR/build.log"
```

必须看到退出码 0 和 `BUILD SUCCEEDED`。仅有 `.app` 文件不算成功，可能是旧产物。

检查本次产物：

```bash
/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.icloud-container-identifiers' \
  "$QA364_DIR/DerivedData/Build/Intermediates.noindex/BeforeShow.build/Debug-iphonesimulator/BeforeShow.build/DerivedSources/Entitlements-Simulated.plist"
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' \
  "$QA364_DIR/DerivedData/Build/Intermediates.noindex/BeforeShow.build/Debug-iphonesimulator/BeforeShow.build/DerivedSources/Entitlements-Simulated.plist"
```

预期分别含 `iCloud.com.doublewaterapps.beforeshow`、`group.com.doublewaterapps.beforeshow`。缺少 iCloud entitlement 时先报告构建环境失败，不继续把启动闪退归因于通知逻辑。模拟器 entitlement 中没有 WeatherKit，不据此单独报本 issue 回归。

### A03 安装并观察启动存活

设备未启动时仅启动指定设备。已启动则跳过 boot。

```bash
xcrun simctl bootstatus 09A7C382-C1EB-41F6-BAEB-3B6B922D4B74 -b
xcrun simctl install 09A7C382-C1EB-41F6-BAEB-3B6B922D4B74 \
  "$QA364_DIR/DerivedData/Build/Products/Debug-iphonesimulator/BeforeShow.app"
xcrun simctl launch --terminate-running-process \
  09A7C382-C1EB-41F6-BAEB-3B6B922D4B74 com.doublewaterapps.beforeshow
```

保存本次返回 PID；等待约 3 秒后用 `ps -p <本次PID> -o pid=,etime=,comm=` 确认存活，并通过设备截图确认 App 已显示。PID 不存在或两秒内退出：保留 crash log、控制台栈，先查签名，A03 失败。不要复用上次运行的 PID。

## 5. 第二阶段：已有自动化回归

### A04 执行明确范围的测试

```bash
cd /Users/water/Desktop/dev/beforeshow/apps/ios
set -o pipefail
xcodebuild -project BeforeShow.xcodeproj -scheme BeforeShow \
  -destination 'platform=iOS Simulator,id=09A7C382-C1EB-41F6-BAEB-3B6B922D4B74' \
  -derivedDataPath "$QA364_DIR/DerivedData" \
  -resultBundlePath "$QA364_DIR/issue364-tests.xcresult" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=29C8MS76CZ \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:BeforeShowTests/ListeningNotificationEntryTests \
  -only-testing:BeforeShowTests/ListeningReminderSchedulingTests \
  -only-testing:BeforeShowTests/ListeningReminderRosterTests \
  -only-testing:BeforeShowTests/LocalNotificationSchedulingTests \
  -only-testing:BeforeShowTests/FeatureRecommendationTests \
  -only-testing:BeforeShowTests/CurrentShowSessionTests \
  -only-testing:BeforeShowTests/ListeningRoomLifecycleTests \
  -only-testing:BeforeShowTests/ListeningArtistPreferenceTests \
  -only-testing:BeforeShowTests/ListeningBrowseTests \
  -only-testing:BeforeShowTests/ListeningCompatibilityTests \
  -only-testing:BeforeShowTests/ListeningArtistLibraryTests \
  test 2>&1 | tee "$QA364_DIR/tests.log"
```

首次结果包路径必须不存在；重跑使用 `issue364-tests-rerun1.xcresult` 等新路径，不删除原失败证据。

预期：退出码 0、`TEST SUCCEEDED`、实际执行了上述 suite，零失败。此前同范围是 144 tests，不能直接复制该数字作为本次结果；新增/删除测试会改变总数。出现零测试或只编译成功不算通过。

`-collect-test-diagnostics never` 是为了避免此前失败后诊断收集长时间挂起，不会把失败改成成功。挂起时保留最后输出和运行状态，不杀其他项目的 Xcode/test 进程。

### A05 阅读关键断言，填写规则覆盖表

读以下三个测试文件；确认测试实际执行、断言与此表一致。不得仅凭函数名打勾，也不新增与现有断言重复的测试。

| 规则 | 已有主要证据 | 应确认的结果 |
| --- | --- | --- |
| 添加当天可排无缓存提醒 | `testUncachedArtistGetsAnEveningReminderFromTheDayTheShowIsAdded` | 演出当地 20:00；艺人兜底；最多每三天 |
| 单艺人队列 | `testSingleArtistStartsWithSingalongThenLatestAlbumThenFeaturedPlaylist` | 大合唱→最新非单曲专辑→精选；后续新歌、深挖及其余专辑核对实际断言 |
| 多艺人队列 | `testFestivalRotatesArtistsAndInsertsACompilationAfterEveryTwo` | 想看/演出时间/阵容排序；每两艺人穿插主题；随后旧专辑 |
| 忽略降频与恢复 | `testThreeIgnoredRemindersThinOutUntilListeningResumesAndTodayStaysQuiet` | 三次未收听后按 T%3；收听当天不排，之后恢复 |
| 过去节点与完成证据 | `testPastNodesKeepTheirPlaceCompletedDiscsAreSkippedAndExhaustionRepeatsEveryOtherDay` | 过去节点占位；全曲真实听过才跳；队列耗尽隔天大合唱 |
| 功能推荐避让 | `testNotificationRecommendationsLeaveListeningToItsOwnRhythm`、`testPassingAFeatureRecommendationDayDoesNotShiftFutureDiscs` | 听不再是通知功能推荐；推荐日不重复听提醒，过去推荐日不重排后续唱片 |
| T-1 与当天合并 | `testFinalRemindersShareExistingNodesAndKeepTheShowDayBodyOnTheRoute` | 不多出独立节点；当天正文 route、动作 listen |
| 日界线与 DST | `testCadenceBoundariesAndStableIdentifiersKeepEventLocalEightPMAcrossDST` | T31/30、T15/14、T2/1；演出时区 20:00、稳定 ID |
| 排除偏好、单曲、真实证据 | `ListeningReminderRosterTests` | 排除艺人真从合辑去除；手动熟悉不等于已听；唱片 ID 与 UI 一致 |
| 正文/播放/缺试听 | `testBodyOpensDetailsAndPlayActionStartsPreviewWithoutRequestingMusicAuthorization` | 正文不播放；动作选首个可播放曲；授权请求次数 0 |
| 午夜后续播 | `testResumingTheSameSongOnANewDayRefreshesTheShowsLastListeningTime` | 同曲跨日恢复会刷新当前现场收听日期 |
| 失效唱片与旧载荷 | `testMissingDiscsFallBackToTheArtistAndLegacyPayloadsStillOpenTheRoom` | 艺人范围/全现场回退，旧载荷仍进入听 |
| 机械操作冲突 | `testPlayWaitsForAnExistingDiscInsertionInsteadOfDroppingTheRequest` | 等待完成后处理，不丢新播放 |
| 未连接艺人回退 | `testUncachedNotificationShowsTheRecommendedArtistsShelfWithoutAuthorization` | 对应艺人范围可见；自动匹配后映射真实艺人 ID |
| 加载时换艺人 | `testAnArtistReplacedWhileEntryLoadsFallsBackToTheWholeShow` | 不把旧槽位错误映射到新艺人 |
| 上限/重排/串行化 | `LocalNotificationSchedulingTests` | 查找相关实际断言，确认 56 上限、旧请求撤销、收听后清理、并发重排顺序 |

表中某条只有实现、没有测试断言时写「覆盖缺口」，不能写测试通过。具体固定日期以测试源码为准，不把示例日期硬套当前系统时间。

不要为了测试跨月、三次忽略和 DST 去改变模拟器系统时钟。这里的确定性测试是时间规则的主要证据，实际系统投递在下一阶段验证。

## 6. 第三阶段准备：真正的 App 与系统通知

### B00 连接设备和调试器

1. 用 Device Hub `open_device_hub`、`device_hub_status`，选指定 UDID，`device_connect`，记下 session ID。
2. 操作前先 capture/get state。按钮优先用最新 accessibility selector；坐标必须来自本次截图的逻辑坐标，不复制旧坐标。
3. 每步执行「观察→操作→观察」。截图保存到第 3 节证据目录，并记录绝对路径。
4. 如需 LLDB，用 Xcode 工具选择 `apps/ios/BeforeShow.xcodeproj`、BeforeShow scheme、指定模拟器，`RunProject(attachDebugger:true)`。
5. 先 `InvokeDebuggerCommand("process status")`；表达式前进程须停止，可在属于本任务的运行会话中 `process interrupt`，表达式后 `continue`。回调只有进程恢复运行后才会执行，不要暂停着等待异步输出。
6. 若已有会话属于别人，不能抢占。无法取得自己的调试会话，标记下面的通知提前步骤 BLOCKED，仍可完成无调试器的 UI 检查。
7. Xcode Run 可能重新构建。保存其 build log，确认源码指纹未变、目标设备正确；不要把 CLI 构建产物与另一个源码版本的 GUI 运行混为一谈。

### B01 建立可辨认的生产测试数据

**不带任何 `--listen-fixture` 启动参数**，用正常 App、正常持久化容器。

1. 截图记录原来的当前现场和系统通知状态，便于恢复。
2. 通过正常新增现场 UI 新建 `QA364-SINGLE-<本次时间>`，开场时间为演出当地未来 10 天 20:00，选择明确时区，艺人填写可查到的真实艺人，例如 Aimer。
3. 通过实际 UI 的「设为当前」或「设为展示」入口设为当前，观察首页名称确认成功。标签可能随入口不同；看实际界面，不能凭空点击不存在的入口。
4. 不先播放。进入「听」，正常加载已有许可下可获取的曲库，记录大合唱、专辑/歌单可见的标题。若需用户主动授权才能加载，由用户明确操作；不要把通知入口自己弹出的音乐授权当成正常。
5. 回到设置确认现有「开场提醒」通知状态。若尚未授权，在用户允许后由用户点现有设置入口完成系统授权。记录前后状态。
6. 返回正常界面，等待排程完成，检查 Xcode 控制台。Debug 设置中的「打印待发通知」只用于排程观察，不是发送测试通知按钮。
7. 核对系统待发列表，取得**此测试现场实际生成**的 show UUID、请求 identifier、fireDate、category、userInfo，保存原始输出。

若当前权限被拒绝或曲库不可用：如实记录；不要重置权限。可以继续验证无缓存艺人兜底和拒绝状态；缓存唱片/播放部分写 BLOCKED。

测试现场可能同步到用户 CloudKit。只创建必要的测试现场，先不批量创建几十场。结束后恢复原当前现场；删除测试现场需用户许可，未删除则报告名称清单。

### B02 读取系统真实待发请求

优先用 Xcode 控制台。下面 Swift LLDB 表达式是操作模板，**本计划撰写时未实际运行这些调试表达式**；不同 Xcode 的表达式上下文可能需要在 Swift 源文件 frame 下执行。不得因表达式失败就改产品源码。

先暂停，再依次执行：

```text
expression -l Swift -- import UserNotifications
expression -l Swift -- UNUserNotificationCenter.current().getPendingNotificationRequests { requests in for r in requests { print("QA364_PENDING", r.identifier, "TITLE", r.content.title, "BODY", r.content.body, "CATEGORY", r.content.categoryIdentifier, "THREAD", r.content.threadIdentifier, "INFO", r.content.userInfo, "FIRE", r.trigger?.nextTriggerDate() as Any) } }
continue
```

通过 GetConsoleOutput 读取 `QA364_PENDING` 行；异步输出不一定出现在表达式的直接返回中。若 LLDB 不能解析模块，先检查运行的是 Debug、frame 是否 Swift、设备与项目是否正确；最多修正上下文重试一次，再交给人工在 Xcode Debug Console 执行或记为 BLOCKED，不无限试表达式。

核对：

- 选中的听提醒 identifier 为 `<showUUID>.listeningReminder.<Unix秒>`。
- category = `listeningReminder`，thread = 该 show UUID。
- userInfo 的 showID 对应测试现场；destination 通常为 listen；有缓存时 discID 对应真实唱片，无缓存时有可识别的艺人范围。
- 触发时间换算成演出时区应为 20:00。系统 trigger 可能打印 UTC，不把 UTC 20:00 当成当地 20:00。
- 当前已有实际收听的当天不能有新的听提醒；其他现场不应有独立 listeningReminder，但普通开场通知可存在。
- 总待发上限 56；不要为手工验证上限在用户库里创建 60 场，使用 A05 自动化证据。

只靠 Debug「打印待发通知」的标题/时间不够证明完整 userInfo 和 category；这两项须读取系统对象或明确记未验证。

### B03 仅提前已有通知的投递时间

目的：不等到 20:00，验证真实系统投递/正文/播放链路。它**不能**证明原生产日历 trigger 已按时触发。

1. 从 B02 复制一条测试现场的完整真实 identifier。先截图/保存其原始 fireDate、content、category、userInfo。
2. 仅对这一条请求使用原 identifier 和原 content，换成 15 秒后的一次性 trigger。不得手填 discID、artistID 或 destination 来让正常路径成立。
3. 进程暂停时执行下面表达式，把 `REPLACE_WITH_EXACT_REQUEST_IDENTIFIER` 替换为刚查到的完整 identifier，不保留占位符：

```text
expression -l Swift -- UNUserNotificationCenter.current().getPendingNotificationRequests { requests in guard let r = requests.first(where: { $0.identifier == "REPLACE_WITH_EXACT_REQUEST_IDENTIFIER" }) else { print("QA364_ACCELERATE_MISSING"); return }; let accelerated = UNNotificationRequest(identifier: r.identifier, content: r.content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15, repeats: false)); UNUserNotificationCenter.current().add(accelerated) { error in print("QA364_ACCELERATE_RESULT", r.identifier, error as Any) } }
continue
```

4. 确认控制台 `QA364_ACCELERATE_RESULT` 的 error 为 nil，马上按 Home 把 App 放后台。不要停留 App 内等待横幅。
5. 约 20 秒后观察通知中心/横幅，截图通知完整标题与正文。一次普通提醒默认无声音，不要求通知铃声。
6. 看不到横幅时打开通知中心查看；App 的 `willPresent` 返回空展示选项，前台没有横幅是预期，不能据此报错。检查系统权限、专注模式、App 是否真的后台、请求是否被正常重排撤销。
7. 如果请求在到时前已被 reconcile 撤销，记录其原因并重新读取实际 pending；不要关闭排程逻辑或改源码强行投递。找不到可提前的真实请求则标 BLOCKED。

此步骤覆盖了系统实际接收、投递和点击；报告必须标注「投递时间被临时提前」。不要写「已实测每天 20:00 自动到达」。不要使用 `simctl push` 替代：那是远程通知注入，不是这里的本地通知排程。

## 7. 第四阶段：逐项实际操作

所有 B 用例都记录：前置状态、精确 identifier、操作序列、动作前后截图、预期/实际、是否提前触发、是否使用真实音源。

### B04 点通知正文，只打开详情

前置：B01 有缓存真实唱片；当前播放器未播放；B03 生成一条系统可见通知。

1. 先记录播放器状态与当前曲目，确认没有正在播放的音频。
2. 点通知**正文区域**，不要长按后点「播放」。
3. 等 App 完成加载，观察「听」页和对应唱片详情。
4. 对比 B02 的 discID 与 UI 唱片标题/归属，必要时通过实际 room 状态辅助确认，不能只看进入了听 Tab。
5. 观察至少 5 秒：没有开始播放、没有曲目自动推进、没有音乐授权弹窗、没有第二个不必要确认。

通过条件：正确现场、正确唱片详情、播放未启动。只到听首页而缓存目标仍存在，判失败；若目标已失效，转 B08，不能把回退当 B04 成功。

### B05 点「播放」，实际有可播放结果

前置：重新取同测试现场另一条真实听提醒并 B03；已有有效真实音源。B04 消耗掉的系统通知不能假装还存在。

1. 展开/长按系统通知，截图可见的「播放」动作。若系统英文则应为本地化 Play。
2. 点动作，等待 App 前台和播放器装载完成。
3. 确认播放的唱片属于通知目标；播放的是首个可播放曲目，不要求总是曲目列表第一个。
4. 分别记录「UI 处于播放态」「进度持续增加」「用户/可用音频工具确认听到实际声音」。三者不互相代替。
5. 如果没有完整音乐权限但有有效试听，应走真实试听且不弹音乐授权。没有有效试听/完整播放资格则不能宣称实际播放通过。
6. 观察一次插入/加载期间是否丢掉动作、卡死或要求第二次确认。

通过条件：动作真实来自系统通知；目标正确；真实播放进度前进；无通知入口主动音乐授权。音频是否实际听到单独列出；如果只能看到进度，把真实音频项标 BLOCKED，不能用“应该有声”代替。

**不要用 fixture 假播放器证明这一项。** 如果宿主设备静音/音频输出不可观察，写具体限制，保留其他已证明的子结论。

### B06 开始实际收听后，撤销当日提醒及已送达提醒

本用例最好在 B05 前预备，避免完成 B05 后才发现当天已经变成有收听状态。

1. 在未收听的 QA 现场准备两条不同 identifier 的真实 listeningReminder。
2. 分别用 B03 提前并投递，确认通知中心里能观察到至少一条尚未被点击移除的该现场听提醒。系统分组时展开组核对，不把组折叠当已撤销。
3. 用另一条通知的播放动作或正常听页开始真实收听，记录曲目和收听时间。
4. 等生产 reconcile 完成，重新读取 pending 和 delivered：

```text
expression -l Swift -- UNUserNotificationCenter.current().getDeliveredNotifications { notifications in for n in notifications { print("QA364_DELIVERED", n.request.identifier, n.request.content.title, n.request.content.userInfo) } }
continue
```

执行表达式前仍须暂停；回调前恢复。不要在运行状态连续发送要求停止进程的表达式。

5. 检查通知中心和系统对象：该现场的已送达 listeningReminder 被撤销；当晚听提醒不再待发；其他现场和其他类型通知没有被一并删除。
6. 若被点击的那一条消失，但另一条仍在，不能说清理通过：点击本身就会移除通知。
7. 若没有两条可用请求，不手工伪造额外提醒；标此项受数据限制，自动化清理测试结论另列。

### B07 没缓存的艺人通知回退

1. 新建 `QA364-UNCACHED-<时间>`，未来 10 天，有艺人名称，设为当前；在正常 App 中保持尚未建立本地曲库缓存。
2. 先读取真实 pending，确认艺人兜底请求确实来自该现场。保存 payload。
3. B03 提前，点正文。
4. 预期进入听，能看到对应推荐艺人范围/唱片架；如果加载时自动匹配成功，范围映射到该艺人的真实 ID。
5. 不应自动请求音乐授权，不应串到另一个艺人；如果艺人无可用唱片，允许正常空状态，但不是空白卡死。
6. 若添加流程已自动缓存，当前样本不成立，记录此事实，不通过清数据库制造“无缓存”；找自然未缓存测试艺人或标 BLOCKED。

### B08 唱片失效与旧通知

分开记录生产样本和合成兼容载荷，不能把合成载荷称作生产排程证据。

- **生产样本优先**：保留真实已投递通知后，通过正常 UI 修改仅测试现场的艺人/排除偏好，使目标自然不可见，再点旧通知。预期回到有效艺人范围或全现场听页，不播放错误唱片、不崩溃。
- 如果正常操作不使目标消失，不强改数据库；自动化相关测试通过只计规则证据，实际失效用例标 BLOCKED。
- **旧载荷边界**：如要实际验证旧版 payload，可由调试器从 QA 现场既有请求复制 mutable content，仅移除 `discID/artistID/artistName`，保留 showID/destination，另给明确 `qa364-legacy-` identifier 后投递。事先记录这是合成兼容请求，需人工/有能力的执行者确认表达式再做。弱模型不要自行发明一段未经验证的注入代码。
- 没做合成投递时，报告中旧 payload 只记 A05 自动化通过，系统兼容点击未实测。

### B09 冷启动与重入

1. 前提：已有一条真实系统已投递的 QA 通知。
2. 终止的是本任务的 App 进程，不卸载、不清数据。用 `simctl terminate <指定UDID> com.doublewaterapps.beforeshow` 或停止自己的 Xcode Run。
3. 点通知正文，确认冷启动后正确详情，不自动播放。保存启动至目标界面的观察记录。
4. 若可再次投递，分别验证前台已在听页和后台恢复两种状态。
5. 两条不同目标通知连续进入的最终目标应为最后一次用户操作；无法稳定制造时记未实测，以自动化并发证据补充，不用快速乱点导致不可追踪的结果。

### B10 编辑界面与 presentation 顺序

1. 先在 QA 现场打开正常编辑 sheet，填写一项但不提交，不动其他用户数据。
2. App 放后台，B03 对已有请求提前并投递；如调试需要前台，要先完成调试再重新保持编辑 sheet 状态并后台，确保触发时 sheet 真实存在。
3. 点通知正文返回 App。
4. 预期不在编辑 sheet 上叠新的唱片详情/确认/音乐权限；通知导航等待现有 presentation 结束。
5. 通过正常关闭/取消结束 QA 编辑，再确认只进入一次目标唱片详情。
6. 如果流程实际没有保留 sheet，则本次不满足前置条件，应重做一次或标未验证，不能据此判断导航 gate 正确。

### B11 T-1 与开场当天：正文和动作语义分开

1. 用正常 UI 新建另一个 QA 现场为演出当地明天开场，设为当前，查看 pending。
2. 预期合并在原 `oneDayBefore` 节点，带音乐目标时有 listeningReminder category；不额外排同一天独立 listeningReminder。单艺人大合唱，多艺人优先想看节目。
3. 另建 QA 现场为演出当地今天、当前时间之后至少 4 小时开场，设为当前，查看开场前三小时节点。若当地日内剩余时间不足，标当天样本 BLOCKED，不改系统时间。
4. 当天节点正文 destination 必须仍为 route。提前投递后点正文，预期路线页。
5. 对同类另一条可重新生成的请求验证「播放」动作，预期听页/对应节目，不是路线页。
6. 不要为了第二次投递直接拼一个正常路径 payload；如果无法重建真实请求，只记录已验证的那一半，其余靠自动化并明确界限。

### B12 当前现场切换及本地化

1. 同时保留两个 QA 现场，记录谁为当前。切换后读取 pending：独立听提醒只属于新当前，旧当前的普通开场节点可保留。
2. 点击旧现场仍有效的通知，核对打开目标现场，同时持久化“当前现场”选择不被通知点击永久改写。
3. 通过支持的 App 语言设置或 scheme 的本次启动参数分别观察简中、繁中、英文。不要改全设备语言而不恢复。
4. 对已有真实请求核对标题、正文、「播放」动作没有裸 key、占位符、错误艺人名或截断到无法理解。
5. 系统已经注册的 action 文案可能要重启 App 才更新，旧的已送达通知也可能保留旧文案。每种语言重启、重新读取和投递，不能拿旧通知报翻译错误。
6. 对未实际跑到的语言写 NOT RUN；静态 xcstrings 存在不等于实际系统通知已验证。

## 8. fixture 只能作为补充检查

可用场景例如 `single-full`、`multi-full`、`preview-only`、`metadata-only`、`unmatched-artist`。使用前读 `ListeningDebugFixtures.swift`，确认场景当前还存在。

以下限制必须写在报告中：

- fixture 使用内存 ModelContainer；每次 launch 的 show UUID 随机。
- 听 feature 的 fixture 容器不能代表 LocalNotificationCenter 的生产容器。
- fixture 播放器是假的；`preview-only` 的示例试听 URL 是 `example.invalid`，不可能证明真实音频。
- `fixture-album-0`、`fixture-artist-0` 不能拿去拼生产 show 的成功通知。
- fixture UI 可验证唱片架、加载态、回退展示；不能替代 B01–B06 的生产排程和真实系统点击。

若使用 fixture，所有用例 ID 另起 `F01...`，不把截图贴到 B05 冒充真实播放。

## 9. 失败、阻塞、重试规则

每个用例只能填写以下状态之一：

- **PASS**：前置满足，实际操作和预期一致，有本次证据。
- **FAIL**：前置满足，实际结果违反预期。重现一次并记录两次结果；不修改代码。
- **BLOCKED**：因权限、账号、真实音源、调试器、数据条件或环境无法完成；写确切卡在哪一步、需要谁做什么。
- **NOT RUN**：尚未执行。不能改写成“看起来没问题”。

失败分类：

| 现象 | 先检查 | 不允许的处理 |
| --- | --- | --- |
| 启动即崩溃 | 本次 entitlements、CloudKit 栈、实际 PID | 省略 Team 重签或关闭 CloudKit |
| 没通知横幅 | 后台状态、通知中心、权限/专注模式、pending 是否仍在 | 前台无横幅就报 bug，或者 `simctl push` 冒充 |
| 没听提醒 | 当前现场、开场日、已收听今天、推荐避让、缓存与降频 | 清空收听记录强行排程 |
| 点正文没详情 | payload 的真实 discID、是否自然失效、当前 presentation | 只看到听 Tab 就算成功 |
| Play 没声音 | 真音源、播放资格/试听 URL、进度和宿主音频 | fixture 状态变 playing 就算有声音 |
| LLDB 表达式失败 | 运行状态、Swift frame、模块导入、Debug 会话归属 | 改产品入口、连续乱试无限重启 |
| 系统授权弹窗 | 是否用户主动请求，还是通知入口触发 | 自动授权后掩盖额外弹窗 |

发现明显产品 bug 后保留证据，完成与其无依赖的后续验证。修复应交回开发任务；如果用户另行授权修复，重新按 TDD，并为修复后的源码生成新指纹重跑受影响项。

## 10. 清理和恢复

1. 暂停实际播放。
2. 恢复执行前的持久化当前现场；确认首页名称。
3. 临时提前了的 pending 请求通过正常重排恢复；再次读系统 pending 确认没有未来 15 秒的测试 trigger 残留。只处理已记录的 QA 请求，不 removeAll。
4. 如存在独立 `qa364-legacy-` 合成请求，只按精确 identifier 清理它的 pending/delivered；不要清理用户其他通知。
5. 恢复本次改过的 App 语言、设备外观等设置；不主动重置权限。
6. 测试现场保留名称清单，待用户决定是否删除。不要默认删除。
7. 停止自己的调试 Run，断开自己的 Device Hub session，不影响其他会话。
8. 再取源码指纹与 `git status --short`。确认产品源码无验证引入的改动。日志、截图、DerivedData、xcresult 都在临时证据目录，不暂存。

## 11. 报告模板

把报告写到 `QA364_DIR/report.md`。报告开头直接给三个独立结论，不用笼统“全部通过”。

```markdown
# #364 验证报告

- 规则回归：PASS / FAIL / BLOCKED
- 生产排程及真实系统通知点击：PASS / FAIL / BLOCKED
- 真实播放/音频：PASS / FAIL / BLOCKED
- 测试时间、时区：
- 源码 HEAD + before/after 指纹路径：
- 设备名称、UDID、iOS、Xcode：
- 构建日志、测试日志、xcresult：
- 是否临时提前投递：是/否；实际自然 20:00 投递是否观察：是/否
- 通知权限 / 音乐权限 / 订阅 / 真实试听可用性（不含账号隐私）：

| ID | 状态 | 前置/测试数据 | 实际动作与结果 | 证据绝对路径 | 限制 |
| --- | --- | --- | --- | --- | --- |
| A01 | | | | | |
| A02 | | | | | |
| A03 | | | | | |
| A04 | | | | | |
| A05 | | | | | |
| B00–B12（逐项展开，不能合并一行） | | | | | |

## 发现的问题

- 问题标题：
- 最短复现：
- 预期 / 实际：
- 两次结果：
- 精确请求 identifier / 脱敏 payload：
- 截图、日志与时间戳：
- 影响范围与是否阻止主流程：

## 尚未证明的内容

逐项列出，不能省略真实音频、系统通知动作、自然定时触发等未执行部分。

## 恢复情况

原当前现场已恢复：
临时请求已恢复/清理：
测试现场保留名称：
语言/设备设置恢复：
源码是否变化：
```

验收报告至少有：本次真实测试日志；本次 production pending 样本；一条真正投递的系统通知截图；正文点击后的详情截图；Play 的实际结果；各项失败/阻塞原因。缺少其中任何项就缩小结论，不能套用先前的 144 tests 结果补缺。

## 12. 可直接交给执行模型的提示词

> 在 `/Users/water/Desktop/dev/beforeshow` 按 `docs/agents/verification-plans/issue-364.md` 执行 #364 验证。先读整份计划和引用的技能。只做验证，不修代码、不提交、不推送、不清数据。当前实现未提交，必须验证此工作区并记录源码指纹。只用 `beforeshow iphone 18 pro`，UDID `09A7C382-C1EB-41F6-BAEB-3B6B922D4B74`。先完成 A01–A05，再执行 B00–B12。每步观察、操作、再观察，有证据才 PASS。真机/真实音源/权限或调试器不足时明确 BLOCKED，不用 fixture 或深链冒充本地通知和真实播放。LLDB 模板尚未实测，遇上下文问题最多修正重试一次，不能改产品源码绕过。每分钟以内给简短进展。报告和截图放 `/tmp` 证据目录，最终给报告绝对路径、三类独立结论、问题及阻塞清单，并恢复原当前现场与测试设置。
