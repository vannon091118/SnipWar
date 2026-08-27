#!/usr/bin/env python3
"""Procedural SnipWar UI sound palette.

No third-party Python packages required. WAV synthesis uses layered oscillators,
filtered noise, envelopes, pitch glides, saturation, and a soft compressor;
ffmpeg converts each WAV to OGG when available.

Usage:
    python audio_synth.py
    python audio_synth.py --output-dir assets/audio/sfx --format ogg
"""

from __future__ import annotations

import argparse
import math
import os
import random
import shutil
import struct
import subprocess
import wave
from pathlib import Path

RATE = 44100
RNG = random.Random(424242)


def clamp(x: float, lo: float = -1.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, x))


def envelope(t: float, duration: float, attack: float, decay: float, sustain: float = 0.0, release: float = 0.0) -> float:
    if t < attack:
        return t / max(attack, 1e-6)
    after_attack = t - attack
    if after_attack < decay:
        return 1.0 + (sustain - 1.0) * after_attack / max(decay, 1e-6)
    if release <= 0:
        return sustain
    release_start = max(0.0, duration - release)
    if t < release_start:
        return sustain
    return sustain * max(0.0, 1.0 - (t - release_start) / release)


def one_pole_noise(n: int, smoothing: float = 0.94) -> list[float]:
    out: list[float] = []
    value = 0.0
    for _ in range(n):
        value = smoothing * value + (1.0 - smoothing) * RNG.uniform(-1.0, 1.0)
        out.append(value)
    return out


def highpass(values: list[float], cutoff: float = 0.08) -> list[float]:
    out: list[float] = []
    previous_x = 0.0
    previous_y = 0.0
    alpha = max(0.01, min(0.99, 1.0 - cutoff))
    for x in values:
        y = alpha * (previous_y + x - previous_x)
        out.append(y)
        previous_x, previous_y = x, y
    return out


def bandlimited_noise(n: int, low_hz: float = 200, high_hz: float = 4000, smoothing_low: float = 0.0, smoothing_high: float = 0.0) -> list[float]:
    smoothing_lp = max(0.01, 1.0 - (high_hz / (RATE / 2.0)))
    hp_cutoff = max(0.001, low_hz / (RATE / 2.0))
    lp_noise = one_pole_noise(n, smoothing=smoothing_lp)
    return highpass(lp_noise, cutoff=hp_cutoff)


def paper_transient(n: int, style: str = 'fingertip') -> list[float]:
    if style == 'fold':
        band = (2000, 6000)
        amp = 0.35
        att, dec = 0.001, 0.008
    elif style == 'slide':
        band = (400, 2500)
        amp = 0.20
        att, dec = 0.01, 0.04
    elif style == 'stamp':
        band = (100, 8000)
        amp = 0.45
        att, dec = 0.0005, 0.015
    else:  # fingertip
        band = (800, 3000)
        amp = 0.15
        att, dec = 0.003, 0.012

    noise = bandlimited_noise(n, low_hz=band[0], high_hz=band[1])
    out = []
    duration = n / RATE
    for i in range(n):
        t = i / RATE
        env = envelope(t, duration, attack=att, decay=dec)
        sample = noise[i] * amp * env
        if style == 'slide':
            sample *= math.sin(2.0 * math.pi * 4.0 * t)
        out.append(sample)
    return out


def paper_transients_sequence(duration: float, density: float = 8.0) -> list[float]:
    n_total = int(duration * RATE)
    out = [0.0] * n_total
    num_transients = int(duration * density)
    for _ in range(num_transients):
        r = RNG.random()
        if r < 0.4:
            style = 'fingertip'
        elif r < 0.7:
            style = 'slide'
        elif r < 0.9:
            style = 'fold'
        else:
            style = 'stamp'

        t_len = RNG.uniform(0.005, 0.030)
        n_trans = int(t_len * RATE)
        if n_trans == 0:
            continue

        start_idx = RNG.randint(0, max(0, n_total - n_trans - 1))
        trans = paper_transient(n_trans, style)
        for i in range(len(trans)):
            idx = start_idx + i
            if idx < n_total:
                out[idx] += trans[i]
    return out


def wow_flutter(phase: float, t: float, rate_hz: float = 0.8, depth: float = 0.003) -> float:
    return phase * (1.0 + depth * math.sin(2.0 * math.pi * rate_hz * t))


