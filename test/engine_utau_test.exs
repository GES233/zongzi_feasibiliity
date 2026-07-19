defmodule ZongziFeasibility.Engine.UTAUTest do
  use ExUnit.Case, async: true

  alias Zongzi.Score.{Key.TwelveET, Note}
  alias Zongzi.Windowing.Segment
  alias ZongziFeasibility.Engine.UTAU

  defp build_note(attrs) do
    {:ok, key} = TwelveET.new(Map.fetch!(attrs, :midi))

    {:ok, note} =
      attrs
      |> Map.put(:key, key)
      |> Note.new()

    note
  end

  defp sample_note(lyric \\ "さ", overrides \\ %{}) do
    note =
      build_note(%{
        id: "Note_1",
        seq_id: 1,
        start_tick: 0,
        duration_tick: 480,
        midi: 60,
        lyric: lyric
      })

    Map.merge(note, overrides)
  end

  test "实现 Zongzi.Engine behaviour（check 必选，render 可选）" do
    assert Code.ensure_loaded?(UTAU)
    assert function_exported?(UTAU, :check, 1)
    assert function_exported?(UTAU, :render, 1)

    behaviours =
      for {k, v} <- UTAU.module_info(:attributes), k == :behaviour, b <- v, do: b

    assert Zongzi.Engine in behaviours
  end

  describe "G-ENG-02: check/render 只吃 segments" do
    test "check 缺 segments → {:error, :missing_segments}" do
      assert {:error, :missing_segments} = UTAU.check(%{})
      assert {:error, :missing_segments} = UTAU.check(%{notes: []})
    end

    test "render 缺 segments → {:error, :missing_segments}" do
      assert {:error, :missing_segments} = UTAU.render(%{})
    end

    test "check 空 segments → 空投影，不触引擎" do
      assert {:ok, artifact} = UTAU.check(%{segments: []})
      assert artifact.projection == []
      assert artifact.spills == []
      assert artifact.resolved == []
      assert artifact.conflicts == []
    end
  end

  describe "UTAU 配置校验" do
    test "缺 utau_config 且 app env 不完整 → {:error, {:missing_utau_config, _}}" do
      original = Application.get_env(:zongzi_feasibility, :utau)

      try do
        Application.put_env(:zongzi_feasibility, :utau, %{})
        {:ok, seg} = Segment.new(0, 480, [1])
        note = sample_note()

        assert {:error, {:missing_utau_config, :voicebank_root}} =
                 UTAU.check(%{segments: [seg], notes_by_seq: %{1 => note}})
      after
        Application.put_env(:zongzi_feasibility, :utau, original)
      end
    end
  end
end
