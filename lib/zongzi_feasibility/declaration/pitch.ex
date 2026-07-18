defmodule ZongziFeasibility.Declaration.Pitch do
  @moduledoc """
  `:pitch` channel 的 `Zongzi.Intervention.Declaration` 样板实现。

  ## 坐标分工

  - **tick 空间是权威**（control-points-authoritative）：
    `payload.control_points` 与 `payload.boundary`。
  - **frame 空间是投影比对 / 叠加的工作空间**：Declaration 自身没有 tempo
    上下文，不做 tick↔frame 换算；由 Caller 在挂载与编辑时把 boundary /
    control_points 换算成帧，缓存进 `payload.frames`。
  - 结构编辑（move / drag）后由 Caller 平移 payload 与 snapshot 的坐标；
    focus split 由 Caller 注入 `:split_hint`，`on_rebase/4` 消费并产出两个子
    intervention（payload-boundary 决策）。

  `on_rebase/4` 的第 4 参 `context` 是 Caller 注入 `rebase_all` 的
  `Anchor.Context`（含 `notes_by_seq`，可做 tick 级维护）；frame 级信息
  （采样率/tempo 换算）context 不携带，仍由 Caller 经 split_hint 提供。

  ## payload 形状

      %{
        control_points: [{tick, offset_cents}],           # 权威，按 tick 升序
        boundary: {start_tick, end_tick},                 # 权威，曲线覆盖区间
        frames: %{
          boundary: {f_start, f_end},                     # 派生缓存（Caller 维护）
          control_points: [{frame, offset_cents}]         # 派生缓存（Caller 维护）
        },
        original: term                                    # 挂载时原始投影切片，备查
      }

  ## snapshot 归一化

  snapshot 存 `[[frame, pitch_rounded_4dp, vuv], ...]` 有序列表，
  对抗 JSON round-trip 的 integer→string key 漂移与 float 精度漂移
  （declaration-projection-resolution：比对不放 tolerance，归一化在序列化侧做）。
  """

  @behaviour Zongzi.Intervention.Declaration

  alias Zongzi.Intervention

  @max_preutterance_ticks 240
  @stale_event [:zongzi_feasibility, :declaration, :stale]

  @doc "scope/2 使用的保守 preutterance 上界（tick）。"
  def max_preutterance_ticks, do: @max_preutterance_ticks

  @doc "snapshot 失配 telemetry 事件名。"
  def stale_event, do: @stale_event

  # ------------------------------------------------------------------
  # scope/2 — 静态保守上界，不读投影，不读 int.scope 缓存
  # ------------------------------------------------------------------

  @impl true
  def scope(%Intervention{payload: %{boundary: {s, e}}}, _tl) do
    {max(s - @max_preutterance_ticks, 0), e + @max_preutterance_ticks}
  end

  # ------------------------------------------------------------------
  # snapshot/2 — 挂载时取 boundary 覆盖帧，归一化为有序列表
  # ------------------------------------------------------------------

  @impl true
  def snapshot(projection, %Intervention{payload: payload}) do
    {f0, f1} = frame_boundary(payload)

    projection
    |> slice(f0, f1)
    |> normalize()
  end

  # ------------------------------------------------------------------
  # resolve/2 — 一致 → 叠 cents offset；不一致 → conflict + telemetry
  # ------------------------------------------------------------------

  @impl true
  def resolve(%Intervention{} = int, fresh_projection) do
    {f0, f1} = frame_boundary(int.payload)
    fresh = fresh_projection |> slice(f0, f1) |> normalize()

    if fresh == int.snapshot do
      {:ok, apply_control_points(fresh_projection, int.payload)}
    else
      emit_stale(int)
      {:conflict, :snapshot_stale}
    end
  end

  # ------------------------------------------------------------------
  # on_rebase/3 — 只处理 focus split（Caller 注入 split_hint）；
  # 其余决策（preserve/rebase/relocate）锚已由 strategy 更新，原样接受。
  # tick 级平移不在此做：Timeline 不持 note tick，
  # 由 Caller 在编辑时维护 payload/snapshot 坐标。
  # ------------------------------------------------------------------

  @impl true
  def on_rebase(%Intervention{payload: %{split_hint: hint}} = int, meta, _tl, _ctx) do
    payload = Map.delete(int.payload, :split_hint)
    split_tick = hint.tick
    split_frame = hint.frame
    after_seq = hint.after_seq

    {bs, be} = payload.boundary
    {f0, f1} = payload.frames.boundary
    {_prev, cur, old_next} = meta.old_anchor

    {cp_a, cp_b} = Enum.split_with(payload.control_points, fn {t, _} -> t < split_tick end)

    {fcp_a, fcp_b} =
      Enum.split_with(payload.frames.control_points, fn {f, _} -> f < split_frame end)

    {snap_a, snap_b} = Enum.split_with(int.snapshot, fn [f, _, _] -> f < split_frame end)
    {orig_a, orig_b} = split_original(Map.get(payload, :original), split_frame)

    child_a = %{
      int
      | id: int.id <> "_a",
        payload: %{
          payload
          | boundary: {bs, split_tick},
            control_points: cp_a,
            frames: %{boundary: {f0, split_frame}, control_points: fcp_a},
            original: orig_a
        },
        snapshot: snap_a
    }

    child_b = %{
      int
      | id: int.id <> "_b",
        anchor: {cur, after_seq, old_next},
        payload: %{
          payload
          | boundary: {split_tick, be},
            control_points: cp_b,
            frames: %{boundary: {split_frame, f1}, control_points: fcp_b},
            original: orig_b
        },
        snapshot: snap_b
    }

    {:split, [child_a, child_b]}
  end

  def on_rebase(int, _meta, _tl, _ctx), do: {:ok, int}

  # ------------------------------------------------------------------
  # helpers
  # ------------------------------------------------------------------

  defp frame_boundary(payload), do: payload.frames.boundary

  @doc "取投影中 `[f0, f1)` 的帧（projection 为 `[[frame, pitch, vuv], ...]` 有序列表）。"
  def slice(projection, f0, f1) do
    Enum.filter(projection, fn [f, _, _] -> f >= f0 and f < f1 end)
  end

  @doc "归一化投影切片：`[[frame, pitch_rounded_4dp, vuv], ...]`。"
  def normalize(frames) do
    Enum.map(frames, fn [f, p, v] -> [f, Float.round(p * 1.0, 4), v] end)
  end

  # 在 boundary 帧区间内按 control_points 叠 cents offset：pitch * 2^(cents/1200)。
  # 返回应用后的切片（仅 boundary 覆盖帧）。
  defp apply_control_points(projection, payload) do
    {f0, f1} = payload.frames.boundary
    cps = payload.frames.control_points

    projection
    |> slice(f0, f1)
    |> Enum.map(fn [f, p, v] ->
      cents = interp_cents(cps, f)
      [f, p * :math.pow(2.0, cents / 1200.0), v]
    end)
  end

  # 分段线性插值；范围外取最近端点值；无控制点则 0。
  defp interp_cents([], _f), do: 0.0
  defp interp_cents([{f0, c0} | _], f) when f <= f0, do: c0 * 1.0

  defp interp_cents(cps, f) do
    case Enum.find(cps, fn {cf, _} -> cf >= f end) do
      nil ->
        {_lf, lc} = List.last(cps)
        lc * 1.0

      {^f, c} ->
        c * 1.0

      {f1, c1} ->
        {f0, c0} = cps |> Enum.take_while(fn {cf, _} -> cf < f end) |> List.last()
        c0 + (c1 - c0) * (f - f0) / (f1 - f0)
    end
  end

  defp split_original(original, split_frame) when is_list(original) do
    Enum.split_with(original, fn
      [f, _, _] -> f < split_frame
      _ -> true
    end)
  end

  defp split_original(original, _split_frame), do: {original, original}

  defp emit_stale(int) do
    if Code.ensure_loaded?(:telemetry) do
      :telemetry.execute(@stale_event, %{count: 1}, %{
        intervention_id: int.id,
        channel: int.channel
      })
    end
  end
end
