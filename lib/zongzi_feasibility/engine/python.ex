defmodule ZongziFeasibility.Engine.Python do
  @moduledoc """
  `System.cmd` → `engine_cli.py` 的 JSON 桥。

  只暴露 `run/1`：request map 写临时 JSON 文件，路径作 argv[1] 传给 CLI
  （`System.cmd` 没有 `:input` 选项，stdin 管道不可行），stdout 收 response。

  Python 解释器与脚本路径走 config：

      config :zongzi_feasibility,
        python: "D:/Conda/python.exe",
        engine_cli: "priv/scripts/engine_cli.py"
  """

  @spec run(map()) :: {:ok, map()} | {:error, String.t()}
  def run(body) when is_map(body) do
    # System.cmd 没有 :input 选项；request 写临时文件，路径作 argv[1] 传给 CLI。
    path =
      Path.join(
        System.tmp_dir!(),
        "zongzi_feasibility_req_#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(body))

    try do
      case System.cmd(python(), [cli(), path], stderr_to_stdout: true) do
        {output, 0} -> decode(output)
        {output, n} -> {:error, "engine_cli exit #{n}: #{String.slice(output, 0, 300)}"}
      end
    after
      File.rm(path)
    end
  rescue
    e in ErlangError -> {:error, "python spawn failed: #{Exception.message(e)}"}
  end

  defp decode(output) do
    case Jason.decode(output) do
      {:ok, %{"error" => err}} -> {:error, err}
      {:ok, result} -> {:ok, result}
      {:error, _} -> {:error, "JSON decode failed: #{String.slice(output, 0, 300)}"}
    end
  end

  defp python, do: Application.get_env(:zongzi_feasibility, :python, "python")
  defp cli, do: Application.get_env(:zongzi_feasibility, :engine_cli, "priv/scripts/engine_cli.py")
end
