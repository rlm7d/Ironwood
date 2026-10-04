#!/usr/bin/env python3
"""Send OS-level input only to this harness's authenticated X11 display.

Uses the XTEST extension, not a browser protocol or an application test hook.
Keyboard, clicks, and focus require an exact window title to guard the target.
Every completed action appends a timestamped JSON event to logs/desktop-events.jsonl.
"""
import argparse
import ctypes as C
import datetime as dt
import json
import os
from pathlib import Path
import time

ROOT = Path(__file__).resolve().parents[1]
DISPLAY = ":97"
AUTH = ROOT / "runtime" / "Xauthority"
TRACE = ROOT / "logs" / "desktop-events.jsonl"


def bind(lib, name, result, *args):
    fn = getattr(lib, name)
    fn.restype = result
    fn.argtypes = list(args)
    return fn


class Desktop:
    def __init__(self):
        # This process deliberately ignores inherited DISPLAY/XAUTHORITY values.
        os.environ["DISPLAY"] = DISPLAY
        os.environ["XAUTHORITY"] = str(AUTH)
        self.x = C.CDLL("libX11.so.6")
        self.t = C.CDLL("libXtst.so.6")
        p, w, i, u = C.c_void_p, C.c_ulong, C.c_int, C.c_uint
        bind(self.x, "XOpenDisplay", p, C.c_char_p)
        bind(self.x, "XCloseDisplay", i, p)
        bind(self.x, "XDefaultScreen", i, p)
        bind(self.x, "XRootWindow", w, p, i)
        bind(self.x, "XDisplayWidth", i, p, i)
        bind(self.x, "XDisplayHeight", i, p, i)
        bind(self.x, "XSync", i, p, i)
        bind(self.x, "XFetchName", i, p, w, C.POINTER(p))
        bind(self.x, "XInternAtom", w, p, C.c_char_p, i)
        bind(self.x, "XGetWindowProperty", i, p, w, w, C.c_long, C.c_long,
             i, w, C.POINTER(w), C.POINTER(i), C.POINTER(w), C.POINTER(w), C.POINTER(p))
        bind(self.x, "XFree", i, p)
        bind(self.x, "XRaiseWindow", i, p, w)
        bind(self.x, "XSetInputFocus", i, p, w, i, w)
        bind(self.x, "XStringToKeysym", w, C.c_char_p)
        bind(self.x, "XKeysymToKeycode", C.c_ubyte, p, w)
        bind(self.x, "XGetGeometry", i, p, w, C.POINTER(w),
             C.POINTER(i), C.POINTER(i), C.POINTER(u), C.POINTER(u),
             C.POINTER(u), C.POINTER(u))
        bind(self.x, "XTranslateCoordinates", i, p, w, w, i, i,
             C.POINTER(i), C.POINTER(i), C.POINTER(w))
        bind(self.x, "XQueryPointer", i, p, w, C.POINTER(w), C.POINTER(w),
             C.POINTER(i), C.POINTER(i), C.POINTER(i), C.POINTER(i), C.POINTER(u))
        bind(self.t, "XTestQueryExtension", i, p, C.POINTER(i), C.POINTER(i),
             C.POINTER(i), C.POINTER(i))
        bind(self.t, "XTestFakeMotionEvent", i, p, i, i, i, w)
        bind(self.t, "XTestFakeButtonEvent", i, p, u, i, w)
        bind(self.t, "XTestFakeKeyEvent", i, p, u, i, w)
        self.d = self.x.XOpenDisplay(DISPLAY.encode())
        if not self.d:
            raise RuntimeError("Cannot open the harness's authenticated X11 display :97.")
        self.screen = self.x.XDefaultScreen(self.d)
        self.root = self.x.XRootWindow(self.d, self.screen)
        values = [i() for _ in range(4)]
        if not self.t.XTestQueryExtension(self.d, *(C.byref(v) for v in values)):
            self.close()
            raise RuntimeError("XTEST input extension is unavailable on :97.")

    def close(self):
        if self.d:
            self.x.XSync(self.d, 0)
            self.x.XCloseDisplay(self.d)
            self.d = None

    def sync(self):
        self.x.XSync(self.d, 0)

    def size(self):
        return [self.x.XDisplayWidth(self.d, self.screen),
                self.x.XDisplayHeight(self.d, self.screen)]

    def pointer(self):
        root, child = C.c_ulong(), C.c_ulong()
        rx, ry, wx, wy = [C.c_int() for _ in range(4)]
        mask = C.c_uint()
        if not self.x.XQueryPointer(self.d, self.root, C.byref(root), C.byref(child),
                                   C.byref(rx), C.byref(ry), C.byref(wx), C.byref(wy),
                                   C.byref(mask)):
            raise RuntimeError("Pointer query failed.")
        return {"x": rx.value, "y": ry.value, "buttons_and_modifiers": mask.value,
                "window": hex(child.value)}

    def check_window(self, window, expected_title):
        name = C.c_void_p()
        if self.x.XFetchName(self.d, window, C.byref(name)) and name.value:
            try:
                actual = C.string_at(name.value).decode("utf-8", "replace")
            finally:
                self.x.XFree(name)
        else:
            # Chromium uses the UTF-8 EWMH title instead of legacy WM_NAME.
            atom = self.x.XInternAtom(self.d, b"_NET_WM_NAME", 1)
            actual_type, count, remaining = C.c_ulong(), C.c_ulong(), C.c_ulong()
            form = C.c_int()
            data = C.c_void_p()
            result = self.x.XGetWindowProperty(self.d, window, atom, 0, 4096, 0, 0,
                C.byref(actual_type), C.byref(form), C.byref(count), C.byref(remaining), C.byref(data))
            if result != 0 or not data.value or form.value != 8:
                if data.value:
                    self.x.XFree(data)
                raise RuntimeError("Target window has no retrievable X11 title.")
            try:
                actual = C.string_at(data.value, count.value).decode("utf-8", "replace")
            finally:
                self.x.XFree(data)
        if actual != expected_title:
            raise RuntimeError(f"Window title mismatch: expected {expected_title!r}, found {actual!r}.")
        return actual

    def focus(self, window, expected_title):
        self.check_window(window, expected_title)
        self.x.XRaiseWindow(self.d, window)
        self.x.XSetInputFocus(self.d, window, 1, 0)  # RevertToPointerRoot, CurrentTime.
        self.sync()

    def move(self, x, y):
        width, height = self.size()
        if not (0 <= x < width and 0 <= y < height):
            raise ValueError(f"Pointer coordinates exceed the {width}x{height} harness display.")
        if not self.t.XTestFakeMotionEvent(self.d, self.screen, x, y, 0):
            raise RuntimeError("XTEST motion failed.")
        self.sync()
        actual = self.pointer()
        if (actual["x"], actual["y"]) != (x, y):
            raise RuntimeError(f"Pointer verification failed: {actual}")
        return actual

    def click(self, window, title, x, y, button):
        self.focus(window, title)
        root, gx, gy = C.c_ulong(), C.c_int(), C.c_int()
        width, height, border, depth = [C.c_uint() for _ in range(4)]
        if not self.x.XGetGeometry(self.d, window, C.byref(root), C.byref(gx), C.byref(gy),
                                  C.byref(width), C.byref(height), C.byref(border), C.byref(depth)):
            raise RuntimeError("Target geometry query failed.")
        if not (0 <= x < width.value and 0 <= y < height.value):
            raise ValueError("Click coordinates exceed the target window.")
        rx, ry, child = C.c_int(), C.c_int(), C.c_ulong()
        if not self.x.XTranslateCoordinates(self.d, window, self.root, x, y,
                                            C.byref(rx), C.byref(ry), C.byref(child)):
            raise RuntimeError("Target coordinate translation failed.")
        pointer = self.move(rx.value, ry.value)
        self.t.XTestFakeButtonEvent(self.d, button, 1, 0)
        try:
            self.sync()
            time.sleep(0.06)
        finally:
            self.t.XTestFakeButtonEvent(self.d, button, 0, 0)
            self.sync()
        return pointer

    def key(self, window, title, keysym, modifiers, duration):
        self.focus(window, title)
        aliases = {"shift": "Shift_L", "ctrl": "Control_L", "alt": "Alt_L", "super": "Super_L"}
        names = [aliases[m] for m in modifiers] + [keysym]
        codes = []
        for name in names:
            sym = self.x.XStringToKeysym(name.encode("ascii"))
            code = self.x.XKeysymToKeycode(self.d, sym) if sym else 0
            if not code:
                raise ValueError(f"Unknown/unmapped key symbol: {name!r}.")
            codes.append(code)
        pressed = []
        try:
            for code in codes:
                self.t.XTestFakeKeyEvent(self.d, code, 1, 0)
                pressed.append(code)
            self.sync()
            time.sleep(duration)
        finally:
            for code in reversed(pressed):
                self.t.XTestFakeKeyEvent(self.d, code, 0, 0)
            self.sync()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("pointer")
    motion = sub.add_parser("move")
    motion.add_argument("x", type=int)
    motion.add_argument("y", type=int)
    for action in ["focus", "click", "key"]:
        command = sub.add_parser(action)
        command.add_argument("--window", required=True, type=lambda v: int(v, 0))
        command.add_argument("--title", required=True)
        if action == "click":
            command.add_argument("x", type=int)
            command.add_argument("y", type=int)
            command.add_argument("--button", type=int, choices=range(1, 8), default=1)
        if action == "key":
            command.add_argument("keysym")
            command.add_argument("--modifiers", nargs="*", choices=["shift", "ctrl", "alt", "super"], default=[])
            command.add_argument("--duration", type=float, default=0.08)
    args = parser.parse_args()
    if args.action == "key" and not (0 <= args.duration <= 10):
        parser.error("Key duration must be between 0 and 10 seconds.")
    desktop = Desktop()
    started = dt.datetime.now(dt.timezone.utc).isoformat()
    try:
        if args.action == "pointer":
            result = desktop.pointer()
        elif args.action == "move":
            result = desktop.move(args.x, args.y)
        elif args.action == "focus":
            desktop.focus(args.window, args.title)
            result = {"window": hex(args.window), "title": args.title}
        elif args.action == "click":
            result = desktop.click(args.window, args.title, args.x, args.y, args.button)
        else:
            desktop.key(args.window, args.title, args.keysym, args.modifiers, args.duration)
            result = {"keysym": args.keysym, "modifiers": args.modifiers, "duration": args.duration}
        event = {"started_at": started, "completed_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                 "display": DISPLAY, "source": "XTEST", "action": args.action,
                 "arguments": vars(args), "result": result}
        TRACE.parent.mkdir(exist_ok=True)
        with TRACE.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(event) + "\n")
        print(json.dumps(event))
    finally:
        desktop.close()


if __name__ == "__main__":
    main()
