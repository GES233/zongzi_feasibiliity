# ZongziFeasibility

zongzi 核三个库外角色的**可执行参考实现 + 验证台**：

- **Caller**（`ZongziFeasibility.Caller`）— 编排者。持 note 表与 interventions，执行编辑，
  跑 rebase → window → check/render 回路。
- **Engine**（`ZongziFeasibility.Engine`）— `Zongzi.Engine` behaviour 的 toy 实现，
  经 `ZongziFeasibility.Engine.Python`（System.cmd 桥）接 toy Python 投影引擎。
- **Declaration 实现**（`ZongziFeasibility.Declaration.Pitch`）— `:pitch` channel 样板：
  控制点 + boundary + snapshot 归一化比对。

可视化是第一优先级：每轮对抗自动落 `priv/output/<scenario>/round_NN.png`，
汇总单文件 `priv/output/report.html`（内嵌 base64 图）+ `report.json`。

## 配置

```elixir
# config/config.exs
config :zongzi_feasibility,
  python: "D:/Conda/python.exe",          # toy 引擎解释器
  engine_cli: "priv/scripts/engine_cli.py"
```

Python 依赖：`priv/scripts/requirements.txt`（numpy + matplotlib）。

## 跑验证

```bash
mix test                          # 单元测试（不依赖 Python）
mix test --only integration       # 集成测试（真实 Python 桥 + 全场景）
mix run -e "ZongziFeasibility.Measurer.run()"   # 跑全部 golden scenario，出报告
```

报告产物：`priv/output/report.html`（每场景卡片：结构决策 / 语义决议 / 期望命中 /
每轮 PNG）、`priv/output/report.json`（机读指标）。

## 场景

对齐 zongzi `GOLDEN_SCENARIOS.md`：G-INT-01/02、G-ENG-02、G-PRE-01..07。
toy 引擎的 preutterance 与歌词联动（`N = preutterance_frames + len(lyric)`），
使"改歌词 → preutterance 前移 → 投影变化 → snapshot 失配"真实发生。

## 结构

```
lib/zongzi_feasibility/
  caller.ex             # Caller 编排（编辑回路 + 坐标换算）
  engine.ex             # Zongzi.Engine behaviour（check/render）
  engine/python.ex      # System.cmd → engine_cli.py 桥
  declaration/pitch.ex  # Zongzi.Intervention.Declaration 实现（:pitch）
  scenario.ex           # golden scenario 契约
  scenarios/            # G-INT/G-ENG/G-PRE 场景
  measurer.ex           # 跑批 + 指标 + console/JSON/HTML 报告
priv/scripts/           # toy Python 引擎（project / visualize）
```
