"""
CLI bridge: reads a JSON request, writes JSON response to stdout.
Replaces the FastAPI server for local smoke testing.

Usage:
    python engine_cli.py [request.json]   # argv[1] = request file; no arg → stdin
    python engine_cli.py < request.json > response.json

Request format:
    {"action": "project",
     "notes": [...], "tempo_segments": [...], "sample_rate": 86.13,
     "preutterance_frames": 0, "window": [start_tick, end_tick]  # optional
    }
    -> {"projection": [[frame, pitch, vuv], ...], "spills": [[f0, f1], ...]}

    {"action": "visualize",
     "baseline": [[f, p, v], ...], "applied": [[f, p, v], ...],
     "spills": [[f0, f1], ...], "notes": [...],
     "tempo_segments": [...], "sample_rate": 86.13,
     "interventions": [{"id", "boundary": [f0, f1], "status"}],
     "output_dir": "...",  # optional, defaults to priv/output
     "tag": "round_001"}
    -> {"path": "<absolute path to PNG>"}

    {"action": "utau_check",
     "notes": [...], "tempo_segments": [...], "sample_rate": 86.13,
     "preutterance_frames": 0, "window": [start_tick, end_tick],
     "utau_config": {"voicebank_root": "...", "resampler": "...", "wavtool": "..."}}
    -> {"projection": [[frame, pitch, vuv], ...], "spills": [[f0, f1], ...]}

    {"action": "utau_render",
     "notes": [...], "tempo_segments": [...],
     "utau_config": {"voicebank_root": "...", "resampler": "...", "wavtool": "..."},
     "out_path": "...",  # optional, defaults to priv/output/<tag>.wav
     "tag": "utau"}
    -> {"path": "<absolute path to WAV>", "duration": ..., "sample_rate": ...}

Errors: {"error": "..."} on stdout, exit code 1.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from engine import Engine
from visualize import plot_comparison
from utau_engine import handle_utau_check, handle_utau_render

# priv/scripts/engine_cli.py -> priv/output
DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parent.parent / "output"

engine = Engine()


def handle_project(req: dict) -> dict:
    return engine.project(
        notes=req["notes"],
        tempo_segments=req["tempo_segments"],
        sample_rate=req["sample_rate"],
        preutterance_frames=req.get("preutterance_frames", 0),
        window=req.get("window"),
    )


def handle_visualize(req: dict) -> dict:
    output_dir = Path(req.get("output_dir") or DEFAULT_OUTPUT_DIR).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    path = plot_comparison(
        baseline=req["baseline"],
        applied=req["applied"],
        notes=req["notes"],
        tempo_segments=req["tempo_segments"],
        sample_rate=req["sample_rate"],
        output_dir=output_dir,
        tag=req.get("tag", "comparison"),
        spills=req.get("spills"),
        interventions=req.get("interventions"),
    )
    return {"path": str(path)}


DISPATCH = {
    "project": handle_project,
    "visualize": handle_visualize,
    "utau_check": handle_utau_check,
    "utau_render": handle_utau_render,
}


def main():
    raw = Path(sys.argv[1]).read_text(encoding="utf-8") if len(sys.argv) > 1 else sys.stdin.read()
    try:
        req = json.loads(raw)
    except json.JSONDecodeError as e:
        json.dump({"error": f"Invalid JSON: {e}"}, sys.stdout)
        sys.exit(1)

    action = req.get("action", "project")
    handler = DISPATCH.get(action)
    if handler is None:
        json.dump({"error": f"Unknown action: {action}"}, sys.stdout)
        sys.exit(1)

    try:
        result = handler(req)
        json.dump(result, sys.stdout)
    except Exception as e:
        json.dump({"error": str(e)}, sys.stdout)
        sys.exit(1)


if __name__ == "__main__":
    main()
