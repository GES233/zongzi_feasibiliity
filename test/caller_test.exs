defmodule ZongziFeasibility.CallerTest do
  use ExUnit.Case, async: true

  alias ZongziFeasibility.Caller

  # 结构层测试不依赖 Python：mount 时注入空投影。
  defp abc_caller do
    Caller.new(%{
      notes: [
        %{start_tick: 0, duration_tick: 480, midi: 60, lyric: "a"},
        %{start_tick: 480, duration_tick: 480, midi: 62, lyric: "ka"},
        %{start_tick: 960, duration_tick: 480, midi: 64, lyric: "sa"}
      ]
    })
  end

  defp mount_on(caller, seq, cps \\ [{480, 100.0}, {960, 0.0}]) do
    Caller.mount_intervention(caller, %{seq: seq, control_points: cps, id: "iv_test"}, [])
  end

  test "new/1: 建轨、seq 顺序分配、notes_by_seq 快照" do
    caller = abc_caller()
    assert Zongzi.Timeline.to_list(caller.timeline) == [1, 2, 3]
    assert Map.keys(caller.notes_by_seq) |> Enum.sort() == [1, 2, 3]
    assert caller.interventions == []
  end

  test "mount_intervention: anchor 三元组、scope、frames 缓存" do
    caller = abc_caller()
    {_caller, int} = mount_on(caller, 2)

    assert int.anchor == {1, 2, 3}
    assert int.declaration == ZongziFeasibility.Declaration.Pitch
    # boundary 默认 focus note 区间；scope = boundary ± 240
    assert int.payload.boundary == {480, 960}
    assert int.scope == {240, 1200}
    # 120bpm @86.13Hz：480 tick = 0.5s ≈ 43 帧
    assert int.payload.frames.boundary == {43, 86}
    assert int.payload.frames.control_points == [{43, 100.0}, {86, 0.0}]
    assert int.snapshot == []
  end

  test "edit_lyric: 结构 preserve，anchor 不变" do
    caller = abc_caller()
    {caller, _int} = mount_on(caller, 2)
    {caller, report} = Caller.edit(caller, {:edit_lyric, 2, "ku"})

    assert report.conflicts == []
    assert [%{id: "iv_test", anchor: {1, 2, 3}}] = report.survived
    assert caller.notes_by_seq[2].lyric == "ku"
    assert [%{seq_ids: [1, 2, 3]}] = report.segments
  end

  test "split: on_rebase 消费 hint，产出两个子 intervention" do
    caller = abc_caller()
    {caller, _int} = mount_on(caller, 2)
    {caller, report} = Caller.edit(caller, {:split, 2, 720})

    assert report.conflicts == []
    assert [a, b] = report.survived

    assert a.id == "iv_test_a"
    assert a.anchor == {1, 2, 4}
    assert a.payload.boundary == {480, 720}
    assert a.payload.control_points == [{480, 100.0}]
    assert a.payload.frames.boundary == {43, 65}
    refute Map.has_key?(a.payload, :split_hint)

    assert b.id == "iv_test_b"
    assert b.anchor == {2, 4, 3}
    assert b.payload.boundary == {720, 960}
    assert b.payload.control_points == [{960, 0.0}]
    assert b.payload.frames.boundary == {65, 86}

    # split 后两个 note 都进了 notes_by_seq，窗随之更新
    assert Map.keys(caller.notes_by_seq) |> Enum.sort() == [1, 2, 3, 4]
    assert [%{seq_ids: [1, 2, 4, 3]}] = report.segments
  end

  test "delete: focus 删除 → relocate 到下一活跃邻居" do
    caller = abc_caller()
    {caller, _int} = mount_on(caller, 2)
    {_caller, report} = Caller.edit(caller, {:delete, 2})

    assert report.conflicts == []
    assert [%{id: "iv_test", anchor: {1, 3, nil}}] = report.survived
  end

  test "move: payload/snapshot 坐标随 focus 平移" do
    caller = abc_caller()
    {caller, _int} = mount_on(caller, 2)
    {_caller, report} = Caller.edit(caller, {:move, 2, 960})

    assert report.conflicts == []
    assert [int] = report.survived
    assert int.payload.boundary == {960, 1440}
    assert int.payload.control_points == [{960, 100.0}, {1440, 0.0}]
    # f(960) - f(480) = 86 - 43 = 43 帧
    assert int.payload.frames.boundary == {86, 129}
    assert int.payload.frames.control_points == [{86, 100.0}, {129, 0.0}]
    # scope 重算
    assert int.scope == {720, 1680}
  end

  test "merge: focus 被 merge → merged_away conflict" do
    caller =
      Caller.new(%{
        notes: [
          %{start_tick: 0, duration_tick: 480, midi: 60, lyric: "a"},
          %{start_tick: 480, duration_tick: 480, midi: 62, lyric: "ka"},
          %{start_tick: 960, duration_tick: 480, midi: 62, lyric: "sa"}
        ]
      })

    {caller, _int} = mount_on(caller, 3)
    {_caller, report} = Caller.edit(caller, {:merge, 2, 3})

    assert report.survived == []
    assert [{int, :merged_away}] = report.conflicts
    assert int.id == "iv_test"
  end

  test "insert: append 新 note，链尾 anchor 的 next 被 rebase 填充" do
    caller = abc_caller()
    {caller, _int} = mount_on(caller, 3)

    {caller, report} =
      Caller.edit(
        caller,
        {:insert, %{start_tick: 1440, duration_tick: 480, midi: 65, lyric: "ta"}}
      )

    assert report.conflicts == []
    # 原 anchor {2, 3, nil} → 新 note seq 4 补位
    assert [%{id: "iv_test", anchor: {2, 3, 4}}] = report.survived
    assert Map.has_key?(caller.notes_by_seq, 4)
  end

  test "window: ≥3 拍空档切开成两个 segment" do
    caller =
      Caller.new(%{
        notes: [
          %{start_tick: 0, duration_tick: 480, midi: 60, lyric: "a"},
          %{start_tick: 1920, duration_tick: 480, midi: 62, lyric: "ka"}
        ]
      })

    {:ok, segments} = Caller.window(caller)
    assert [%{seq_ids: [1]}, %{seq_ids: [2]}] = segments
  end
end
