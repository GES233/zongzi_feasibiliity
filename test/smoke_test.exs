defmodule ZongziFeasibility.SmokeTest do
  use ExUnit.Case, async: true

  alias ZongziFeasibility.Declaration.Pitch
  alias Zongzi.Intervention

  defp pitch_int(snapshot) do
    %Intervention{
      id: "int_1",
      channel: :pitch,
      anchor: {1, 2, 3},
      payload: %{
        control_points: [{0, 100.0}],
        boundary: {0, 480},
        frames: %{boundary: {0, 2}, control_points: [{0, 100.0}]}
      },
      snapshot: snapshot,
      declaration: Pitch
    }
  end

  @tag :smoke
  test "Declaration.Pitch resolve: snapshot match → apply cents offset" do
    snap = [[0, 440.0, 1], [1, 440.0, 1]]
    int = pitch_int(snap)

    projection = [[0, 440.0, 1], [1, 440.0, 1], [2, 220.0, 1]]

    assert {:ok, applied} = Pitch.resolve(int, projection)
    expected = 440.0 * :math.pow(2.0, 100.0 / 1200.0)
    assert [[0, p0, 1], [1, p1, 1]] = applied
    assert_in_delta p0, expected, 0.0001
    assert_in_delta p1, expected, 0.0001
  end

  @tag :smoke
  test "Declaration.Pitch resolve: mismatch → conflict" do
    snap = [[0, 440.0, 1], [1, 440.0, 1]]
    int = pitch_int(snap)

    # frame 1 投影变了
    projection = [[0, 440.0, 1], [1, 445.0, 1], [2, 220.0, 1]]

    assert {:conflict, :snapshot_stale} = Pitch.resolve(int, projection)
  end

  @tag :smoke
  test "Declaration.Pitch snapshot: 归一化为 4 位小数有序列表" do
    projection = [
      [0, 440.000001, 1],
      [1, 442.123456789, 1],
      [2, 220.0, 0]
    ]

    int = pitch_int([])

    assert Pitch.snapshot(projection, int) == [
             [0, 440.0, 1],
             [1, 442.1235, 1]
           ]
  end

  @tag :smoke
  test "Declaration.Pitch scope: boundary ± max_preutterance，静态可算" do
    int = pitch_int([])
    assert Pitch.scope(int, :no_timeline_needed) == {0 - 0, 480 + 240}

    int2 = put_in(int.payload.boundary, {960, 1440})
    assert Pitch.scope(int2, nil) == {960 - 240, 1440 + 240}
  end
end
