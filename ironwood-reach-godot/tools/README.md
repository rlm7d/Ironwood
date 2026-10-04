# Local Godot and browser tooling

Run from the isolated `ironwood-reach-godot` folder. No command changes the public
prototype, system packages, global policy, or external hosting. Runtime state and
builds are ignored by Git.

```sh
python3 tools/check.py
python3 tools/build.py
python3 tools/run_server.py
python3 tools/serve.py --build battlefield-003
```

`check.py` uses pinned Godot with writable project-local XDG paths and runs only
the deterministic simulation assertions, with a 120-second timeout. It saves the
actual command, exit code, check count, stdout/stderr and source/test hashes to
`docs/evidence/simulation.json`; earlier owned reports are archived in
`.runtime/check-history`. It does not start an authority or claim browser or
client recovery validation. Explicit XDG bindings are honored.

`build.py` reads `Rules.BUILD_ID`, requires official Godot 4.6.3, imports and exports
the non-threaded Compatibility Web preset, and writes `builds/<build-id>/index.html`.
The source and artifact hashes are saved in `build-manifest.json`. Unchanged
verified candidates are reused. A rebuild updates only a recognized candidate
whose current files still match its marker; the previous candidate is retained in
`.runtime/build-history`. Unknown files and changed artifacts block replacement.
`--rebuild` forces a new export; `--check-only` checks prerequisites without export.

The cloud template receipt is reused through a project-local template link. On a
desktop without the harness, install matching Godot web templates normally. Set
`GODOT_BIN` for a custom executable. Explicit XDG bindings are honored. Desktop
template checks distinguish their ZIP/version validation from the cloud's pinned
official checksum receipt.

The authority runs headless on `127.0.0.1:8775`; HTTP serves only candidate builds
on `127.0.0.1:9088`, with correct WASM MIME and no-store headers. Launchers verify
the saved process UID, command and start time, reuse owned processes, and preserve
unknown processes or occupied ports. Stale owned metadata is archived. Service
readiness is a transport/content baseline; multiplayer behavior needs browser
verification. Stop a service only after verifying its owned metadata and actual
process identity. Restarting the authority discards the in-memory trial session.

Safe lifecycle commands:

```sh
python3 tools/browser_clients.py --stop-owned
python3 tools/run_server.py --restart-owned
```

Stop the owned browser helper first when resetting a trial. `--stop-owned` on
`run_server.py` stops without starting a replacement. These options verify saved
ownership and process identity; they do not target the disposable probe. Browser
stop requests preserve profiles and their reconnect storage. Authority restart
discards seats, reservations and simulation state because restart persistence is
outside this approval milestone. Reopen clients only after the new server is ready.

For cloud interactive testing, start/reuse the authenticated harness display first:

```sh
python3 /workspace/ironwood-cloud-harness/tools/start_display.py
python3 tools/browser_clients.py --build battlefield-003 --seconds 1800
```

Launch Chromium through the platform's approved expanded execution path when its
restricted shell blocks user namespaces. The helper retains browser and GPU
sandboxes, checks actual GPU/seccomp protection, and refuses unsafe flags. It
creates two independent dedicated profiles under `.runtime/browser-clients`,
separate from the disposable probe. `--inspect-only` checks profile ownership
without launching or cleaning. Existing owned live helpers are reused.
Without `--build` or `--url`, the helper reads the current `Rules.BUILD_ID`.

Gameplay input comes from the existing XTEST desktop helper. Browser automation
only navigates, sets the browser viewport, and observes passive WebSocket/error logs; reconnect tokens are
redacted. Godot may update the window title during startup: inspect the actual
X11 title/window geometry before sending guarded OS input. Current page titles
are recorded in browser `state.json`.

The browser helper also accepts an explicitly guarded local candidate URL:

```sh
python3 tools/browser_clients.py --url http://127.0.0.1:9088/battlefield-003/index.html
```

While the owned helper is running, write one request to
`.runtime/browser-clients/control.json`:

```json
{"action":"navigate","build":"battlefield-003"}
```

`{"action":"stop"}` closes only its own two contexts. Navigation targets must
remain the project's loopback HTTP service and optional loopback authority.
Control files and runtime profile contents are never publication artifacts.

The default viewport is 640×820 per independent client. Launch flags
`--viewport-width` and `--viewport-height` accept 640–1920 and 480–1080 pixels.
The actual dimensions are recorded per client in `state.json`. Choose dimensions
that fit the display when demonstrating real interaction; a configured viewport
outside the visible display does not establish that the whole game was observed.

After starting the updated helper, resize only client 2 for a wide minimap check:

```sh
python3 tools/browser_clients.py --resize-owned --client 2 --viewport-width 1280 --viewport-height 820
python3 tools/browser_clients.py --resize-owned --client 2 --viewport-width 640 --viewport-height 820
```

Omit `--client` to resize both. The equivalent owned control request is
`{"action":"viewport","width":1280,"height":820,"client":2}`. This uses
Playwright's viewport resize, which also resizes the headed browser window; it
does not inject game input or navigate away. Inspect and position the actual
window with the desktop helper for visible play. A helper already running older
code must be stopped and relaunched before it can accept viewport requests.

For a fresh trial after an authority restart, close the owned clients, restart
the authority, and launch with clean profiles:

```sh
python3 tools/browser_clients.py --stop-owned
python3 tools/run_server.py --restart-owned
python3 tools/browser_clients.py --fresh-profiles
```

`--fresh-profiles` requires an exclusive runtime lease, no live profile user,
and matching previous helper/UID/profile metadata. It renames only those closed
dedicated profile directories into `.runtime/browser-clients/profile-history`,
along with their previous runtime receipt. It preserves all contents, reads no
browser storage, and never deletes profiles or edits reconnect tokens. The
archives remain private local runtime data and must not be published. Ordinary
startup continues to preserve reconnect storage. Unknown ownership, replaced
directories, or active profile users block archival. If archival is blocked,
close the identified owner and inspect the saved metadata before retrying; do
not clear storage, delete profiles, or remove another browser's locks. An
interrupted archive reports its preserved destination and moved directory names
for review without overwriting a replacement directory.

Build, service, and browser sandbox checks do not establish fun, balance, human
approval, gameplay performance, or public deployment readiness. Public serving
and a secure external authority/proxy require separate deployment work; none is
configured by these local helpers.
