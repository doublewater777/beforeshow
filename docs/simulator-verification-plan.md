# iOS 模拟器实机验证方案

> 目标：在 `iPhone 18 Pro` 模拟器上验证气象胶囊、气象抽屉与“开场前 3 小时日落现场”通知的完整链路。

---

## 一、前置条件与模拟器启动

确保模拟器为 `iPhone 18 Pro` 并处于运行状态：

```bash
# 1. 启动 iPhone 18 Pro 模拟器
xcrun simctl boot "iPhone 18 Pro" 2>/dev/null || true
open -a Simulator
```

构建并安装最新 App：

```bash
cd apps/ios

# 2. 编译并签名（必须带上开发团队，保证 Entitlements 生效）
xcodebuild -project BeforeShow.xcodeproj -scheme BeforeShow \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=29C8MS76CZ build

# 3. 安装到模拟器
xcrun simctl install "iPhone 18 Pro" $(xcodebuild -project BeforeShow.xcodeproj -scheme BeforeShow -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -showBuildSettings | grep -m 1 TARGET_BUILD_DIR | awk '{print $3}')/BeforeShow.app

# 4. 启动 App 并观察控制台输出
xcrun simctl launch --console-pty "iPhone 18 Pro" app.beforeshow.ios
```

---

## 二、测试场景与操作步骤

### 场景 1：首页气象胶囊与抽屉交互 (UI/UX)
1. **进入有场次的演出**：在首页选择或新增一个演出（城市填入已知城市如 `北京` / `阿那亚` / `上海`）。
2. **气象胶囊状态**：
   - 检查倒计时下方是否展示气象胶囊（温度、天气简况图标、氛围底色）。
   - 点击气象胶囊，验证弹出 `CurrentShowWeatherSheet` 半屏抽屉。
3. **气象抽屉内容**：
   - 抽屉顶部显示场地位置与体感温标。
   - 观演建议卡片：检查是否根据温差/紫外线/降水给出了出行装备建议（如外套、雨具、墨镜）。
   - 日落时段条目：展示日落具体时间及日落时段氛围说明。
   - 关闭抽屉：下滑或点击完成按钮，确认无二次弹窗（符合 Presentation 准则）。

---

### 场景 2：日落乐队与“开场前 3 小时”通知验证

本项验证需要演出满足两个条件：
- **演出日期**：今天（或即将开场）。
- **时间表 (Timetable)**：包含当日 18:00 ~ 19:30（覆盖日落时间）的乐队演出（如 "Sunset Rollercoaster" / "落日飞车"）。

#### 路径 A：应用内真实调度验证
1. 在 App 内为该演出添加时间表，在 18:30 安排一支乐队（例如设定为“落日飞车”）。
2. App 进入后台触发通知调度：
   - `showDay` 通知的触发时间应为开场前 3 小时。
   - 调度文案末尾应附带：`" 今天的日落现场是落日飞车。"`。

#### 路径 B：通过 `simctl push` 模拟通知推送与深链点击
在终端向模拟器直接发送测试推送：

```bash
# 生成临时推送载荷
cat << 'EOF' > /tmp/sunset_notification.apns
{
  "Simulator Target Bundle": "app.beforeshow.ios",
  "aps": {
    "alert": {
      "title": "还有 3 小时开场",
      "body": "还有 3 小时开场，带好门票和证件。今天的日落现场是落日飞车。"
    },
    "sound": "default"
  },
  "url": "beforeshow://show/detail?sheet=weather"
}
EOF

# 发送通知到模拟器
xcrun simctl push "iPhone 18 Pro" app.beforeshow.ios /tmp/sunset_notification.apns
```

**验证预期**：
1. 模拟器顶部弹出通知 Banner，文案包含 `"今天的日落现场是落日飞车。"`。
2. 点击通知横幅，App 被拉起并直接展开对应演出的**气象抽屉**。

---

## 三、检查清单 (Checklist)

| 检查项 | 验证点 | 预期结果 |
| :--- | :--- | :--- |
| **启动稳定性** | `simctl launch` 后进程存活 | 进程常驻无 SIGTRAP 闪退（Entitlements 完整） |
| **胶囊渲染** | 首页倒计时区 | 天气与温差胶囊正常加载，色调跟随日落/夜间氛围 |
| **抽屉交互** | 点击气象胶囊 | 弹出中性导航栏抽屉，包含日落时间与装备建议 |
| **无日落乐队** | 时间表当日无重叠演出的场次 | 通知文案不显示“今天的日落现场是”句式 |
| **有日落乐队** | 时间表有覆盖日落时间的演出 | 通知文案末尾追加 `今天的日落现场是xx。` |
| **深链跳转** | 点击气象深链通知 | 自动路由到指定 Show 的气象抽屉 |
