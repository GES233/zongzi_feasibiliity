# zongzi_feasibility 会话交接文档

> 本文件由 Kimi Code 生成，用于跨仓库迁移会话时作为上下文注入。当前会话原计划：先完成 zongzi_feasibility 的 toy 引擎 + 可视化验证台，再并行修复 NPSS 作为真实后端。

---

## 1. 项目定位

zongzi 核只负责三件事：**序列真相（Timeline）+ 结构 rebase（Anchor）+ 契约壳（Engine / Declaration / Windowing）**。

`zongzi_feasibility`（`D:/CodeRepo/Qy/zongzi_feasibility`）是这三个库外角色的**可执行参考实现 + 验证台**：

- **Caller**：编排者。持 note 表，执行编辑，组装 `Anchor.Context` / `Windowing.Context`，跑 rebase → window → check/render 回路。
- **Engine**：实现 `Zongzi.Engine` behaviour。先接 toy Python 引擎；修复后接真实 NPSS 引擎。
- **Declaration 实现**：以 `:pitch` channel 为样板，实现 `Zongzi.Intervention.Declaration`。
- **可视化**：结果可视化是最高优先级。每轮对抗出图，汇总 HTML 报告。
- **Scenarios + Measurer**：把 `GOLDEN_SCENARIOS.md` 骨架跑成可执行用例，输出存活/冲突指标。

---

## 2. zongzi 核心契约（必读，不要猜）

| 文件 | 关键内容 |
|------|----------|
| `lib/zongzi/engine.ex` | `check/1` 必选，`render/1` 可选；request 是 map，**`segments: [Windowing.Segment.t()]` 必填**；`params` 与 `interventions` 分流。 |
| `lib/zongzi/intervention/declaration.ex` | `scope/2`（静态算 `{start_tick, end_tick}` 保守上界，**不能依赖投影**）、`snapshot/2`（挂载时取原始值）、`resolve/2`（`{:ok, artifact} \| {:conflict, reason}`）、`on_rebase/3`（optional）。 |
| `lib/zongzi/intervention.ex` | `Intervention` struct：`id, channel, anchor, payload, snapshot, scope, strategy, declaration`。 |
| `lib/zongzi/anchor.ex` | `Anchor.rebase_all(interventions, timeline, context, opts)` 返回 `%{survived: [], conflicts: []}`。 |
| `lib/zongzi/windowing.ex` | `Windowing.run_stages(ctx, [RestSplit3Beats])` 输出瞬态 `[Segment]`。 |
| `lib/zongzi/windowing/context.ex` | `timeline` + `notes_by_seq` + `tempo_map` + `interventions` 等。 |
| `lib/zongzi/windowing/segment.ex` | `start_tick, end_tick, seq_ids`，左闭右开。 |
| `docs/zh/spec/decisions/*.md` | 设计决策依据：`control-points-authoritative`（控制点真源）、`declaration-projection-resolution`（snapshot 归一化）、`payload-boundary`（`on_rebase/3`）、`anchor-operate-orthogonality`（结构锚 ⊥ 语义 operate）、`windowing-post-rebase`（硬管道）。 |

---

## 3. zongzi_feasibility 现状（启动前）

目录结构：

```
lib/feasibility/
  engine.ex              # 未实现 Zongzi.Engine，自造 Request struct，硬编码 D:\Conda\python.exe
  engine/request.ex      # 自造 Request struct，要删或改为工具函数
  declaration/pitch.ex   # 契约未对齐：scope 读缓存、resolve 返回 {:skip, _}、payload 用 frame 索引
  measurer.ex            # :todo stub
  zongzi_feasibility.ex  # hello world 占位
priv/scripts/
  engine.py              # toy 投影引擎，带 apply() 函数（应删，apply 移回 Elixir 侧）
  engine_cli.py          # stdin/stdout JSON 桥，action: project/apply/visualize
  visualize.py           # 简单对比图，待增强
  server.py              # 已废弃，应删除
  requirements.txt       # 列了未用的 pyworld
```

模块命名空间是 `ZongziFeasibility.*`，但目录是 `lib/feasibility/`——应统一为 `lib/zongzi_feasibility/`。

---

## 4. Track A：zongzi_feasibility 任务拆解

### A1. 契约对齐清理

- 目录：`lib/feasibility/` → `lib/zongzi_feasibility/`，所有模块名改为 `ZongziFeasibility.*`。
- 删除 `priv/scripts/server.py`；`requirements.txt` 去掉 `pyworld`。
- Python 路径可配置：`Application.get_env(:zongzi_feasibility, :python, "python")`；在 `config/config.exs` 中可写死为 `"D:/Conda/python.exe"`（正斜杠）。
- telemetry 事件前缀：`[:zongzi, :intervention, :stale]` → `[:zongzi_feasibility, :declaration, :stale]`。
- 验收：`mix compile --warnings-as-errors` 通过。

### A2. Declaration.Pitch 重写

