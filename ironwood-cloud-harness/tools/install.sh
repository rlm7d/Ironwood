#!/usr/bin/env bash
# Reuse verified image tools and templates; validate an isolated disposable probe.
# This script changes no selected repository, service, browser, or system policy.
set -euo pipefail

HARNESS_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export HARNESS_ROOT
export XDG_DATA_HOME="$HARNESS_ROOT/runtime/godot-data"
export XDG_CONFIG_HOME="$HARNESS_ROOT/runtime/godot-config"
export XDG_CACHE_HOME="$HARNESS_ROOT/runtime/godot-cache"
export XDG_RUNTIME_DIR="$HARNESS_ROOT/runtime/godot-runtime"
mkdir -p -- "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR" "$HARNESS_ROOT/runtime/install-validation"

python - <<'PY'
import ctypes, importlib.metadata, json, os, shutil, subprocess
from pathlib import Path
required = ['godot', 'chromium', 'Xorg', 'xdpyinfo', 'xauth', 'xwininfo', 'ffmpeg', 'ffprobe', 'python']
missing = [name for name in required if not shutil.which(name)]
if missing:
    raise SystemExit('Missing image prerequisites: ' + ', '.join(missing) + '. Provision these with the environment provider; this script does not change system packages.')
def output(command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout.strip()
versions = {'godot': output(['godot', '--version']), 'chromium': output(['chromium', '--version']),
            'playwright': importlib.metadata.version('playwright')}
if versions['godot'] != '4.6.3.stable.official.7d41c59c4':
    raise SystemExit('Expected pinned official Godot 4.6.3; preserving installed toolchain.')
if not versions['chromium'].startswith('Chromium 151.0.7922.173 '):
    raise SystemExit('Expected the verified Chromium 151.0.7922.173 image prerequisite.')
if versions['playwright'] != '1.62.0':
    raise SystemExit('Expected Playwright 1.62.0; use a local pinned installation before retrying.')
for name in ['libX11.so.6', 'libXtst.so.6', 'libGL.so.1']:
    ctypes.CDLL(name)
dummy = Path('/usr/lib/xorg/modules/drivers/dummy_drv.so')
if not dummy.is_file():
    raise SystemExit('Missing Xorg dummy driver; provider image provisioning is required.')
packages = {name: output(['dpkg-query', '-W', '-f=${Version}', name]) for name in
            ['xserver-xorg-core', 'xserver-xorg-video-dummy', 'ffmpeg']}
print(json.dumps({'status': 'verified_existing_dependencies', 'versions': versions, 'packages': packages,
                  'system_package_changes': False}))
PY

# Retained-template hashes are checked before the installer may contact GitHub.
# In the verified environment this invocation uses the receipt and no network.
python "$HARNESS_ROOT/tools/install_web_templates.py"
python "$HARNESS_ROOT/tools/generate_probe.py" --build-id v2 --spin-rate 2.0

VALIDATION_DIR="$(mktemp -d "$HARNESS_ROOT/runtime/install-validation/run-XXXXXXXX")"
mkdir -- "$VALIDATION_DIR/export"
export VALIDATION_DIR

godot --headless --path /tmp/ironwood-capability-probe --import --log-file "$VALIDATION_DIR/import-godot.log" >"$VALIDATION_DIR/import.log" 2>&1
godot --headless --path /tmp/ironwood-capability-probe --log-file "$VALIDATION_DIR/self-test-godot.log" -- --self-test >"$VALIDATION_DIR/self-test.log" 2>&1
godot --headless --path /tmp/ironwood-capability-probe --log-file "$VALIDATION_DIR/export-godot.log" --export-release Web "$VALIDATION_DIR/export/index.html" >"$VALIDATION_DIR/export.log" 2>&1

python - <<'PY'
import datetime, hashlib, json, os
from pathlib import Path
root = Path(os.environ['VALIDATION_DIR'])
log = (root / 'self-test.log').read_text()
if 'AUTOMATED DISPOSABLE CHECKS PASS' not in log:
    raise SystemExit('Supplemental self-test pass marker missing; inspect ' + str(root))
for name in ['import.log', 'self-test.log', 'export.log']:
    text = (root / name).read_text()
    if 'SCRIPT ERROR:' in text or 'Parse Error:' in text or '\nERROR:' in text:
        raise SystemExit('Godot reported errors; inspect ' + str(root / name))
artifacts = {}
for name in ['index.html', 'index.js', 'index.pck', 'index.wasm']:
    path = root / 'export' / name
    if not path.is_file() or not path.stat().st_size:
        raise SystemExit('Expected browser-export artifact missing: ' + str(path))
    artifacts[name] = {'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
with (root / 'export/index.wasm').open('rb') as binary:
    if binary.read(4) != b'\0asm':
        raise SystemExit('Exported WASM header is invalid.')
report = {'checked_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'status': 'supplemental_install_validation_passed', 'fixture': '/tmp/ironwood-capability-probe',
          'build_id': 'v2', 'spin_rate': 2.0, 'validation_directory': str(root), 'artifacts': artifacts,
          'scope': 'automated dependency/self-test/export baseline; interactive Gate 0 is separate',
          'services_or_browsers_restarted': False, 'system_configuration_changed': False}
(root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
PY
