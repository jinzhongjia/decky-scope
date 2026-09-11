#!/usr/bin/env python3
"""Bundle prebuilt artifacts as a full Decky development ZIP (no remote binary downloads)."""
import json
import stat
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs/DeckScope-dev.zip"
FILES = [Path("main.py"), Path("plugin.json"), Path("package.json"), Path("dist/index.js"), Path("bin/deckscope-monitor")]
FILES += sorted(path.relative_to(ROOT) for path in (ROOT / "py_modules").glob("*.py"))
for relative in FILES:
    if not (ROOT / relative).is_file() or (ROOT / relative).stat().st_size == 0:
        raise SystemExit(f"Missing build artifact: {relative}")
name = json.loads((ROOT / "plugin.json").read_text())["name"]
assert name == "DeckScope"
OUT.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for relative in FILES:
        item = zipfile.ZipInfo(f"{name}/{relative.as_posix()}", date_time=(2026, 1, 1, 0, 0, 0))
        item.compress_type = zipfile.ZIP_DEFLATED
        mode = 0o755 if relative.parts[0] == "bin" else 0o644
        item.external_attr = (stat.S_IFREG | mode) << 16
        archive.writestr(item, (ROOT / relative).read_bytes())
with zipfile.ZipFile(OUT) as archive:
    assert archive.testzip() is None
    assert all(not any(x in name for x in ("dev_mode", ".env", "settings.json", ".work/")) for name in archive.namelist())
print(OUT)
