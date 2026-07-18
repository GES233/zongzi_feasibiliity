defmodule ZongziFeasibility.Scenarios.GPre04 do
  @moduledoc "G-PRE-04：小 gap·有 interv。spill 先不碰撞（apply）后真碰撞（conflict）——判真假。"
  @behaviour ZongziFeasibility.Scenario

  import ZongziFeasibility.Scenario, only: [base_caller: 1, mount: 4]

  @impl true
  def id, do: "G-PRE-04"
  @impl true
  def title, do: "小 gap·有 interv：spill 两轮逼近——先 apply（未碰撞）后 conflict（真碰撞）"

  # 几何同 G-PRE-03：A 帧尾 43，B 帧头 54，iv_a 覆盖帧 [22, 43)。
  @impl true
  def setup do
    base_caller([
      %{start_tick: 0, duration_tick: 480, midi: 60, lyric: "a"},
      %{start_tick: 600, duration_tick: 480, midi: 62, lyric: "ka"}
    ])
    |> mount(1, {240, 480}, "iv_a")
  end

  @impl true
  def edits(_caller), do: [{:edit_lyric, 2, "kas"}, {:edit_lyric, 2, "kasamayan"}]

  @impl true
  def expect(%{rounds: [baseline, r1, r2]}) do
    cond do
      baseline.semantic.resolved != ["iv_a"] ->
        {:miss, "baseline 应 resolve iv_a，实际 #{inspect(baseline.semantic)}"}

      # N = 4 + len("kas") = 7 → spill [47, 54)，不触及 A 边界 [22, 43)
      r1.semantic.resolved != ["iv_a"] ->
        {:miss, "round1 spill 未碰撞，应 resolve（判假通过），实际 #{inspect(r1.semantic)}"}

      r1.semantic.conflicts != [] ->
        {:miss, "round1 不应误报 conflict，实际 #{inspect(r1.semantic.conflicts)}"}

      # N = 4 + len("kasamayan") = 13 → spill [41, 54)，帧 41/42 落入 iv_a 边界
      r2.semantic.conflicts != [{"iv_a", :snapshot_stale}] ->
        {:miss, "round2 spill 真碰撞，应 conflict，实际 #{inspect(r2.semantic.conflicts)}"}

      true ->
        :ok
    end
  end
end
