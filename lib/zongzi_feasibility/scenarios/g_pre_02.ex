defmodule ZongziFeasibility.Scenarios.GPre02 do
  @moduledoc "G-PRE-02：紧靠·有 interv。A 尾部 interv 被 B preutterance 覆盖 → 语义 conflict。"
  @behaviour ZongziFeasibility.Scenario

  import ZongziFeasibility.Scenario, only: [base_caller: 1, mount: 4]

  @impl true
  def id, do: "G-PRE-02"
  @impl true
  def title, do: "紧靠·有 interv：B preutterance 挤入 A 尾部 → iv_a conflict"

  @impl true
  def setup do
    base_caller([
      %{start_tick: 0, duration_tick: 480, midi: 60, lyric: "a"},
      %{start_tick: 480, duration_tick: 480, midi: 62, lyric: "ka"}
    ])
    |> mount(1, {240, 480}, "iv_a")
  end

  @impl true
  def edits(_caller), do: [{:edit_lyric, 2, "kasama"}]

  @impl true
  def expect(%{rounds: [baseline, r1]}) do
    cond do
      baseline.semantic.resolved != ["iv_a"] ->
        {:miss, "baseline 应 resolve iv_a，实际 #{inspect(baseline.semantic)}"}

      r1.decisions != %{"iv_a" => :preserve} ->
        {:miss, "歌词编辑不改结构，应 preserve，实际 #{inspect(r1.decisions)}"}

      r1.semantic.conflicts != [{"iv_a", :snapshot_stale}] ->
        {:miss, "spill 覆盖 A 尾部应判真 conflict，实际 #{inspect(r1.semantic.conflicts)}"}

      r1.semantic.resolved != [] ->
        {:miss, "conflict 后不应再 apply，实际 #{inspect(r1.semantic.resolved)}"}

      true ->
        :ok
    end
  end
end
