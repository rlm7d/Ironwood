# Separate public candidate: review draft

**No public candidate has been deployed.** These files propose one existing Linux VM deployment; they do not select a provider, create accounts, install services, change DNS/firewalls, obtain certificates, or replace the existing prototype at `https://ironwood-reach.rlm7d.chatgpt.site`.

The next required decision is an **existing approved host and separate approved hostname**, plus an available deployment method within its existing access. New spending, credentials/access, public listeners, or security/network configuration require the owner's approval before execution. `candidate.example.invalid` is a deliberately unusable placeholder, not an assigned hostname.

## Proposed layout and route

```text
https://<approved-candidate-host>/index.html?server=wss%3A%2F%2F<approved-candidate-host>%2Fsession
  Caddy: HTTPS, complete static Godot export
  /session: WSS reverse proxy -> 127.0.0.1:8775
  native Godot authority: one in-memory room, REACH-01
```

The client already accepts a `wss://` endpoint through the `server` query parameter. The native authority already binds loopback; the proxy must run on that same machine. The development HTTP helper at port 9088 is unnecessary on this host. The example opens only the separate candidate site; never merge it over an existing server configuration or use the public prototype's hostname.

Suggested release layout:

```text
/opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64
/srv/ironwood-reach/releases/<approved-build-id>/game/     # matching source/imports
/srv/ironwood-reach/releases/<approved-build-id>/web/      # export runtime files only
/srv/ironwood-reach/releases/<approved-build-id>/build-manifest.json
/srv/ironwood-reach/current -> releases/<approved-build-id>
/srv/ironwood-reach/web -> current/web
```

Copy every export runtime file named by the build manifest, including `.html`, `.js`, `.wasm`, `.pck`, images and audio worklets. Keep source, credentials, profiles, `.runtime`, logs and evidence outside the public web root. Retain the manifest as a release receipt and verify its artifact hashes after transfer. Source and export must share the same build/protocol version. Caddy's user needs read/traverse access to public assets; it does not need write access or access to private runtime state.

## Prerequisites and review-only templates

Use official **Godot 4.6.3**, exact version `4.6.3.stable.official.7d41c59c4`, on Linux x86_64 with a compatible glibc runtime. The current binary resolves `libc.so.6`, `libm.so.6`, `libdl.so.2`, `libpthread.so.0`, `librt.so.1`, and `/lib64/ld-linux-x86-64.so.2`; verify resolution on the selected host. The headless authority needs no desktop/browser/GPU. Import the matching source on that host before making the release read-only. Building the web export also needs matching official **4.6.3 export templates**, Python 3, and the existing build tools; export templates are not a backend runtime dependency. Retain GDScript, Compatibility and single-threaded web export.

[Caddyfile.example](../deploy/Caddyfile.example) assumes an approved installed Caddy service with its existing certificate storage and permissions. Caddy automatically manages HTTPS only after valid DNS, certificate eligibility and approved port access exist. Port 80/443 changes and certificate provisioning have **not** been performed. Caddy normally serves `.wasm` as `application/wasm`; verify actual responses after deployment. No threaded-export cross-origin isolation is proposed.

[authority.service.example](../deploy/authority.service.example) proposes a dedicated unprivileged `ironwood` user/group, read-only release files and private writable state/cache directories. User creation and unit installation need later approval. It deliberately does not restart automatically: a crash stops this in-memory trial. The selected host must validate the unit's hardening and Godot runtime compatibility before activation.

These are **unexecuted checks for the selected host**, after paths/hostname are reviewed:

```sh
/opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64 --version
ldd /opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64
caddy adapt --config /path/to/reviewed/Caddyfile --adapter caddyfile --pretty
systemd-analyze verify /path/to/staged/ironwood-authority.service
```

Do not install or reload either template merely to inspect it. There is no Caddy binary in this task environment, and neither template has been tested as a service.

## Actual access and lifecycle limits

This is a **public single-room trial** if exposed unchanged. There is no account/invite login or WebSocket Origin allowlist in the authority; the Caddy example does not add either. Any visitor can claim a vacant Builder or General seat. A random bearer reconnect token owns recovery of a claimed seat within that running room; it is not account authentication. Never log WebSocket payloads or reconnect tokens.

The room supports two complementary seats and bounded transport/command validation, not multiple rooms, durable progression, host migration, or recovery across authority restart. Missing either player pauses the battle and preserves occupied seats/holds indefinitely. A stranger claiming a seat, a lost token, or an abandoned seat can block the trial until an explicit room reset. Restart/reset discards the entire battlefield, seats, holds and command ledger. Preserve these limits in the playable-build handoff; do not describe this deployment as private authenticated co-op or durable hosting. Any new access control is separate implementation/configuration work requiring review and corresponding tests.

## Verification and rollback after approval

Deployment is not complete until the actual candidate provides valid HTTPS/WSS, all manifest-listed files/hashes and correct MIME/cache responses, followed by real input in two independent browsers: complementary joins/readiness, actions from both roles, converged revisions, disconnect/pause, original-seat reconnect and duplicate-command recovery. Check browser/server errors and reload the declared build. Same-machine success does not establish remote-device compatibility; include a client on another network before claiming that scope. Record measured loading/latency conditions rather than deriving performance from a local build.

Keep the prior candidate release and site configuration. A reviewed rollback restores the **candidate** source/export together, then explicitly restarts its authority; this loses the current room. Tell connected trial players before a deliberate restart. Do not alter the preserved public prototype. Its URL is not a rollback target.

## What was actually done

Executed: read-only tool, source, manifest and runtime-link inspection. The existing HTTPS Git proxy read succeeded; authenticated GitHub repository/Pages API reads returned `Forbidden`, so Pages availability remains unknown. No callable deployment/publication tool or approved provider deployment configuration was found. See local interactive/build evidence separately; these observations do not prove hosting readiness.

**Not executed:** host/user provisioning, artifact transfer, systemd/Caddy validation or activation, DNS/TLS/public port changes, public export serving, WSS proxying, public multiplayer tests or rollback. This draft supplies a concrete plan for the host/access decision, with no public URL claimed.
