# Local display input and capture

These helpers operate only on the authenticated disposable display `:97`, using
`runtime/Xauthority`. They do not print the authentication cookie. Start the
display with `start_display.py` first. They need the installed runtime libraries
`libX11.so.6`, `libXtst.so.6`, FFmpeg, and `xwininfo`; no extra Python packages or
proprietary computer-use SDK are required.

Inspect window identifiers and exact titles:

```sh
DISPLAY=:97 XAUTHORITY=/workspace/ironwood-cloud-harness/runtime/Xauthority xwininfo -root -tree
```

Query and move the real pointer:

```sh
python tools/desktop_input.py pointer
python tools/desktop_input.py move 100 100
```

Send a click or key to a known window. Replace the example identifier and title
with those of a window belonging to this harness. Click coordinates are relative
to the window's content; motion coordinates are relative to the whole display.
Keys use X11 key symbols, such as `space`, `Return`, `Left`, and `a`.

```sh
python tools/desktop_input.py click --window 0x400001 --title 'Ironwood Harness Input Probe' 120 120
python tools/desktop_input.py key --window 0x400001 --title 'Ironwood Harness Input Probe' a --modifiers shift
python tools/desktop_input.py key --window 0x400001 --title 'Ironwood Harness Input Probe' Right --duration 0.5
```

Keyboard and click operations check the exact title, raise only that window,
and focus it. Pressed buttons and keys are released even when an operation is
interrupted. Completed actions are timestamped in `logs/desktop-events.jsonl`.
Do not type secrets through a logged input helper.

Capture the actual running desktop or a short recording. Use a new filename each
time; existing evidence files are preserved.

```sh
python tools/capture_display.py frame --out /workspace/ironwood-cloud-harness/evidence/example.png
python tools/capture_display.py record --duration 4 --fps 12 --out /workspace/ironwood-cloud-harness/evidence/example.mp4
```

Each capture has a matching JSON metadata file containing timestamps, command,
dimensions, and FFmpeg diagnostics. The shell sandbox currently denies FFmpeg's
MIT-SHM capture path; FFmpeg falls back to ordinary X11 capture successfully.
This fallback is preserved in the diagnostics.

## Verified baseline

The harness's private `xev` probe received real XTEST button press/release,
lowercase `a`, and Shift+`a` (`A`) key events. Pointer coordinates were checked
through `XQueryPointer`. The probe was stopped after verification. Evidence:

- `evidence/input-probe-checks.json`
- `logs/input-probe-xev.log`
- `logs/desktop-events.jsonl`
- `evidence/input-probe.mp4`: 4 seconds, 48 frames at 12 fps, 1364 by 1024
- `evidence/input-probe-video-metadata.json`
- `evidence/input-baseline-before.png` and `evidence/input-probe-after.png`

This establishes a generic OS input and real display capture baseline. It does
not establish game animation, browser gameplay, networking, multiplayer behavior,
human feedback, or passage of the requested Gate 0.
