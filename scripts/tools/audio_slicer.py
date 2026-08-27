#!/usr/bin/env python3
"""
Audio Palette Slicer — schneidet einen langen Track in kleine OGG-Assets.

Verwendung:
    python audio_slicer.py slices.json
    python audio_slicer.py slices.json --output-dir assets/audio/sfx
    python audio_slicer.py slices.json --dry-run

slices.json Format:
{
  "source": "sound_palette.mp3",
  "output_dir": "assets/audio/sfx",
  "fade_ms": 150,
  "slices": [
    {"name": "ui_click",     "start": "0:00", "end": "0:05"},
    {"name": "battle_intro", "start": "0:20", "end": "0:35", "fade_in_ms": 300}
  ]
}
"""

import json
import subprocess
import sys
import os
from pathlib import Path

def time_to_seconds(t: str) -> float:
    """Convert 'M:SS' or 'MM:SS' or seconds float to float seconds."""
    if ":" in t:
        parts = t.split(":")
        return int(parts[0]) * 60 + float(parts[1])
    return float(t)

def slice_audio(source: str, name: str, start: str, end: str,
                output_dir: str, fade_ms: int = 150,
                fade_in_ms: int | None = None, dry_run: bool = False) -> str:
    """Cut a slice from source, apply fade, output as OGG."""
    start_s = time_to_seconds(start)
    end_s = time_to_seconds(end)
    duration = end_s - start_s

    if duration <= 0:
        print(f"  SKIP {name}: duration {duration}s <= 0")
        return ""

    output_path = os.path.join(output_dir, f"{name}.ogg")

    # Build ffmpeg filter chain
    filters = []
    fi = fade_in_ms if fade_in_ms is not None else fade_ms
    fo = fade_ms
    if fi > 0 and duration > (fi * 2) / 1000:
        filters.append(f"afade=t=in:st=0:d={fi / 1000}")
    if fo > 0 and duration > (fo * 2) / 1000:
        fade_start = max(0, duration - fo / 1000)
        filters.append(f"afade=t=out:st={fade_start}:d={fo / 1000}")

    cmd = [
        "ffmpeg", "-y",
        "-i", source,
        "-ss", str(start_s),
        "-t", str(duration),
    ]
    if filters:
        cmd += ["-af", ",".join(filters)]
    cmd += [
        "-c:a", "libvorbis",
        "-q:a", "4",
        output_path
    ]

    if dry_run:
        print(f"  DRY: {' '.join(cmd)}")
        return output_path

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  ERROR {name}: {result.stderr[-200:]}")
        return ""

    # Get file size
    size_kb = os.path.getsize(output_path) / 1024
    print(f"  OK   {name}.ogg  ({duration:.1f}s, {size_kb:.0f}KB)")
    return output_path


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    config_path = sys.argv[1]
    dry_run = "--dry-run" in sys.argv

    # Parse --output-dir override
    output_dir_override = None
    for i, arg in enumerate(sys.argv):
        if arg == "--output-dir" and i + 1 < len(sys.argv):
            output_dir_override = sys.argv[i + 1]

    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)

    source = config["source"]
    output_dir = output_dir_override or config.get("output_dir", "assets/audio/sfx")
    fade_ms = config.get("fade_ms", 150)
    slices = config.get("slices", [])

    if not os.path.isfile(source):
        print(f"ERROR: Source file not found: {source}")
        sys.exit(1)

    os.makedirs(output_dir, exist_ok=True)

    print(f"Source:  {source}")
    print(f"Output:  {output_dir}/")
    print(f"Fade:    {fade_ms}ms")
    print(f"Slices:  {len(slices)}")
    print()

    success = 0
    for s in slices:
        fi = s.get("fade_in_ms")
        result = slice_audio(
            source=source,
            name=s["name"],
            start=s["start"],
            end=s["end"],
            output_dir=output_dir,
            fade_ms=s.get("fade_ms", fade_ms),
            fade_in_ms=fi,
            dry_run=dry_run,
        )
        if result:
            success += 1

    print(f"\nDone: {success}/{len(slices)} slices created.")


if __name__ == "__main__":
    main()
