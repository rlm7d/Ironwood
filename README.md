# Ironwood Reach

An isolated Godot 4.6.3 authoritative co-op battlefield prototype. The existing
[public prototype](https://ironwood-reach.rlm7d.chatgpt.site) is preserved.

The current candidate is **battlefield-006**. It remains a partial approval
prototype: precise territory rules, public candidate hosting and human approval
are outstanding. Full campaign development remains gated by battlefield approval.

## Play the Windows test

[Download the Windows test package](releases/ironwood-reach-windows-006.zip)
(46 MB). Extract the whole ZIP, then double-click **Start Ironwood Reach.exe**.
Choose Builder in one game window and General in the other; press Ready in both.
Keep the launcher open while playing. Closing it ends the unsaved local battle.

Requires Windows 10/11, 64-bit, and installed Edge or Chrome. The Godot runtime is
bundled; Godot/Python installation and command-line setup are unnecessary.
The launcher, HTTP transfers, owned server lifetime and co-op protocol passed
under Wine. Actual Windows-PC browser gameplay remains untested. This is local
two-role testing on one computer; public multiplayer hosting remains pending.
[Verification and build tooling](packaging/windows/README.md).

## Source and evidence

- [Game startup, controls and prerequisites](ironwood-reach-godot/README.md)
- [Verification results and evidence limits](ironwood-reach-godot/docs/VERIFICATION.md)
- [Open issues](ironwood-reach-godot/docs/OPEN_ISSUES.md)
- [Compact build and source ZIP](releases/ironwood-reach-battlefield-006-playable.zip)
  (11.5 MB; [SHA-256](releases/SHA256SUMS))

The repository includes the current Web export, original game source, tests,
tooling, design documents, and archived playtest evidence. The compact ZIP omits
bulky proof captures and traces; those remain in the repository. Its Web export
requires the authoritative Godot server. Opening the HTML alone does not create
a complete co-op deployment. Godot and export templates are not bundled.

## Cloud setup source

[The cloud harness](ironwood-cloud-harness/README.md) contains the source for the
virtual display, real desktop input, captures and two independent browser clients.
Its installer checks pinned provider-installed dependencies and obtains matching
verified Web templates; it does not provision system packages. The recorded cloud
commands expect the harness at `/workspace/ironwood-cloud-harness`, outside the
checkout. Preserve the existing installed harness; for a fresh environment place
this source there before following the recorded commands. A fresh environment
still needs capability checks and supported browser sandbox permissions.

The Godot project has its own frozen package manifest. Local runtime directories,
browser profiles, credentials, caches and obsolete Web exports are excluded.
