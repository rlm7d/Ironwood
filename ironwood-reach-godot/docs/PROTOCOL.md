# Battlefield approval protocol

This is one native Godot authority and one in-memory room, `REACH-01`, using
WebSocket JSON messages. The local authority binds **127.0.0.1:8775**. Browser
clients use WebSockets, not ENet. The current content build is `battlefield-006`,
protocol version `1`; the shared rules file is authoritative for these versions.
This document describes behavior; verification results belong in evidence logs.

There are exactly two seats, `Builder` and `General`. Commands receive their role
from their authenticated seat, never from a payload. A connection ID identifies a
transport connection and changes on reconnect; it is not durable player identity.

## Join and reconnect

A first join sends:

```json
{"type":"join","protocol":1,"build_id":"battlefield-006","room":"REACH-01","role":"Builder","token":""}
```

On acceptance, the authority sends `welcome` with `protocol`, `build_id`, `room`,
`role`, `connection_id`, `sequence`, `resumed`, and a cryptographically random
role-scoped reconnect `token`. The token is 32 random bytes represented as 64 hex
characters. Keep it private in role/room-scoped client storage; server logs never
include it or the raw join message. Welcome `sequence` is the last processed
command sequence, including recorded rejections.

An occupied seat rejects a third client or a takeover, even if a valid token is
supplied. When a connection closes, its seat becomes disconnected and the room
pauses. Its token, command ledger, readiness and any purchase reservation remain
reserved indefinitely for this process's room lifetime. To recover it, send the
same join with that seat's token. A token for the other role cannot recover it.
An empty token cannot claim a previously reserved seat.

The prototype has no automatic seat expiry, host migration, accounts, multiple
rooms, or recovery across authority restart. A lost token requires an explicit
room reset; the server does not invent another identity. A process restart loses
the battlefield and token/command ledger. No durable persistence is claimed.

## Commands and results

```json
{"type":"command","seq":1,"expected_revision":2,"payload":{"action":"ready","value":true}}
```

Sequences are independent per role and start at `1`. New commands must use the
last processed sequence plus one. A sequence gap returns `sequence_gap` without
advancing it. Each valid next-sequence envelope records its outcome, including a
schema, revision, permission or simulation rejection. Malformed envelopes do not
consume a sequence.

Results have this shape:

```json
{"type":"result","seq":1,"revision":3,"ok":true,"replayed":false,"result":{"ok":true,"result":"readiness_updated","revision":3}}
```

`result` preserves the exact simulation outcome. Transport validation failures
use an outcome containing `ok:false` and an `error` code. Outer `revision` is the
authoritative revision after that outcome. Cached replies preserve the original
outcome and original revision.

The role/sequence pair is the command identity. The authority normalizes finite
integral `socket` and `slot` fields, then canonicalizes the payload with sorted
JSON keys and full numeric precision. Repeating the same identity and payload
returns its cached result with `replayed:true`; it never executes again. Reusing
the identity with a changed payload returns `command_id_conflict`. The expected
revision is a concurrency precondition, not part of payload identity.

The room retains up to **4096 outcomes per role** without expiry. At that limit,
further commands return `ledger_full` and stop; old identities are never silently
forgotten. A room reset is required for additional commands. This bound is an
explicit limit of this approval prototype.

An expected revision newer than the authority returns `future_revision`. A
revision over **400 revisions** behind returns `stale_revision`. This is a
revision count, not a duration promise. Those outcomes are recorded like other
next-sequence rejections. Duplicate cached commands replay before revision checks.
The revision tolerance is a documented prototype policy to review with networking
feedback, not final campaign semantics.

After a lost acknowledgment, reconnect with the same token and preserve the
pending command identity. Query:

```json
{"type":"command_status","seq":1}
```

An existing outcome returns its cached `result` with `replayed:true`. An absent
outcome returns `unknown_command` and the current `sequence`. The client may retry
the exact pending identity/payload only when it is the next sequence; it must not
silently mint a new identity for that purchase or order.

## Payload schema

The simulation owns entity ownership, role permissions, purchase kinds, treasury
transactions, ability targets/cooldowns and other confirmed rules. Transport
validation does not grant permission merely because a packet is well formed.

| Action | Fields |
| --- | --- |
| `ready` | `value`: boolean; allowed while waiting or paused |
| `reserve` | `kind`: identifier string; Builder uses integral `socket`, General uses `building` identifier |
| `confirm` | No additional fields |
| `cancel` | No additional fields |
| `order` | `units`: 1–32 distinct identifiers; `mode`: `move`, `attack_move` or `stop`; finite `x`,`z` required except for `stop` |
| `ability` | Integral `slot`: 0 or 1; Builder uses `building`, General uses `units`; optional supplied coordinates must be finite and in bounds |

Identifiers are nonempty strings up to 64 characters. Current entity existence
and ownership are checked by the authoritative simulation. Coordinates must be
inside shared map bounds: X **−26 through 26**, Z **−19 through 19**, inclusive.
Sockets are IDs **0 through 7**. Unknown fields, including a client-supplied role,
are rejected. Missing semantic targets and wrong purchase kinds are rejected by
the simulation. Integer-like JSON numbers for `socket` and `slot` are normalized
to GDScript integers; nonintegral values are rejected.

The user approved testing a shared treasury and one reservation per player:
holds last until Confirm or Cancel, confirmation charges and starts once,
and there is no automatic expiry or post-confirmation refund. These are trial
rules, subject to later feedback. This transport does not define territory
capture, final balance, campaign persistence, or a replacement for unresolved rules.

## Snapshots, pause and limits

The authority advances the deterministic simulation at **20 Hz**, with at most
five catch-up steps per process frame. It broadcasts snapshots at **10 Hz** and
after command outcomes and seat lifecycle changes. The simulation owns pause and
readiness: missing either seat pauses, retaining both readiness values permits
resume on reconnection. Ready controls remain available while paused.

Each `snapshot` contains the simulation's JSON-friendly `build_id`, `protocol`,
`seed`, `tick`, `revision`, status, economy, reservations, buildings, units,
workers, sockets, territories, abilities, `connected` and `readiness` state. The
server adds `type:"snapshot"`, `room`, `server_build`, and a `connections` map of
role to active connection ID or empty string. Snapshots never contain tokens.

Inbound packets are text JSON, at most **8192 bytes**, with at most 10 nesting
levels, 16 object fields, 32 array entries, 64-character object keys and
2048-character general strings. Nesting is checked before JSON parsing. Processing
is bounded at 64 messages per poll, eight per client per poll, 60 messages per
connection per one-second rate window, and 16 pending/active transports. Unjoined
connections time out after 10 seconds. Binary, oversized, malformed, excessively
nested or rate-limited traffic is safely rejected and closed.

`ping` accepts an optional `id` string up to 64 characters or a nonnegative
integer and returns `pong` with that ID and current revision. Protocol errors use
`{type:"error",code,revision}` and may include `seq`/current `sequence`; no raw
packet or token is echoed. Build, protocol and room mismatches reject joining.

Loopback WS tests do not establish public multiplayer, remote-device compatibility,
latency tolerance, load capacity or security readiness for public hosting. Public
HTTPS clients need an approved secure WSS route and separate deployment tests;
this helper does not open a public listener or change network policy.
