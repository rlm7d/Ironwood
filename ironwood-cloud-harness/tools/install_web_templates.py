#!/usr/bin/env python3
"""Install only Godot 4.6.3 web templates, with the official archive checksum."""
import datetime as dt
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.6.3"
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable"
NAME = f"Godot_v{VERSION}-stable_export_templates.tpz"
CACHE = ROOT / "downloads"
CACHE.mkdir(exist_ok=True)
ARCHIVE = CACHE / NAME
TARGET = ROOT / "runtime/godot-data/godot/export_templates" / f"{VERSION}.stable"
RECEIPT = ROOT / "runtime/web-templates-receipt.json"
OFFICIAL_SHA512 = "da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68"
WEB_NAMES = {
    "web_debug.zip", "web_release.zip", "web_nothreads_debug.zip", "web_nothreads_release.zip",
    "web_dlink_debug.zip", "web_dlink_release.zip", "web_dlink_nothreads_debug.zip",
    "web_dlink_nothreads_release.zip",
}

def digest(path, algorithm="sha512"):
    result = hashlib.new(algorithm)
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()

def retained_templates_match(receipt):
    if (receipt.get("version") != VERSION or receipt.get("archive_name") != NAME
            or receipt.get("official_archive_sha512") != OFFICIAL_SHA512
            or receipt.get("official_checksums_url") != BASE + "/SHA512-SUMS.txt"):
        return False
    templates = receipt.get("templates", {})
    if set(templates) != WEB_NAMES:
        return False
    if {path.name for path in TARGET.glob("web_*.zip")} != WEB_NAMES:
        return False
    return all((TARGET / name).is_file()
               and (TARGET / name).stat().st_size == details.get("bytes")
               and digest(TARGET / name, "sha256") == details.get("sha256")
               for name, details in templates.items())

if RECEIPT.exists():
    receipt = json.loads(RECEIPT.read_text())
    if retained_templates_match(receipt):
        print(json.dumps({"status": "verified_cached_templates", "version": VERSION,
                          "templates": len(WEB_NAMES), "receipt": str(RECEIPT),
                          "network_used": False, "official_archive_sha512": OFFICIAL_SHA512}), flush=True)
        raise SystemExit(0)

with urllib.request.urlopen(BASE + "/SHA512-SUMS.txt", timeout=30) as response:
    sums = response.read().decode("utf-8")
expected = next(line.split()[0] for line in sums.splitlines() if line.split()[-1] == NAME)
if expected != OFFICIAL_SHA512:
    raise SystemExit("Official checksum listing differs from the pinned SHA-512; refusing installation.")
sums_file = ROOT / "evidence/godot-4.6.3-SHA512-SUMS.txt"
sums_file.parent.mkdir(exist_ok=True)
if sums_file.exists():
    if sums_file.read_text() != sums:
        raise SystemExit("Preserving unexpected existing checksum evidence.")
else:
    sums_file.write_text(sums)

if not ARCHIVE.exists():
    partial = ARCHIVE.with_suffix(".partial")
    count = 0
    milestone = 100 * 1024 * 1024
    with urllib.request.urlopen(BASE + "/" + NAME, timeout=30) as response, partial.open("wb") as output:
        print("Downloading official Godot web-template archive.", flush=True)
        for chunk in iter(lambda: response.read(1024 * 1024), b""):
            output.write(chunk)
            count += len(chunk)
            if count >= milestone:
                print(f"Downloaded {count // (1024 * 1024)} MiB.", flush=True)
                milestone += 100 * 1024 * 1024
    if digest(partial) != expected:
        partial.unlink()
        raise SystemExit("Official template checksum mismatch; no templates installed.")
    partial.rename(ARCHIVE)
elif digest(ARCHIVE) != expected:
    raise SystemExit("Cached archive checksum mismatch; refusing to use it.")

TARGET.mkdir(parents=True, exist_ok=True)
template_receipts = {}
with zipfile.ZipFile(ARCHIVE) as archive:
    entries = [entry for entry in archive.infolist()
               if Path(entry.filename).name.startswith("web_") and entry.filename.endswith(".zip")]
    if {Path(entry.filename).name for entry in entries} != WEB_NAMES or len(entries) != len(WEB_NAMES):
        raise SystemExit("The verified archive does not have the exact expected web-template set.")
    for entry in entries:
        data = archive.read(entry)
        target = TARGET / Path(entry.filename).name
        if target.exists() and target.read_bytes() != data:
            raise SystemExit(f"Preserving unexpected existing template: {target}")
        if not target.exists():
            with target.open("xb") as output:
                output.write(data)
        template_receipts[target.name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

new_receipt = {"version": VERSION, "archive_name": NAME,
               "official_archive_sha512": OFFICIAL_SHA512,
               "official_checksums_url": BASE + "/SHA512-SUMS.txt",
               "verified_at": dt.datetime.now(dt.timezone.utc).isoformat(),
               "templates": template_receipts}
if RECEIPT.exists():
    old_receipt = json.loads(RECEIPT.read_text())
    if any(old_receipt.get(key) != new_receipt[key] for key in new_receipt if key != "verified_at"):
        raise SystemExit("Preserving unexpected existing template receipt.")
else:
    with RECEIPT.open("x", encoding="utf-8") as output:
        output.write(json.dumps(new_receipt, indent=2) + "\n")
if not retained_templates_match(json.loads(RECEIPT.read_text())):
    raise SystemExit("Template receipt verification failed after installation.")
print(json.dumps({"status": "verified_archive_and_templates", "version": VERSION,
                  "templates": len(WEB_NAMES), "receipt": str(RECEIPT),
                  "official_archive_sha512": OFFICIAL_SHA512}), flush=True)
