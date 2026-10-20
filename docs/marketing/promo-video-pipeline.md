# 宣传短片制作流程

首支宣传片（2026-10）沉淀下来的做法。故事是：拼盘演出里很想看 Bad Sweetheart，好久没去现场有点犹豫 → 用「开场前」睡前连听几晚 → 买票 → 到现场跟唱。

故事 → 分镜 → 关键帧 → 图生视频 → 真实录屏 → 粗剪 → 逐段配音 → 配乐 → 封面与发布

核心：先把每段做对再合成整条；画面、配音、音乐分开调，每次反馈只改对应那一层。

## 1. 故事与分镜

- 一个具体的人、一个具体的犹豫，App 帮她跨过去。
- 分镜表每段写清：画面 / 时长 / 旁白 / 来源（AI 镜头 or 真实录屏）。旁白按 Vivi 约 4–5 字/秒控制长度。

## 2. 关键帧（ChatGPT Image，网页版）

- 先出角色设定图（正侧背 + 两套服装 + 面部特写），同一对话里逐镜出 9:16 关键帧。
- 每条 prompt 固定风格词 `cinematic, 35mm film look, shallow depth of field, soft grain`，服装写死（例：灰色圆领套头睡衣，不是开襟款）。
- 出完拼总览图查一致性，不一致的单张重做。生图和评图分开对话。

## 3. 图生视频（Gemini 视频 / Veo）

- 一次只提交一个镜头：首帧 + 只写动作和镜头运动的英文 prompt，强调 keep face/hair/clothing exactly the same、no text、物体不移动/不消失。
- 有生成额度上限，用完要等重置。
- 每段抽帧检查，只取稳定部分；有问题局部重做（首支重做了手机翻面、手机消失两个镜头）。

## 4. 产品画面一律真实录屏

- `xcrun simctl status_bar <udid> override --time 21:41 --cellularBars 4 --wifiBars 3 --batteryState charged --batteryLevel 100`
- `xcrun simctl io <udid> recordVideo --codec=h264 take.mp4`，Ctrl-C（SIGINT）结束。
- 剪之前先转恒定帧率：`ffmpeg -i take.mp4 -vf fps=30 -fps_mode cfr ...`，否则剪切点错位。
- 拖动类手势（取碟装碟）用逐点 touch path 才能录出来；拖动很快，剪辑时放慢。
- 第三方购票页（秀动）用模拟器 Safari 录，停在下单前，绝不提交订单；发布前打码平台 logo。
- 「听」里需要完整播放时，要在登录 Apple Music 的真机上录，模拟器会显示「试听模式」。

## 5. 粗剪 · 配音 · 配乐

脚本在 [`scripts/promo-video/`](../../scripts/promo-video/)，中间文件放在 `~/Downloads/开场前-工作区/`：

- `roughcut.py`：按 `SEGMENTS` 表统一成 1080×1920/30fps；录屏比例更窄，用自身模糊放大垫底；字幕用 PIL + 苹方渲染成 PNG 叠加（本机 ffmpeg 没有 drawtext）；生成结尾 Logo。
- `seg_vo.py`：**逐段配音**。每段单独 TTS，从段首 0.2s 开口；语音比画面长就延长该段末帧，不加速。原视频声音全部静音，只留 TTS。改台词后删掉 `segvo/*.mp3` 缓存再跑。
- `volc_v3.py`：单句合成。
- 成片最后做响度标准化：`-af loudnorm=I=-16:TP=-1.5:LRA=11`。

不要按整条时间轴一次性配音：首支这样做，旁白和画面错位，返工成逐段。

配乐：先拼完整再按场景加。音乐按场景缓慢升降，不跟每句话起伏；切段用等功率交叉淡化，避免音量下陷；到现场前推高。

## 6. TTS · 豆包语音合成 2.0（火山引擎）

- v3 接口 `https://openspeech.bytedance.com/api/v3/tts/unidirectional`，请求头 `X-Api-Key`、`X-Api-Resource-Id: seed-tts-2.0`。账号只开通了 2.0，1.0 音色会报资源不匹配。
- Key 放在仓库根目录 `.env`（已在 `.gitignore`）：`VOLC_TTS_API_KEY=...`。
- 可用女声（`_uranus_bigtts` 后缀）：`zh_female_vv`（Vivi，首支选用）、`zh_female_xiaohe`、`zh_female_shuangkuaisisi`、`zh_female_cancan`、`zh_female_qingxinnvsheng`。

## 7. 封面与发布

- 单独出封面图；准备标题、正文、话题和「AI 演绎」说明，上传后核对。
- App Store 预览视频只能展示 App 自身界面，第三方页面不能用。
