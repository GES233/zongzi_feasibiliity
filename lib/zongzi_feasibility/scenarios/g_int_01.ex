defmodule ZongziFeasibility.Scenarios.GInt01 do
  @moduledoc "G-INT-01：挂载→编辑→rebase→resolve 完整对抗轮（happy path）。"
  @behaviour ZongziFeasibility.Scenario

  import ZongziFeasibility.Scenario, only: [base_caller: 2, mount: 4]

  @impl true
  def id, do: "G-INT-01"
  @impl true
  def title, do: "挂载→编辑→rebase→resolve 完整对抗一轮"

  @impl true
  def setup do
    # preutterance 0 + lyric 全 nil → 无溢出，split 不改变投影，子干预应全部 resolve。
    notes = for t <- [0, 480, 960], do: %{start_tick: t, duration_tick: 480, midi: 62, lyric: nil}

    notes
    |> base_caller(%{preutterance_frames: 0})
    |> mount(2, {480, 960}, "iv_b")
  end

  @impl true
  def edits(_caller), do: [{:split, 2, 720}]

  @impl true
  def expect(%{rounds: [baseline, r1]}) do
    cond do
      baseline.semantic.resolved != ["iv_b"] ->
        {:miss, "baseline 应 resolve iv_b，实际 #{inspect(baseline.semantic)}"}

      baseline.structural.conflicts != [] ->
        {:miss, "baseline 不应有结构冲突"}

      Enum.sort(r1.structural.survived) != ["iv_b_a", "iv_b_b"] ->
        {:miss, "split 后应存活 iv_b_a/iv_b_b，实际 #{inspect(r1.structural.survived)}"}

      r1.decisions != %{"iv_b_a" => :split, "iv_b_b" => :split} ->
        {:miss, "决策应为两个 split，实际 #{inspect(r1.decisions)}"}

      r1.structural.conflicts != [] ->
        {:miss, "split 不应有结构冲突，实际 #{inspect(r1.structural.conflicts)}"}

      Enum.sort(r1.semantic.resolved) != ["iv_b_a", "iv_b_b"] ->
        {:miss, "两个子干预都应 resolve，实际 #{inspect(r1.semantic)}"}

      r1.semantic.conflicts != [] ->
        {:miss, "投影未变，不应有语义冲突，实际 #{inspect(r1.semantic.conflicts)}"}

      true ->
        :ok
    end
  end
end
