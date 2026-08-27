#!/usr/bin/env python3
"""
Audio Analyzer & Evidence Pipeline — SnipWar Audio Vision Layer.

Subcommands:
    analyze         Full audio analysis (peaks, RMS, LUFS, spectrum, transients, classification)
    compare         Compare two audio files (spectral, loudness, transient similarity)
    render-evidence Render visual evidence artifacts (waveform, spectrum, transients, loudness)
    slice           Auto-slice audio file into OGG segments

Usage:
    python audio_analyzer.py analyze <file> [--output <json>] [--quiet]
    python audio_analyzer.py compare <file_a> <file_b> [--output <json>] [--quiet]
    python audio_analyzer.py render-evidence <file> [--output-dir <dir>] [--quiet]
    python audio_analyzer.py slice <file> [--auto] [--output-dir <dir>] [--json <config>] [--quiet]

All analysis is stdlib-only (no numpy/scipy). Spectral analysis uses Goertzel filters.
"""

from __future__ import annotations

import json
import math
import os
import struct
import subprocess
import sys
from pathlib import Path

# ═══════════════════════════════════════════════════════════════
# Constants
# ═══════════════════════════════════════════════════════════════

ANALYSIS_SAMPLE_RATE = 8000  # Downsampled rate for analysis (fast)
FULL_SAMPLE_RATE = 44100     # Full rate for spectral analysis
FRAME_SIZE = 1024            # Samples per spectral frame

# 7-band frequency ranges for Goertzel analysis
SPECTRUM_BANDS = {
    "sub_bass":   (20, 60),
    "bass":       (60, 250),
    "low_mid":    (250, 500),
    "mid":        (500, 2000),
    "upper_mid":  (2000, 4000),
    "presence":   (4000, 6000),
    "brilliance": (6000, 20000),
}

# K-weighting biquad coefficients (48kHz reference, adapted for our rates)
# Shelf boost ~+4dB at high frequencies, roll-off below 100Hz
K_WEIGHT_HP_CUTOFF = 0.012  # ~100Hz highpass for K-weighting approximation
K_WEIGHT_SHELF_GAIN = 1.58  # ~+4dB shelf above 1.5kHz

# Evidence image dimensions
IMG_WIDTH = 1024
IMG_HEIGHT = 256


# ═══════════════════════════════════════════════════════════════
# ffprobe / ffmpeg helpers
# ═══════════════════════════════════════════════════════════════

def get_audio_info_ffprobe(source: str) -> dict | None:
    """Use ffprobe to extract stream format details if available."""
    cmd = [
        "ffprobe", "-v", "quiet",
        "-print_format", "json",
        "-show_format", "-show_streams",
        source
    ]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        data = json.loads(res.stdout)
        fmt = data.get("format", {})
        streams = data.get("streams", [])
        audio_stream = next((s for s in streams if s.get("codec_type") == "audio"), {})

        duration = float(fmt.get("duration", audio_stream.get("duration", 0.0)))
        sample_rate = int(audio_stream.get("sample_rate", 44100))
        channels = int(audio_stream.get("channels", 2))
        codec = audio_stream.get("codec_name", "unknown")

        return {
            "duration": round(duration, 3),
            "sample_rate": sample_rate,
            "channels": channels,
            "codec": codec,
            "bit_rate": int(fmt.get("bit_rate", 0))
        }
    except Exception:
        return None


def decode_pcm_stream(source: str, sample_rate: int = ANALYSIS_SAMPLE_RATE) -> list[int] | None:
    """Decode audio to mono s16le PCM via ffmpeg pipe. Returns raw int16 samples."""
    cmd = [
        "ffmpeg", "-y", "-i", source,
        "-f", "s16le", "-ac", "1", "-ar", str(sample_rate),
        "pipe:1"
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True)
        if proc.returncode != 0:
            return None
        raw = proc.stdout
        count = len(raw) // 2
        if count == 0:
            return None
        return list(struct.unpack(f"<{count}h", raw))
    except Exception:
        return None


# ═══════════════════════════════════════════════════════════════
# DSP primitives (stdlib-only)
# ═══════════════════════════════════════════════════════════════

def goertzel_magnitude(samples: list[int], target_freq: float, sample_rate: int) -> float:
    """Goertzel algorithm: compute magnitude at a single frequency. O(N)."""
    n = len(samples)
    if n == 0:
        return 0.0
    k = round(target_freq * n / sample_rate)
    w = 2.0 * math.pi * k / n
    coeff = 2.0 * math.cos(w)
    s0 = 0.0
    s1 = 0.0
    s2 = 0.0
    for sample in samples:
        s0 = sample + coeff * s1 - s2
        s2 = s1
        s1 = s0
    power = s1 * s1 + s2 * s2 - coeff * s1 * s2
    return math.sqrt(max(0.0, power)) / n


def goertzel_band_energy(samples: list[int], low_hz: float, high_hz: float,
                         sample_rate: int, num_probes: int = 5) -> float:
    """Estimate energy in a frequency band by probing num_probes frequencies via Goertzel."""
    if low_hz >= high_hz or len(samples) == 0:
        return 0.0
    nyquist = sample_rate / 2.0
    actual_high = min(high_hz, nyquist - 1)
    if low_hz >= actual_high:
        return 0.0
    step = (actual_high - low_hz) / max(1, num_probes - 1)
    total = 0.0
    for i in range(num_probes):
        freq = low_hz + step * i
        total += goertzel_magnitude(samples, freq, sample_rate) ** 2
    return math.sqrt(total / num_probes)


