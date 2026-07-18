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
  ]
  """
