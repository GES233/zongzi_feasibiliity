defmodule ZongziFeasibility.EngineTest do
  use ExUnit.Case, async: true

  alias Zongzi.Windowing.Segment
  alias ZongziFeasibility.Engine

  # 本文件全是契约路径（segments 必填、params 校验），不触 Python 桥。

  test "实现 Zongzi.Engine behaviour（check 必选，render 可选）" do
    # function_exported?/3 对未加载模块返回 false；先确保加载，消除加载竞态。
    assert Code.ensure_loaded?(Engine)
    assert function_exported?(Engine, :check, 1)
    assert function_exported?(Engine, :render, 1)

    behaviours =
      for {k, v} <- Engine.module_info(:attributes), k == :behaviour, b <- v, do: b

    assert Zongzi.Engine in behaviours
  end

  describe "G-ENG-02: check/render 只吃 segments" do
    test "check 缺 segments → {:error, :missing_segments}" do
      assert {:error, :missing_segments} = Engine.check(%{})
      assert {:error, :missing_segments} = Engine.check(%{notes: []})
    end

    test "render 缺 segments → {:error, :missing_segments}" do
      assert {:error, :missing_segments} = Engine.render(%{})
    end

    test "check 空 segments → 空投影，不触引擎" do
      assert {:ok, artifact} = Engine.check(%{segments: []})
      assert artifact.projection == []
      assert artifact.resolved == []
      assert artifact.conflicts == []
    end
  end

  describe "params 校验（非 intervention 旋钮）" do
    setup do
      {:ok, seg} = Segment.new(0, 480, [])
      %{req: %{segments: [seg]}}
    end

    test "gender 超范围", %{req: req} do
      assert {:error, {:invalid_params, {:gender, :out_of_range, {-1.0, 1.0}}}} =
               Engine.check(Map.put(req, :params, %{gender: 5.0}))
    end

    test "energy 非数值", %{req: req} do
      assert {:error, {:invalid_params, {:energy, :not_a_number}}} =
               Engine.check(Map.put(req, :params, %{energy: "loud"}))
    end

    test "未知参数", %{req: req} do
      assert {:error, {:invalid_params, {:unknown_param, :vibrato}}} =
               Engine.check(Map.put(req, :params, %{vibrato: 1.0}))
    end

    test "params 非 map", %{req: req} do
      assert {:error, {:invalid_params, :not_a_map}} =
               Engine.check(Map.put(req, :params, gender: 0))
    end
  end
end