def compute_rms(samples: list[int]) -> float:
    """RMS of int16 samples, normalized to [0, 1]."""
    if not samples:
        return 0.0
    sum_sq = sum(s * s for s in samples)
    return math.sqrt(sum_sq / len(samples)) / 32768.0


def compute_rms_float(samples: list[float]) -> float:
    """RMS of float samples."""
    if not samples:
        return 0.0
    sum_sq = sum(s * s for s in samples)
    return math.sqrt(sum_sq / len(samples))


def rms_to_db(rms: float) -> float:
    """Convert RMS to dB, with floor at -96 dB."""
    if rms < 1e-6:
        return -96.0
    return 20.0 * math.log10(rms)


def k_weight_samples(samples: list[int], sample_rate: int) -> list[float]:
    """Apply simplified K-weighting (highpass + shelf) to int16 samples.
    Returns float samples normalized to [-1, 1]."""
    # Highpass ~100Hz
    alpha = max(0.01, min(0.99, 1.0 - K_WEIGHT_HP_CUTOFF * (44100.0 / sample_rate)))
    prev_x = 0.0
    prev_y = 0.0
    hp_out: list[float] = []
    for s in samples:
        x = s / 32768.0
        y = alpha * (prev_y + x - prev_x)
        hp_out.append(y)
        prev_x, prev_y = x, y

    # High shelf approximation: boost frequencies above ~1.5kHz
    # Simple one-pole: blend original with HP-boosted version
    shelf_cutoff = 1500.0 / (sample_rate / 2.0)
    s_alpha = max(0.01, min(0.99, 1.0 - shelf_cutoff))
    prev_lp = 0.0
    result: list[float] = []
    for x in hp_out:
        prev_lp = s_alpha * prev_lp + (1.0 - s_alpha) * x
        high_part = x - prev_lp
        weighted = prev_lp + high_part * K_WEIGHT_SHELF_GAIN
        result.append(weighted)
    return result


def compute_lufs_momentary(k_weighted: list[float], sample_rate: int,
                           window_ms: int = 400) -> list[float]:
    """LUFS momentary (400ms sliding window) from K-weighted float samples."""
    window_samples = int(sample_rate * window_ms / 1000)
    if len(k_weighted) < window_samples:
        rms = compute_rms_float(k_weighted)
        return [rms_to_db(rms) - 0.691] if rms > 0 else [-96.0]

    result: list[float] = []
    # Sliding window with step = window_samples (non-overlapping for speed)
    for start in range(0, len(k_weighted) - window_samples + 1, window_samples):
        chunk = k_weighted[start:start + window_samples]
        rms = compute_rms_float(chunk)
        lufs = rms_to_db(rms) - 0.691  # K-weighted offset
        result.append(round(lufs, 1))
    return result


def compute_lufs_integrated(k_weighted: list[float]) -> float:
    """LUFS integrated with absolute gating (ITU-BS.1770 simplified).
    Gate threshold: -70 LUFS absolute, then relative gate at -10 dB below ungated mean."""
    if not k_weighted:
        return -96.0

    # 400ms blocks
    block_size = max(1, int(len(k_weighted) * 0.01))  # ~1% of total ≈ adaptive block
    if len(k_weighted) > 3200:
        block_size = 3200  # ~400ms at 8kHz

    block_powers: list[float] = []
    for start in range(0, len(k_weighted) - block_size + 1, block_size):
        chunk = k_weighted[start:start + block_size]
        power = sum(s * s for s in chunk) / len(chunk)
        block_powers.append(power)

    if not block_powers:
        return -96.0

    # Absolute gate: -70 LUFS
    abs_gate_power = 10 ** ((-70.0 + 0.691) / 10.0)
    gated = [p for p in block_powers if p > abs_gate_power]
    if not gated:
        return -96.0

    # Ungated mean
    ungated_mean = sum(gated) / len(gated)

    # Relative gate: -10 dB below ungated mean
    rel_gate = ungated_mean * 0.1
    final_gated = [p for p in gated if p > rel_gate]
    if not final_gated:
        return -96.0

    mean_power = sum(final_gated) / len(final_gated)
    return round(-0.691 + 10.0 * math.log10(max(1e-12, mean_power)), 1)


def detect_transients(rms_per_frame: list[float], threshold_factor: float = 2.5,
                      min_gap_frames: int = 3) -> list[int]:
    """Detect transient onsets as frames where RMS jumps significantly."""
    if len(rms_per_frame) < 2:
        return []

    # Compute running average
    avg_window = 5
    transient_frames: list[int] = []
    last_onset = -min_gap_frames

    for i in range(1, len(rms_per_frame)):
        # Local average of preceding frames
        start = max(0, i - avg_window)
        local_avg = sum(rms_per_frame[start:i]) / max(1, i - start)

        delta = rms_per_frame[i] - local_avg
        if delta > local_avg * threshold_factor and delta > 0.01:
            if i - last_onset >= min_gap_frames:
                transient_frames.append(i)
                last_onset = i

    return transient_frames


