defmodule ZongziFeasibility.Scenarios.GPre03 do
  @moduledoc "G-PRE-03：小 gap·无 interv。preutterance 溢出到 gap 内，不触及 A。"
  @behaviour ZongziFeasibility.Scenario

  import ZongziFeasibility.Scenario, only: [base_caller: 1]

  @impl true
  def id, do: "G-PRE-03"
  @impl true
  def title, do: "小 gap·无 interv：preutterance 溢出到 gap 内，不触及 A"

  # A [0,480) → 帧尾 43；gap 120 tick；B [600,1080) → 帧头 54。
  @impl true
  def setup do
    base_caller([
      %{start_tick: 0, duration_tick: 480, midi: 60, lyric: "a"},
      %{start_tick: 600, duration_tick: 480, midi: 62, lyric: "ka"}
    ])
  end

  @impl true
  def edits(_caller), do: [{:edit_lyric, 2, "kas"}]

  @impl true
  def expect(%{rounds: [baseline, r1]}) do
    cond do
      baseline.spills == r1.spills ->
        {:miss, "改歌词后 spill 应前移，实际未变 #{inspect(r1.spills)}"}

      r1.structural.conflicts != [] or r1.semantic.conflicts != [] ->
        {:miss, "无 intervention，不应有任何冲突"}

      not spill_within_gap?(baseline.spills) or not spill_within_gap?(r1.spills) ->
        {:miss, "spill 应始终留在 gap 内 [43, 54)，实际 #{inspect({baseline.spills, r1.spills})}"}

      true ->
        :ok
    end
  end

  defp spill_within_gap?(spills) do
    Enum.all?(spills, fn [f0, f1] -> f0 >= 43 and f1 <= 54 end)
  end
end
