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
    """Frame-level projection engine (baseline + preutterance spill)."""

    def project(self, notes, tempo_segments, sample_rate,
                preutterance_frames=0, window=None):
        """Project notes onto a frame grid.

        Args:
            notes: [{"id", "seq_id", "start_tick", "duration_tick",
                     "midi", "lyric"}]
            tempo_segments: [[tick, bpm], ...]
            sample_rate: frames per second.
            preutterance_frames: base spill length in frames; each note
                head spills `preutterance_frames + len(lyric)` frames
                backward over the preceding frames (lyric-dependent, so a
                lyric edit moves the spill frontier — G-PRE semantics).
            window: optional [start_tick, end_tick) in ticks; defaults to
                [0, last note end frame + 10 frames).

        Returns:
            {"projection": [[frame, pitch_hz, vuv], ...] ascending by frame,
             "spills": [[f0, f1], ...] actual spill frame intervals, ascending}
        """
        if window is None:
            if not notes:
                return {"projection": [], "spills": []}
            max_end_tick = max(
                n["start_tick"] + n["duration_tick"] for n in notes
            )
            end_t = ticks_to_seconds([max_end_tick], tempo_segments)[0]
            f_start, f_end = 0, time_to_frame(end_t, sample_rate) + 10
        else:
            t0, t1 = ticks_to_seconds([window[0], window[1]], tempo_segments)
            f_start = time_to_frame(t0, sample_rate)
            f_end = time_to_frame(t1, sample_rate)

        n_frames = max(0, f_end - f_start)
        pitch = np.zeros(n_frames, dtype=float)
        vuv = np.zeros(n_frames, dtype=int)

        def note_frames(note):
            t0 = ticks_to_seconds([note["start_tick"]], tempo_segments)[0]
            t1 = ticks_to_seconds(
                [note["start_tick"] + note["duration_tick"]], tempo_segments
            )[0]
            return (time_to_frame(t0, sample_rate),
                    time_to_frame(t1, sample_rate))

        # Baseline: note body -> pitch = note hz, vuv = 1 (clipped to window).
        for note in notes:
            f0, f1 = note_frames(note)
            lo, hi = max(f0, f_start), min(f1, f_end)
            if lo < hi:
                pitch[lo - f_start:hi - f_start] = midi_to_hz(note["midi"])
                vuv[lo - f_start:hi - f_start] = 1

        # Preutterance spill: [note_f0 - N, note_f0) is overwritten with the
        # note's pitch and vuv = 0 (consonant onset has no fundamental).
        # Later notes may overwrite earlier notes' tails.
        # Toy semantics: N depends on the lyric — different phonemes have
        # different preutterance, so a lyric edit moves the spill frontier.
        # N(note) = preutterance_frames + len(lyric).
        spills = []
        for note in notes:
            n = preutterance_frames + len(note.get("lyric") or "")
            if n <= 0:
                continue
            f0, _ = note_frames(note)
            lo = max(f0 - n, f_start)
            hi = min(f0, f_end)
            if lo < hi:
                pitch[lo - f_start:hi - f_start] = midi_to_hz(note["midi"])
                vuv[lo - f_start:hi - f_start] = 0
                spills.append([lo, hi])
        spills.sort()

        projection = [
            [f_start + i, float(pitch[i]), int(vuv[i])]
            for i in range(n_frames)
        ]
        return {"projection": projection, "spills": spills}