def compute_spectral_centroid(band_energies: dict[str, float],
                              band_ranges: dict[str, tuple[float, float]]) -> float:
    """Spectral centroid from band energies (weighted mean frequency)."""
    total_energy = sum(band_energies.values())
    if total_energy < 1e-10:
        return 0.0
    weighted_sum = 0.0
    for band_name, energy in band_energies.items():
        low, high = band_ranges[band_name]
        center = (low + high) / 2.0
        weighted_sum += center * energy
    return round(weighted_sum / total_energy, 1)


def compute_spectral_flatness(band_energies: dict[str, float]) -> float:
    """Spectral flatness: geometric mean / arithmetic mean of band energies.
    1.0 = white noise, 0.0 = pure tone."""
    values = [max(1e-10, e) for e in band_energies.values()]
    n = len(values)
    if n == 0:
        return 0.0
    log_sum = sum(math.log(v) for v in values)
    geometric_mean = math.exp(log_sum / n)
    arithmetic_mean = sum(values) / n
    if arithmetic_mean < 1e-10:
        return 0.0
    return round(min(1.0, geometric_mean / arithmetic_mean), 4)


# ═══════════════════════════════════════════════════════════════
# Classification
# ═══════════════════════════════════════════════════════════════

def classify_audio(spectral_flatness: float, tonal_ratio: float,
                   noise_floor_db: float, silence_ratio: float,
                   dynamic_range_db: float) -> list[str]:
    """Generate classification tags from audio metrics."""
    tags: list[str] = []

    # Tonality
    if tonal_ratio > 0.6:
        tags.append("tonal")
    elif tonal_ratio > 0.3:
        tags.append("mixed_tonal_noise")
    else:
        tags.append("noise_dominant")

    # Noise character
    if spectral_flatness > 0.7:
        tags.append("white_noise_like")
    elif spectral_flatness > 0.4:
        tags.append("colored_noise")

    # Noise floor
    if noise_floor_db > -30:
        tags.append("high_noise")
    elif noise_floor_db < -55:
        tags.append("low_noise")

    # Dynamics
    if dynamic_range_db > 20:
        tags.append("wide_dynamics")
    elif dynamic_range_db < 6:
        tags.append("compressed")
    else:
        tags.append("moderate_dynamics")

    # Silence
    if silence_ratio > 0.3:
        tags.append("sparse")
    elif silence_ratio < 0.05:
        tags.append("dense")

    return tags


# ═══════════════════════════════════════════════════════════════
# Core analysis
# ═══════════════════════════════════════════════════════════════

