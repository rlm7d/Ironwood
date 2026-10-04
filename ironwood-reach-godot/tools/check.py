#!/usr/bin/env python3
"""Run deterministic simulation assertions and save evidence; no services are started."""
import json
from pathlib import Path
import re
import subprocess
import tempfile
from build import build_id, source_manifest
from tool_runtime import GODOT_VERSION, OWNER, ROOT, RUNTIME, godot_binary, godot_environment, now, owned_directory, sha256


def main():
    environment = godot_environment()
    godot = godot_binary(environment)
    test = ROOT / "tests/simulation_tests.gd"
    if test.is_symlink() or not test.is_file():
        raise RuntimeError("A regular simulation test script is required.")
    evidence = owned_directory(ROOT / "docs/evidence") / "simulation.json"
    if evidence.is_symlink():
        raise RuntimeError("Preserving unexpected simulation evidence symlink.")
    prior_hash = None
    if evidence.exists():
        if not evidence.is_file() or json.loads(evidence.read_text()).get("owner") != OWNER:
            raise RuntimeError("Preserving unrecognized simulation evidence.")
        prior_hash = sha256(evidence)
    sources = source_manifest()
    tests = {str(test.relative_to(ROOT)): {"bytes": test.stat().st_size, "sha256": sha256(test)}}
    command = [godot, "--headless", "--path", str(ROOT / "game"), "--script", str(test)]
    started = now()
    timed_out = False
    try:
        result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True,
                                text=True, timeout=120)
        exit_code, stdout, stderr = result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired as error:
        timed_out = True
        exit_code = 124
        stdout, stderr = error.stdout or "", error.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", errors="replace")
    match = re.search(r"^SIMULATION TESTS PASS: (\d+) checks$", stdout, re.M)
    failures = re.search(r"^SIMULATION TESTS FAIL: (\d+)/(\d+) checks failed$", stderr, re.M)
    sources_unchanged = sources == source_manifest() and tests[next(iter(tests))]["sha256"] == sha256(test)
    clean_output = not re.search(r"SCRIPT ERROR:|Parse Error:|^ERROR:", stdout + "\n" + stderr, re.M)
    passed = exit_code == 0 and match is not None and int(match[1]) > 0 and clean_output and sources_unchanged
    report = {"owner": OWNER, "scope": "Automated deterministic simulation assertions only",
              "status": "passed" if passed else "failed", "build_id": build_id(),
              "started_at": started, "finished_at": now(), "godot_version": GODOT_VERSION,
              "command": command, "timeout_seconds": 120, "timed_out": timed_out,
              "exit_code": exit_code, "checks": int(match[1]) if match else (int(failures[2]) if failures else None),
              "failed_checks": int(failures[1]) if failures else (0 if passed else None),
              "sources_unchanged_during_check": sources_unchanged, "sources": sources, "tests": tests,
              "tool_hashes": {name: sha256(ROOT / name) for name in ("tools/check.py", "tools/tool_runtime.py")},
              "stdout": stdout, "stderr": stderr}
    if evidence.is_symlink() or (prior_hash is None and evidence.exists()) or (prior_hash is not None and (not evidence.is_file() or sha256(evidence) != prior_hash)):
        raise RuntimeError("Evidence changed during the check; preserving it.")
    if prior_hash is not None:
        history = owned_directory(RUNTIME / "check-history")
        with (history / ("simulation-" + started.replace(":", "-") + ".json")).open("xb") as output:
            output.write(evidence.read_bytes())
    descriptor, temporary = tempfile.mkstemp(prefix=".simulation-", suffix=".json", dir=evidence.parent)
    with open(descriptor, "w") as output:
        output.write(json.dumps(report, indent=2) + "\n")
    Path(temporary).replace(evidence)
    print(json.dumps({"status": report["status"], "build_id": report["build_id"],
                      "checks": report["checks"], "exit_code": exit_code,
                      "godot_version": GODOT_VERSION, "evidence": str(evidence)}))
    return 0 if passed else (exit_code if exit_code > 0 else 1)


if __name__ == "__main__":
    raise SystemExit(main())