def tape_saturation(x: float, drive: float = 1.5, warmth: float = 0.3) -> float:
    driven = x * drive
    if driven >= 0:
        out = math.tanh(driven)
    else:
        out = math.tanh(driven * (1.0 + warmth))
    out += warmth * 0.1 * (driven * driven)
    return clamp(out, -1.0, 1.0)


def loudness_match(samples: list[float], target_rms: float = 0.15) -> list[float]:
    if not samples:
        return samples
    current_rms = math.sqrt(sum(x * x for x in samples) / len(samples))
    if current_rms < 0.0001:
        return samples
    gain = min(target_rms / current_rms, 4.0)
    return [clamp(x * gain, -1.0, 1.0) for x in samples]


def soft_compress(x: float, threshold: float = 0.55, ratio: float = 3.0) -> float:
    sign = -1.0 if x < 0 else 1.0
    level = abs(x)
    if level <= threshold:
        return x
    return sign * (threshold + (level - threshold) / ratio)


def render(duration: float, generator) -> list[float]:
    n = max(1, int(duration * RATE))
    samples = [generator(i / RATE, duration, i, n) for i in range(n)]
    peak = max(0.001, max(abs(x) for x in samples))
    # Leave headroom, then apply a gentle final compressor.
    gain = min(0.86 / peak, 1.0)
    return [soft_compress(clamp(x * gain), 0.58, 3.2) for x in samples]


def write_wav(path: Path, samples: list[float]) -> None:
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        frames = b"".join(struct.pack("<h", int(clamp(x) * 32767)) for x in samples)
        out.writeframes(frames)


def pitch_click(t: float, d: float, _i: int, _n: int) -> float:
    e = envelope(t, d, 0.001, 0.045, 0.0, 0.018)
    phase = 2.0 * math.pi * (1050.0 * t + 180.0 * t * t / d)
    paper = RNG.uniform(-1.0, 1.0) if t < 0.014 else 0.0
    return e * (0.72 * math.sin(phase) + 0.18 * paper)


def hover(t: float, d: float, _i: int, _n: int) -> float:
    e = envelope(t, d, 0.012, 0.08, 0.12, 0.05)
    phase = 2.0 * math.pi * (620.0 * t + 55.0 * t * t / d)
    hiss = RNG.uniform(-1.0, 1.0) * math.exp(-t * 65.0)
    return e * (0.55 * math.sin(phase) + 0.15 * hiss)


def confirm(t: float, d: float, _i: int, _n: int) -> float:
    e = envelope(t, d, 0.006, 0.12, 0.0, 0.1)
    f = 440.0 + 240.0 * min(1.0, t / d)
    return e * (0.55 * math.sin(2 * math.pi * f * t) + 0.16 * math.sin(2 * math.pi * f * 2.01 * t))


def back(t: float, d: float, _i: int, _n: int) -> float:
    e = envelope(t, d, 0.003, 0.16, 0.0, 0.08)
    f = 500.0 - 220.0 * min(1.0, t / d)
    return e * 0.65 * math.sin(2 * math.pi * f * t)


def toast(t: float, d: float, _i: int, _n: int) -> float:
    first = envelope(t, d, 0.004, 0.09, 0.0, 0.06) * math.sin(2 * math.pi * 523.25 * t)
    offset = max(0.0, t - 0.105)
    second = envelope(offset, d - 0.105, 0.004, 0.12, 0.0, 0.07) * math.sin(2 * math.pi * 783.99 * offset)
    return 0.43 * first + 0.34 * second


def transition(t: float, d: float, _i: int, _n: int) -> float:
    # Filtered paper sweep: rising radio noise with a soft low-frequency body.
    sweep = 180.0 + 2200.0 * (t / d) ** 1.8
    e = envelope(t, d, 0.012, 0.09, 0.25, 0.09)
    radio = RNG.uniform(-1.0, 1.0) * (0.55 + 0.45 * math.sin(2 * math.pi * 8.0 * t))
    body = math.sin(2 * math.pi * 90.0 * t) * 0.22
    return e * (0.18 * radio * math.sin(2 * math.pi * sweep * t) + body)


