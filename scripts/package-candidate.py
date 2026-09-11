#!/usr/bin/env python3
"""Archive a verified private sideload candidate; never upload or publish."""
import hashlib
import importlib.util
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("release_check", ROOT / "scripts/release-check.py")
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)
result = check.inspect()
if not result["candidate_ok"]:
    raise SystemExit("Candidate preflight failed: " + "; ".join(result["candidate_errors"]))
path = ROOT / f'outputs/DeckScope-{result["version"]}.zip'
shutil.copyfile(ROOT / "outputs/DeckScope-dev.zip", path)
checksum = hashlib.sha256(path.read_bytes()).hexdigest()
assert checksum == result["zip_sha256"]
checksum_file = path.with_suffix(".zip.sha256")
checksum_file.write_text(f"{checksum}  {path.name}\n")
report = ROOT / "outputs/DeckScope-release-preflight.json"
report.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
print(path)
print(checksum_file)
print(report)
