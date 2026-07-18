defmodule ZongziFeasibility.Scenarios.GPre05 do
  @moduledoc "G-PRE-05：大 gap。两窗各自渲染，B 的 preutterance 不跨窗边界，A 的 interv 稳定 apply。"
  @behaviour ZongziFeasibility.Scenario

  import ZongziFeasibility.Scenario, only: [base_caller: 1, mount: 4]

  @impl true
  def id, do: "G-PRE-05"
  @impl true
  def title, do: "大 gap：RestSplit3Beats 切两窗，preutterance 不跨窗边界"

  # gap 2160 tick = 4.5 拍（iv_a scope ±240 撑宽 A 侧 span 后仍 ≥ 3 拍）→ 切窗。
  @impl true
  def setup do
    base_caller([
      %{start_tick: 0, duration_tick: 480, midi: 60, lyric: "a"},
      %{start_tick: 2880, duration_tick: 480, midi: 62, lyric: "ka"}
    ])
    |> mount(1, {240, 480}, "iv_a")
  end

  @impl true
  def edits(_caller), do: [{:edit_lyric, 2, "kasama"}]

  @impl true
  def expect(%{rounds: [baseline, r1]}) do
    cond do
      baseline.segments != 2 or r1.segments != 2 ->
        {:miss, "大 gap 应切两窗，实际 #{inspect({baseline.segments, r1.segments})}"}

      baseline.semantic.resolved != ["iv_a"] ->
        {:miss, "baseline 应 resolve iv_a，实际 #{inspect(baseline.semantic)}"}

      r1.semantic.resolved != ["iv_a"] or r1.semantic.conflicts != [] ->
        {:miss, "B 的 spill 不跨窗，iv_a 应稳定 resolve，实际 #{inspect(r1.semantic)}"}

      baseline.spills == r1.spills ->
        {:miss, "B 歌词变化应移动 B 窗内 spill，实际未变"}

      true ->
        :ok
    end
  end
end
