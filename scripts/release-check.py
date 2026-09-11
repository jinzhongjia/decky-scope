#!/usr/bin/env python3
"""Mechanical release checks only; not license advice or store approval."""
import argparse
import hashlib
import json
import re
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def inspect():
    package = json.loads((ROOT / "package.json").read_text())
    plugin = json.loads((ROOT / "plugin.json").read_text())
    version = package["version"]
    problems = []
    model = (ROOT / "monitor/src/model.zig").read_text()
    if f'pub const version = "{version}";' not in model:
        problems.append("Native/package versions differ")
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version):
        problems.append("Invalid version")
    for required in ("bin/deckscope-monitor", "dist/index.js"):
        path = ROOT / required
        if not path.is_file() or not path.stat().st_size:
            problems.append(f"Missing {required}")
    archive = ROOT / "outputs/DeckScope-dev.zip"
    if not archive.is_file():
        problems.append("Missing development ZIP; run scripts/check.sh")
    else:
        with zipfile.ZipFile(archive) as z:
            if z.testzip():
                problems.append("ZIP checksum failed")
            for relative in ("main.py", "plugin.json", "package.json", "dist/index.js", "bin/deckscope-monitor"):
                name = f'{plugin["name"]}/{relative}'
                if name not in z.namelist() or z.read(name) != (ROOT / relative).read_bytes():
                    problems.append(f"Stale archive: {relative}")
            for path in (ROOT / "py_modules").glob("*.py"):
                if z.read(f'{plugin["name"]}/py_modules/{path.name}') != path.read_bytes():
                    problems.append(f"Stale archive: {path.name}")
    public = []
    if not any((ROOT / name).is_file() for name in ("LICENSE", "LICENSE.md", "LICENSE.txt")):
        public.append("Main license and reference-code authorization unresolved")
    if not (ROOT / "THIRD-PARTY-NOTICES.md").is_file():
        public.append("Third-party redistribution notices not finalized")
    if not plugin.get("publish", {}).get("image"):
        public.append("No public store image URL")
    remote = subprocess.run(["git", "remote"], cwd=ROOT, capture_output=True, text=True, check=True)
    if not remote.stdout.strip():
        public.append("No release repository configured")
    if not package.get("packageManager", "").startswith("pnpm@9."):
        public.append("Official-template pnpm 9 build compatibility not verified")
    if not (ROOT / "backend").is_dir():
        public.append("Official custom-backend build integration not present")
    if "-" in version:
        public.append("Version is a prerelease, not a stable release")
    return {"version": version, "candidate_ok": not problems, "candidate_errors": problems,
            "zip_sha256": hashlib.sha256(archive.read_bytes()).hexdigest() if archive.is_file() else None,
            "public_preflight_ok": not public, "public_blockers": public,
            "manual_review_required": ["License and redistribution", "Store and compatibility acceptance", "Explicit approval before public actions"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--public", action="store_true", help="Fail for unresolved public-release gates")
    args = parser.parse_args()
    result = inspect()
    print(json.dumps(result, indent=2, ensure_ascii=False))
    raise SystemExit(0 if result["candidate_ok"] and (not args.public or result["public_preflight_ok"]) else 1)
