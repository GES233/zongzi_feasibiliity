defmodule ZongziFeasibility.EngineIntegrationTest do
  use ExUnit.Case, async: false

  alias ZongziFeasibility.Caller

  @moduletag :integration

  # 真实 Python 桥（D:/Conda/python.exe + priv/scripts/engine_cli.py）。
  # 默认排除；手动：mix test --only integration

  defp two_note_caller(opts) do
    Caller.new(%{
      notes: [
        %{start_tick: 0, duration_tick: 480, midi: 60, lyric: "a"},
        %{start_tick: 480, duration_tick: 480, midi: 62, lyric: "ka"}
      ],
      opts: opts
    })
  end

  test "check: 投影为升序帧列表，preutterance 溢出覆盖前 note 尾部" do
    caller = two_note_caller(%{preutterance_frames: 5})
    {:ok, artifact} = Caller.check_round(caller)

    proj = artifact.projection
    assert [[f0, _, _] | _] = proj
    assert f0 == 0
    assert proj == Enum.sort_by(proj, fn [f, _, _] -> f end)

    # 120bpm @86.13Hz：B(ka) 起始帧 f(480)=43；N = 5 + len("ka") = 7 → spill [36, 43)
    assert [36, 43] in artifact.spills
    b_hz = 440.0 * :math.pow(2.0, (62 - 69) / 12)
    assert [42, p42, 0] = Enum.find(proj, fn [f, _, _] -> f == 42 end)
    assert_in_delta p42, b_hz, 0.001
    # frame 35 仍是 A 的 vuv=1
    assert [35, _, 1] = Enum.find(proj, fn [f, _, _] -> f == 35 end)
  end

  test "render: 返回 applied 投影与 PNG 路径" do
    caller = two_note_caller(%{preutterance_frames: 5})
    out = Path.join([File.cwd!(), "priv", "output", "integration"])

    {:ok, artifact} =
      Caller.render_round(caller, "render_smoke", %{opts: %{output_dir: out}})

    assert artifact.applied == artifact.projection
    assert File.exists?(artifact.path)
  end

  test "check → mount → 无变化再 check：resolve 成功" do
    caller = two_note_caller(%{preutterance_frames: 5})

    {caller, _int} =
      Caller.mount_intervention(caller, %{seq: 2, control_points: [{480, 100.0}], id: "iv_b"})

    {:ok, artifact} = Caller.check_round(caller)
    assert artifact.conflicts == []
    assert [{int, applied}] = artifact.resolved
    assert int.id == "iv_b"
    assert [[43, p, 1] | _] = applied
    # +100 cents：p = base * 2^(100/1200)
    base = 440.0 * :math.pow(2.0, (62 - 69) / 12)
    assert_in_delta p, base * :math.pow(2.0, 100.0 / 1200.0), 0.001
  end

  test "edit_key 改变 boundary 内投影 → snapshot_stale conflict" do
    caller = two_note_caller(%{preutterance_frames: 5})

    {caller, _int} =
      Caller.mount_intervention(caller, %{seq: 2, control_points: [{480, 100.0}], id: "iv_b"})

    {caller, _report} = Caller.edit(caller, {:edit_key, 2, 65})
    {:ok, artifact} = Caller.check_round(caller)

    assert artifact.resolved == []
    assert [{int, :snapshot_stale}] = artifact.conflicts
    assert int.id == "iv_b"
  end
end