def extract_full_analysis(source: str) -> dict:
    """Full audio analysis: peaks, RMS, LUFS, spectrum, transients, classification."""
    info = get_audio_info_ffprobe(source)
    if not info:
        file_size = os.path.getsize(source) if os.path.isfile(source) else 0
        info = {
            "duration": 0.0,
            "sample_rate": 44100,
            "channels": 2,
            "codec": Path(source).suffix.lstrip("."),
            "bit_rate": 0,
            "file_size": file_size
        }

    duration = info.get("duration", 0.0)

    # ─── Decode at analysis rate (8kHz) for peaks, RMS, silence ───
    samples_8k = decode_pcm_stream(source, ANALYSIS_SAMPLE_RATE)
    if samples_8k is None:
        return {"ok": False, "error": "Failed to decode audio via ffmpeg"}

    chunk_size = ANALYSIS_SAMPLE_RATE  # 1 second chunks
    peaks: list[float] = []
    rms_per_second: list[float] = []
    silence_ranges: list[dict] = []
    recommended_cuts: list[dict] = []

    noise_threshold = 0.03
    min_silence_len = 0.3

    is_silent = False
    silence_start = 0.0
    in_sound = False
    last_sound_start = 0.0
    non_silent_blocks: list[tuple[float, float]] = []

    for sec_idx in range(0, len(samples_8k), chunk_size):
        chunk = samples_8k[sec_idx:sec_idx + chunk_size]
        if not chunk:
            break
        max_val = max(abs(s) for s in chunk)
        peak = round(max_val / 32768.0, 4)
        peaks.append(peak)

        rms = compute_rms(chunk)
        rms_per_second.append(round(rms, 4))

        sec_start = sec_idx / ANALYSIS_SAMPLE_RATE
        sec_end = (sec_idx + len(chunk)) / ANALYSIS_SAMPLE_RATE

        if peak < noise_threshold:
            if not is_silent:
                is_silent = True
                silence_start = sec_start
                if in_sound:
                    non_silent_blocks.append((last_sound_start, sec_start))
                    in_sound = False
        else:
            if is_silent:
                is_silent = False
                silence_dur = sec_start - silence_start
                if silence_dur >= min_silence_len:
                    silence_ranges.append({
                        "start": round(silence_start, 2),
                        "end": round(sec_start, 2),
                        "duration": round(silence_dur, 2)
                    })
            if not in_sound:
                in_sound = True
                last_sound_start = sec_start

    total_seconds = len(samples_8k) / ANALYSIS_SAMPLE_RATE

    if is_silent:
        silence_dur = total_seconds - silence_start
        if silence_dur >= min_silence_len:
            silence_ranges.append({
                "start": round(silence_start, 2),
                "end": round(total_seconds, 2),
                "duration": round(silence_dur, 2)
            })
    elif in_sound:
        non_silent_blocks.append((last_sound_start, total_seconds))

    cut_idx = 1
    for start, end in non_silent_blocks:
        dur = end - start
        if dur >= 0.2:
            recommended_cuts.append({
                "name": f"slice_{cut_idx:02d}",
                "start": round(start, 2),
                "end": round(end, 2),
                "duration": round(dur, 2)
            })
            cut_idx += 1

    # ─── Peak dB and dynamic range ───
    peak_val = max(peaks) if peaks else 0.0
    peak_db = round(rms_to_db(peak_val), 1)
    min_nonzero_rms = min((r for r in rms_per_second if r > 0.001), default=0.001)
    max_rms = max(rms_per_second) if rms_per_second else 0.001
    dynamic_range_db = round(rms_to_db(max_rms) - rms_to_db(min_nonzero_rms), 1)

    # ─── LUFS (K-weighted) ───
    k_weighted = k_weight_samples(samples_8k, ANALYSIS_SAMPLE_RATE)
    lufs_momentary = compute_lufs_momentary(k_weighted, ANALYSIS_SAMPLE_RATE)
    lufs_integrated = compute_lufs_integrated(k_weighted)

    # ─── Spectral analysis (decode at higher rate for accuracy) ───
    # Use 22050 Hz as compromise between accuracy and speed
    spectral_rate = 22050
    samples_hq = decode_pcm_stream(source, spectral_rate)
    if samples_hq is None:
        samples_hq = samples_8k
        spectral_rate = ANALYSIS_SAMPLE_RATE

    # Analyze multiple frames and average band energies
    band_energies: dict[str, float] = {name: 0.0 for name in SPECTRUM_BANDS}
    num_frames = 0
    for frame_start in range(0, len(samples_hq) - FRAME_SIZE, FRAME_SIZE * 4):
        frame = samples_hq[frame_start:frame_start + FRAME_SIZE]
        for band_name, (low, high) in SPECTRUM_BANDS.items():
            energy = goertzel_band_energy(frame, low, high, spectral_rate, num_probes=3)
            band_energies[band_name] += energy
        num_frames += 1

    if num_frames > 0:
        for name in band_energies:
            band_energies[name] = round(band_energies[name] / num_frames, 4)

    # Normalize band energies to [0, 1]
    max_energy = max(band_energies.values()) if band_energies else 1.0
    if max_energy < 1e-10:
        max_energy = 1.0
    band_energies_norm = {name: round(e / max_energy, 4) for name, e in band_energies.items()}

    spectral_centroid = compute_spectral_centroid(band_energies, SPECTRUM_BANDS)
    spectral_flatness = compute_spectral_flatness(band_energies)

    # ─── Transient detection ───
    transient_frames = detect_transients(rms_per_second, threshold_factor=2.0, min_gap_frames=2)
    transient_positions = [round(f * 1.0, 2) for f in transient_frames]  # 1 frame = 1 second
    transient_density = round(len(transient_frames) / max(0.1, duration), 2)

    # ─── Classification ───
    # Tonal ratio: inverse of spectral flatness (low flatness = tonal)
    tonal_ratio = round(1.0 - spectral_flatness, 2)
    # Noise floor: lowest non-zero RMS in dB
    noise_floor_db = round(rms_to_db(min_nonzero_rms), 1)
    # Paper noise ratio: combination of high-freq energy + flatness
    hf_energy = band_energies_norm.get("presence", 0.0) + band_energies_norm.get("brilliance", 0.0)
    paper_noise_ratio = round(min(1.0, spectral_flatness * 0.6 + hf_energy * 0.4), 2)
    # Silence ratio
    total_silence = sum(s["duration"] for s in silence_ranges)
    silence_ratio = round(total_silence / max(0.1, duration), 2)

    tags = classify_audio(spectral_flatness, tonal_ratio, noise_floor_db,
                          silence_ratio, dynamic_range_db)

    # ─── Build result ───
    return {
        "ok": True,
        "file": os.path.basename(source),
        "path": source,
        "technical": {
            "duration": info["duration"],
            "sample_rate": info["sample_rate"],
            "channels": info["channels"],
            "codec": info["codec"],
            "bit_rate": info.get("bit_rate", 0),
        },
        "waveform": {
            "peaks_per_second": peaks,
            "rms_per_second": rms_per_second,
            "lufs_integrated": lufs_integrated,
            "lufs_momentary": lufs_momentary,
            "peak_db": peak_db,
            "dynamic_range_db": dynamic_range_db,
        },
        "spectrum": {
            "bands": {
                name: {
                    "range_hz": list(SPECTRUM_BANDS[name]),
                    "energy": band_energies_norm[name],
                }
                for name in SPECTRUM_BANDS
            },
            "spectral_centroid_hz": spectral_centroid,
            "spectral_flatness": spectral_flatness,
        },
        "transients": {
            "count": len(transient_positions),
            "positions_sec": transient_positions,
            "density_per_sec": transient_density,
        },
        "classification": {
            "paper_noise_ratio": paper_noise_ratio,
            "tonal_ratio": tonal_ratio,
            "noise_floor_db": noise_floor_db,
            "silence_ratio": silence_ratio,
            "tags": tags,
        },
        # Legacy-compatible fields
        "duration": info["duration"],
        "sample_rate": info["sample_rate"],
        "channels": info["channels"],
        "codec": info["codec"],
        "peaks": peaks,
        "silence_ranges": silence_ranges,
        "recommended_cuts": recommended_cuts,
    }


# ═══════════════════════════════════════════════════════════════
# Compare
# ═══════════════════════════════════════════════════════════════

