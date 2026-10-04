# Disposable capability proof archive

Gate 0 passed before battlefield implementation. Its toy cube/sphere scene
established actual Godot launch, mouse and keyboard input, animated browser play,
a changed behavior rebuilt and retested, and two independent browsers sharing
one authoritative session with disconnect, pause, reconnect and duplicate-safe
commands. It did not establish any Ironwood game rule or quality approval.

These are historical reports, copied unchanged with their original dates and
hashes. Their absolute `/workspace` links refer to the original cloud workspace;
use the relative links below for the portable subset. Statements saying the
battlefield has not been built describe the earlier Gate 0 milestone.

- [Original seven-check report](evidence/gate0/gate_0.md)
- [Independent agent review](evidence/gate0/review/gate_0_review.md)
- [Machine-readable checks](evidence/gate0/review/gate_0_checks.json)
- [Native real-input recording](evidence/gate0/native-v1-input.mp4)
- [Browser v1 real-input recording](evidence/gate0/browser-v1-interactive.mp4)
- [Complete browser disconnect/reconnect recording](evidence/gate0/browser-v1-reconnect.mp4)
- [Changed v2 behavior and browser retest](evidence/gate0/browser-v2-interactive.mp4)
- [Actual Godot editor inspection](evidence/gate0/editor-v2-scene-inspected.png)
- [Official matching-template receipt](evidence/gate0/web-templates-receipt.json)
- [Archive file hashes](evidence/gate0/archive-manifest.json)

The published environment was then restored: the dependency/display/service
[baseline](evidence/gate0/fresh-restoration-baseline.json) passed, and additional
[real probe input](evidence/gate0/restored-probe-input.mp4) was recorded. That
baseline is not itself interactive proof. The short restoration recording ends
before the later disconnect/reconnect captures and does not independently prove
that complete sequence. The current battlefield's distinct browser proof is
documented in [VERIFICATION.md](VERIFICATION.md).

All interaction was agent-operated on the cloud display. There was no human play,
personal desktop control, public WSS deployment or target-hardware performance
measurement. Gate 0's source, startup harness and full evidence remain preserved
in `/workspace/ironwood-cloud-harness`; the game package includes the selected
proof archive rather than that separate harness or its runtime profiles.
