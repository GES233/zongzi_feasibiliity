defmodule ZongziFeasibility.Scenarios.GPre07 do
  @moduledoc "G-PRE-07：三重链。改 B 歌词 → A 尾 iv_a conflict，C 头 iv_c 不受影响稳定 apply。"
  @behaviour ZongziFeasibility.Scenario

  import ZongziFeasibility.Scenario, only: [base_caller: 1, mount: 4]

  @impl true
  def id, do: "G-PRE-07"
  @impl true
  def title, do: "三重链：A 尾 + C 头各挂 interv，改 B 歌词只波及 A 尾"

  @impl true
  def setup do
    base_caller([
      %{start_tick: 0, duration_tick: 480, midi: 60, lyric: "a"},
      %{start_tick: 480, duration_tick: 480, midi: 62, lyric: "ka"},
      %{start_tick: 960, duration_tick: 480, midi: 64, lyric: "sa"}
    ])
    |> mount(1, {240, 480}, "iv_a")
    |> mount(3, {960, 1440}, "iv_c")
  end

  @impl true
  def edits(_caller), do: [{:edit_lyric, 2, "kasama"}]

  @impl true
  def expect(%{rounds: [baseline, r1]}) do
    cond do
      Enum.sort(baseline.semantic.resolved) != ["iv_a", "iv_c"] ->
        {:miss, "baseline 应 resolve iv_a/iv_c，实际 #{inspect(baseline.semantic)}"}

      r1.decisions != %{"iv_a" => :preserve, "iv_c" => :preserve} ->
        {:miss, "歌词编辑不改结构，两个锚都应 preserve，实际 #{inspect(r1.decisions)}"}

      r1.semantic.conflicts != [{"iv_a", :snapshot_stale}] ->
        {:miss, "B spill 扩张应只波及 A 尾，实际 #{inspect(r1.semantic.conflicts)}"}

      r1.semantic.resolved != ["iv_c"] ->
        {:miss, "C 头投影未变，iv_c 应稳定 resolve，实际 #{inspect(r1.semantic.resolved)}"}

      true ->
        :ok
    end
  end
end
