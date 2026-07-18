defmodule ZongziFeasibility.Engine.Python do
  @moduledoc """
  Pythonx → engine.py 直调桥（替代 System.cmd）。

  通过 Pythonx.eval/2 直接调用 Python 引擎，避免 subprocess + 临时文件开销。
  request body 以 JSON 字符串传入 Python 侧，json.loads 解析后分发给 engine_cli 的 DISPATCH。
  """

  @spec run(map()) :: {:ok, map()} | {:error, String.t()}
  def run(body) when is_map(body) do
    json_str = Jason.encode!(body)
    scripts = Path.join(File.cwd!(), "priv/scripts")

    {result, _globals} =
      Pythonx.eval(
        """
        import json, sys

        sys.path.insert(0, r\"#{scripts}\")
        from engine import Engine
        from engine_cli import DISPATCH

        engine = Engine()
        req = json.loads(json_str)
        action = req.get('action', 'project')
        handler = DISPATCH[action]
        result = handler(req)
        json.dumps(result)
        """,
        %{"json_str" => json_str}
      )

    case Jason.decode(Pythonx.decode(result)) do
      {:ok, %{"error" => err}} -> {:error, err}
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, "JSON decode failed: #{String.slice(inspect(result), 0, 200)}"}
    end
  rescue
    e in RuntimeError ->
      {:error, "pythonx eval failed: #{Exception.message(e)}"}

    e in Pythonx.Error ->
      {:error, "python exception: #{Exception.message(e)}"}
  end
end