def warning(t: float, d: float, _i: int, _n: int) -> float:
    e = envelope(t, d, 0.004, 0.18, 0.12, 0.1)
    pulse = 0.5 + 0.5 * math.sin(2 * math.pi * 5.5 * t)
    return e * pulse * 0.55 * math.sin(2 * math.pi * 210.0 * t)


def paper_rustle(t: float, d: float, _i: int, _n: int) -> float:
    # Slowly changing paper texture, band-limited by low-passed noise.
    raw = RNG.uniform(-1.0, 1.0)
    e = envelope(t, d, 0.03, 0.22, 0.42, 0.18)
    modulation = 0.55 + 0.45 * math.sin(2 * math.pi * 3.1 * t + 0.7 * math.sin(t))
    return e * modulation * raw * 0.18


def space_noise(t: float, d: float, _i: int, _n: int) -> float:
    e = envelope(t, d, 0.8, 1.2, 0.38, 1.2)
    raw = RNG.uniform(-1.0, 1.0)
    drone = 0.10 * math.sin(2 * math.pi * 58.0 * t) + 0.045 * math.sin(2 * math.pi * 117.0 * t)
    return e * (0.12 * raw + drone)


def paper_rustle_v2(t: float, d: float, i: int, n: int) -> float:
    e = envelope(t, d, 0.04, 0.15, 0.35, 0.20)
    base = bandlimited_noise(1, 600, 3500)[0] * 0.12
    crinkle = 0.0
    if RNG.random() < 0.0008:
        crinkle = bandlimited_noise(1, 1500, 5000)[0] * 0.3
    wf_t = wow_flutter(t, t, 0.6, 0.002)
    modulation = 0.5 + 0.5 * math.sin(2 * math.pi * 2.8 * wf_t + 0.5 * math.sin(wf_t * 1.3))
    combined = (base + crinkle) * modulation
    sat = tape_saturation(combined, drive=1.2, warmth=0.15)
    return e * sat


def old_radio_hiss(t: float, d: float, i: int, n: int) -> float:
    e = envelope(t, d, 0.3, 0.8, 0.3, 0.5)
    phase = 2.0 * math.pi * 85.0 * t
    mod_phase = wow_flutter(phase, t, 1.2, 0.004)
    drone = math.sin(mod_phase) + 0.5 * math.sin(mod_phase * 2.0) + 0.25 * math.sin(mod_phase * 3.0)
    noise = bandlimited_noise(1, 200, 2000)[0]
    crackle = 0.0
    if RNG.random() < 0.0003:
        crackle = RNG.uniform(-0.5, 0.5)
    mixed = 0.4 * drone + 0.15 * noise + crackle
    sat = tape_saturation(mixed, drive=1.8, warmth=0.25)
    return e * sat


SOUNDS = {
    "ui_click": (0.085, pitch_click),
    "ui_hover": (0.18, hover),
    "ui_confirm": (0.34, confirm),
    "ui_back": (0.28, back),
    "toast_note": (0.30, toast),
    "menu_transition": (0.52, transition),
    "warning": (0.42, warning),
    "paper_rustle": (0.72, paper_rustle),
    "space_noise": (4.0, space_noise),
    "paper_rustle_v2": (0.85, paper_rustle_v2),
    "old_radio_hiss": (3.5, old_radio_hiss),
}


def convert_to_ogg(wav_path: Path, ogg_path: Path) -> bool:
    if shutil.which("ffmpeg") is None:
        return False
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", str(wav_path), "-c:a", "libvorbis", "-q:a", "4", str(ogg_path)],
        capture_output=True,
        text=True,
    )
    return result.returncode == 0 and ogg_path.exists()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", default="assets/audio/sfx")
    parser.add_argument("--format", choices=("wav", "ogg", "both"), default="ogg")
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Generating {len(SOUNDS)} SnipWar paper/scifi sounds in {output_dir}/")

    for name, (duration, generator) in SOUNDS.items():
        wav_path = output_dir / f"{name}.wav"
        ogg_path = output_dir / f"{name}.ogg"
        write_wav(wav_path, render(duration, generator))
        made = [wav_path.name]
        if args.format in ("ogg", "both") and convert_to_ogg(wav_path, ogg_path):
            made.append(ogg_path.name)
        if args.format == "ogg" and ogg_path.exists():
            wav_path.unlink()
        print("  OK  " + ", ".join(made))


if __name__ == "__main__":
    main()
