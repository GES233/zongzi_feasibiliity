defmodule ZongziFeasibility.Scenarios.GPre01 do
  @moduledoc "G-PRE-01：紧靠·无 intervention。改 B 歌词 → preutterance 前移，无任何冲突。"
  @behaviour ZongziFeasibility.Scenario

  import ZongziFeasibility.Scenario, only: [base_caller: 1]

  @impl true
  def id, do: "G-PRE-01"
  @impl true
  def title, do: "紧靠·无 interv：改 B 歌词 → preutterance 前移（被连续音符吸收）"

  @impl true
  def setup do
    base_caller([
      %{start_tick: 0, duration_tick: 480, midi: 60, lyric: "a"},
      %{start_tick: 480, duration_tick: 480, midi: 62, lyric: "ka"}
    ])
  end

  @impl true
  def edits(_caller), do: [{:edit_lyric, 2, "kasama"}]

  @impl true
  def expect(%{rounds: [baseline, r1]}) do
    cond do
      baseline.spills == r1.spills ->
        {:miss, "改歌词后 spill 应前移，实际未变 #{inspect(r1.spills)}"}

      r1.structural.conflicts != [] or r1.semantic.conflicts != [] ->
        {:miss, "无 intervention，不应有任何冲突"}

      true ->
        :ok
    end
  end
end
