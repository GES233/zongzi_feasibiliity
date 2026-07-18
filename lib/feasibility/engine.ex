defmodule ZongziFeasibility.Engine do
  @moduledoc """
  Local engine bridge via System.cmd → engine_cli.py.

  Spawns `D:\\Conda\\python.exe priv/scripts/engine_cli.py`,
  pipes JSON via stdin, reads result from stdout.

  ## Actions

  - `:project`  — notes → frame-level pitch/vuv
  - `:apply`    — project + interventions → baseline + applied
  - `:visualize` — project + apply → saves PNG → returns path
  """

  alias ZongziFeasibility.Engine.Request

  @python "D:\\Conda\\python.exe"
  @cli    "priv/scripts/engine_cli.py"

  @doc "Generate baseline projection from notes."
  def project(%Request{} = req) do
    body = build_body(req, "project")
    case run(body) do
      {:ok, %{"baseline" => baseline}} -> {:ok, baseline}
      {:error, _} = err -> err
    end
  end

  @doc "Project + apply interventions, returning baseline and applied projections."
  def render(%Request{} = req) do
    body = build_body(req, "apply")
    case run(body) do
      {:ok, %{"baseline" => base, "applied" => appl}} -> {:ok, base, appl}
      {:error, _} = err -> err
    end
  end

  @doc "Render + save visualization PNG, returning file path."
  def visualize(%Request{} = req, tag \\ "comparison") do
    body = build_body(req, "visualize") |> Map.put("tag", tag)
    case run(body) do
      {:ok, %{"path" => path}} -> {:ok, path}
      {:error, _} = err -> err
    end
  end

  # ---- helpers ----

  defp run(body) do
    json = Jason.encode!(body)
    {output, exit_code} = System.cmd(@python, [@cli],
      input: json,
      stderr_to_stdout: true
    )

    case exit_code do
      0 ->
        case Jason.decode(output) do
          {:ok, result} ->
            if Map.has_key?(result, "error") do
              {:error, result["error"]}
            else
              {:ok, result}
            end
          {:error, _} -> {:error, "JSON decode failed: #{String.slice(output, 0, 200)}"}
        end
      n -> {:error, "engine_cli exit #{n}: #{String.slice(output, 0, 200)}"}
    end
  end

  defp build_body(%Request{} = req, action) do
    %{
      "action" => action,
      "notes" => Enum.map(req.notes, &serialize_note/1),
      "tempo_segments" => req.tempo_segments,
      "sample_rate" => req.sample_rate,
      "engine" => req.engine,
      "interventions" => Enum.map(req.interventions, &serialize_intervention/1)
    }
  end

  defp serialize_note(note) do
    %{
      "id" => note.id,
      "seq_id" => note.seq_id,
      "start_tick" => note.start_tick,
      "duration_tick" => note.duration_tick,
      "midi" => Zongzi.Score.Key.to_midi(note.key),
      "lyric" => note.lyric
    }
  end

  defp serialize_intervention(int) do
    %{
      "id" => int.id,
      "channel" => int.channel,
      "anchor" => Tuple.to_list(int.anchor),
      "payload" => int.payload,
      "scope" => int.scope
    }
  end
end