这是语义核心。所有改动必须对齐 `Zongzi.Intervention.Declaration` behaviour。

- **payload 形状**：改为 tick 坐标（不再是 frame 索引）：
  ```elixir
  %{control_points: [{tick, offset_cents}], boundary: {start_tick, end_tick}, original: term}
  ```
- **scope/2**：用 `boundary ± @max_preutterance_ticks` 静态算 `{start_tick, end_tick}`，不读 `int.scope` 缓存。
- **snapshot/2**：从投影取 boundary 覆盖帧，**归一化**为有序列表：
  ```elixir
  [[frame, pitch_4位小数, vuv], ...]
  ```
  目的：对抗 JSON round-trip 的 integer→string key 漂移和 float 精度漂移。
- **resolve/2**：
  - 一致 → `{:ok, applied_projection}`
  - 不一致 → `{:conflict, :snapshot_stale}`，并触发 telemetry
  - 在 applied 中按 `control_points` 叠 cents offset（`2^(cents/1200)`）。
- **on_rebase/3**：
  - rebase 平移：按 anchor 变化平移 control_points tick。
  - focus split：按 `split_tick` 切 boundary + control_points → `{:split, [child1, child2]}`。
- **测试**：`test/smoke_test.exs` 同步更新（resolve 返回值、新 payload 形状）。

### A3. Engine + toy 引擎扩展

- `ZongziFeasibility.Engine`：`@behaviour Zongzi.Engine`。
  - `check/1`：segments → Python `project` → baseline 投影 → 逐条 intervention 调 `Declaration.Pitch.resolve` → `%{projection, resolved, conflicts}`。
  - `render/1`（optional）：合并 resolved 得 applied 投影 → 调 Python `visualize` → PNG 路径。
  - `params` 校验：gender/energy 等全局参数非法时返回 `{:error, {:invalid_params, ...}}`。
- `ZongziFeasibility.Engine.Python`：System.cmd 桥下沉至此；只暴露 `run(map_body) :: {:ok, map} \| {:error, String.t}`。
- `engine.py`：
  - 删除 `apply()`（delta apply 移回 Elixir 侧 `resolve`）。
  - `project` 加 `preutterance_frames` 参数：每 note 头部向前溢出 N 帧，溢出帧标定 pitch/vuv，可覆盖进前 note 尾部——这是 G-PRE 场景能真实发生的前提。
- `engine_cli.py`：保留 `project`/`visualize`；删除 `apply` action。
- `visualize.py`：增强为 baseline vs applied 曲线 + note 边界竖线 + intervention 作用域色块 + snapshot 失配区间高亮。
- 删除 `ZongziFeasibility.Engine.Request` struct，request 用 zongzi 规定的 map。
- 验收：
  - `mix test` 全绿。
  - Engine 是 `Zongzi.Engine` behaviour。
  - Python 桥集成测试打 `@tag :integration`，`test_helper.exs` 默认 `exclude: [:integration]`；手动 `mix test --only integration` 可验证。

### A4. Caller 编排

新建 `ZongziFeasibility.Caller`：

- `new/1`：从 score 建 `%Caller{timeline, notes_by_seq, interventions, tempo_map, ...}`。
- `mount_intervention/2`：构造 `Intervention` 并调 `declaration.snapshot` 挂载。
- `edit/2`：支持 ops：`edit_lyric`, `split`, `delete`, `insert`, `move`, `merge`。
  - 内部：Timeline 写 → 组装 `Anchor.Context` → `Anchor.rebase_all` → `Windowing.run_stages` → 返回决策报告。
- `check_round/1` / `render_round/1`：组 Engine request，调用 Engine，触发可视化。
- 这是 zongzi README sequence diagram 的可执行版。

### A5. 可视化层（第一优先级）

- `visualize.py` 输出：
  - baseline vs applied f0 曲线
  - vuv  voiced/unvoiced 带
  - note 边界竖线（请求带 notes）
  - intervention 作用域色块（请求带 interventions boundary）
  - snapshot 失配区间高亮
  - preutterance 溢出区标注
- 每轮对抗自动落 `priv/output/<scenario>/<round>.png`。
- `report.html` 单文件汇总：每场景一张卡片，内嵌 base64 图 + 结构决策 + 语义决议 + 期望命中 + 指标表。
- 验收：手动跑一次端到端，打开 report.html 可读。

### A6. Scenarios + Measurer

- `ZongziFeasibility.Scenario` behaviour：`setup/0`, `edits/1`, `expect/2`。
- 落地场景（对齐 `GOLDEN_SCENARIOS.md`）：
  - G-INT-01：挂载→编辑→rebase→resolve 完整对抗轮
  - G-INT-02：snapshot 失配 → conflict（不静默 apply）
  - G-ENG-02：check/render 只吃 segments
  - G-PRE-01..07：紧靠/小 gap/大 gap/重叠/三重链 × 有无 intervention
