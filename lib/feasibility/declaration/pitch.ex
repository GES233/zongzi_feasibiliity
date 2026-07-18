defmodule ZongziFeasibility.Declaration.Pitch do
  @moduledoc """
  Frame-level pitch declaration. Minimal implementation for smoke test.
  """

  @behaviour Zongzi.Intervention.Declaration

  alias Zongzi.Intervention

  @impl true
  def scope(int, _tl), do: int.scope

  @impl true
  def snapshot(_projection, %Intervention{payload: p}) do
    Map.get(p, :original, %{})
  end

  @impl true
  def resolve(%Intervention{snapshot: snap, payload: p}, fresh_projection) do
    delta = Map.get(p, :delta, %{})

    if frames_match?(snap, fresh_projection, Map.keys(delta)) do
      {:ok, apply_delta(fresh_projection, delta)}
    else
      emit_stale(p)
      {:skip, :snapshot_stale}
    end
  end

  defp emit_stale(payload) do
    if Code.ensure_loaded?(:telemetry) do
      :telemetry.execute(
        [:zongzi, :intervention, :stale],
        %{intervention_id: Map.get(payload, :id)},
        %{}
      )
    end
  end

  defp frames_match?(snap, proj, frame_keys) do
    Enum.all?(frame_keys, fn f ->
      Map.get(snap, f) == Map.get(proj, f)
    end)
  end

  defp apply_delta(proj, delta) do
    Map.merge(proj, delta, fn _frame, base, shift ->
      Map.merge(base, shift, fn
        :pitch, b, s -> b + s
        _, _b, s -> s
      end)
    end)
  end
end
