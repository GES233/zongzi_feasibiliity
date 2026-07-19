defmodule ZongziFeasibility.Measurer do
  @moduledoc """
  场景跑批 + 指标 + 报告。

  `run/1` 顺序执行全部 golden scenario（round 1 = baseline，之后每个 edit 一轮
  对抗：`Caller.edit → render_round`），每轮自动落
  `priv/output/<scenario>/round_NN.png`。

  输出：console 表 + `priv/output/report.json` + `priv/output/report.html`（单文件，
  内嵌 base64 图）。

  指标：结构决策分布（preserve/rebase/relocate/split/conflict）、
  语义决议分布（apply/conflict）、期望命中率。
  telemetry：`[:zongzi_feasibility, :scenario, :round]`。
  """

  alias ZongziFeasibility.Caller

  @scenarios [
    ZongziFeasibility.Scenarios.GInt01,
    ZongziFeasibility.Scenarios.GInt02,
    ZongziFeasibility.Scenarios.GEng02,
    ZongziFeasibility.Scenarios.GPre01,
    ZongziFeasibility.Scenarios.GPre02,
    ZongziFeasibility.Scenarios.GPre03,
    ZongziFeasibility.Scenarios.GPre04,
    ZongziFeasibility.Scenarios.GPre05,
    ZongziFeasibility.Scenarios.GPre06,
    ZongziFeasibility.Scenarios.GPre07
  ]

  @round_event [:zongzi_feasibility, :scenario, :round]

  def output_dir, do: Path.join([File.cwd!(), "priv", "output"])

  def run(scenarios \\ @scenarios) do
    results = Enum.map(scenarios, &run_scenario/1)
    metrics = aggregate(results)

    File.mkdir_p!(output_dir())
    write_json(metrics, results)
    write_html(metrics, results)
    print_console(metrics, results)

    %{metrics: metrics, results: results}
  end

  @doc "跑单个 scenario，返回 %{id, title, verdict, rounds}。"
  def run_scenario(scenario) do
    caller = scenario.setup()
    dir = Path.join(output_dir(), scenario.id())
    File.mkdir_p!(dir)

    {final_caller, rounds} = run_rounds(scenario, caller, dir)
    verdict = scenario.expect(%{rounds: rounds, final_caller: final_caller})

    %{id: scenario.id(), title: scenario.title(), verdict: verdict, rounds: rounds}
  end

  # ------------------------------------------------------------------
  # 对抗轮
  # ------------------------------------------------------------------

  defp run_rounds(scenario, caller, dir) do
    ops = [:baseline | scenario.edits(caller)]

    {rounds, caller} =
      ops
      |> Enum.with_index(1)
      |> Enum.map_reduce(caller, fn {op, i}, caller ->
        {caller, report} = edit_or_baseline(caller, op)
        tag = "round_#{String.pad_leading(Integer.to_string(i), 2, "0")}"

        {duration, {:ok, artifact}} =
          :timer.tc(fn -> Caller.render_round(caller, tag, %{opts: %{output_dir: dir}}) end)

        :telemetry.execute(@round_event, %{duration: duration}, %{
          scenario: scenario.id(),
          round: i,
          op: inspect(report.op)
        })

        {summarize_round(i, report, artifact), caller}
      end)

    {caller, rounds}
  end

  defp edit_or_baseline(caller, :baseline) do
    {:ok, segments} = Caller.window(caller)

    {caller,
     %{
       op: :baseline,
       survived: caller.interventions,
       conflicts: [],
       decisions: %{},
       segments: segments
     }}
  end

  defp edit_or_baseline(caller, op), do: Caller.edit(caller, op)

  defp summarize_round(i, report, artifact) do
    %{
      round: i,
      op: report.op,
      decisions: report.decisions,
      structural: %{
        survived: Enum.map(report.survived, & &1.id),
        conflicts: Enum.map(report.conflicts, fn {int, r} -> {int.id, r} end)
      },
      semantic: %{
        resolved: Enum.map(artifact.resolved, fn {int, _} -> int.id end),
        conflicts: Enum.map(artifact.conflicts, fn {int, r} -> {int.id, r} end)
      },
      spills: artifact.spills,
      segments: length(report.segments),
      png: artifact.path
    }
  end

  # ------------------------------------------------------------------
  # 指标
  # ------------------------------------------------------------------

  defp aggregate(results) do
    rounds = Enum.flat_map(results, & &1.rounds)

    structural =
      rounds
      |> Enum.flat_map(fn r -> Map.values(r.decisions) end)
      |> Enum.frequencies()

    passed = Enum.count(results, &(&1.verdict == :ok))
    total = length(results)

    %{
      structural_decisions: structural,
      semantic: %{
        apply: rounds |> Enum.map(fn r -> length(r.semantic.resolved) end) |> Enum.sum(),
        conflict: rounds |> Enum.map(fn r -> length(r.semantic.conflicts) end) |> Enum.sum()
      },
      expectations: %{
        passed: passed,
        total: total,
        hit_rate: if(total > 0, do: Float.round(passed / total, 4), else: 0.0)
      }
    }
  end

  # ------------------------------------------------------------------
  # console
  # ------------------------------------------------------------------

  defp print_console(metrics, results) do
    IO.puts("\n== zongzi_feasibility 对抗报告 ==\n")

    for r <- results do
      case r.verdict do
        :ok -> IO.puts("PASS  #{r.id}  #{r.title}")
        {:miss, msg} -> IO.puts("MISS  #{r.id}  #{r.title}\n      #{msg}")
      end
    end

    e = metrics.expectations

    IO.puts("""

    结构决策分布: #{inspect(metrics.structural_decisions)}
    语义决议:     apply=#{metrics.semantic.apply} conflict=#{metrics.semantic.conflict}
    期望命中:     #{e.passed}/#{e.total} (#{trunc(e.hit_rate * 100)}%)

    report: #{Path.join(output_dir(), "report.html")}
    """)
  end

  # ------------------------------------------------------------------
  # report.json
  # ------------------------------------------------------------------

  defp write_json(metrics, results) do
    payload = %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      metrics: metrics,
      scenarios:
        Enum.map(results, fn r ->
          %{
            id: r.id,
            title: r.title,
            verdict: verdict_str(r.verdict),
            rounds: Enum.map(r.rounds, &json_round/1)
          }
        end)
    }

    File.write!(Path.join(output_dir(), "report.json"), Jason.encode!(payload, pretty: true))
  end

  defp json_round(r) do
    %{
      r
      | op: inspect(r.op),
        structural: %{
          survived: r.structural.survived,
          conflicts: Enum.map(r.structural.conflicts, &fmt_conflict/1)
        },
        semantic: %{
          resolved: r.semantic.resolved,
          conflicts: Enum.map(r.semantic.conflicts, &fmt_conflict/1)
        }
    }
  end

  # ------------------------------------------------------------------
  # report.html
  # ------------------------------------------------------------------

  defp write_html(metrics, results) do
    html = """
    <!DOCTYPE html>
    <html lang="zh">
    <head>
    <meta charset="utf-8">
    <title>zongzi_feasibility 对抗报告</title>
    <style>
      body{font-family:system-ui,-apple-system,sans-serif;margin:2rem;background:#fafafa;color:#222}
      h1{font-size:1.4rem} h2{font-size:1.15rem;margin:0} h3{font-size:1rem;color:#555}
      .card{background:#fff;border:1px solid #ddd;border-radius:8px;padding:1rem 1.5rem;margin:1.5rem 0}
      .pass{color:#087f23;font-weight:600}.fail{color:#c62828;font-weight:600}
      img{max-width:100%;border:1px solid #eee;border-radius:4px;margin:.5rem 0}
      table{border-collapse:collapse;margin:.5rem 0}
      td,th{border:1px solid #ccc;padding:.25rem .6rem;font-size:.85rem;text-align:left}
      code{background:#f0f0f0;padding:0 .3rem;border-radius:3px}
    </style>
    </head>
    <body>
    <h1>zongzi_feasibility 对抗报告</h1>
    <p>生成于 #{DateTime.utc_now() |> DateTime.to_iso8601()}</p>
    #{summary_html(metrics)}
    #{Enum.map_join(results, "\n", &scenario_html/1)}
    </body>
    </html>
    """

    File.write!(Path.join(output_dir(), "report.html"), html)
  end

  defp summary_html(metrics) do
    e = metrics.expectations

    rows =
      metrics.structural_decisions
      |> Enum.map(fn {k, v} -> "<tr><td>#{k}</td><td>#{v}</td></tr>" end)
      |> Enum.join("")

    """
    <div class="card">
    <h2>汇总</h2>
    <p>期望命中：<strong>#{e.passed}/#{e.total}</strong>（#{trunc(e.hit_rate * 100)}%）　
       语义决议：apply=#{metrics.semantic.apply} / conflict=#{metrics.semantic.conflict}</p>
    <table><tr><th>结构决策</th><th>次数</th></tr>#{rows}</table>
    </div>
    """
  end

  defp scenario_html(r) do
    {cls, label} =
      case r.verdict do
        :ok -> {"pass", "PASS"}
        {:miss, msg} -> {"fail", "MISS: #{msg}"}
      end

    """
    <div class="card">
      <h2>#{r.id} <span class="#{cls}">#{label}</span></h2>
      <p>#{r.title}</p>
      #{Enum.map_join(r.rounds, "\n", &round_html/1)}
    </div>
    """
  end

  defp round_html(round) do
    img =
      case File.read(round.png) do
        {:ok, bin} ->
          ~s(<img src="data:image/png;base64,#{Base.encode64(bin)}" alt="round #{round.round}">)

        {:error, _} ->
          "<p>(png missing: #{round.png})</p>"
      end

    """
    <div>
      <h3>round #{round.round} — <code>#{inspect(round.op)}</code></h3>
      <table>
        <tr><th>结构决策</th><th>结构冲突</th><th>语义 apply</th><th>语义 conflict</th><th>segments</th><th>spills</th></tr>
        <tr>
          <td>#{fmt_decisions(round.decisions)}</td>
          <td>#{fmt_conflicts(round.structural.conflicts)}</td>
          <td>#{Enum.join(round.semantic.resolved, ", ") |> presence()}</td>
          <td>#{fmt_conflicts(round.semantic.conflicts)}</td>
          <td>#{round.segments}</td>
          <td>#{inspect(round.spills)}</td>
        </tr>
      </table>
      #{img}
    </div>
    """
  end

  # ------------------------------------------------------------------
  # fmt helpers
  # ------------------------------------------------------------------

  defp verdict_str(:ok), do: "PASS"
  defp verdict_str({:miss, msg}), do: "MISS: #{msg}"

  defp fmt_conflict({id, reason}), do: "#{id}:#{inspect(reason)}"

  defp fmt_decisions(map) when map_size(map) == 0, do: "—"

  defp fmt_decisions(map) do
    map |> Enum.map(fn {id, d} -> "#{id}:#{d}" end) |> Enum.join(", ")
  end

  defp fmt_conflicts([]), do: "—"
  defp fmt_conflicts(cs), do: Enum.map_join(cs, ", ", &fmt_conflict/1)

  defp presence(""), do: "—"
  defp presence(s), do: s
end
