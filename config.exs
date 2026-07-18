import Config


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
