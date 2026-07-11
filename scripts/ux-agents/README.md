# UX Agents Orchestrator（tmux + Claude Code）

把 `docs/agents/ux-plans/*.md` 丢给 **Claude Code**（`claude -p`）按波次串行执行，避免多 agent 同时改 `RootView.swift` / `ShowToolViews.swift` 撞车。

## 依赖

- `claude` CLI（已测：`~/.local/bin/claude`）
- `tmux`
- 仓库根有 `Agents.md` / `AGENTS.md`
- 已登录 Claude（能跑 `claude -p "ping"`）

## 快速开始

```bash
cd /Users/water/Desktop/dev/beforeshow

# 只看队列
./scripts/ux-agents/orchestrate.sh --dry-run

# 起 tmux：orch 跑队列 + status 轮询 + logs 窗
./scripts/ux-agents/tmux-launch.sh --attach

# 或只跑前两个 plan
./scripts/ux-agents/tmux-launch.sh --only 01,02 --attach

# 从某个 plan 继续
./scripts/ux-agents/tmux-launch.sh --from 05 --attach
```

## tmux 窗口

| 窗口 | 作用 |
|------|------|
| `orch` | `orchestrate.sh` 串行调 `worker.sh` |
| `status` | 每 5s 刷新各 plan 状态 |
| `logs` | 日志目录 |

```bash
tmux attach -t bs-ux
tmux kill-session -t bs-ux
```

## 单 plan 手动

```bash
./scripts/ux-agents/worker.sh 01
# 日志: scripts/ux-agents/logs/01-*.log
# 状态: scripts/ux-agents/status/01.json
```

## 波次（`waves.conf`）

默认 **全串行**（安全）：

1. `01`（首页）
2. `05` → `03` → `04` → `06` → `07`（工具大页，共享 `ShowToolViews`）
3. `08` → `09` → `10`（添加 / 列表 / 详情）
4. `11` → `12` → `13`
5. `14` 视觉收尾

> 「今晚先听」模块已删除；plan `02` 不再存在。

同文件冲突的 plan **不要**并行。若要真并行，请用 **git worktree 每 job 一棵树** 再改本脚本（当前未开 worktree 并行，避免 merge 灾难）。

## Worker 行为

- `claude -p` + `--dangerously-skip-permissions`（无人值守队列必需；仅在你信任本机自动化时使用）
- 注入 plan 路径 + `Agents.md` 硬规则
- **不自动 git commit / push**
- 退出码写入 `status/NN.json`

## 编排者（你 / Grok）职责

1. 开队列前确认工作区干净或可接受大 diff  
2. 跑完后按 plan 验收表 review（可再开 review agent）  
3. 失败看 `logs/NN-*.log`，修 plan 或手改后 `--from NN` 续跑  

## 安全注意

- 会改真实仓库代码  
- 会调用 Claude API（费用）  
- 14 个 plan 全跑可能很久、很贵 — 建议先 `--only 01,02` 试跑
