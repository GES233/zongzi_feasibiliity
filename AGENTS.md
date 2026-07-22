# AGENTS.md

## Project Overview

Elixir + Python hybrid: a reference implementation and verification bench for the **zongzi** singing synthesis framework. Implements three contract roles (Caller, Engine, Declaration) and runs 10 golden scenarios against a toy Python engine to validate the zongzi core contracts.

**Status**: Track A (toy engine + visualization) is complete (10/10 scenarios passing). Track B (NPSS) is shelved. UTAU/DiffSinger real engine adapter is in progress.

## Essential Commands

```bash
mix test                          # Unit tests (~22, no Python dependency, integration excluded)
mix test --only integration       # Integration tests (~14, real Pythonx bridge + all scenarios)
mix compile --warnings-as-errors  # Strict compilation — must pass
mix run -e "ZongziFeasibility.Measurer.run()"  # Run all golden scenarios, generate reports
mix format                        # Elixir formatter
```

Reports land in `priv/output/report.html` (embedded base64 PNGs) and `priv/output/report.json`.

## Architecture & Control Flow

```
Caller.new → mount_intervention → edit → [rebase → window → check/render] loop
```

**Core loop** (`caller.ex:146-173`):
1. `apply_op` — mutate timeline + notes_by_seq + intervention coordinates
2. `Anchor.rebase_all` — structural survival: preserve/rebase/relocate/split/conflict
3. `refresh_scope` — recompute scope after rebase
4. `Windowing.run_stages` — split into segments (≥3-beat gap = new segment)
5. `Engine.check/render` — per-segment Python projection → Declaration.resolve → merge

**Module map**:

| Module | Role |
|--------|------|
| `Caller` | Orchestrator. Holds Timeline, notes_by_seq, interventions, tempo. Owns tick↔frame conversion. |
| `Engine` | `Zongzi.Engine` behaviour — toy impl. `check/1` → project segments → resolve interventions. `render/1` → check + visualize. |
| `Engine.UTAU` | Real UTAU engine adapter. Same behaviour, delegates frame projection to toy engine, renders via external resampler+wavtool. |
| `Engine.Python` | Pythonx bridge — calls `priv/scripts/` Python code directly in-process. |
| `Declaration.Pitch` | `:pitch` channel. scope/snapshot/resolve/on_rebase. Snapshot normalization at 4dp. |
| `Scenario` | Behaviour + helpers (`base_caller`, `mount`). Each scenario: setup → edits → expect. |
| `Measurer` | Batch runner. Drives scenarios, collects metrics, writes console/JSON/HTML reports. |

**Python side** (`priv/scripts/`):
- `engine.py` — `Engine.project()`: tick→time→frame pipeline, pitch contour synthesis, preutterance spill
- `engine_cli.py` — CLI bridge with DISPATCH dict: `project`, `visualize`, `utau_check`, `utau_render`
- `visualize.py` — matplotlib baseline vs applied plot with notes/spills/intervention overlays
- `utau_engine.py` — UTAU classic: oto.ini parsing, resampler+wavtool shell-out

## Critical Invariants

**Tick↔frame synchronization**: `Caller.tick_to_frame/2` and `engine.py`'s `ticks_to_seconds` must stay algorithmically identical. Elixir uses `round/1` (half-up); Python uses `round()` (half-even). At 86.13 Hz sample rate this difference doesn't manifest, but be aware if sample rate changes.

**Coordinate division**: Tick space is authoritative (control_points, boundary in payload). Frame space is a derived cache maintained by Caller in `payload.frames`. Declaration never does tick↔frame conversion.

**Snapshot normalization**: Snapshots are `[[frame, pitch_rounded_4dp, vuv], ...]` ordered lists. This guards against JSON integer→string key drift and float precision drift during round-trip. No tolerance in comparison — normalization happens at serialization boundary.

**Preutterance spill**: `N(note) = preutterance_frames + len(lyric)`. Changing a lyric changes the spill frontier, which is the mechanism behind G-PRE scenarios.

**`on_rebase` split mechanism**: Timeline doesn't carry note tick info, so `Anchor.rebase_all` meta has no tick. Caller injects `:split_hint` into intervention payload for focus splits; `Declaration.Pitch.on_rebase/4` consumes it and returns `{:split, [child_a, child_b]}`. Caller strips the hint afterward.

**Engine request contract**: Always a plain map (never struct). `segments` is required. Common keys: `notes_by_seq`, `interventions`, `tempo_segments`, `params`, `opts`. Engine rejects requests without `segments` with `{:error, :missing_segments}`.

## Gotchas

- **`zongzi` is a local path dependency** (`../zongzi`). The sibling repo must exist and compile.
- **Integration tests excluded by default** — `test_helper.exs` does `ExUnit.start(exclude: [:integration])`. Use `mix test --only integration` explicitly.
- **Pythonx manages its own Python** via uv — `config/config.exs` has `config :pythonx, :uv_init` with inline pyproject.toml. No system Python needed. `priv/scripts/requirements.txt` is only for standalone `engine_cli.py` usage.
- **`on_rebase/4` not `/3`**: Declaration.Pitch implements 4-arity `on_rebase(int, meta, tl, ctx)` — the 4th arg is `Anchor.Context` injected by Caller. The `@impl true` callback signature matters.
- **`edit_key` was unplanned** (added for G-INT-02) — it changes projection within boundary, directly triggering snapshot_stale conflict.
- **`move` is tick-axis drag**, not chain reordering. Caller shifts all payload/snapshot coordinates. Chain reorder not implemented.
- **Output files are gitignored** (`*.png`, `*.json`, `*.html`, `*.wav` in `.gitignore`).
- **G-INT-01 uses `preutterance_frames: 0` + nil lyric** to isolate happy-path split behavior from preutterance-induced conflicts.
- **Frame merge in Engine**: Adjacent segments may produce overlapping frames at boundaries due to rounding. `merge_frames/1` sorts and deduplicates by frame number.

## Code Style

- Chinese comments throughout (moduledocs, inline)
- Standard Elixir formatter (`.formatter.exs` covers `{config,lib,test}/**/*.{ex,exs}`)
- Module attributes for constants (`@tpqn 480`, `@default_sample_rate 86.13`, `@max_preutterance_ticks 240`)
- Telemetry events: `[:zongzi_feasibility, :declaration, :stale]` and `[:zongzi_feasibility, :scenario, :round]`
- Tests use `ExUnit.Case, async: true` for unit, `async: false` for integration

## UTAU Adapter (In Progress)

Config in `config/config.exs` under `:zongzi_feasibility, :utau` — requires `voicebank_root`, `resampler`, `wavtool` paths. The UTAU engine delegates frame projection to the toy `Engine.project()` and adds oto.ini lyric lookup + external tool rendering. Integration tests tagged `@moduletag :integration` in `engine_utau_integration_test.exs`.

## Sibling Projects

| Project | Path |
|---------|------|
| zongzi (core) | `D:/CodeRepo/Qy/zongzi` |
| zongzi-svs (UTAU/DiffSinger PoC) | `D:/CodeRepo/SingingSynthesis/zongzi-svs` |
