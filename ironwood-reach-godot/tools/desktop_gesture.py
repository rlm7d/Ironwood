#!/usr/bin/env python3
"""Guarded XTEST drag/modified-click for the existing cloud display.

No browser or game API is used. This requires the separate installed harness.
"""
import argparse
import ctypes as C
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import time

HARNESS = Path('/workspace/ironwood-cloud-harness')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['drag', 'click'])
    parser.add_argument('--window', required=True, type=lambda value: int(value, 0))
    parser.add_argument('--title', required=True)
    parser.add_argument('--from', dest='start', nargs=2, type=int, required=True)
    parser.add_argument('--to', dest='end', nargs=2, type=int)
    parser.add_argument('--button', type=int, choices=range(1, 8), default=1)
    parser.add_argument('--shift', action='store_true')
    parser.add_argument('--duration', type=float, default=0.6)
    args = parser.parse_args()
    if not 0.05 <= args.duration <= 3:
        parser.error('Gesture duration must be between 0.05 and 3 seconds.')
    if args.action == 'drag' and args.end is None:
        parser.error('A drag requires --to X Y.')
    spec = importlib.util.spec_from_file_location('ironwood_desktop', HARNESS / 'tools/desktop_input.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    trace = module.TRACE
    if trace.is_symlink() or (trace.exists() and trace.stat().st_uid != os.getuid()):
        raise RuntimeError('Preserving unexpected desktop input trace.')
    desktop = module.Desktop()
    started = datetime.now(timezone.utc).isoformat()
    shift_code = None
    button_down = False
    try:
        desktop.focus(args.window, args.title)
        root, x, y = C.c_ulong(), C.c_int(), C.c_int()
        width, height, border, depth = [C.c_uint() for _ in range(4)]
        if not desktop.x.XGetGeometry(desktop.d, args.window, C.byref(root), C.byref(x), C.byref(y), C.byref(width), C.byref(height), C.byref(border), C.byref(depth)):
            raise RuntimeError('Cannot inspect the guarded target geometry.')
        def screen(point):
            if not (0 <= point[0] < width.value and 0 <= point[1] < height.value):
                raise ValueError('Gesture coordinates exceed the target window.')
            rx, ry, child = C.c_int(), C.c_int(), C.c_ulong()
            if not desktop.x.XTranslateCoordinates(desktop.d, args.window, desktop.root, point[0], point[1], C.byref(rx), C.byref(ry), C.byref(child)):
                raise RuntimeError('Cannot translate target coordinates.')
            return rx.value, ry.value
        start = screen(args.start)
        end = screen(args.end) if args.end else start
        if args.shift:
            shift_code = desktop.x.XKeysymToKeycode(desktop.d, desktop.x.XStringToKeysym(b'Shift_L'))
            if not shift_code:
                raise RuntimeError('Shift key is unmapped.')
            desktop.t.XTestFakeKeyEvent(desktop.d, shift_code, 1, 0)
        desktop.move(*start)
        desktop.t.XTestFakeButtonEvent(desktop.d, args.button, 1, 0)
        button_down = True
        desktop.sync()
        for step in range(1, 13):
            time.sleep(args.duration / 12)
            desktop.move(round(start[0] + (end[0] - start[0]) * step / 12), round(start[1] + (end[1] - start[1]) * step / 12))
        desktop.t.XTestFakeButtonEvent(desktop.d, args.button, 0, 0)
        button_down = False
        desktop.sync()
        event = {'started_at': started, 'completed_at': datetime.now(timezone.utc).isoformat(),
                 'display': ':97', 'source': 'XTEST', 'action': args.action + '_gesture', 'arguments': vars(args)}
        with trace.open('a') as stream:
            stream.write(json.dumps(event) + '\n')
        print(json.dumps(event))
    finally:
        if button_down:
            desktop.t.XTestFakeButtonEvent(desktop.d, args.button, 0, 0)
        if shift_code:
            desktop.t.XTestFakeKeyEvent(desktop.d, shift_code, 0, 0)
        desktop.close()


if __name__ == '__main__':
    main()
