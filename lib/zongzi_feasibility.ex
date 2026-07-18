defmodule ZongziFeasibility do
  @moduledoc """
  zongzi 核三个库外角色的可执行参考实现 + 验证台。

  入口：

  - `ZongziFeasibility.Caller` — 编排：编辑 → rebase → window → check/render。
  - `ZongziFeasibility.Measurer` — golden scenario 跑批与报告：
    `mix run -e "ZongziFeasibility.Measurer.run()"`。
  """
end
