defmodule ZongziFeasibility.Scenarios.GEng02 do
  @moduledoc "G-ENG-02：check/render 只吃 segments；整轨 = 单段。"
  @behaviour ZongziFeasibility.Scenario

  import ZongziFeasibility.Scenario, only: [base_caller: 1]

  @impl true
  def id, do: "G-ENG-02"
  @impl true
  def title, do: "segments 统一入口：整轨相邻音符 = 单 Segment"

  @impl true
  def setup do
    base_caller([
      %{start_tick: 0, duration_tick: 480, midi: 60, lyric: "a"},
      %{start_tick: 480, duration_tick: 480, midi: 62, lyric: "ka"}
    ])
  end

  @impl true
  def edits(_caller), do: []

  @impl true
  def expect(%{rounds: [baseline]}) do
    cond do
      baseline.segments != 1 ->
        {:miss, "紧靠双音符整轨应切 1 段，实际 #{baseline.segments}"}

      baseline.structural.conflicts != [] or baseline.semantic.conflicts != [] ->
        {:miss, "不应有任何冲突"}

      true ->
        :ok
    end
  end
end