- `Measurer`：
  - 结构决策分布（preserve/rebase/relocate/conflict）
  - 语义决议分布（apply/conflict）
  - 期望命中率
  - 输出：console 表 + `priv/output/report.json` + `report.html`
  - telemetry：`[:zongzi_feasibility, :scenario, :round]`

### A7. 测试与验收

- 修 `smoke_test.exs`（resolve 返回值）。
- Engine contract 测试：检查 `check` 吃 segments map，非法 params 报错。
- 每 G-* 场景一个 describe。
- 最终验收：
  - `mix test` 全绿
  - `mix run -e "ZongziFeasibility.Measurer.run()"` 出报告且期望全命中
  - `report.html` 可打开阅读

---

## 5. Track B：NPSS 并行线（真实后端）

### 已发现的致命问题

- `D:/CodeRepo/SingingSynthesis/NPSS` 的 4 个 ONNX 模型已导出，但 **全部塌陷为恒等拷贝**：
  - vuv train_loss = 0.000000
  - harmonic best NLL = -5.14
  - f0 TF 相关系数 0.9999
- 根因：`scripts/dataset.py` 的 `y = tgt[start+R : start+R+T]`，而因果卷积 left-pad 让 `output[j]` 能看见 `x[j]` 本身，拷贝即最优解。
- `data/output/npss_4_full_pred.wav` 等文件是用 `inference_full.py` 做 **teacher-forcing 重建** 产生的，不是自回归生成。

### 已做的修复

- 本地 `scripts/dataset.py`：
  - `y = tgt[start+R+1 : start+R+T+1]`（output[j] 预测 x[j+1]）
  - `cond` 同步右移一帧（对齐被预测帧）
  - `_build_index` 收紧一帧，避免末样本静默截短
  - 补 vuv 1-D target 的 ndim 处理
  - 已本地验证：4 个 Dataset 形状、边界、内部对齐、collate 全通过。
- 云端 `/root/autodl-tmp/NPSS/scripts/dataset.py`：已上传同步修复后的版本，但未跑冒烟验证（实例已关闭）。

### 恢复后的下一步

1. 开带卡 AutoDL 实例（云端路径 `/root/autodl-tmp/NPSS`）。
2. 用 `/root/miniconda3/bin/python` 跑云端 dataset 冒烟检查。
3. 先训 harmonic 50–100 epoch（约 0.5–1 小时）。
4. 用 `scripts/inference_spike.py` 探针验收：
   - teacher-forcing shift 表峰值应在 **+1**
   - 末帧扰动增益 ≈ 0
   - 短程 AR 不发散
5. 验收通过后，全量 4 模型重训 → 导出 ONNX → 下载到本地。
6. 在 zongzi_feasibility 中新增 `ZongziFeasibility.Engine.NPSS` 实现，替换 toy 后端（A3 的接口不变）。

---

## 6. Agent 状态

- **agent-0**：NPSS 修复。曾被启动并完成了本地 `dataset.py` 的 y 右移基础修复；后续 cond 对齐、ndim 处理、边界收紧、云端同步由本会话手动完成。目前任务已 kill，恢复 NPSS 线时可直接用当前文件状态继续，无需 resume。
- **agent-1**：zongzi_feasibility 契约层（A1–A3）。被启动后未返回进度即被 kill。恢复 zongzi_feasibility 主线时，建议重新从当前仓库状态出发，不必 resume agent-1。

---

## 7. 恢复检查清单

迁移到新仓库后，先确认：

- [ ] 当前工作目录是 `D:/CodeRepo/Qy/zongzi_feasibility`。
- [ ] 能读取 `../zongzi` 作为 path dependency（`mix.exs` 已配置）。
- [ ] 若继续 NPSS 线，先开 AutoDL 带卡实例并验证云端 `dataset.py` 状态。
- [ ] 从 A1 开始推进 zongzi_feasibility 主线，或先跳到 A4–A5 快速可视化（前提是 A1–A3 已有人完成）。

---

## 8. 相关路径速查

| 项目 | 路径 |
|------|------|
| zongzi_feasibility | `D:/CodeRepo/Qy/zongzi_feasibility` |
| zongzi | `D:/CodeRepo/Qy/zongzi` |
| NPSS 本地 | `D:/CodeRepo/SingingSynthesis/NPSS` |
| NPSS 云端(已关机) | `root@connect.weste.seetacloud.com:48036:/root/autodl-tmp/NPSS` |
| 已改文件 | `D:/CodeRepo/SingingSynthesis/NPSS/scripts/dataset.py` |
| 待改文件 | `lib/zongzi_feasibility/engine.ex`、`lib/zongzi_feasibility/declaration/pitch.ex`、`lib/zongzi_feasibility/caller.ex` 等 |

---

## 9. 用户补充

现在 `D:/CodeRepo/SingingSynthesis/zongzi-svs` 已经有了 UTAU 以及 DiffSinger 实例，PoC 跑通，但需要进一步打磨。
