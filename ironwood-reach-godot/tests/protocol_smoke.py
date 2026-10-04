#!/usr/bin/env python3
"""Actual loopback WebSocket regression for a freshly started native authority.

This is automated protocol validation, not browser interaction or human feedback.
Reconnect credentials exist only in memory and are never included in evidence.
Run on a fresh room, then restart the authority before interactive approval play.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import time
from urllib.parse import urlsplit

from websockets.sync.client import connect


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def current_build_id():
    rules = Path(__file__).resolve().parents[1] / "game/scripts/shared/rules.gd"
    match = re.search(r'^\s*const\s+BUILD_ID\s*(?::\s*String\s*)?(?::=|=)\s*"([A-Za-z0-9_-]{1,64})"\s*$',
                      rules.read_text(), re.MULTILINE)
    require(match is not None, "Shared rules must declare a literal build ID, or supply --build explicitly")
    return match.group(1)


class Client:
    def __init__(self, url, role, build, token=""):
        self.ws = connect(url, open_timeout=5, close_timeout=2, max_size=262144)
        self.role = role
        self.token = token
        self.sequence = 0
        self.revision = 0
        self.ws.send(json.dumps({"type": "join", "protocol": 1, "build_id": build,
                                 "room": "REACH-01", "role": role, "token": token}))
        welcome = self.receive(lambda packet: packet.get("type") in ("welcome", "error"))
        require(welcome.get("type") == "welcome", "Expected seat join acceptance")
        self.token = welcome["token"]
        self.sequence = welcome["sequence"]
        self.connection_id = welcome["connection_id"]
        self.resumed = welcome["resumed"]
        self.snapshot()

    def receive(self, predicate, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            packet = json.loads(self.ws.recv(timeout=max(0.001, deadline - time.monotonic())))
            if packet.get("type") == "snapshot":
                self.revision = packet["revision"]
            if predicate(packet):
                return packet
        raise TimeoutError("Expected protocol response did not arrive")

    def snapshot(self, predicate=lambda packet: True):
        return self.receive(lambda packet: packet.get("type") == "snapshot" and predicate(packet))

    def command(self, payload, expected_revision=None):
        self.sequence += 1
        command = {"type": "command", "seq": self.sequence,
                   "expected_revision": self.revision if expected_revision is None else expected_revision,
                   "payload": payload}
        self.ws.send(json.dumps(command, allow_nan=False))
        result = self.receive(lambda packet: packet.get("type") == "result" and packet.get("seq") == self.sequence)
        self.revision = max(self.revision, result["revision"])
        return command, result

    def close(self):
        self.ws.close()


def rejection(url, message, code):
    with connect(url, open_timeout=5, close_timeout=2, max_size=262144) as ws:
        ws.send(message if isinstance(message, (str, bytes)) else json.dumps(message))
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            packet = json.loads(ws.recv(timeout=max(0.001, deadline - time.monotonic())))
            if packet.get("type") == "error":
                require(packet.get("code") == code, f"Expected rejection code {code}")
                return
        raise TimeoutError("Expected protocol rejection did not arrive")


def run(args):
    results = []
    clients = []

    def passed(name, details=None):
        entry = {"check": name, "status": "PASS"}
        if details:
            entry.update(details)
        results.append(entry)
        print(json.dumps(entry), flush=True)

    join = {"type": "join", "protocol": 1, "build_id": args.build,
            "room": "REACH-01", "role": "Builder", "token": ""}
    rejection(args.url, dict(join, protocol=2), "protocol_mismatch")
    rejection(args.url, dict(join, build_id="wrong-candidate"), "build_mismatch")
    rejection(args.url, dict(join, room="OTHER"), "unknown_room")
    passed("join_version_and_room_rejections")
    builder = Client(args.url, "Builder", args.build)
    general = Client(args.url, "General", args.build)
    clients.extend((builder, general))
    require(builder.connection_id != general.connection_id, "Connections must be independent")
    require(builder.sequence == general.sequence == 0, "Protocol test requires a fresh room")
    rejection(args.url, join, "seat_occupied")
    rejection(args.url, dict(join, token=builder.token), "seat_occupied")
    passed("independent_roles_and_takeover_rejection")
    try:
        builder.command({"action": "ready", "value": True})
        general.command({"action": "ready", "value": True})
        initial = builder.snapshot(lambda packet: packet["status"] == "playing")
        unit_id = next(unit["id"] for unit in initial["units"] if unit["team"] == "ally")
        _, denied_builder = builder.command({"action": "order", "units": [unit_id], "mode": "stop"})
        _, denied_general = general.command({"action": "reserve", "kind": "tower", "socket": 0})
        require(not denied_builder["ok"] and not denied_general["ok"], "Wrong-role commands must fail")
        passed("server_bound_role_permissions")

        _, builder_reservation = builder.command({"action": "reserve", "kind": "tower", "socket": 0})
        _, general_reservation = general.command({"action": "reserve", "kind": "footmen", "building": "ally_barracks"})
        require(builder_reservation["ok"] and general_reservation["ok"], "Both reservations should fit initial treasury")
        reserved = builder.snapshot(lambda packet: len(packet["reservations"]) == 2)
        require(reserved["gold"] >= reserved["reserved_gold"] >= 0, "Reserved treasury must remain solvent")
        require(reserved["available_gold"] == reserved["gold"] - reserved["reserved_gold"], "Available treasury accounting")
        expected_spend = reserved["spent"] + sum(item["cost"] for item in reserved["reservations"].values())
        passed("shared_treasury_reservations", {"reservation_count": 2})

        # The application sends a purchase confirmation, then intentionally never
        # consumes its result. WebSocket ordering delivers it before the close.
        builder.sequence += 1
        pending = {"type": "command", "seq": builder.sequence, "expected_revision": builder.revision,
                   "payload": {"action": "confirm"}}
        saved_token = builder.token
        old_connection = builder.connection_id
        builder.ws.send(json.dumps(pending))
        general.snapshot(lambda packet: "Builder" not in packet["reservations"])
        builder.close()
        paused = general.snapshot(lambda packet: not packet["connected"]["Builder"])
        require(paused["status"] == "paused", "Missing seat must pause")
        later = general.snapshot(lambda packet: not packet["connected"]["Builder"])
        require(later["tick"] == paused["tick"], "Pause must freeze simulation ticks")
        require(later["readiness"]["Builder"], "Readiness should survive disconnect")
        rejection(args.url, join, "seat_reserved")
        builder = Client(args.url, "Builder", args.build, saved_token)
        clients.append(builder)
        require(builder.resumed and builder.connection_id != old_connection, "Reconnect must recover seat with a new transport")
        require(builder.sequence == pending["seq"], "Processed confirmation must survive lost acknowledgment")
        builder.ws.send(json.dumps({"type": "command_status", "seq": pending["seq"]}))
        recovered = builder.receive(lambda packet: packet.get("type") == "result" and packet.get("seq") == pending["seq"])
        require(recovered["ok"] and recovered["replayed"], "Lost acknowledgment must recover cached purchase result")
        builder.ws.send(json.dumps(pending))
        duplicate = builder.receive(lambda packet: packet.get("type") == "result" and packet.get("seq") == pending["seq"])
        require(duplicate == recovered, "Retry must preserve exact prior outcome")
        _, general_confirmation = general.command({"action": "confirm"})
        require(general_confirmation["ok"], "General confirmation should succeed")
        committed = builder.snapshot(lambda packet: packet["spent"] == expected_spend and not packet["reservations"])
        require(len([building for building in committed["buildings"] if building["id"] == "building_001"]) == 1,
                "Builder purchase must create exactly one building")
        passed("lost_ack_idempotent_purchase_and_reconnect", {"spent_once": committed["spent"],
                                                             "tick_frozen_while_missing": paused["tick"]})

        changed = dict(pending, payload={"action": "cancel"})
        builder.ws.send(json.dumps(changed))
        conflict = builder.receive(lambda packet: packet.get("type") == "error")
        require(conflict["code"] == "command_id_conflict", "Changed payload must conflict")
        builder.ws.send(json.dumps({"type": "command", "seq": builder.sequence + 2,
                                   "expected_revision": builder.revision, "payload": {"action": "cancel"}}))
        gap = builder.receive(lambda packet: packet.get("type") == "error")
        require(gap["code"] == "sequence_gap" and gap["sequence"] == builder.sequence, "Gap must preserve sequence")
        _, future = builder.command({"action": "ready", "value": True}, expected_revision=2147483647)
        require(not future["ok"] and future["result"]["error"] == "future_revision", "Future revision must fail")
        _, outside = general.command({"action": "order", "units": [unit_id], "mode": "move", "x": 27, "z": 0})
        require(not outside["ok"] and outside["result"]["error"] == "invalid_position", "Out-of-map command must fail")
        _, unknown = general.command({"action": "order", "units": ["unknown_unit"], "mode": "stop"})
        require(not unknown["ok"], "Unknown unit must fail")
        _, wrong_field = builder.command({"action": "ready", "value": False, "role": "General"})
        require(not wrong_field["ok"], "Payload cannot override bound role")
        passed("command_identity_revision_schema_and_bounds")

        rejection(args.url, b"{}", "text_json_required")
        rejection(args.url, "{broken}", "malformed_json")
        rejection(args.url, "[" * 11 + "0" + "]" * 11, "invalid_message")
        rejection(args.url, " " * 8193, "packet_too_large")
        rejection(args.url, {"type": "command", "seq": 1, "expected_revision": 0,
                             "payload": {"action": "order", "units": [f"unit_{n}" for n in range(33)], "mode": "stop"}},
                  "invalid_message")
        passed("binary_malformed_depth_size_and_array_limits")
        with connect(args.url, open_timeout=5, close_timeout=2, max_size=262144) as outsider:
            for index in range(61):
                outsider.send(json.dumps({"type": "ping", "id": index}))
            found = False
            for _ in range(61):
                response = json.loads(outsider.recv(timeout=5))
                if response.get("code") == "rate_limited":
                    found = True
                    break
            require(found, "Rate limit should close excessive packet stream")
        passed("bounded_rate_limit")

        # General absent: a Builder credential cannot claim that reserved seat.
        general_token = general.token
        general.close()
        builder.snapshot(lambda packet: not packet["connected"]["General"])
        rejection(args.url, dict(join, role="General", token=builder.token), "invalid_resume_token")
        general = Client(args.url, "General", args.build, general_token)
        clients.append(general)
        require(general.resumed, "General should recover its own reserved seat")
        resumed = builder.snapshot(lambda packet: packet["connected"]["General"] and packet["status"] == "playing")
        digest = hashlib.sha256(json.dumps(resumed, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        passed("role_scoped_token_and_state_recovery", {"snapshot_revision": resumed["revision"], "snapshot_sha256": digest})

        if args.ledger_limit:
            builder.command({"action": "ready", "value": False})
            started = time.monotonic()
            while builder.sequence < 4096:
                sent_at = time.monotonic()
                _, reply = builder.command({"action": "ready", "value": False})
                require(reply["ok"], "Ledger filler command should be accepted")
                if builder.sequence % 512 == 0:
                    print(json.dumps({"progress": "ledger_capacity", "processed": builder.sequence}), flush=True)
                time.sleep(max(0, 0.02 - (time.monotonic() - sent_at)))
            builder.ws.send(json.dumps({"type": "command", "seq": 4097, "expected_revision": builder.revision,
                                       "payload": {"action": "ready", "value": True}}))
            full = builder.receive(lambda packet: packet.get("type") == "error")
            require(full["code"] == "ledger_full" and full["sequence"] == 4096, "Full ledger must stop without forgetting")
            builder.ws.send(json.dumps({"type": "command", "seq": 1, "expected_revision": 0,
                                       "payload": {"action": "ready", "value": True}}))
            first = builder.receive(lambda packet: packet.get("type") == "result" and packet.get("seq") == 1)
            require(first["ok"] and first["replayed"], "Oldest command must remain replayable at capacity")
            unchanged = builder.snapshot(lambda packet: not packet["readiness"]["Builder"])
            require(not unchanged["readiness"]["Builder"], "Oldest replay must not execute readiness again")
            passed("ledger_capacity_retains_oldest_identity", {"outcomes": 4096, "seconds": round(time.monotonic() - started, 3)})
    finally:
        for client in clients:
            client.close()
    evidence = {"kind": "automated_protocol_integration", "build_id": args.build,
                "protocol": 1, "checks": results, "tokens_logged": False,
                "browser_interaction": False, "human_feedback": False,
                "ledger_capacity_tested": args.ledger_limit}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="ws://127.0.0.1:8775")
    parser.add_argument("--build", help="Expected authority build; defaults to the current shared rules BUILD_ID")
    parser.add_argument("--ledger-limit", action="store_true")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "docs/evidence/protocol-smoke.json")
    options = parser.parse_args()
    if options.build is None:
        options.build = current_build_id()
    destination = urlsplit(options.url)
    require(destination.scheme == "ws" and destination.hostname == "127.0.0.1" and destination.port == 8775
            and destination.username is None and destination.password is None,
            "This regression driver is limited to the authorized local authority")
    run(options)
