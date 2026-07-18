defmodule ZongziFeasibility.Engine.Request do
  @moduledoc """
  Rendered request sent to the Python FastAPI engine server.
  """

  alias Zongzi.Score.Note

  @enforce_keys [:notes, :tempo_segments, :sample_rate, :engine]
  defstruct [
    :notes,
    :tempo_segments,
    :sample_rate,
    :engine,
    interventions: []
  ]

  @type t :: %__MODULE__{
          notes: [Note.t()],
          tempo_segments: [{non_neg_integer(), float()}],
          sample_rate: float(),
          engine: atom(),
          interventions: [term()]
        }

  def new(attrs), do: struct(__MODULE__, attrs)
end
