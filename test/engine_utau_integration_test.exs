defmodule ZongziFeasibility.Engine.UTAUIntegrationTest do
  use ExUnit.Case, async: false

  alias Zongzi.Score.{Key.TwelveET, Note}
  alias Zongzi.Windowing.Segment
  alias ZongziFeasibility.Engine.UTAU

  @moduletag :integration

  defp build_note(attrs) do
    {:ok, key} = TwelveET.new(Map.fetch!(attrs, :midi))
    {:ok, note} = attrs |> Map.put(:key, key) |> Note.new()
    note
  end

  defp utau_req(notes, opts \\ %{}) do
    notes_by_seq = Map.new(notes, fn n -> {n.seq_id, n} end)
    max_end = notes |> Enum.map(&(&1.start_tick + &1.duration_tick)) |> Enum.max(fn -> 0 end)
    {:ok, seg} = Segment.new(0, max_end, Map.keys(notes_by_seq))
    %{segments: [seg], notes_by_seq: notes_by_seq, tempo_segments: [[0, 120.0]], opts: opts}
  end

  test "check: 已知歌词返回升序投影" do
    note =
      build_note(%{
        id: "Note_1",
        seq_id: 1,
        start_tick: 0,
        duration_tick: 480,
        midi: 60,
        lyric: "さ"
      })

    assert {:ok, artifact} = UTAU.check(utau_req([note]))
    assert is_list(artifact.projection)
    assert artifact.projection == Enum.sort_by(artifact.projection, fn [f, _, _] -> f end)
    assert is_list(artifact.spills)
    assert artifact.resolved == []
    assert artifact.conflicts == []
  end

  test "check: 未知歌词返回错误" do
    note =
      build_note(%{
        id: "Note_1",
        seq_id: 1,
        start_tick: 0,
        duration_tick: 480,
        midi: 60,
        lyric: "不存在"
      })

    assert {:error, err} = UTAU.check(utau_req([note]))
    assert is_binary(err)
  end

  test "render: 单音符渲染出 WAV" do
    note =
      build_note(%{
        id: "Note_1",
        seq_id: 1,
        start_tick: 0,
        duration_tick: 480,
        midi: 60,
        lyric: "さ"
      })

    opts = %{
      output_dir: Path.join([File.cwd!(), "priv", "output", "utau_integration"]),
      tag: "single"
    }

    {:ok, check_artifact} = UTAU.check(utau_req([note], opts))
    checked = %{request: utau_req([note], opts), artifact: check_artifact, fingerprint: nil}
    assert {:ok, artifact} = UTAU.render(checked)
    assert File.exists?(artifact.render["path"])
    assert artifact.render["sample_rate"] > 0
    assert artifact.render["duration"] > 0
  end
end
