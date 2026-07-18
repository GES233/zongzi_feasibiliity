# zongzi_feasibility 会话交接文档

> 本文件由 Kimi Code 生成，用于跨仓库迁移会话时作为上下文注入。
> **状态更新（2026-07-18）：Track A（toy 引擎 + 可视化验证台）已全部完成并验收（10/10 场景命中）。
> Track B（NPSS）按用户决定搁置——`zongzi-svs` 的 UTAU/DiffSinger 实例将作为真实引擎替代线。**

---

## 1. 项目定位

zongzi 核只负责三件事：**序列真相（Timeline）+ 结构 rebase（Anchor）+ 契约壳（Engine / Declaration / Windowing）**。

`zongzi_feasibility`（`D:/CodeRepo/Qy/zongzi_feasibility`）是这三个库外角色的**可执行参考实现 + 验证台**：

- **Caller**：`ZongziFeasibility.Caller`——编排者。持 note 表，执行编辑，组装 `Anchor.Context` / `Windowing.Context`，跑 rebase → window → check/render 回路。
- **Engine**：`ZongziFeasibility.Engine`——`Zongzi.Engine` behaviour 的 toy 实现，接 toy Python 引擎。
- **Declaration 实现**：`ZongziFeasibility.Declaration.Pitch`——`:pitch` channel 样板。
- **可视化**：每轮对抗自动落 `priv/output/<scenario>/round_NN.png`，汇总 `priv/output/report.html` + `report.json`。
- **Scenarios + Measurer**：G-INT-01/02、G-ENG-02、G-PRE-01..07 全部落地，期望 10/10 命中。

---

## 2. zongzi 核心契约（必读，不要猜）

| 文件 | 关键内容 |
|------|----------|
| `lib/zongzi/engine.ex` | `check/1` 必选，`render/1` 可选；request 是 map，**`segments: [Windowing.Segment.t()]` 必填**；`params` 与 `interventions` 分流。 |
| `lib/zongzi/intervention/declaration.ex` | `scope/2`（静态保守上界，**不能依赖投影**）、`snapshot/2`（挂载时取原始值）、`resolve/2`（`{:ok, artifact} \| {:conflict, reason}`）、`on_rebase/3`（optional）。 |
| `lib/zongzi/intervention.ex` | `Intervention` struct：`id, channel, anchor, payload, snapshot, scope, strategy, declaration`。 |
| `lib/zongzi/anchor.ex` | `Anchor.rebase_all(interventions, timeline, context, opts)` 返回 `%{survived: [], conflicts: []}`；`on_rebase` 的 meta 只有 `%{decision, old_anchor, new_anchor}`。 |
| `lib/zongzi/windowing.ex` | `Windowing.run_stages(ctx, [RestSplit3Beats])` 输出瞬态 `[Segment]`；intervention `scope` 会撑窗。 |
| `docs/zh/spec/decisions/*.md` | 设计决策依据。 |

---

## 3. 当前架构（Track A 已完成）

```
lib/zongzi_feasibility/
  caller.ex             # Caller：new/mount_intervention/edit/window/check_round/render_round/tick_to_frame
  engine.ex             # @behaviour Zongzi.Engine；check/render；params（gender/energy）校验
  engine/python.ex      # System.cmd 桥；run(map) :: {:ok, map} | {:error, String.t}
  declaration/pitch.ex  # scope/snapshot/resolve/on_rebase；telemetry [:zongzi_feasibility, :declaration, :stale]
  scenario.ex           # Scenario behaviour（id/title/setup/edits/expect）+ base_caller/mount 助手
  scenarios/            # g_int_01/02, g_eng_02, g_pre_01..07
  measurer.ex           # 跑批 + console 表 + priv/output/report.{json,html}；telemetry [:zongzi_feasibility, :scenario, :round]
priv/scripts/
  engine.py             # project（含 lyric 联动 preutterance 溢出）；无 apply
  engine_cli.py         # argv[1]=request.json 或 stdin；action: project/visualize
  visualize.py          # baseline vs applied + vuv + note 竖线 + intervention 色块 + spill 标注
config/config.exs       # config :zongzi_feasibility, python:/engine_cli:
```

验收口径（2026-07-18 全绿）：

- `mix compile --warnings-as-errors` 通过。
- `mix test` 22 全绿（单元，不依赖 Python；integration 默认排除）。
- `mix test --only integration` 14 全绿（4 引擎桥 + 10 场景）。
- `mix run -e "ZongziFeasibility.Measurer.run()"` 期望命中 10/10，`priv/output/report.html` 可读。

---

## 4. Track A 实施要点与偏离记录

相对原 A1–A7 计划的实际落地差异：

