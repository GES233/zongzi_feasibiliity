defmodule ZongziFeasibility.SmokeTest do
  use ExUnit.Case, async: true

  alias ZongziFeasibility.Engine.Request
  alias ZongziFeasibility.Declaration.Pitch
  alias Zongzi.{Intervention, Score}

  @tag :smoke
  test "Declaration.Pitch resolve: snapshot match → apply delta" do
    snap = %{0 => %{pitch: 440.0, vuv: 1}, 1 => %{pitch: 442.0, vuv: 1}}
    delta = %{0 => %{pitch: 3.0}}
    payload = %{original: snap, delta: delta, id: "int_1"}

    int = %Intervention{
      id: "int_1",
      channel: :pitch,
      anchor: {1, 2, 3},
      payload: payload,
      snapshot: snap
    }

    current_proj = %{0 => %{pitch: 440.0, vuv: 1}, 1 => %{pitch: 442.0, vuv: 1}}

    assert {:ok, applied} = Pitch.resolve(int, current_proj)
    assert applied[0][:pitch] == 443.0
    assert applied[1][:pitch] == 442.0
  end

  @tag :smoke
  test "Declaration.Pitch resolve: mismatch → skip" do
    snap = %{0 => %{pitch: 440.0, vuv: 1}}
    payload = %{original: snap, delta: %{0 => %{pitch: 1.0}}, id: "int_2"}

    int = %Intervention{
      id: "int_2",
      channel: :pitch,
      anchor: {1, 2, 3},
      payload: payload,
      snapshot: snap
    }

    # current projection differs at frame 0
    current_proj = %{0 => %{pitch: 445.0, vuv: 1}}

    assert {:skip, :snapshot_stale} = Pitch.resolve(int, current_proj)
  end

  @tag :smoke
  test "Engine.Request struct builds" do
    {:ok, key} = Score.Key.TwelveET.new(60)
    {:ok, note} = Score.Note.new(%{
      id: "n1", start_tick: 0, duration_tick: 480, key: key, lyric: "a"
    })

    req = Request.new(
      notes: [note],
      tempo_segments: [{0, 120.0}],
      sample_rate: 86.13,
      engine: :diff_singer
    )

    assert req.notes == [note]
    assert req.tempo_segments == [{0, 120.0}]
    assert req.sample_rate == 86.13
  end
end
