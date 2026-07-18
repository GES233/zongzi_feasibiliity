defmodule ZongziFeasibility.Scenarios.GInt02 do
  @moduledoc "G-INT-02：snapshot 失配 → conflict，不静默 apply。"
  @behaviour ZongziFeasibility.Scenario

  import ZongziFeasibility.Scenario, only: [base_caller: 1, mount: 4]

  @impl true
  def id, do: "G-INT-02"
  @impl true
  def title, do: "snapshot 失配 → conflict（不静默 apply）"

  @impl true
  def setup do
    notes = for t <- [0, 480], do: %{start_tick: t, duration_tick: 480, midi: 62, lyric: nil}

    notes
    |> base_caller()
    |> mount(2, {480, 960}, "iv_b")
  end

  @impl true
  def edits(_caller), do: [{:edit_key, 2, 65}]

  @impl true
  def expect(%{rounds: [baseline, r1]}) do
    cond do
      baseline.semantic.resolved != ["iv_b"] ->
        {:miss, "baseline 应 resolve iv_b，实际 #{inspect(baseline.semantic)}"}

      r1.decisions != %{"iv_b" => :preserve} ->
        {:miss, "edit_key 不改结构，应 preserve，实际 #{inspect(r1.decisions)}"}

      r1.semantic.resolved != [] ->
        {:miss, "失配后不应再 apply（不静默），实际 #{inspect(r1.semantic.resolved)}"}

      r1.semantic.conflicts != [{"iv_b", :snapshot_stale}] ->
        {:miss, "应 conflict :snapshot_stale，实际 #{inspect(r1.semantic.conflicts)}"}

      true ->
        :ok
    end
  end
end
