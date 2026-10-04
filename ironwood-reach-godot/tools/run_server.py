#!/usr/bin/env python3
"""Start/reuse the owned authoritative Godot process on loopback port 8775."""
import argparse
import json
import socket
from tool_runtime import GAME, ensure_service, godot_binary, godot_environment, stop_owned_service, wait_for_port_release


def ready():
    with socket.create_connection(("127.0.0.1", 8775), timeout=1):
        pass  # Transport baseline only; no WebSocket seat or game command is sent.
    return {"tcp_reachable": True, "scope": "transport baseline; browser join/gameplay proof is separate"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reuse-only", action="store_true")
    lifecycle = parser.add_mutually_exclusive_group()
    lifecycle.add_argument("--stop-owned", action="store_true", help="SIGTERM only the verified owned authority")
    lifecycle.add_argument("--restart-owned", action="store_true", help="Discard the current in-memory trial and start a new owned authority")
    args = parser.parse_args()
    environment = godot_environment()
    godot = godot_binary(environment)
    if not (GAME / "scripts/server/session_server.gd").is_file():
        raise RuntimeError("Authoritative server source has not been created yet.")
    command = [godot, "--headless", "--path", str(GAME), "--", "--server"]
    if args.reuse_only and (args.stop_owned or args.restart_owned):
        parser.error("--reuse-only cannot be combined with a lifecycle change.")
    if args.stop_owned or args.restart_owned:
        stopped = stop_owned_service("authority", command, 8775)
        if args.stop_owned:
            print(json.dumps(stopped))
            return
        print(json.dumps(stopped), flush=True)
        if stopped["status"] in ("stopped", "owned_process_exited"):
            print(json.dumps({"port_release": wait_for_port_release(8775)}), flush=True)
    print(json.dumps(ensure_service("authority", command, 8775, ready,
                                   environment=environment, reuse_only=args.reuse_only)))


if __name__ == "__main__":
    main()
