#!/usr/bin/env python3
"""Import/export a pinned Godot Web candidate without replacing unknown files."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from tool_runtime import BUILDS, GAME, GODOT_VERSION, OWNER, ROOT, RUNTIME, candidate_lease, godot_binary, godot_environment, now, owned_directory, sha256, verify_web_template


def build_id():
    rules = GAME / "scripts/shared/rules.gd"
    match = re.search(r'^\s*const\s+BUILD_ID\s*(?::=|=)\s*"([A-Za-z0-9_-]+)"', rules.read_text(), re.M)
    if not match:
        raise RuntimeError("Rules.BUILD_ID must be a literal safe candidate identifier.")
    return match.group(1)


def source_manifest():
    manifest = {}
    for path in sorted(GAME.rglob("*")):
        relative = path.relative_to(GAME)
        if ".godot" in relative.parts:
            continue
        if path.is_symlink():
            raise RuntimeError(f"Preserving unexpected game-source symlink: {relative}")
        if path.is_dir():
            continue
        manifest[str(relative)] = {"bytes": path.stat().st_size, "sha256": sha256(path)}
    return manifest


def existing_candidate(directory, identifier):
    if directory.is_symlink():
        raise RuntimeError("Preserving unexpected build-directory symlink.")
    if not directory.exists():
        return None
    marker = directory / ".ironwood-build.json"
    if not marker.is_file() or marker.is_symlink():
        raise RuntimeError("Existing candidate has no owned build marker; preserving all files.")
    prior = json.loads(marker.read_text())
    if prior.get("owner") != OWNER or prior.get("build_id") != identifier:
        raise RuntimeError("Existing build marker is unrecognized; preserving all files.")
    expected = set(prior.get("artifacts", {})) | {marker.name, "build-manifest.json"}
    actual = {path.name for path in directory.iterdir()}
    if actual != expected:
        raise RuntimeError("Unexpected files exist in the candidate; preserving them.")
    for name, details in prior["artifacts"].items():
        path = directory / name
        if Path(name).name != name or path.is_symlink() or not path.is_file() or sha256(path) != details["sha256"]:
            raise RuntimeError(f"Existing candidate artifact changed; preserving {name}.")
    manifest = directory / "build-manifest.json"
    if manifest.is_symlink() or json.loads(manifest.read_text()) != prior:
        raise RuntimeError("Existing candidate manifest changed; preserving it.")
    return prior


def run_godot(command, environment, log):
    with log.open("x") as output:
        result = subprocess.run(command, env=environment, cwd=ROOT,
                                stdout=output, stderr=subprocess.STDOUT, timeout=180)
    text = re.sub(r'\x1b\[[0-9;]*m', '', log.read_text())
    if result.returncode or "SCRIPT ERROR:" in text or "Parse Error:" in text or re.search(r'^ERROR:', text, re.M):
        raise RuntimeError(f"Godot import/export failed; inspect {log}.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rebuild", action="store_true", help="Rebuild even when the current source/artifacts match")
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    environment = godot_environment(use_templates=True)
    godot = godot_binary(environment)
    template = verify_web_template(environment)
    for name in ["project.godot", "export_presets.cfg", "main.tscn", "main.gd",
                 "scripts/shared/rules.gd", "scripts/client/battlefield.gd", "scripts/server/session_server.gd"]:
        if not (GAME / name).is_file():
            raise RuntimeError(f"Required game source is not present yet: {name}.")
    if 'renderer/rendering_method="gl_compatibility"' not in (GAME / "project.godot").read_text():
        raise RuntimeError("Expected Compatibility rendering in the Godot project.")
    if 'variant/thread_support=false' not in (GAME / "export_presets.cfg").read_text():
        raise RuntimeError("Expected the browser-compatible non-threaded Web preset.")
    identifier = build_id()
    sources = source_manifest()
    if args.check_only:
        print(json.dumps({"status": "toolchain_and_source_prerequisites_ready", "godot": GODOT_VERSION,
                          "build_id": identifier, "source_files": len(sources), "template": template}))
        return
    with candidate_lease(identifier):
        publish(args, environment, godot, identifier, sources, template)


def publish(args, environment, godot, identifier, sources, template):
    owned_directory(BUILDS)
    target = BUILDS / identifier
    previous = existing_candidate(target, identifier)
    if previous and previous.get("sources") == sources and not args.rebuild:
        print(json.dumps({"status": "reused_verified_candidate", "build_id": identifier,
                          "entry": str(target / "index.html"), "manifest": str(target / "build-manifest.json")}))
        return
    stage_parent = owned_directory(RUNTIME / "build-staging")
    stage = Path(tempfile.mkdtemp(prefix=identifier + "-", dir=stage_parent))
    export = owned_directory(stage / "export")
    run_godot([godot, "--headless", "--path", str(GAME), "--import", "--log-file", str(stage / "import-engine.log")],
              environment, stage / "import.log")
    sources = source_manifest()
    run_godot([godot, "--headless", "--path", str(GAME), "--log-file", str(stage / "export-engine.log"),
               "--export-release", "Web", str(export / "index.html")], environment, stage / "export.log")
    if source_manifest() != sources:
        raise RuntimeError("Game sources changed during export; candidate preserved. Retry after the edit finishes.")
    for name in ["index.html", "index.js", "index.pck", "index.wasm"]:
        if not (export / name).is_file() or not (export / name).stat().st_size:
            raise RuntimeError(f"Expected Web export is missing: {name}.")
    with (export / "index.wasm").open("rb") as wasm:
        if wasm.read(4) != b"\x00asm":
            raise RuntimeError("Exported WebAssembly header is invalid.")
    artifacts = {path.name: {"bytes": path.stat().st_size, "sha256": sha256(path)}
                 for path in sorted(export.iterdir()) if path.is_file()}
    report = {"owner": OWNER, "build_id": identifier, "built_at": now(), "godot": GODOT_VERSION,
              "rendering": "Compatibility", "threads": False, "sources": sources, "artifacts": artifacts,
              "template": template,
              "validation": "Godot import/export and artifact integrity only; interactive play evidence is separate"}
    text = json.dumps(report, indent=2) + "\n"
    (export / ".ironwood-build.json").write_text(text)
    (export / "build-manifest.json").write_text(text)
    if previous:
        # Revalidate immediately before updating only this owned candidate.
        if existing_candidate(target, identifier) != previous:
            raise RuntimeError("Candidate changed during build; preserving it.")
        history = owned_directory(RUNTIME / "build-history")
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        shutil.copytree(target, history / (identifier + "-" + stamp))
        for path in target.iterdir():
            path.unlink()
        for path in export.iterdir():
            shutil.move(str(path), target / path.name)
    else:
        if target.exists() or target.is_symlink():
            raise RuntimeError("A candidate appeared during build; preserving it.")
        export.rename(target)
    print(json.dumps({"status": "built_candidate", "build_id": identifier, "entry": str(target / "index.html"),
                      "manifest": str(target / "build-manifest.json"), "logs": str(stage)}))


if __name__ == "__main__":
    main()
