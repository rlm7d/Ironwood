> Source-build documentation: examples and the directory layout below describe
> the generated build directory. In the distributed ZIP, the same executable is
> named **Start Ironwood Reach.exe**, notices are in `Licenses/`, and source files
> are in `Source/`. Follow the top-level `README.txt` to play.

# Ironwood Reach — Windows battlefield test launcher

For **Windows 10/11, 64-bit**, with Microsoft Edge or Google Chrome installed.
Godot is bundled. You do not need Python, the Godot editor, export templates,
an administrator account, commands, or firewall changes.

1. Extract the **whole ZIP** into a folder. Keep its `data` folder beside the EXE.
2. Double-click **IronwoodReachTest.exe**.
3. In the first game window click **Join Builder**; in the second click
   **Join General**. Click **Ready** in both windows.

The launcher automatically starts the authoritative battle server and opens two
independent browser profiles. Use Alt+Tab to switch between their windows.
This is a local, two-role test on one computer. It is not public internet co-op.

Keep the launcher open while playing. **End local test**, or closing the
launcher, ends the unsaved battle. Close the two game windows afterwards.
Reopen the launcher for a fresh battle. Use the game's Reconnect button to
recover a disconnected seat while its original battle is still running;
reopening a closed game window from the launcher reuses that seat's profile.
The full campaign and Brass Tactics territory behavior remain pending.

## Controls

- Builder: select a home construction circle, choose a building, then Confirm.
- General: select the barracks, reserve Footmen/Archers, Confirm, and wait for training.
- Select troops with left-click or drag; Shift adds selection.
- Right-click moves; A then left-click gives an attack-move order; S stops.
- Q/E activate abilities; Ctrl+1–9 saves groups and 1–9 recalls them.
- Mouse wheel zooms; arrow keys/middle drag pan; F centers selection; H overview.
- Controls opens help; both roles must remain connected for the battle to run.

## Troubleshooting

- **Missing or changed file:** extract the entire original ZIP again. Do not move only the EXE.
- **Port 8775 in use:** close your previous Ironwood test launcher/server first.
  The launcher preserves unrelated processes and refuses to reuse an unknown server.
- **Browser not found:** install Microsoft Edge or Google Chrome, then retry.
- **Server exited or not ready:** report the exact message and the session log
  folder displayed in that error. The release Godot engine may produce no log text.
- **Blank/failed game view:** report the message shown in the game window and
  browser/GPU model. A browser with WebAssembly and WebGL 2 is required.

Per-run browser profiles and the server log stay in a unique
`%TEMP%\IronwoodReach-{GUID}` folder. Your usual browser profile is not used.
Do not delete a test profile while its browser window remains open.
The launcher binds only to `127.0.0.1`, chooses an available HTTP port, and
preserves normal browser sandboxes. It does not open ports on your network.

## Audit and reproducible build

`launcher.c` is generated launcher tooling; the existing battlefield-006 game
source and Web export are unchanged. `build-record.json` records source/EXE
hashes, compiler version, target, commands, and imported Windows DLLs.

The package layout is:

```
IronwoodReachTest.exe
launcher.c
README.md
build-record.json
third-party/
data/
  authority.exe       # Official Godot 4.6.3 Windows x64 release template
  authority.pck       # Byte-identical copy of the tested Web index.pck
  web/               # Nine byte-identical battlefield-006 Web export files
```

The authority release template discovers `authority.pck` beside itself.
Its launch command is `authority.exe --headless -- --server`.
The official release does not support `--main-pack` path overrides and suppresses
normal print output. The launcher verifies readiness by finding the **owned
child PID** listening on `127.0.0.1:8775` through `GetExtendedTcpTable`, checking
that child is alive, and connecting to the socket. Only the authority is attached
to the launcher's kill-on-close job; it never kills a process by name or port.

A native self-check runs without game clients, authority startup, or seat changes:

```powershell
.\IronwoodReachTest.exe --verify --verify-report "$PWD\launcher-self-check.json"
```

Choose a new report filename; the check refuses to overwrite an existing file.
It checks the official authority SHA-256 and x64 PE format, the adjacent PCK,
all nine Web artifact hashes, and actual HTTP requests including full binary
PCK/WASM transfer hashes, GET/HEAD MIME and lengths, no-store, traversal,
unknown-file, and method rejection. Self-check results do not prove Windows
browser gameplay. Check the package's verification records for executed scope.

A separate authority-lifetime diagnostic exercises the same startup and cleanup
functions as normal launch, without opening browsers:

```powershell
.\IronwoodReachTest.exe --verify-live --seconds 60 --verify-report "$PWD\launcher-live.json"
```

The initial record has `phase: "ready"`, the owned Windows process PID and HTTP
port. After the requested duration, `.completed.json` records completion and
an authority-port-release check. Only the live diagnostic starts an authority;
use a fresh battle and an available port. The two records do not establish
interactive Windows gameplay.

The launcher was cross-compiled with Zig 0.16.0, targeting x86_64-windows-gnu.
It imports Windows system libraries/UCRT only; no custom runtime DLL is required
on supported Windows 10/11. Zig/MinGW notices are included in `third-party`.
Godot's separate notices are supplied with the containing game package.
The executable is an unsigned development build.
