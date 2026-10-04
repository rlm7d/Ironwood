#!/usr/bin/env python3
"""Start/reuse only the owned loopback candidate HTTP server on port 9088."""
import argparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
import urllib.request
import urllib.parse
from tool_runtime import BUILDS, OWNER, ROOT, ensure_service, sha256

PORT = 9088


class CandidateHandler(SimpleHTTPRequestHandler):
    extensions_map = dict(SimpleHTTPRequestHandler.extensions_map, **{".wasm": "application/wasm", ".js": "text/javascript"})

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(BUILDS), **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def list_directory(self, path):
        self.send_error(403, "Candidate directory listing is disabled")
        return None

    def translate_path(self, path):
        candidate = Path(super().translate_path(path))
        try:
            relative = candidate.relative_to(BUILDS)
            current = BUILDS
            if current.is_symlink():
                return str(BUILDS / "__blocked_symlink__")
            for component in relative.parts:
                current = current / component
                if current.is_symlink():
                    return str(BUILDS / "__blocked_symlink__")
            if not candidate.resolve().is_relative_to(BUILDS.resolve()):
                return str(BUILDS / "__blocked_path__")
        except ValueError:
            return str(BUILDS / "__blocked_path__")
        return str(candidate)

    def do_GET(self):
        if self.path == "/__ironwood_health":
            data = json.dumps({"owner": OWNER, "service": "candidate-http", "port": PORT}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        super().do_GET()


def ready(build=None):
    base = f"http://127.0.0.1:{PORT}"
    with urllib.request.urlopen(base + "/__ironwood_health", timeout=2) as response:
        state = json.loads(response.read())
    if state != {"owner": OWNER, "service": "candidate-http", "port": PORT}:
        raise RuntimeError("HTTP port does not serve our candidate service.")
    result = {"http_health": True, "loopback_only": True}
    if build:
        entry = BUILDS / build / "index.html"
        if not entry.is_file():
            raise RuntimeError(f"Candidate {build!r} has not been built.")
        with urllib.request.urlopen(base + f"/{build}/index.html", timeout=5) as response:
            import hashlib
            if hashlib.sha256(response.read()).hexdigest() != sha256(entry):
                raise RuntimeError("Served HTML differs from the local candidate.")
            cache = response.headers.get("Cache-Control")
        with urllib.request.urlopen(base + f"/{build}/index.wasm", timeout=5) as response:
            if response.headers.get_content_type() != "application/wasm":
                raise RuntimeError("WASM MIME is incorrect.")
            digest = hashlib.sha256()
            magic = b""
            while block := response.read(1024 * 1024):
                if not magic:
                    magic = block[:4]
                digest.update(block)
        if magic != b"\x00asm" or digest.hexdigest() != sha256(BUILDS / build / "index.wasm"):
            raise RuntimeError("Served WASM differs from the local candidate.")
        if cache != "no-store, max-age=0":
            raise RuntimeError("Candidate cache header is not the expected no-store policy.")
        result.update({"entry": base + f"/{build}/index.html", "index_matches_export": True,
                       "wasm_matches_export": True, "wasm_mime": "application/wasm", "cache": cache})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--foreground", action="store_true")
    parser.add_argument("--build")
    parser.add_argument("--reuse-only", action="store_true")
    args = parser.parse_args()
    if args.build and (not args.build.replace("-", "").replace("_", "").isalnum()):
        parser.error("Build identifier must be letters, numbers, dash, or underscore.")
    if args.foreground:
        if args.build or args.reuse_only:
            parser.error("--foreground has no launcher options.")
        with ThreadingHTTPServer(("127.0.0.1", PORT), CandidateHandler) as server:
            print(json.dumps({"status": "listening", "host": "127.0.0.1", "port": PORT}), flush=True)
            server.serve_forever()
    else:
        command = [str(Path(sys.executable).resolve()), str(Path(__file__).resolve()), "--foreground"]
        print(json.dumps(ensure_service("http", command, PORT, lambda: ready(args.build), reuse_only=args.reuse_only)))


if __name__ == "__main__":
    main()
