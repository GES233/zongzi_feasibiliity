defmodule ZongziFeasibility.ScenariosIntegrationTest do
  use ExUnit.Case, async: false

  alias ZongziFeasibility.Measurer

  @moduletag :integration

  # 每 G-* 场景一个 describe；真实 Python 桥，默认排除。
  # 手动：mix test --only integration

  @scenarios [
    ZongziFeasibility.Scenarios.GInt01,
    ZongziFeasibility.Scenarios.GInt02,
    ZongziFeasibility.Scenarios.GEng02,
    ZongziFeasibility.Scenarios.GPre01,
    ZongziFeasibility.Scenarios.GPre02,
    ZongziFeasibility.Scenarios.GPre03,
    ZongziFeasibility.Scenarios.GPre04,
    ZongziFeasibility.Scenarios.GPre05,
    ZongziFeasibility.Scenarios.GPre06,
    ZongziFeasibility.Scenarios.GPre07
  ]

  for mod <- @scenarios do
    describe "#{inspect(mod)}" do
      test "expect 命中" do
        assert :ok = Measurer.run_scenario(unquote(mod)).verdict
      end
    end
  end
end
