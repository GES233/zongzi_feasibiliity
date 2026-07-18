"""
CLI bridge: reads JSON request from stdin, writes JSON response to stdout.
Replaces the FastAPI server for local smoke testing.

Usage:
    python engine_cli.py < request.json > response.json

Request format (stdin):
    {
        "action": "project" | "apply" | "visualize",
        "notes": [...],
        "tempo_segments": [...],
        "sample_rate": 86.13,
        "interventions": [...]   # for "apply" and "visualize"
    }

Response format (stdout):
    {"baseline": {...}, "applied": {...}, "n_frames": N}
    or {"path": "output/..."} for visualize action
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from engine import Engine
from visualize import plot_comparison

OUTPUT_DIR = Path(__file__).parent.parent / "output"
OUTPUT_DIR.mkdir(exist_ok=True)

engine = Engine()


def handle_project(req: dict) -> dict:
    baseline = engine.project(
        notes=req["notes"],
        tempo_segments=req["tempo_segments"],
        sample_rate=req["sample_rate"],
    )
    return {"baseline": baseline, "n_frames": len(baseline)}


def handle_apply(req: dict) -> dict:
    baseline = engine.project(
        notes=req["notes"],
        tempo_segments=req["tempo_segments"],
        sample_rate=req["sample_rate"],
    )
    applied = engine.apply(baseline, req.get("interventions", []))
    return {"baseline": baseline, "applied": applied, "n_frames": len(baseline)}


def handle_visualize(req: dict) -> dict:
    baseline = engine.project(
        notes=req["notes"],
        tempo_segments=req["tempo_segments"],
        sample_rate=req["sample_rate"],
    )
    applied = engine.apply(baseline, req.get("interventions", []))
    tag = req.get("tag", "comparison")
    path = plot_comparison(
        baseline, applied,
        notes=req["notes"],
        tempo_segments=req["tempo_segments"],
        sample_rate=req["sample_rate"],
        output_dir=OUTPUT_DIR,
        tag=tag,
    )
    return {"path": str(path)}


DISPATCH = {
    "project": handle_project,
    "apply": handle_apply,
    "visualize": handle_visualize,
}


def main():
    raw = sys.stdin.read()
    try:
        req = json.loads(raw)
    except json.JSONDecodeError as e:
        json.dump({"error": f"Invalid JSON: {e}"}, sys.stdout)
        sys.exit(1)

    action = req.get("action", "apply")
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
