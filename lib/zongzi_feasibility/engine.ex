defmodule ZongziFeasibility.Engine do
  @default_sample_rate 86.13
  @param_ranges %{gender: {-1.0, 1.0}, energy: {0.0, 1.0}}

  @moduledoc """
  `Zongzi.Engine` behaviour 的 toy 实现。

  - `check/1`：params 校验 → 逐 segment 调 Python `project` 投影 →
    逐 intervention 调 `Declaration.Pitch.resolve` →
    `{:ok, %{projection, spills, resolved, conflicts}}`。
  - `render/1`：消费 `checked_request`（已过 check 的 request + artifact +
    fingerprint），合并 resolved 得 applied 投影 → Python `visualize`
    → artifact 加 `applied` / `path`。

  request 为 map（zongzi 契约，不用 struct）：`segments` 必填；常用
  `notes_by_seq`（或 `notes`）、`interventions`（结构存活集）、
  `tempo_segments`、`params`、`opts`。

  opts 常用键：`:sample_rate`（默认 #{@default_sample_rate}）、
  `:preutterance_frames`（默认 0）、`:output_dir` / `:tag`（render 用）。
  """

  @behaviour Zongzi.Engine

  alias Zongzi.Score.Key
  alias Zongzi.Windowing.Segment
  alias ZongziFeasibility.Declaration.Pitch
  alias ZongziFeasibility.Engine.Python

  # ------------------------------------------------------------------
  # check/1
  # ------------------------------------------------------------------

  @impl true
  def check(%{segments: segments} = req) when is_list(segments) do
    with :ok <- validate_params(Map.get(req, :params, %{})),
         {:ok, projection, spills} <- project_segments(segments, req) do
      {resolved, conflicts} = resolve_all(Map.get(req, :interventions, []), projection)

      {:ok,
       %{
         projection: projection,
         spills: spills,
         resolved: resolved,
         conflicts: conflicts
       }}
    end
  end

  def check(_req), do: {:error, :missing_segments}

  # ------------------------------------------------------------------
  # render/1
  # ------------------------------------------------------------------

  @impl true
  def render(%{request: req, artifact: artifact} = _checked) do
    applied = apply_resolved(artifact.projection, artifact.resolved)

    body = %{
      "action" => "visualize",
      "baseline" => artifact.projection,
      "applied" => applied,
      "spills" => artifact.spills,
      "notes" => req |> all_notes() |> Enum.map(&serialize_note/1),
      "tempo_segments" => tempo_segments(req),
      "sample_rate" => sample_rate(req),
      "interventions" => serialize_interventions(req, artifact),
      "output_dir" => opts(req)[:output_dir] || default_output_dir(),
      "tag" => opts(req)[:tag] || "comparison"
    }

    case Python.run(body) do
      {:ok, %{"path" => path}} -> {:ok, Map.merge(artifact, %{applied: applied, path: path})}
      {:error, _} = err -> err
    end
  end

  # ------------------------------------------------------------------
  # params 校验（gender / energy 全局旋钮，非 intervention）
  # ------------------------------------------------------------------

  defp validate_params(params) when is_map(params) do
    Enum.reduce_while(params, :ok, fn {k, v}, :ok ->
      case validate_param(k, v) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:invalid_params, reason}}}
      end
    end)
  end

  defp validate_params(_), do: {:error, {:invalid_params, :not_a_map}}

  defp validate_param(k, v) do
    case Map.fetch(@param_ranges, k) do
      :error ->
        {:error, {:unknown_param, k}}

      {:ok, {lo, hi}} ->
        cond do
          not is_number(v) -> {:error, {k, :not_a_number}}
          v < lo or v > hi -> {:error, {k, :out_of_range, {lo, hi}}}
          true -> :ok
        end
    end
  end

  # ------------------------------------------------------------------
  # 逐 segment 投影
  # ------------------------------------------------------------------

  defp project_segments(segments, req) do
    segments
    |> Enum.reduce_while({:ok, [], []}, fn seg, {:ok, proj_acc, spill_acc} ->
      body = %{
        "action" => "project",
        "notes" => seg |> segment_notes(req) |> Enum.map(&serialize_note/1),
        "tempo_segments" => tempo_segments(req),
        "sample_rate" => sample_rate(req),
        "preutterance_frames" => opts(req)[:preutterance_frames] || 0,
        "window" => [seg.start_tick, seg.end_tick]
      }

      case Python.run(body) do
        {:ok, %{"projection" => proj, "spills" => spills}} ->
          {:cont, {:ok, proj_acc ++ proj, spill_acc ++ spills}}

        {:ok, other} ->
          {:halt, {:error, {:unexpected_project_response, other}}}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
    |> case do
      {:ok, proj, spills} -> {:ok, merge_frames(proj), merge_spills(spills)}
      {:error, _} = err -> err
    end
  end

  # 相邻 segment 的帧窗口 disjoint；排序 + 去重兜底边界取整重叠。
  defp merge_frames(frames) do
    frames
    |> Enum.sort_by(fn [f, _, _] -> f end)
    |> Enum.uniq_by(fn [f, _, _] -> f end)
  end

  defp merge_spills(spills), do: Enum.sort_by(spills, fn [f0, _] -> f0 end)

  # ------------------------------------------------------------------
  # resolve / applied 合并
  # ------------------------------------------------------------------

  defp resolve_all(interventions, projection) do
    interventions
    |> Enum.reduce({[], []}, fn int, {ok_acc, c_acc} ->
      decl = int.declaration || Pitch

      case decl.resolve(int, projection) do
        {:ok, applied} -> {[{int, applied} | ok_acc], c_acc}
        {:conflict, reason} -> {ok_acc, [{int, reason} | c_acc]}
      end
    end)
    |> then(fn {oks, cs} -> {Enum.reverse(oks), Enum.reverse(cs)} end)
  end

  # 把 resolved 切片叠回 baseline；重叠帧后到的 intervention 覆盖（确定性）。
  defp apply_resolved(projection, resolved) do
    base = Map.new(projection, fn [f, p, v] -> {f, [f, p, v]} end)

    resolved
    |> Enum.reduce(base, fn {_int, applied_slice}, acc ->
      Enum.reduce(applied_slice, acc, fn [f, p, v], m -> Map.put(m, f, [f, p, v]) end)
    end)
    |> Map.values()
    |> Enum.sort_by(fn [f, _, _] -> f end)
  end

  # ------------------------------------------------------------------
  # 序列化
  # ------------------------------------------------------------------

  defp segment_notes(%Segment{seq_ids: seq_ids}, req) do
    case Map.get(req, :notes_by_seq) do
      nil ->
        notes = Map.get(req, :notes, [])
        Enum.filter(notes, fn n -> n.seq_id in seq_ids end)

      by_seq ->
        seq_ids |> Enum.map(&Map.get(by_seq, &1)) |> Enum.reject(&is_nil/1)
    end
  end

  defp all_notes(req) do
    case Map.get(req, :notes_by_seq) do
      nil -> Map.get(req, :notes, [])
      by_seq -> Map.values(by_seq)
    end
  end

  defp serialize_note(note) do
    %{
      "id" => note.id,
      "seq_id" => note.seq_id,
      "start_tick" => note.start_tick,
      "duration_tick" => note.duration_tick,
      "midi" => Key.to_midi(note.key),
      "lyric" => note.lyric
    }
  end

  defp serialize_interventions(req, artifact) do
    resolved_ids = MapSet.new(artifact.resolved, fn {int, _} -> int.id end)

    req
    |> Map.get(:interventions, [])
    |> Enum.map(fn int ->
      {f0, f1} = frame_boundary(int.payload)

      %{
        "id" => to_string(int.id),
        "boundary" => [f0, f1],
        "status" => if(MapSet.member?(resolved_ids, int.id), do: "resolved", else: "conflict")
      }
    end)
  end

  defp frame_boundary(%{frames: %{boundary: {f0, f1}}}), do: {f0, f1}
  defp frame_boundary(_), do: {0, 0}

  defp tempo_segments(req) do
    req
    |> Map.get(:tempo_segments, [[0, 120.0]])
    |> Enum.map(fn
      {t, bpm} -> [t, bpm]
      [t, bpm] -> [t, bpm]
    end)
  end

  defp sample_rate(req), do: opts(req)[:sample_rate] || @default_sample_rate

  defp opts(req), do: req |> Map.get(:opts, %{}) |> Map.new()

  defp default_output_dir, do: Path.join([File.cwd!(), "priv", "output"])
end
