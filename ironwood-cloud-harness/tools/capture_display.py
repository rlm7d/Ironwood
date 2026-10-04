#!/usr/bin/env python3
"""Capture real frames or a short video from the authenticated harness display.

Outputs must stay under the harness directory and existing files are preserved.
No browser protocol, offline renderer, or game test hooks are used.
"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DISPLAY = ":97"
AUTH = ROOT / "runtime" / "Xauthority"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=["frame", "record"])
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--duration", type=float, default=3)
    parser.add_argument("--fps", type=int, default=12)
    args = parser.parse_args()
    output = args.out.resolve()
    if not output.is_relative_to(ROOT):
        parser.error("Output must be inside /workspace/ironwood-cloud-harness.")
    metadata_file = output.with_suffix(output.suffix + ".json")
    if output.exists() or metadata_file.exists():
        parser.error("Output exists; use a new evidence filename.")
    if not (0 < args.duration <= 60 and 1 <= args.fps <= 60):
        parser.error("Duration must be at most 60 seconds; fps must be 1–60.")
    if args.kind == "frame" and output.suffix.lower() != ".png":
        parser.error("Frame output must end in .png.")
    if args.kind == "record" and output.suffix.lower() != ".mp4":
        parser.error("Recording output must end in .mp4.")
    environment = dict(os.environ, DISPLAY=DISPLAY, XAUTHORITY=str(AUTH))
    geometry = subprocess.run(["xwininfo", "-display", DISPLAY, "-root"],
                              env=environment, capture_output=True, text=True, check=True)
    width = int(re.search(r"Width:\s+(\d+)", geometry.stdout).group(1))
    height = int(re.search(r"Height:\s+(\d+)", geometry.stdout).group(1))
    output.parent.mkdir(parents=True, exist_ok=True)
    command = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "warning", "-n",
               "-f", "x11grab", "-draw_mouse", "1", "-framerate", str(args.fps),
               "-video_size", f"{width}x{height}", "-i", DISPLAY + ".0"]
    if args.kind == "frame":
        command += ["-frames:v", "1", "-update", "1", str(output)]
    else:
        # yuv420p/H.264 needs even dimensions; pad the real capture if needed.
        command += ["-t", str(args.duration), "-an", "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2",
                    "-c:v", "libx264", "-preset", "ultrafast", "-crf", "20",
                    "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(output)]
    started = dt.datetime.now(dt.timezone.utc).isoformat()
    captured = subprocess.run(command, env=environment, capture_output=True, text=True,
                              timeout=args.duration + 30)
    metadata = {"started_at": started, "completed_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                "display": DISPLAY, "source": "ffmpeg-x11grab", "kind": args.kind,
                "size": [width, height], "fps": args.fps,
                "duration_requested": args.duration if args.kind == "record" else None,
                "output": str(output), "exit_code": captured.returncode,
                "stderr": captured.stderr, "command": command}
    if output.exists():
        metadata["bytes"] = output.stat().st_size
    metadata_file.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    if captured.returncode != 0:
        raise SystemExit(f"Capture failed; inspect {metadata_file}.")
    print(json.dumps(metadata))


if __name__ == "__main__":
    main()