1. **Request struct 已删**：request 一律用 zongzi 契约 map（`segments` 必填）。
2. **System.cmd 没有 `:input` 选项**（原 engine.ex 从来没真正跑通过）：request 写临时 JSON 文件，路径作 argv[1] 传给 `engine_cli.py`（stdin 模式保留）。
3. **toy 引擎 preutterance 与歌词联动**：`N(note) = preutterance_frames + len(lyric)`。这是 G-PRE 场景"改歌词 → preutterance 前移 → 投影变化"能真实发生的前提。投影输出为 `[[frame, pitch, vuv], ...]` 升序列表（从源杜绝 JSON string-key 漂移）；spill 帧标 `vuv=0`。
4. **坐标分工**：tick 空间权威（control_points/boundary），frame 空间缓存由 Caller 维护（`payload.frames`）；Declaration 不做 tick↔frame 换算。Caller 的 `tick_to_sec` 与 `engine.py` 严格同构。注意 Elixir `round/1`（half-up）与 Python `round()`（half-even）的理论差异，86.13 采样率下实际不触发。
5. **on_rebase 分工**：`Anchor.rebase_all` 给的 meta 无 tick 信息（Timeline 不持 note 字段），所以 move 的 payload/snapshot 平移由 **Caller** 在编辑时做；focus split 由 Caller 注入 `:split_hint`，`Declaration.Pitch.on_rebase/3` 消费并返回 `{:split, [child_a, child_b]}`。
6. **Caller ops**：`edit_lyric / edit_key / split / delete / insert / move / merge`。`edit_key` 是计划外新增（G-INT-02 需要确定性改变 boundary 内投影）。`move` 是 tick 平移（drag），不是链序重排。
7. **场景设计要点**：G-INT-01 用 `preutterance_frames: 0` + nil lyric（否则 split 在切点引入新 preutterance 导致 child_a 合理 conflict——该行为本身正确，happy path 需隔离）；G-PRE-05 的 gap 要计入 scope ±240 撑窗（4.5 拍才切两窗）；G-PRE-04 两轮逼近演示"判假不 conflict、判真才 conflict"。
8. **根目录 `config.exs` 原不被 Mix 加载**，已并入 `config/config.exs`（含原 pythonx 配置）。
9. `Measurer` 的 round 记录含 `decisions`（preserve/rebase/relocate/split/conflict，由 `Caller.edit` 标注）。

---

## 5. Track B：NPSS 线（已搁置）

用户决定：NPSS 搁置，`D:/CodeRepo/SingingSynthesis/zongzi-svs` 的 UTAU/DiffSinger 实例作为真实引擎替代（PoC 已跑通，需打磨）。`config/config.exs` 里保留的 pythonx/onnxruntime 配置即为该方向预留。

若未来恢复 NPSS：

1. 开带卡 AutoDL 实例（云端路径 `/root/autodl-tmp/NPSS`），用 `/root/miniconda3/bin/python` 冒烟云端 `scripts/dataset.py`（y 右移 +1 修复已同步）。
2. 先训 harmonic 50–100 epoch，用 `scripts/inference_spike.py` 探针验收（shift 表峰值 +1、末帧扰动增益 ≈ 0、短程 AR 不发散）。
3. 全量 4 模型重训 → 导出 ONNX → 下载本地。
4. 新增 `ZongziFeasibility.Engine.NPSS`（A3 的 request 契约不变，直接替换后端）。

---

## 6. 下一步（Track A 之后）

- **接 zongzi-svs 真实引擎**：参考 `ZongziFeasibility.Engine` 实现新的 Engine 适配器（UTAU / DiffSinger），`check/render` request 契约不变；G-PRE 场景可从 toy 语义平移到真实 preutterance。
- **snapshot 归一化的浮点口径**：toy 引擎确定性良好；真实引擎需确认同版本同输入逐位可复现，否则按 declaration-projection-resolution 的口径在序列化侧归一化。
- `pythonx` 依赖目前闲置（Track A 用 System.cmd 桥），接真实引擎时启用。

---

## 7. 相关路径速查

| 项目 | 路径 |
|------|------|
| zongzi_feasibility | `D:/CodeRepo/Qy/zongzi_feasibility` |
| zongzi | `D:/CodeRepo/Qy/zongzi` |
| zongzi-svs（UTAU/DiffSinger PoC） | `D:/CodeRepo/SingingSynthesis/zongzi-svs` |
| NPSS 本地（搁置） | `D:/CodeRepo/SingingSynthesis/NPSS` |
| NPSS 云端（搁置，已关机） | `root@connect.weste.seetacloud.com:48036:/root/autodl-tmp/NPSS` |