def compare_audio(source_a: str, source_b: str) -> dict:
    """Compare two audio files across all dimensions."""
    a = extract_full_analysis(source_a)
    b = extract_full_analysis(source_b)

    if not a.get("ok"):
        return {"ok": False, "error": f"Failed to analyze {source_a}: {a.get('error', 'unknown')}"}
    if not b.get("ok"):
        return {"ok": False, "error": f"Failed to analyze {source_b}: {b.get('error', 'unknown')}"}

    dur_a = a["technical"]["duration"]
    dur_b = b["technical"]["duration"]

    rms_a = compute_rms_float(a["waveform"]["rms_per_second"])
    rms_b = compute_rms_float(b["waveform"]["rms_per_second"])

    # Band energy differences
    bands_a = a["spectrum"]["bands"]
    bands_b = b["spectrum"]["bands"]
    band_diffs = {}
    for name in SPECTRUM_BANDS:
        e_a = bands_a.get(name, {}).get("energy", 0.0)
        e_b = bands_b.get(name, {}).get("energy", 0.0)
        band_diffs[name] = round(abs(e_a - e_b), 4)

    centroid_diff = abs(a["spectrum"]["spectral_centroid_hz"] - b["spectrum"]["spectral_centroid_hz"])
    flatness_diff = abs(a["spectrum"]["spectral_flatness"] - b["spectrum"]["spectral_flatness"])
    transient_density_diff = abs(a["transients"]["density_per_sec"] - b["transients"]["density_per_sec"])

    # Similarity score (0 = identical, 1 = completely different)
    # Weighted sum of normalized differences
    max_centroid = max(1.0, a["spectrum"]["spectral_centroid_hz"], b["spectrum"]["spectral_centroid_hz"])
    norm_centroid = centroid_diff / max_centroid
    norm_flatness = flatness_diff
    norm_rms = abs(rms_to_db(max(rms_a, 1e-6)) - rms_to_db(max(rms_b, 1e-6))) / 48.0
    norm_bands = sum(band_diffs.values()) / max(1, len(band_diffs))
    norm_transients = min(1.0, transient_density_diff / max(0.1,
        max(a["transients"]["density_per_sec"], b["transients"]["density_per_sec"])))

    raw_distance = (
        norm_centroid * 0.25 +
        norm_flatness * 0.20 +
        norm_rms * 0.15 +
        norm_bands * 0.25 +
        norm_transients * 0.15
    )
    similarity = round(max(0.0, min(1.0, 1.0 - raw_distance)), 2)

    # Verdict
    if similarity >= 0.85:
        verdict = "very_similar"
    elif similarity >= 0.65:
        verdict = "similar_character"
    elif similarity >= 0.40:
        verdict = "moderately_different"
    else:
        verdict = "very_different"

    return {
        "ok": True,
        "file_a": os.path.basename(source_a),
        "file_b": os.path.basename(source_b),
        "comparison": {
            "duration_diff_sec": round(abs(dur_a - dur_b), 2),
            "rms_diff_db": round(abs(rms_to_db(max(rms_a, 1e-6)) - rms_to_db(max(rms_b, 1e-6))), 1),
            "lufs_diff": round(abs(a["waveform"]["lufs_integrated"] - b["waveform"]["lufs_integrated"]), 1),
            "spectral_centroid_diff_hz": round(centroid_diff, 1),
            "spectral_flatness_diff": round(flatness_diff, 4),
            "transient_density_diff": round(transient_density_diff, 2),
            "band_energy_diff": band_diffs,
            "similarity_score": similarity,
            "verdict": verdict,
        }
    }


# ═══════════════════════════════════════════════════════════════
# BMP evidence rendering (stdlib-only, no PIL)
# ═══════════════════════════════════════════════════════════════

def _bmp_header(width: int, height: int) -> bytes:
    """Create a 24-bit BMP file header."""
    row_size = (width * 3 + 3) & ~3  # Row size padded to 4-byte boundary
    pixel_data_size = row_size * height
    file_size = 54 + pixel_data_size

    header = struct.pack("<2sIHHI", b"BM", file_size, 0, 0, 54)
    info = struct.pack("<IIIHHIIIIII",
                       40, width, height, 1, 24, 0, pixel_data_size, 2835, 2835, 0, 0)
    return header + info


def _render_bmp(width: int, height: int, pixels: list[list[tuple[int, int, int]]]) -> bytes:
    """Render a BMP from a 2D pixel array [row][col] = (R, G, B). Bottom-up row order."""
    data = _bmp_header(width, height)
    row_padding = (4 - (width * 3) % 4) % 4
    rows = bytearray()
    # BMP is bottom-up
    for y in range(height - 1, -1, -1):
        row = pixels[y] if y < len(pixels) else [(0, 0, 0)] * width
        for x in range(width):
            r, g, b = row[x] if x < len(row) else (0, 0, 0)
            rows.extend(struct.pack("BBB", b, g, r))  # BMP is BGR
        rows.extend(b"\x00" * row_padding)
    return data + bytes(rows)


