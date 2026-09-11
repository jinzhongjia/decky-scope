"""Bounded NDJSON control channel. Never log raw frames."""
import asyncio
import json

MAX_LINE = 256 * 1024


def failure(code: str) -> dict:
    return {"ok": False, "error": {"code": code, "message": code}}


class Channel:
    def __init__(self, reader, writer, emit):
        self.reader, self.writer, self.emit = reader, writer, emit
        self.pending = {}
        self.next_id = 0
        self.lock = asyncio.Lock()
        self.closed = False

    async def request(self, method: str, args: dict | None = None) -> dict:
        if self.closed or len(self.pending) >= 32:
            return failure("monitor_busy" if not self.closed else "monitor_unavailable")
        self.next_id = self.next_id % 0xFFFFFFFF + 1
        rid = self.next_id
        body = json.dumps({"type": "request", "id": rid, "method": method, "args": args or {}},
                          separators=(",", ":"), allow_nan=False).encode() + b"\n"
        if len(body) > MAX_LINE:
            return failure("request_too_large")
        future = asyncio.get_running_loop().create_future()
        self.pending[rid] = future
        try:
            async with self.lock:
                self.writer.write(body)
                await asyncio.wait_for(self.writer.drain(), 3)
            return await asyncio.wait_for(future, 5)
        except asyncio.TimeoutError:
            return failure("monitor_timeout")
        except (OSError, ConnectionError):
            return failure("monitor_unavailable")
        finally:
            self.pending.pop(rid, None)

    async def run(self):
        try:
            while True:
                line = await self.reader.readline()
                if not line:
                    break
                if len(line) > MAX_LINE or not line.endswith(b"\n"):
                    raise ValueError("frame_limit")
                msg = json.loads(line)
                if not isinstance(msg, dict):
                    raise ValueError("invalid_frame")
                if msg.get("type") == "response":
                    rid = msg.get("id")
                    if type(rid) is not int or type(msg.get("ok")) is not bool:
                        raise ValueError("invalid_response")
                    if msg["ok"] and not isinstance(msg.get("data"), dict):
                        raise ValueError("invalid_response")
                    if not msg["ok"] and not isinstance(msg.get("error"), dict):
                        raise ValueError("invalid_response")
                    future = self.pending.get(rid)
                    if future and not future.done():
                        future.set_result({k: v for k, v in msg.items() if k in ("ok", "data", "error")})
                elif msg.get("type") == "event":
                    if msg.get("name") in {"metrics", "connectivity_changed", "source_changed"} and isinstance(msg.get("data"), dict):
                        try:
                            await self.emit(msg["name"], msg["data"])
                        except Exception:
                            pass  # CEF reload must not terminate collection.
                else:
                    raise ValueError("invalid_frame")
        except (ValueError, OSError, ConnectionError):
            pass
        finally:
            await self.close()

    async def close(self):
        self.closed = True
        for future in self.pending.values():
            if not future.done():
                future.set_result(failure("monitor_unavailable"))
        self.writer.close()
        try:
            await self.writer.wait_closed()
        except (OSError, ConnectionError):
            pass
