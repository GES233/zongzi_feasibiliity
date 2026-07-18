defmodule ZongziFeasibility.Scenario do
  @moduledoc """
  Golden scenario 契约（对齐 zongzi `GOLDEN_SCENARIOS.md` 骨架）。

  流程（由 `ZongziFeasibility.Measurer` 驱动）：

  1. `setup/0` — 建 Caller、挂载 interventions（此刻取 snapshot，需要投影）。
  2. round 0 — baseline render（无编辑，出基线图）。
  3. `edits/1` 每个 op 一轮对抗：`Caller.edit → render_round`。
  4. `expect/1` — 判定全部 round 的结构/语义结果。

  `expect/1` 收到的 round 记录：

      %{
        round: non_neg_integer(),
        op: term(),
        decisions: %{intervention_id => :preserve | :rebase | :relocate | :split | :conflict},
        structural: %{survived: [id], conflicts: [{id, reason}]},
        semantic: %{resolved: [id], conflicts: [{id, reason}]},
        spills: [[f0, f1]],
        segments: non_neg_integer(),
        png: String.t()
      }
  """

  alias ZongziFeasibility.Caller

  @callback id() :: String.t()
  @callback title() :: String.t()
  @callback setup() :: Caller.t()
  @callback edits(Caller.t()) :: [term()]
  @callback expect(%{rounds: [map()], final_caller: Caller.t()}) :: :ok | {:miss, String.t()}

  @doc "标准 Caller：120bpm 单 tempo，preutterance 基础值 4 帧。"
  def base_caller(notes, opts \\ %{}) do
    Caller.new(%{
      notes: notes,
      opts: Map.merge(%{preutterance_frames: 4}, Map.new(opts))
    })
  end

  @doc "挂载 pitch intervention（单控制点 +100 cents 于 boundary 起点）。"
  def mount(caller, seq, boundary, id) do
    {bs, _be} = boundary

    {caller, _int} =
      Caller.mount_intervention(caller, %{
        seq: seq,
        boundary: boundary,
        control_points: [{bs, 100.0}],
        id: id
      })

    caller
  end
end
