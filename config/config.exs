import Config

config :pythonx, :uv_init,
  pyproject_toml: """
  [project]
  name = "zongzi-svs"
  version = "0.1.0"
  requires-python = ">=3.11"
  dependencies = [
      "numpy",
      "matplotlib",
      "soundfile",
      "pyyaml",
  ]
  """

config :zongzi_feasibility, :utau,
  voicebank_root: "D:/CodeRepo/SingingSynthesis/UTAU/重音テト音声ライブラリー",
  resampler: "D:/CodeRepo/SingingSynthesis/UTAU/doppeltler64.exe",
  wavtool: "D:/CodeRepo/SingingSynthesis/UTAU/wavtool64.exe"
