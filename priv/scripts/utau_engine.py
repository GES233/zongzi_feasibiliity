"""UTAU classic engine adapter for the Zongzi contract.

Parses oto.ini and shells out to the external UTAU resampler and wavtool.
The frame-level projection is delegated to the existing toy frame engine.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import wave
from pathlib import Path
from typing import Any

DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parent.parent / "output"

# ---------------------------------------------------------------------------
# oto.ini / voicebank helpers
# ---------------------------------------------------------------------------

def parse_oto(path: str) -> dict[str, dict[str, Any]]:
    """Parse an oto.ini file (Shift_JIS) into {alias: params}."""
    entries: dict[str, dict[str, Any]] = {}
    with open(path, "r", encoding="shift_jis", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or "=" not in line:
                continue
            wav_name, rest = line.split("=", 1)
            parts = rest.split(",")
            if len(parts) < 6:
                continue
            alias = parts[0].strip()
            offset, consonant, cutoff, preutterance, overlap = map(float, parts[1:6])
            entries[alias] = {
                "wav": os.path.join(os.path.dirname(path), wav_name),
                "offset": offset,
                "consonant": consonant,
                "cutoff": cutoff,
                "preutterance": preutterance,
                "overlap": overlap,
            }
    return entries


def find_voicebank(root: str) -> str:
    """Find the first oto.ini under a voicebank root, preferring CV folders."""
    candidates: list[str] = []
    for dirpath, _, files in os.walk(root):
        if "oto.ini" in files:
            path = os.path.join(dirpath, "oto.ini")
            # Prefer CV (単独音) folders over extras.
            if "単独音" in dirpath or "ÆPô╞ë╣" in dirpath:
                candidates.insert(0, path)
            else:
                candidates.append(path)
    if not candidates:
        raise FileNotFoundError(f"oto.ini not found under {root}")
    return candidates[0]


# ---------------------------------------------------------------------------
# Pitch / timing helpers
# ---------------------------------------------------------------------------

def midi_to_utau_pitch(midi: float | int) -> str:
    """Convert MIDI note number to UTAU pitch name (C4 = 60)."""
    midi = int(midi)
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    octave = midi // 12 - 1
    return f"{names[midi % 12]}{octave}"


def ticks_to_seconds(ticks: list[int], tempo_segments: list[list[float]], ticks_per_beat: int = 480) -> list[float]:
    """Convert tick positions to absolute time in seconds."""
    if not tempo_segments:
        return [t / ticks_per_beat * 60 / 120.0 for t in ticks]

    result = []
    seg_idx = 0
    current_time = 0.0
    current_tick = 0

    for tick in sorted(ticks):
        while seg_idx + 1 < len(tempo_segments) and tick >= tempo_segments[seg_idx + 1][0]:
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


def tempo_at_tick(tick: int, tempo_segments: list[list[float]]) -> float:
    """Return the BPM active at the given tick."""
    current = tempo_segments[0][1] if tempo_segments else 120.0
    for seg_tick, bpm in tempo_segments:
        if tick >= seg_tick:
            current = bpm
        else:
            break
    return current


def note_duration_seconds(note: dict, tempo_segments: list[list[float]]) -> float:
    """Return the duration of a note in seconds."""
    start = ticks_to_seconds([note["start_tick"]], tempo_segments)[0]
    end = ticks_to_seconds([note["start_tick"] + note["duration_tick"]], tempo_segments)[0]
    return end - start


# ---------------------------------------------------------------------------
# Engine
# ---------------------------------------------------------------------------

class UTAUEngine:
    """UTAU classic engine wrapper: oto.ini + resampler + wavtool."""

    def __init__(self, voicebank_root: str, resampler: str, wavtool: str) -> None:
        self.vb_root = voicebank_root
        self.resampler = resampler
        self.wavtool = wavtool
        oto_path = find_voicebank(voicebank_root)
        self.oto = parse_oto(oto_path)
        self.oto_dir = os.path.dirname(oto_path)

    # -- check -------------------------------------------------------------

    def check(
        self,
        notes: list[dict],
        tempo_segments: list[list[float]],
        sample_rate: float,
        preutterance_frames: int = 0,
        window: list[int] | None = None,
    ) -> dict[str, Any]:
        """Check lyric coverage and return a frame projection/spills.

        The frame projection is produced by the toy frame engine so that the
        upstream Zongzi contract (check artifact must contain projection and
        spills) can be satisfied without reimplementing frame math here.
        """
        missing = sorted({n["lyric"] for n in notes if n["lyric"] not in self.oto})
        if missing:
            return {"ok": False, "missing": missing, "oto_size": len(self.oto)}

        from engine import Engine as FrameEngine

        frame_engine = FrameEngine()
        projection = frame_engine.project(
            notes=notes,
            tempo_segments=tempo_segments,
            sample_rate=sample_rate,
            preutterance_frames=preutterance_frames,
            window=window,
        )
        return {
            "ok": True,
            "projection": projection["projection"],
            "spills": projection["spills"],
            "oto_size": len(self.oto),
        }

    # -- render ------------------------------------------------------------

    def render(
        self,
        notes: list[dict],
        tempo_segments: list[list[float]],
        out_path: str,
    ) -> dict[str, Any]:
        """Render notes to a WAV file using the external UTAU toolchain."""
        out_path = os.path.abspath(out_path)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)

        with tempfile.TemporaryDirectory() as td:
            # 1. Render each note to a cache WAV.
            cache_files: list[tuple[str, float]] = []
            for i, note in enumerate(notes):
                entry = self.oto[note["lyric"]]
                pitch = midi_to_utau_pitch(note["midi"])
                duration_ms = note_duration_seconds(note, tempo_segments) * 1000.0
                tempo_bpm = tempo_at_tick(note["start_tick"], tempo_segments)
                cache_wav = os.path.join(td, f"note_{i:03d}.wav")

                cmd = [
                    self.resampler,
                    entry["wav"],
                    cache_wav,
                    pitch,
                    "100",  # velocity
                    "",     # flags
                    str(int(entry["offset"])),
                    str(int(duration_ms)),
                    str(int(entry["consonant"])),
                    str(int(entry["cutoff"])),
                    "100",  # volume
                    "0",    # modulation
                    f"!{tempo_bpm}",
                    "AA",   # pitchbend
                ]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
                if result.returncode != 0 or not os.path.exists(cache_wav):
                    raise RuntimeError(f"resampler failed for {note['lyric']}: {result.stderr}")

                cache_files.append((cache_wav, duration_ms))

            # 2. Concatenate with wavtool.
            for cache_wav, duration_ms in cache_files:
                cmd = [
                    self.wavtool,
                    out_path,
                    cache_wav,
                    "0",                         # STP
                    str(int(duration_ms)),
                    "0", "0", "0",               # p1 p2 p3
                    "100", "100", "100", "100",  # v1..v4
                    "0",                         # ovr
                    "0", "0", "100",             # p4 p5 v5
                ]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
                if result.returncode != 0:
                    raise RuntimeError(f"wavtool failed: {result.stderr}")

            # 3. wavtool writes .whd + .dat; combine into the final WAV.
            whd_path = out_path + ".whd"
            dat_path = out_path + ".dat"
            with open(whd_path, "rb") as f:
                whd = f.read()
            with open(dat_path, "rb") as f:
                dat = f.read()
            with open(out_path, "wb") as f:
                f.write(whd + dat)

            for ext in [".whd", ".dat"]:
                p = out_path + ext
                if os.path.exists(p):
                    os.remove(p)

        # 4. Read output metadata.
        try:
            import soundfile as sf
            info = sf.info(out_path)
            return {
                "path": out_path,
                "duration": info.duration,
                "sample_rate": info.samplerate,
                "channels": info.channels,
            }
        except Exception:
            with wave.open(out_path, "rb") as wf:
                frames = wf.getnframes()
                rate = wf.getframerate()
                channels = wf.getnchannels()
                return {
                    "path": out_path,
                    "duration": frames / rate if rate else 0.0,
                    "sample_rate": rate,
                    "channels": channels,
                }


# ---------------------------------------------------------------------------
# Module-level helpers for engine_cli.py
# ---------------------------------------------------------------------------

def _engine_from_request(req: dict) -> UTAUEngine:
    cfg = req.get("utau_config") or {}
    voicebank = cfg.get("voicebank_root")
    resampler = cfg.get("resampler")
    wavtool = cfg.get("wavtool")
    if not voicebank or not resampler or not wavtool:
        raise ValueError(
            "utau_config must contain voicebank_root, resampler and wavtool"
        )
    return UTAUEngine(voicebank, resampler, wavtool)


def _default_out_path(req: dict) -> str:
    tag = req.get("tag", "utau")
    output_dir = Path(req.get("output_dir") or DEFAULT_OUTPUT_DIR).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    return str(output_dir / f"{tag}.wav")


def handle_utau_check(req: dict) -> dict:
    engine = _engine_from_request(req)
    result = engine.check(
        notes=req["notes"],
        tempo_segments=req.get("tempo_segments", [[0, 120.0]]),
        sample_rate=req.get("sample_rate", 86.13),
        preutterance_frames=req.get("preutterance_frames", 0),
        window=req.get("window"),
    )
    if not result["ok"]:
        return {"error": f"missing lyrics: {result['missing']}"}
    return {"projection": result["projection"], "spills": result["spills"]}


def handle_utau_render(req: dict) -> dict:
    engine = _engine_from_request(req)
    out_path = req.get("out_path") or _default_out_path(req)
    return engine.render(
        notes=req["notes"],
        tempo_segments=req.get("tempo_segments", [[0, 120.0]]),
        out_path=out_path,
    )
