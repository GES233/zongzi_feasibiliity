import Config

# toy Python 引擎桥（System.cmd）使用的解释器路径
config :zongzi_feasibility,
  python: "D:/Conda/python.exe",
  engine_cli: "priv/scripts/engine_cli.py"

config :pythonx, :uv_omot,
  pyproject: """
  [project]
  name = "zongzi-svs"
  version = "0.1.0"
  description = "UTAU classic + DiffSinger engine adapters for Zongzi contract validation"
  requires-python = ">=3.11"
  dependencies = [
      "onnxruntime",
      "soundfile",
      "pyyaml",
      "numpy",
  ]
  """
