"""
Matplotlib comparison: baseline vs applied pitch contours.
Saves to priv/output/ as PNG. Non-interactive (Agg backend).
"""
from __future__ import annotations

from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from engine import ticks_to_seconds, time_to_frame


def plot_comparison(
    baseline,
    applied,
    notes,
    tempo_segments,
    sample_rate,
    output_dir,
    tag="comparison",
):
    """Plot pitch contours with note boundaries."""
    frames = sorted(baseline.keys())
    base_pitch = [baseline[f]["pitch"] for f in frames]
    appl_pitch = [applied[f]["pitch"] for f in frames] if applied else None

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 8), sharex=True)

    # Pitch overlay
    ax1.plot(frames, base_pitch, "b-", lw=0.8, alpha=0.7, label="baseline")
    if appl_pitch:
        ax1.plot(frames, appl_pitch, "r-", lw=0.8, alpha=0.7, label="applied")
    ax1.set_ylabel("Pitch (Hz)")
    ax1.legend(fontsize=8)
    ax1.grid(True, alpha=0.3)

    # Note boundaries
    for note in notes:
        t0 = ticks_to_seconds([note["start_tick"]], tempo_segments)[0]
        t1 = ticks_to_seconds(
            [note["start_tick"] + note["duration_tick"]], tempo_segments
        )[0]
        f0 = time_to_frame(t0, sample_rate)
        f1 = time_to_frame(t1, sample_rate)
        mid = (f0 + f1) / 2
        ax1.axvspan(f0, f1, alpha=0.08, color="green")
        ymax = ax1.get_ylim()[1]
        ax1.text(mid, ymax * 0.95, note.get("lyric", ""),
                 ha="center", fontsize=7, color="green")

    # VUV
    base_vuv = [baseline[f]["vuv"] for f in frames]
    ax2.fill_between(frames, base_vuv, step="mid", alpha=0.5,
                     color="blue", label="vuv")
    ax2.set_ylabel("V/UV")
    ax2.set_xlabel("Frame")
    ax2.set_ylim(-0.1, 1.1)
    ax2.legend(fontsize=8)
    ax2.grid(True, alpha=0.3)

    fig.suptitle(f"Zongzi Feasibility - {tag}", fontsize=12)
    plt.tight_layout()

    out_path = output_dir / f"{tag}.png"
    fig.savefig(out_path, dpi=120)
    plt.close(fig)

    return out_path
