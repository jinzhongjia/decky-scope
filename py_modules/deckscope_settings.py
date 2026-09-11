"""Private atomic settings; live subscriptions are deliberately not persisted."""
import json
import os
import tempfile
from pathlib import Path

DEFAULTS = {"schema_version": 1, "interval_ms": 1000, "privacy_mask": True}


def load(path: Path) -> dict:
    try:
        data = json.loads(path.read_text())
        if not isinstance(data, dict) or data.get("schema_version") != 1:
            return DEFAULTS.copy()
        result = DEFAULTS.copy()
        if type(data.get("interval_ms")) is int and 500 <= data["interval_ms"] <= 5000:
            result["interval_ms"] = data["interval_ms"]
        if type(data.get("privacy_mask")) is bool:
            result["privacy_mask"] = data["privacy_mask"]
        return result
    except (OSError, ValueError):
        return DEFAULTS.copy()


def save(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(prefix=".settings-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            os.fchmod(stream.fileno(), 0o600)
            json.dump(data, stream, separators=(",", ":"))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)
