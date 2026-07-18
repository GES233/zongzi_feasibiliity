defmodule ZongziFeasibility.Scenarios.GPre06 do
  @moduledoc "G-PRE-06：重叠音符。A 尾与 B 头重叠，preutterance 在重叠区内变化。"
  @behaviour ZongziFeasibility.Scenario

  import ZongziFeasibility.Scenario, only: [base_caller: 1, mount: 4]

  @impl true
  def id, do: "G-PRE-06"
  @impl true
  def title, do: "重叠音符：B preutterance 在 A/B 重叠区内变化 → iv_a conflict"

  # A [0,600) → 帧 [0,54)；B [480,960) → 帧 [43,86)；重叠区 [43,54) 被 B 覆盖。
  @impl true
  def setup do
    base_caller([
      %{start_tick: 0, duration_tick: 600, midi: 60, lyric: "a"},
      %{start_tick: 480, duration_tick: 480, midi: 62, lyric: "ka"}
    ])
    |> mount(1, {240, 600}, "iv_a")
  end

  @impl true
  def edits(_caller), do: [{:edit_lyric, 2, "kasama"}]

  @impl true
  def expect(%{rounds: [baseline, r1]}) do
    cond do
      baseline.semantic.resolved != ["iv_a"] ->
        {:miss, "baseline 应 resolve iv_a（含重叠区投影），实际 #{inspect(baseline.semantic)}"}

      r1.decisions != %{"iv_a" => :preserve} ->
        {:miss, "歌词编辑不改结构，应 preserve，实际 #{inspect(r1.decisions)}"}

      r1.semantic.conflicts != [{"iv_a", :snapshot_stale}] ->
        {:miss, "重叠区内 spill 扩张应判 conflict，实际 #{inspect(r1.semantic.conflicts)}"}

      true ->
        :ok
    end
  end
end