def _lerp_color(c1: tuple[int, int, int], c2: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    """Linear interpolate between two RGB colors."""
    t = max(0.0, min(1.0, t))
    return (
        int(c1[0] + (c2[0] - c1[0]) * t),
        int(c1[1] + (c2[1] - c1[1]) * t),
        int(c1[2] + (c2[2] - c1[2]) * t),
    )


def render_waveform_bmp(peaks: list[float], rms: list[float], width: int, height: int) -> bytes:
    """Render waveform (peaks as gray, RMS as blue overlay)."""
    bg = (18, 18, 24)
    peak_color = (90, 90, 100)
    rms_color = (60, 120, 200)
    center_line = (40, 40, 50)

    pixels = [[bg] * width for _ in range(height)]
    mid = height // 2

    # Center line
    for x in range(width):
        pixels[mid][x] = center_line

    n = max(len(peaks), len(rms), 1)

    for x in range(width):
        idx = int(x * n / width)

        # Peak bars (symmetric around center)
        if idx < len(peaks):
            p = peaks[idx]
            bar_h = int(p * mid * 0.95)
            for dy in range(-bar_h, bar_h + 1):
                y = mid + dy
                if 0 <= y < height:
                    pixels[y][x] = peak_color

        # RMS overlay (narrower, brighter)
        if idx < len(rms):
            r = rms[idx]
            bar_h = int(r * mid * 0.95)
            for dy in range(-bar_h, bar_h + 1):
                y = mid + dy
                if 0 <= y < height:
                    pixels[y][x] = rms_color

    return _render_bmp(width, height, pixels)


def render_spectrum_bmp(band_energies: dict[str, dict], width: int, height: int) -> bytes:
    """Render 7-band spectrum as vertical bars."""
    bg = (18, 18, 24)
    colors = [
        (180, 40, 40),   # sub_bass - red
        (200, 100, 30),  # bass - orange
        (200, 180, 40),  # low_mid - yellow
        (60, 180, 60),   # mid - green
        (40, 160, 200),  # upper_mid - cyan
        (80, 80, 220),   # presence - blue
        (160, 60, 200),  # brilliance - purple
    ]

    pixels = [[bg] * width for _ in range(height)]
    bands = list(band_energies.items())
    n_bands = len(bands)
    bar_width = width // (n_bands + 1)
    gap = bar_width // 4
    margin = (width - n_bands * bar_width) // 2

    for i, (name, info) in enumerate(bands):
        energy = info.get("energy", 0.0)
        bar_h = int(energy * (height - 20))
        x_start = margin + i * bar_width + gap
        x_end = x_start + bar_width - 2 * gap
        color = colors[i % len(colors)]

        for x in range(x_start, min(x_end, width)):
            for y in range(height - 10 - bar_h, height - 10):
                if 0 <= y < height:
                    # Gradient: darker at bottom
                    t = (y - (height - 10 - bar_h)) / max(1, bar_h)
                    c = _lerp_color((color[0] // 3, color[1] // 3, color[2] // 3), color, t)
                    pixels[y][x] = c

    return _render_bmp(width, height, pixels)


def render_transients_bmp(transient_positions: list[float], duration: float,
                          width: int, height: int) -> bytes:
    """Render transient onset positions as vertical markers on timeline."""
    bg = (18, 18, 24)
    marker_color = (220, 80, 60)
    timeline_color = (50, 50, 60)

    pixels = [[bg] * width for _ in range(height)]

    # Timeline bar
    timeline_y = height - 30
    for x in range(width):
        if 0 <= timeline_y < height:
            pixels[timeline_y][x] = timeline_color

    if duration <= 0:
        return _render_bmp(width, height, pixels)

    # Transient markers
    for pos in transient_positions:
        x = int(pos / duration * (width - 1))
        if 0 <= x < width:
            for y in range(10, height - 20):
                fade = 1.0 - abs(y - height // 2) / (height // 2)
                c = _lerp_color(bg, marker_color, max(0.3, fade))
                pixels[y][x] = c
                # Make markers 3px wide
                if x + 1 < width:
                    pixels[y][x + 1] = _lerp_color(bg, marker_color, max(0.1, fade * 0.5))
                if x - 1 >= 0:
                    pixels[y][x - 1] = _lerp_color(bg, marker_color, max(0.1, fade * 0.5))

    return _render_bmp(width, height, pixels)


def render_loudness_bmp(lufs_momentary: list[float], lufs_integrated: float,
                        width: int, height: int) -> bytes:
    """Render LUFS momentary curve with integrated reference line."""
    bg = (18, 18, 24)
    curve_color = (80, 200, 120)
    integrated_color = (200, 160, 40)
    grid_color = (35, 35, 45)

    pixels = [[bg] * width for _ in range(height)]

    # LUFS range: -60 to 0
    lufs_min = -60.0
    lufs_max = 0.0
    lufs_range = lufs_max - lufs_min

    # Grid lines every 10 LUFS
    for lufs_val in range(-60, 1, 10):
        y = int((1.0 - (lufs_val - lufs_min) / lufs_range) * (height - 1))
        if 0 <= y < height:
            for x in range(width):
                pixels[y][x] = grid_color

    # Integrated reference line
    if lufs_integrated > lufs_min:
        ref_y = int((1.0 - (lufs_integrated - lufs_min) / lufs_range) * (height - 1))
        if 0 <= ref_y < height:
            for x in range(0, width, 3):  # Dashed line
                pixels[ref_y][x] = integrated_color
                if x + 1 < width:
                    pixels[ref_y][x + 1] = integrated_color

    # Momentary curve
    n = len(lufs_momentary)
    if n > 0:
        prev_y = -1
        for x in range(width):
            idx = int(x * n / width)
            if idx >= n:
                idx = n - 1
            lufs_val = max(lufs_min, min(lufs_max, lufs_momentary[idx]))
            y = int((1.0 - (lufs_val - lufs_min) / lufs_range) * (height - 1))
            y = max(0, min(height - 1, y))

            # Draw vertical line between prev_y and y for continuity
            if prev_y >= 0:
                y_low = min(prev_y, y)
                y_high = max(prev_y, y)
                for dy in range(y_low, y_high + 1):
                    if 0 <= dy < height:
                        pixels[dy][x] = curve_color
            else:
                pixels[y][x] = curve_color
            prev_y = y

    return _render_bmp(width, height, pixels)


def convert_bmp_to_png(bmp_path: str, png_path: str) -> bool:
    """Convert BMP to PNG via ffmpeg if available."""
    try:
        result = subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-i", bmp_path, png_path],
            capture_output=True, text=True
        )
        if result.returncode == 0 and os.path.isfile(png_path):
            os.unlink(bmp_path)
            return True
    except Exception:
        pass
    return False


def render_evidence(source: str, output_dir: str = "audio_evidence") -> dict:
    """Render all visual evidence artifacts for an audio file."""
    analysis = extract_full_analysis(source)
    if not analysis.get("ok"):
        return analysis

    os.makedirs(output_dir, exist_ok=True)
    basename = Path(source).stem
    artifacts: list[str] = []

    # 1. Waveform
    waveform_path = os.path.join(output_dir, f"{basename}_waveform")
    bmp_data = render_waveform_bmp(
        analysis["waveform"]["peaks_per_second"],
        analysis["waveform"]["rms_per_second"],
        IMG_WIDTH, IMG_HEIGHT
    )
    bmp_file = waveform_path + ".bmp"
    with open(bmp_file, "wb") as f:
        f.write(bmp_data)
    png_file = waveform_path + ".png"
    if convert_bmp_to_png(bmp_file, png_file):
        artifacts.append(png_file)
    else:
        artifacts.append(bmp_file)

    # 2. Spectrum
    spectrum_path = os.path.join(output_dir, f"{basename}_spectrum")
    bmp_data = render_spectrum_bmp(
        analysis["spectrum"]["bands"],
        IMG_WIDTH, IMG_HEIGHT
    )
    bmp_file = spectrum_path + ".bmp"
    with open(bmp_file, "wb") as f:
        f.write(bmp_data)
    png_file = spectrum_path + ".png"
    if convert_bmp_to_png(bmp_file, png_file):
        artifacts.append(png_file)
    else:
        artifacts.append(bmp_file)

    # 3. Transients
    transients_path = os.path.join(output_dir, f"{basename}_transients")
    bmp_data = render_transients_bmp(
        analysis["transients"]["positions_sec"],
        analysis["technical"]["duration"],
        IMG_WIDTH, IMG_HEIGHT
    )
    bmp_file = transients_path + ".bmp"
    with open(bmp_file, "wb") as f:
        f.write(bmp_data)
    png_file = transients_path + ".png"
    if convert_bmp_to_png(bmp_file, png_file):
        artifacts.append(png_file)
    else:
        artifacts.append(bmp_file)

    # 4. Loudness
    loudness_path = os.path.join(output_dir, f"{basename}_loudness")
    bmp_data = render_loudness_bmp(
        analysis["waveform"]["lufs_momentary"],
        analysis["waveform"]["lufs_integrated"],
        IMG_WIDTH, IMG_HEIGHT
    )
    bmp_file = loudness_path + ".bmp"
    with open(bmp_file, "wb") as f:
        f.write(bmp_data)
    png_file = loudness_path + ".png"
    if convert_bmp_to_png(bmp_file, png_file):
        artifacts.append(png_file)
    else:
        artifacts.append(bmp_file)

    return {
        "ok": True,
        "file": os.path.basename(source),
        "output_dir": output_dir,
        "artifacts": artifacts,
        "analysis_summary": {
            "duration": analysis["technical"]["duration"],
            "lufs_integrated": analysis["waveform"]["lufs_integrated"],
            "spectral_centroid_hz": analysis["spectrum"]["spectral_centroid_hz"],
            "transient_count": analysis["transients"]["count"],
            "tags": analysis["classification"]["tags"],
        }
    }


# ═══════════════════════════════════════════════════════════════
# Slice (legacy-compatible)
# ═══════════════════════════════════════════════════════════════

def time_to_seconds(t: str | float) -> float:
    if isinstance(t, (int, float)):
        return float(t)
    if ":" in t:
        parts = t.split(":")
        return int(parts[0]) * 60 + float(parts[1])
    return float(t)


def slice_audio_segment(source: str, name: str, start: str | float, end: str | float,
                        output_dir: str, fade_ms: int = 150) -> str:
    start_s = time_to_seconds(start)
    end_s = time_to_seconds(end)
    duration = end_s - start_s

    if duration <= 0:
        return ""

    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, f"{name}.ogg")

    filters = []
    if fade_ms > 0 and duration > (fade_ms * 2) / 1000:
        filters.append(f"afade=t=in:st=0:d={fade_ms / 1000}")
        fade_start = max(0, duration - fade_ms / 1000)
        filters.append(f"afade=t=out:st={fade_start}:d={fade_ms / 1000}")

    cmd = [
        "ffmpeg", "-y",
        "-i", source,
        "-ss", str(start_s),
        "-t", str(duration),
    ]
    if filters:
        cmd += ["-af", ",".join(filters)]
    cmd += ["-c:a", "libvorbis", "-q:a", "4", output_path]

    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode == 0:
        return output_path
    return ""


def slice_audio_auto(source: str, output_dir: str = "assets/audio/sfx",
                     auto: bool = True, config_json: str | None = None) -> dict:
    if not os.path.isfile(source):
        return {"ok": False, "error": f"Source file not found: {source}"}

    cuts = []
    if config_json and os.path.isfile(config_json):
        with open(config_json, "r", encoding="utf-8") as f:
            cfg = json.load(f)
            cuts = cfg.get("slices", cfg.get("recommended_cuts", []))
    elif auto:
        analysis = extract_full_analysis(source)
        cuts = analysis.get("recommended_cuts", [])

    if not cuts:
        return {"ok": False, "error": "No slice definitions or recommended cuts found", "slices_created": 0}

    created_files = []
    for c in cuts:
        name = c.get("name", "slice")
        start = c.get("start", 0)
        end = c.get("end", 0)
        out_path = slice_audio_segment(source, name, start, end, output_dir)
        if out_path:
            created_files.append(out_path)

    return {
        "ok": True,
        "source": source,
        "output_dir": output_dir,
        "slices_created": len(created_files),
        "files": created_files
    }


# ═══════════════════════════════════════════════════════════════
# Legacy-compatible analyze wrapper
# ═══════════════════════════════════════════════════════════════

def analyze_audio(source: str, output_json: str | None = None) -> dict:
    """Legacy-compatible analyze function. Delegates to extract_full_analysis."""
    if not os.path.isfile(source):
        err = {"ok": False, "error": f"Source file not found: {source}"}
        print(json.dumps(err))
        return err

    result = extract_full_analysis(source)

    out_path = output_json or "audio_analysis.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    return result


# ═══════════════════════════════════════════════════════════════
# CLI
# ═══════════════════════════════════════════════════════════════

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    # --quiet: redirect all stderr to devnull
    quiet = "--quiet" in sys.argv
    if quiet:
        sys.stderr = open(os.devnull, 'w')

    cmd = sys.argv[1]

    if cmd == "analyze":
        if len(sys.argv) < 3:
            print("Usage: python audio_analyzer.py analyze <file> [--output <json>]")
            sys.exit(1)
        source = sys.argv[2]
        output_json = None
        if "--output" in sys.argv:
            idx = sys.argv.index("--output")
            if idx + 1 < len(sys.argv):
                output_json = sys.argv[idx + 1]
        res = analyze_audio(source, output_json)
        print(json.dumps(res, indent=2))

    elif cmd == "compare":
        if len(sys.argv) < 4:
            print("Usage: python audio_analyzer.py compare <file_a> <file_b> [--output <json>]")
            sys.exit(1)
        source_a = sys.argv[2]
        source_b = sys.argv[3]
        if not os.path.isfile(source_a):
            print(json.dumps({"ok": False, "error": f"File not found: {source_a}"}))
            sys.exit(1)
        if not os.path.isfile(source_b):
            print(json.dumps({"ok": False, "error": f"File not found: {source_b}"}))
            sys.exit(1)
        res = compare_audio(source_a, source_b)
        output_json = None
        if "--output" in sys.argv:
            idx = sys.argv.index("--output")
            if idx + 1 < len(sys.argv):
                output_json = sys.argv[idx + 1]
        if output_json:
            with open(output_json, "w", encoding="utf-8") as f:
                json.dump(res, f, indent=2)
        print(json.dumps(res, indent=2))

    elif cmd == "render-evidence":
        if len(sys.argv) < 3:
            print("Usage: python audio_analyzer.py render-evidence <file> [--output-dir <dir>]")
            sys.exit(1)
        source = sys.argv[2]
        if not os.path.isfile(source):
            print(json.dumps({"ok": False, "error": f"File not found: {source}"}))
            sys.exit(1)
        output_dir = "audio_evidence"
        if "--output-dir" in sys.argv:
            idx = sys.argv.index("--output-dir")
            if idx + 1 < len(sys.argv):
                output_dir = sys.argv[idx + 1]
        res = render_evidence(source, output_dir)
        print(json.dumps(res, indent=2))

    elif cmd == "slice":
        if len(sys.argv) < 3:
            print("Usage: python audio_analyzer.py slice <file> [--auto] [--output-dir <dir>] [--json <config>]")
            sys.exit(1)
        source = sys.argv[2]
        auto = "--auto" in sys.argv
        output_dir = "assets/audio/sfx"
        if "--output-dir" in sys.argv:
            idx = sys.argv.index("--output-dir")
            if idx + 1 < len(sys.argv):
                output_dir = sys.argv[idx + 1]
        config_json = None
        if "--json" in sys.argv:
            idx = sys.argv.index("--json")
            if idx + 1 < len(sys.argv):
                config_json = sys.argv[idx + 1]
        res = slice_audio_auto(source, output_dir=output_dir, auto=auto, config_json=config_json)
        print(json.dumps(res, indent=2))

    else:
        print(f"Unknown command: {cmd}")
        print("Available: analyze, compare, render-evidence, slice")
        sys.exit(1)


if __name__ == "__main__":
    main()
