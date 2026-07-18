"""
Matplotlib comparison: baseline vs applied pitch contours.
Saves PNG under priv/output/. Non-interactive (Agg backend).
"""
from __future__ import annotations

from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from engine import ticks_to_seconds, time_to_frame


def plot_comparison(baseline, applied, notes, tempo_segments, sample_rate,
                    output_dir, tag, spills=None, interventions=None):
    """Plot pitch contours + vuv with note boundaries and scope highlights.

    baseline / applied: [[frame, pitch_hz, vuv], ...] (applied may be
        identical to baseline when no intervention was applied)
    spills: [[f0, f1], ...] preutterance spill frame intervals
    interventions: [{"id", "boundary": [f0, f1],
                     "status": "resolved" | "conflict"}]

    Saves output_dir / f"{tag}.png" and returns its Path.
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    frames = [r[0] for r in baseline]
    base_pitch = [r[1] for r in baseline]
    base_vuv = [r[2] for r in baseline]

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 8), sharex=True)

    # Top: pitch overlay
    ax1.plot(frames, base_pitch, "b-", lw=1.0, label="baseline")
    if applied:
        ax1.plot([r[0] for r in applied], [r[1] for r in applied],
                 "r-", lw=0.8, alpha=0.7, label="applied")
    ax1.set_ylabel("Pitch (Hz)")
    ax1.grid(True, alpha=0.3)

    # Bottom: baseline vuv band
    ax2.fill_between(frames, base_vuv, step="mid", alpha=0.5,
                     color="blue", label="baseline vuv")
    ax2.set_ylabel("V/UV")
    ax2.set_xlabel("Frame")
    ax2.set_ylim(-0.1, 1.1)
    ax2.grid(True, alpha=0.3)

    # Note boundaries + lyric labels
    for note in notes:
        t0 = ticks_to_seconds([note["start_tick"]], tempo_segments)[0]
        t1 = ticks_to_seconds(
            [note["start_tick"] + note["duration_tick"]], tempo_segments
        )[0]
        f0 = time_to_frame(t0, sample_rate)
        f1 = time_to_frame(t1, sample_rate)
        for ax in (ax1, ax2):
            ax.axvline(f0, color="green", ls="--", lw=0.8, alpha=0.6)
            ax.axvline(f1, color="green", ls="--", lw=0.8, alpha=0.6)
        ax1.text((f0 + f1) / 2, 0.98, note.get("lyric", ""),
                 transform=ax1.get_xaxis_transform(),
                 ha="center", va="top", fontsize=7, color="green")

    # Intervention scopes
    for intv in interventions or []:
        f0, f1 = intv["boundary"]
        if intv.get("status") == "resolved":
            style = {"facecolor": "green", "alpha": 0.15}
        elif intv.get("status") == "conflict":
            style = {"facecolor": "red", "alpha": 0.25,
                     "hatch": "//", "edgecolor": "darkred", "lw": 0.0}
        else:
            continue
        ax1.axvspan(f0, f1, label=intv.get("id"), **style)
        ax2.axvspan(f0, f1, **style)

    # Preutterance spills
    for i, (f0, f1) in enumerate(spills or []):
        label = "preutterance" if i == 0 else None
        ax1.axvspan(f0, f1, color="orange", alpha=0.2, label=label)
        ax2.axvspan(f0, f1, color="orange", alpha=0.2)

    ax1.legend(fontsize=8)
    ax2.legend(fontsize=8)

    fig.suptitle(f"Zongzi Feasibility - {tag}", fontsize=12)
    plt.tight_layout()

    out_path = output_dir / f"{tag}.png"
    fig.savefig(out_path, dpi=120)
    plt.close(fig)

    return out_path
