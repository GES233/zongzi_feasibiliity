defmodule ZongziFeasibility.Caller do
  @moduledoc """
  编排者（zongzi 契约里 Caller 角色的可执行参考实现）。

  持有：Timeline、notes_by_seq 快照、interventions、tempo（线格式 segments）。
  编辑回路（zongzi README sequence diagram 的可执行版）：

      Timeline 写 → payload/snapshot 坐标维护 → Anchor.rebase_all
      → Windowing.run_stages → 决策报告

  `check_round/2` / `render_round/2` 组 Engine request 调 `ZongziFeasibility.Engine`。

  ## 坐标分工

  tick↔frame 换算只发生在这里（Caller 有 tempo 上下文），
  换算结果缓存进 `payload.frames`；`tick_to_sec/2` 与
  `priv/scripts/engine.py` 的 `ticks_to_seconds` 严格同构，
  保证 frames 缓存与 Python 投影帧对齐（见 Declaration.Pitch 的坐标分工）。

  ## move 语义

  `{:move, seq, new_start_tick}` 是 tick 轴平移（drag），不是链序重排；
  挂在 focus 上的 intervention 的 boundary/control_points/snapshot 由 Caller
  同步平移。链序重排未实现（场景暂不需要）。
  """

  alias Zongzi.{Anchor, Intervention, Timeline, Windowing}
  alias Zongzi.Score.{Key, Note}
  alias Zongzi.Util.ID
  alias ZongziFeasibility.{Declaration.Pitch, Engine}

  @tpqn 480
  @default_sample_rate 86.13

  @type t :: %__MODULE__{
          timeline: nil | Timeline.t(),
          notes_by_seq: %{},
          interventions: [Intervention.t()],
          tempo_segments: [],
          opts: map()
        }

  defstruct timeline: nil,
            notes_by_seq: %{},
            interventions: [],
            tempo_segments: [],
            opts: %{}

  # ------------------------------------------------------------------
  # 构造
  # ------------------------------------------------------------------

  @doc """
  从 score 建 Caller。

  attrs: `:notes`（`%{start_tick, duration_tick, midi, lyric}` 或 `%Note{}` 列表）、
  `:tempo_segments`（`[[tick, bpm], ...]`，默认 `[[0, 120.0]]`）、
  `:track_id`、`:opts`（`:sample_rate` / `:preutterance_frames` / `:beat_ticks`）。
  """
  def new(attrs) do
    {:ok, tl} = Timeline.new(Map.get(attrs, :track_id, "track_1"))

    {tl, notes_by_seq} =
      attrs
      |> Map.get(:notes, [])
      |> Enum.reduce({tl, %{}}, fn n, {tl, acc} ->
        {:ok, note} = build_note(n)
        {:ok, tl, note} = Timeline.insert_note(tl, note)
        {tl, Map.put(acc, note.seq_id, note)}
      end)

    %__MODULE__{
      timeline: tl,
      notes_by_seq: notes_by_seq,
      tempo_segments: normalize_tempo(Map.get(attrs, :tempo_segments, [[0, 120.0]])),
      opts: Map.new(Map.get(attrs, :opts, %{}))
    }
  end

  # ------------------------------------------------------------------
  # 挂载
  # ------------------------------------------------------------------

  @doc """
  构造 pitch intervention 并挂载：取 anchor 三元组、payload.frames 缓存，
  并对当前投影取 snapshot。

  attrs: `:seq`（focus）、`:control_points`（`[{tick, cents}]`）、
  `:boundary`（默认 focus note 的 `[start, end)`）、`:id`。

  `projection` 可选注入（测试用）；缺省时现场跑一轮 Engine.check 取投影。
  """
  def mount_intervention(caller, attrs, projection \\ nil) do
    seq = Map.fetch!(attrs, :seq)
    anchor = triplet(caller.timeline, seq)
    note = Map.fetch!(caller.notes_by_seq, seq)
    boundary = Map.get(attrs, :boundary, {note.start_tick, note.start_tick + note.duration_tick})
    cps = Map.get(attrs, :control_points, [])

    payload = %{
      control_points: cps,
      boundary: boundary,
      frames: frames_cache(caller, cps, boundary)
    }

    {:ok, int} =
      Intervention.new(
        id: Map.get(attrs, :id, ID.generate_id("iv_")),
        channel: :pitch,
        anchor: anchor,
        payload: payload,
        declaration: Pitch
      )

    projection = projection || project_current(caller)
    {:ok, int} = Intervention.mount(int, payload, anchor, caller.timeline, projection)

    # Caller-specific: 挂原始投影切片备查（不在 Intervention 契约内）
    {f0, f1} = payload.frames.boundary
    int = %{int | payload: Map.put(int.payload, :original, Pitch.slice(projection, f0, f1))}

    {%{caller | interventions: caller.interventions ++ [int]}, int}
  end

  # ------------------------------------------------------------------
  # 编辑
  # ------------------------------------------------------------------

  @doc """
  执行一个编辑 op 并跑完整编辑回路。

  ops: `{:edit_lyric, seq, lyric}` / `{:edit_key, seq, midi}` /
  `{:split, seq, split_tick}` / `{:delete, seq}` / `{:insert, attrs}`
  （attrs 可含 `:after`）/ `{:move, seq, new_start_tick}` / `{:merge, seq_a, seq_b}`。

  `edit_key` 改音高：投影在 intervention boundary 内确定性变化，
  是 snapshot 失配 → conflict（G-INT-02）的直接触发手段。

  返回 `{caller, report}`；report = `%{op, survived, conflicts, segments}`。
  """
  def edit(caller, op) do
    {:ok, caller, op_desc} = apply_op(caller, op)

    ctx = Anchor.Context.new(notes_by_seq: caller.notes_by_seq)

    %{survived: survived, conflicts: conflicts, decisions: decisions} =
      Anchor.rebase_all(caller.interventions, caller.timeline, ctx)

    survived = Enum.map(survived, &strip_hint/1)
    conflicts = Enum.map(conflicts, fn {int, reason} -> {strip_hint(int), reason} end)

    caller = %{caller | interventions: survived}
    {:ok, segments} = window(caller)

    report = %{
      op: op_desc,
      survived: survived,
      conflicts: conflicts,
      segments: segments,
      decisions: decisions
    }

    {caller, report}
  end

  defp apply_op(caller, {:edit_lyric, seq, lyric}) do
    note = Map.fetch!(caller.notes_by_seq, seq)
    {:ok, note} = Note.update_lyric(note, lyric)
    {:ok, put_note(caller, note), {:edit_lyric, seq, lyric}}
  end

  defp apply_op(caller, {:edit_key, seq, midi}) do
    note = Map.fetch!(caller.notes_by_seq, seq)
    {:ok, key} = Key.TwelveET.new(midi)
    {:ok, note} = Note.drag_note(note, key: key)
    {:ok, put_note(caller, note), {:edit_key, seq, midi}}
  end

  defp apply_op(caller, {:split, seq, split_tick}) do
    note = Map.fetch!(caller.notes_by_seq, seq)

    {:ok, tl, before_n, after_n} =
      Timeline.split_note(caller.timeline, note, split_tick, ID.generate_id("Note_"))

    split_frame = tick_to_frame(caller, split_tick)

    notes =
      caller.notes_by_seq
      |> Map.put(before_n.seq_id, before_n)
      |> Map.put(after_n.seq_id, after_n)

    ints =
      Enum.map(caller.interventions, fn int ->
        if focus(int) == seq and inside_boundary?(int, split_tick) do
          put_in(int.payload[:split_hint], %{
            tick: split_tick,
            frame: split_frame,
            after_seq: after_n.seq_id
          })
        else
          int
        end
      end)

    {:ok, %{caller | timeline: tl, notes_by_seq: notes, interventions: ints},
     {:split, seq, split_tick}}
  end

  defp apply_op(caller, {:delete, seq}) do
    {:ok, tl} = Timeline.delete_note(caller.timeline, seq)

    {:ok, %{caller | timeline: tl, notes_by_seq: Map.delete(caller.notes_by_seq, seq)},
     {:delete, seq}}
  end

  defp apply_op(caller, {:insert, attrs}) do
    {:ok, note} = build_note(attrs)

    {:ok, tl, note} =
      case Map.get(attrs, :after) do
        nil -> Timeline.insert_note(caller.timeline, note)
        after_seq -> Timeline.insert_note_after(caller.timeline, note, after_seq)
      end

    {:ok, %{caller | timeline: tl, notes_by_seq: Map.put(caller.notes_by_seq, note.seq_id, note)},
     {:insert, note.seq_id}}
  end

  defp apply_op(caller, {:move, seq, new_start}) do
    note = Map.fetch!(caller.notes_by_seq, seq)
    {:ok, moved} = Note.drag_note(note, start_tick: new_start)

    tick_delta = new_start - note.start_tick
    frame_delta = tick_to_frame(caller, new_start) - tick_to_frame(caller, note.start_tick)

    ints =
      Enum.map(caller.interventions, fn int ->
        if focus(int) == seq, do: shift_int(int, tick_delta, frame_delta), else: int
      end)

    {:ok, %{caller | notes_by_seq: Map.put(caller.notes_by_seq, seq, moved), interventions: ints},
     {:move, seq, new_start}}
  end

  defp apply_op(caller, {:merge, seq_a, seq_b}) do
    na = Map.fetch!(caller.notes_by_seq, seq_a)
    nb = Map.fetch!(caller.notes_by_seq, seq_b)

    {:ok, tl, merged} =
      Timeline.merge_notes(caller.timeline, na, nb, ID.generate_id("Note_"))

    notes = caller.notes_by_seq |> Map.put(seq_a, merged) |> Map.delete(seq_b)

    {:ok, %{caller | timeline: tl, notes_by_seq: notes}, {:merge, seq_a, seq_b}}
  end

  # ------------------------------------------------------------------
  # window / check / render 回路
  # ------------------------------------------------------------------

  @doc "post-rebase 切窗（默认 RestSplit3Beats）。"
  def window(caller) do
    ctx =
      Windowing.Context.new(%{
        timeline: caller.timeline,
        notes_by_seq: caller.notes_by_seq,
        interventions: caller.interventions,
        tempo_map: compile_tempo_map(caller.tempo_segments),
        opts: %{beat_ticks: caller.opts[:beat_ticks] || @tpqn}
      })

    Windowing.run_stages(ctx)
  end

  defp compile_tempo_map([]), do: nil

  defp compile_tempo_map(tempo_segments) do
    events =
      Enum.map(tempo_segments, fn [tick, bpm] ->
        {tick, %Zongzi.Score.Tempo.Event{module: Zongzi.Score.Tempo.Step, context: %{bpm: bpm * 1.0}}}
      end)

    case Zongzi.Score.TempoMap.compile(events, tpqn: @tpqn) do
      {:ok, tm} -> tm
      {:error, _} -> nil
    end
  end

  @doc "组 Engine request（zongzi 契约 map）。"
  def request(caller, segments, extra \\ %{}) do
    %{
      segments: segments,
      notes_by_seq: caller.notes_by_seq,
      interventions: caller.interventions,
      tempo_segments: caller.tempo_segments,
      params: Map.get(extra, :params, %{}),
      opts: caller.opts |> Map.merge(Map.get(extra, :opts, %{})) |> Map.new()
    }
  end

  @doc "切窗 → Engine.check。"
  def check_round(caller, extra \\ %{}) do
    with {:ok, segments} <- window(caller) do
      Engine.check(request(caller, segments, extra))
    end
  end

  @doc "切窗 → Engine.render（触发可视化 PNG）。"
  def render_round(caller, tag, extra \\ %{}) do
    with {:ok, segments} <- window(caller) do
      opts =
        caller.opts
        |> Map.merge(Map.get(extra, :opts, %{}))
        |> Map.put(:tag, tag)

      Engine.render(%{request(caller, segments, extra) | opts: opts})
    end
  end

  # ------------------------------------------------------------------
  # 坐标换算（与 engine.py ticks_to_seconds 严格同构）
  # ------------------------------------------------------------------

  @doc "tick → frame（与 engine.py 同算法：sec × sample_rate 四舍五入）。"
  def tick_to_frame(caller, tick) do
    round(tick_to_sec(caller.tempo_segments, tick) * sample_rate(caller))
  end

  # 镜像 priv/scripts/engine.py 的 ticks_to_seconds（单 tick 版）。
  defp tick_to_sec([[seg_tick, bpm] | rest], tick) do
    advance(rest, tick, seg_tick, bpm, 0.0)
  end

  defp advance([[next_tick, _] | _] = rest, tick, seg_tick, bpm, time) do
    if tick >= next_tick do
      [[_, next_bpm] | rest2] = rest

      advance(
        rest2,
        tick,
        next_tick,
        next_bpm,
        time + (next_tick - seg_tick) / @tpqn * 60.0 / bpm
      )
    else
      time + (tick - seg_tick) / @tpqn * 60.0 / bpm
    end
  end

  defp advance([], tick, seg_tick, bpm, time) do
    time + (tick - seg_tick) / @tpqn * 60.0 / bpm
  end

  # ------------------------------------------------------------------
  # helpers
  # ------------------------------------------------------------------

  defp project_current(caller) do
    with {:ok, segments} <- window(caller),
         {:ok, artifact} <- Engine.check(request(caller, segments)) do
      artifact.projection
    else
      {:error, reason} -> raise "Caller: projection failed: #{inspect(reason)}"
    end
  end

  defp triplet(tl, seq) do
    prev = tl |> Timeline.Query.scan(seq, :prev, limit: 1) |> List.first()
    next = tl |> Timeline.Query.scan(seq, :next, limit: 1) |> List.first()
    {prev, seq, next}
  end

  defp focus(int), do: elem(int.anchor, 1)

  defp inside_boundary?(int, tick) do
    {bs, be} = int.payload.boundary
    bs < tick and tick < be
  end

  defp strip_hint(int), do: %{int | payload: Map.delete(int.payload, :split_hint)}


  defp shift_int(int, tick_delta, frame_delta) do
    p = int.payload
    {bs, be} = p.boundary
    {f0, f1} = p.frames.boundary

    payload = %{
      p
      | boundary: {bs + tick_delta, be + tick_delta},
        control_points: Enum.map(p.control_points, fn {t, c} -> {t + tick_delta, c} end),
        frames: %{
          boundary: {f0 + frame_delta, f1 + frame_delta},
          control_points: Enum.map(p.frames.control_points, fn {f, c} -> {f + frame_delta, c} end)
        }
    }

    snapshot = Enum.map(int.snapshot, fn [f, pitch, v] -> [f + frame_delta, pitch, v] end)

    %{int | payload: payload, snapshot: snapshot}
  end

  defp frames_cache(caller, cps, {bs, be}) do
    %{
      boundary: {tick_to_frame(caller, bs), tick_to_frame(caller, be)},
      control_points: Enum.map(cps, fn {t, c} -> {tick_to_frame(caller, t), c} end)
    }
  end

  defp put_note(caller, note),
    do: %{caller | notes_by_seq: Map.put(caller.notes_by_seq, note.seq_id, note)}

  defp build_note(%Note{} = n), do: {:ok, n}

  defp build_note(%{} = n) do
    {:ok, key} = Key.TwelveET.new(Map.fetch!(n, :midi))

    Note.new(%{
      id: Map.get(n, :id, ID.generate_id("Note_")),
      start_tick: Map.fetch!(n, :start_tick),
      duration_tick: Map.fetch!(n, :duration_tick),
      key: key,
      lyric: Map.get(n, :lyric)
    })
  end

  defp normalize_tempo(segs) do
    Enum.map(segs, fn
      {t, bpm} -> [t, bpm]
      [t, bpm] -> [t, bpm]
    end)
  end

  defp sample_rate(caller), do: caller.opts[:sample_rate] || @default_sample_rate
end
