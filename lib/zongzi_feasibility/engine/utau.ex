defmodule ZongziFeasibility.Engine.UTAU do
  @moduledoc """
  UTAU 真实引擎适配器（zongzi-svs 线）。

  实现 `Zongzi.Engine` behaviour：
  - `check/1`：校验声库配置、oto.ini 歌词覆盖，并返回帧级投影/溢出。
  - `render/1`：消费 `checked_request`，调用外部 resampler + wavtool 渲染最终 WAV。

  依赖配置项：

      config :zongzi_feasibility, :utau,
        voicebank_root: "...",
        resampler: "...",
        wavtool: "..."

  也可以在 `req.opts[:utau_config]` 里覆盖。
  """

  @behaviour Zongzi.Engine

  alias Zongzi.Score.Key
  alias Zongzi.Windowing.Segment
  alias ZongziFeasibility.Declaration.Pitch
  alias ZongziFeasibility.Engine.Python

  @default_sample_rate 86.13

  # ------------------------------------------------------------------
  # check/1
  # ------------------------------------------------------------------

  @impl true
  def check(%{segments: segments} = req) when is_list(segments) do
    with {:ok, utau_config} <- utau_config(req),
         {:ok, projection, spills} <- project_segments(segments, req, utau_config) do
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
    with {:ok, render_result} <- render_all(req) do
      applied = apply_resolved(artifact.projection, artifact.resolved)
      {:ok, Map.merge(artifact, %{applied: applied, render: render_result})}
    end
  end

  # ------------------------------------------------------------------
  # UTAU 配置
  # ------------------------------------------------------------------

  defp utau_config(req) do
    config =
      req
      |> opts()
      |> Map.get(:utau_config, %{})
      |> Map.new()

    app_config = Application.get_env(:zongzi_feasibility, :utau, %{})
    merged = Map.merge(Map.new(app_config), config)

    case {merged[:voicebank_root], merged[:resampler], merged[:wavtool]} do
      {nil, _, _} -> {:error, {:missing_utau_config, :voicebank_root}}
      {_, nil, _} -> {:error, {:missing_utau_config, :resampler}}
      {_, _, nil} -> {:error, {:missing_utau_config, :wavtool}}
      {vb, r, w} -> {:ok, %{"voicebank_root" => vb, "resampler" => r, "wavtool" => w}}
    end
  end

  # ------------------------------------------------------------------
  # 逐 segment 投影 / 检查
  # ------------------------------------------------------------------

  defp project_segments(segments, req, utau_config) do
    segments
    |> Enum.reduce_while({:ok, [], []}, fn seg, {:ok, proj_acc, spill_acc} ->
      body = %{
        "action" => "utau_check",
        "notes" => seg |> segment_notes(req) |> Enum.map(&serialize_note/1),
        "tempo_segments" => tempo_segments(req),
        "sample_rate" => sample_rate(req),
        "preutterance_frames" => opts(req)[:preutterance_frames] || 0,
        "window" => [seg.start_tick, seg.end_tick],
        "utau_config" => utau_config
      }

      case Python.run(body) do
        {:ok, %{"projection" => proj, "spills" => spills}} ->
          {:cont, {:ok, proj_acc ++ proj, spill_acc ++ spills}}

        {:ok, other} ->
          {:halt, {:error, {:unexpected_utau_check_response, other}}}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
    |> case do
      {:ok, proj, spills} -> {:ok, merge_frames(proj), merge_spills(spills)}
      {:error, _} = err -> err
    end
  end

  defp merge_frames(frames) do
    frames
    |> Enum.sort_by(fn [f, _, _] -> f end)
    |> Enum.uniq_by(fn [f, _, _] -> f end)
  end

  defp merge_spills(spills), do: Enum.sort_by(spills, fn [f0, _] -> f0 end)

  # ------------------------------------------------------------------
  # render
  # ------------------------------------------------------------------

  defp render_all(req) do
    with {:ok, utau_config} <- utau_config(req) do
      notes = req |> all_notes() |> Enum.map(&serialize_note/1)

      body = %{
        "action" => "utau_render",
        "notes" => notes,
        "tempo_segments" => tempo_segments(req),
        "utau_config" => utau_config,
        "output_dir" => opts(req)[:output_dir] || default_output_dir(),
        "tag" => opts(req)[:tag] || "utau"
      }

      case Python.run(body) do
        {:ok, %{"path" => path} = result} ->
          {:ok, Map.put(result, "path", path)}

        {:error, _} = err ->
          err
      end
    end
  end

  # ------------------------------------------------------------------
  # resolve / applied 合并（与 toy engine 一致）
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
