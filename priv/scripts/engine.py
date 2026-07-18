"""
Tick to time to frame pipeline. CPU-only.
Synthesizes pitch contour from MIDI notes.
"""
from __future__ import annotations

import numpy as np


# ---- Tick / Time / Frame conversion ----

def ticks_to_seconds(ticks, tempo_segments, ticks_per_beat=480):
    """Convert tick positions to absolute time in seconds."""
    if not tempo_segments:
        return [t / ticks_per_beat * 60 / 120.0 for t in ticks]

    result = []
    seg_idx = 0
    current_time = 0.0
    current_tick = 0

    for tick in sorted(ticks):
        while (seg_idx + 1 < len(tempo_segments) and
               tick >= tempo_segments[seg_idx + 1][0]):
            seg_tick, seg_bpm = tempo_segments[seg_idx]
            next_tick = tempo_segments[seg_idx + 1][0]
            beat_dur = (next_tick - seg_tick) / ticks_per_beat
            current_time += beat_dur * 60.0 / seg_bpm
            current_tick = next_tick
            seg_idx += 1

        seg_tick, seg_bpm = tempo_segments[seg_idx]
        beat_dur = (tick - current_tick) / ticks_per_beat
        t = current_time + beat_dur * 60.0 / seg_bpm
        result.append(t)

    return result


def time_to_frame(t, sample_rate):
    return int(round(t * sample_rate))


def midi_to_hz(midi):
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


# ---- Engine ----

class Engine:
    """Frame-level projection engine."""

    def project(self, notes, tempo_segments, sample_rate):
        """Generate baseline projection: {frame: {pitch, vuv}}."""
        n_frames = self._max_frame(notes, tempo_segments, sample_rate)
        projection = {f: {"pitch": 0.0, "vuv": 0} for f in range(n_frames)}

        for note in notes:
            t0 = ticks_to_seconds([note["start_tick"]], tempo_segments)[0]
            t1 = ticks_to_seconds(
                [note["start_tick"] + note["duration_tick"]], tempo_segments
            )[0]
            f0 = time_to_frame(t0, sample_rate)
            f1 = time_to_frame(t1, sample_rate)
            hz = midi_to_hz(note["midi"])

            for f in range(f0, min(f1, n_frames)):
                projection[f] = {"pitch": hz, "vuv": 1}

        return projection

    def apply(self, projection, interventions):
        """Apply intervention deltas. Returns NEW dict."""
        result = {f: dict(d) for f, d in projection.items()}

        for intv in interventions:
            delta = intv.get("payload", {}).get("delta", {})
            for f_str, shift in delta.items():
                f = int(f_str)
                if f in result:
                    result[f]["pitch"] = max(
                        0.0, result[f]["pitch"] + shift.get("pitch", 0.0)
                    )

        return result

    def _max_frame(self, notes, tempo_segments, sample_rate):
        if not notes:
            return 0
        max_end = max(n["start_tick"] + n["duration_tick"] for n in notes)
        end_t = ticks_to_seconds([max_end], tempo_segments)[0]
        return time_to_frame(end_t, sample_rate) + 10
