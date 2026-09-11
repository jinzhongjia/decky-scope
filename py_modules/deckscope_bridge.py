"""Decky control plane: stdlib only, no sampling and no history ownership."""
import asyncio
import os
import socket
import struct
import time
from pathlib import Path

import decky
from deckscope_protocol import Channel, MAX_LINE, failure
import deckscope_settings as settings


class Bridge:
    def __init__(self):
        self.root = Path(decky.DECKY_PLUGIN_DIR)
        self.runtime = Path(decky.DECKY_PLUGIN_RUNTIME_DIR) / "ipc"
        self.history = Path(decky.DECKY_PLUGIN_RUNTIME_DIR) / "history"
        self.settings_path = Path(decky.DECKY_PLUGIN_SETTINGS_DIR) / "settings.json"
        self.config = settings.load(self.settings_path)
        self.server = self.process = self.channel = self.supervisor = None
        self.accept_tasks = set()
        self.connected = asyncio.Event()
        self.spawned = asyncio.Event()
        self.stopping = False
        self.config_lock = asyncio.Lock()
        self.last_error = None

    async def start(self):
        self.runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.runtime, 0o700)
        self.history.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.socket_path = self.runtime / "deckscope.sock"
        # Private plugin-owned socket path; no user-controlled unlink target.
        if self.socket_path.exists():
            if not self.socket_path.is_socket():
                self.last_error = "unsafe_socket_path"
                return
            self.socket_path.unlink()
        self.server = await asyncio.start_unix_server(self._accept, str(self.socket_path), limit=MAX_LINE)
        os.chmod(self.socket_path, 0o600)
        self.supervisor = asyncio.create_task(self._supervise())

    async def _emit(self, name, data):
        await decky.emit(name, data)

    async def _accept(self, reader, writer):
        task = asyncio.current_task()
        self.accept_tasks.add(task)
        channel = None
        try:
            await asyncio.wait_for(self.spawned.wait(), 5)
            sock = writer.get_extra_info("socket")
            pid, uid, _ = struct.unpack("3i", sock.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
            if not self.process or pid != self.process.pid or uid != os.getuid() or self.channel:
                return
            channel = Channel(reader, writer, self._emit)
            self.channel = channel
            self.connected.set()
            await channel.run()
        except (OSError, asyncio.TimeoutError):
            pass
        finally:
            if self.channel is channel and channel is not None:
                self.channel = None
                self.connected.clear()
            writer.close()
            self.accept_tasks.discard(task)

    async def _stderr(self, stream):
        while await stream.readline():
            # Logs are deliberately metadata-only: no socket/user paths or payloads.
            decky.logger.warning("[monitor] diagnostic emitted; inspect local debug build")

    async def _supervise(self):
        starts = []
        while not self.stopping:
            now = time.monotonic()
            starts = [t for t in starts if now - t < 60]
            if len(starts) >= 3:
                self.last_error = "restart_limit"
                decky.logger.error("[bridge] monitor restart limit reached")
                return
            starts.append(now)
            self.spawned.clear()
            stderr_task = None
            try:
                self.process = await asyncio.create_subprocess_exec(
                    str(self.root / "bin" / "deckscope-monitor"), str(self.socket_path), str(self.history),
                    stdin=asyncio.subprocess.DEVNULL, stdout=asyncio.subprocess.DEVNULL,
                    stderr=asyncio.subprocess.PIPE, limit=8192,
                )
                self.spawned.set()
                stderr_task = asyncio.create_task(self._stderr(self.process.stderr))
                await asyncio.wait_for(self.connected.wait(), 5)
                reply = await self.channel.request("set_config", {"interval_ms": self.config["interval_ms"], "live_push": False})
                if not reply["ok"]:
                    raise RuntimeError("configuration_failed")
                self.last_error = None
                decky.logger.info("[bridge] monitor ready")
                await self.process.wait()
            except (OSError, asyncio.TimeoutError, RuntimeError):
                self.last_error = "monitor_start_failed"
            finally:
                if self.channel:
                    await self.channel.close()
                self.connected.clear()
                if self.process and self.process.returncode is None:
                    self.process.terminate()
                    try:
                        await asyncio.wait_for(self.process.wait(), 2)
                    except asyncio.TimeoutError:
                        self.process.kill()
                        await self.process.wait()
                if stderr_task:
                    stderr_task.cancel()
                    await asyncio.gather(stderr_task, return_exceptions=True)
                self.process = None
                self.spawned.clear()
            if not self.stopping:
                await asyncio.sleep(min(len(starts), 3))  # bounded process-restart backoff, not metric polling

    async def _request(self, method, args=None):
        if not self.channel:
            try:
                await asyncio.wait_for(self.connected.wait(), 3)
            except asyncio.TimeoutError:
                return failure(self.last_error or "monitor_unavailable")
        channel = self.channel
        if not channel:
            return failure("monitor_unavailable")
        try:
            return await channel.request(method, args)
        except (TypeError, ValueError):
            return failure("invalid_request")

    async def get_status(self):
        reply = await self._request("get_status")
        if reply["ok"]:
            reply["data"]["settings"] = dict(self.config)
        return reply

    async def get_device_info(self):
        reply = await self._request("get_device_info")
        if reply["ok"]:
            reply["data"]["decky_version"] = str(getattr(decky, "DECKY_VERSION", "unknown"))
        return reply

    async def get_connectivity(self):
        return await self._request("get_connectivity")

    async def query_history(self, args: dict):
        if not isinstance(args, dict):
            return failure("invalid_request")
        return await self._request("query_history", args)

    async def set_config(self, args: dict):
        if not isinstance(args, dict) or set(args) - {"interval_ms", "live_push", "privacy_mask"}:
            return failure("invalid_request")
        if "interval_ms" in args and (type(args["interval_ms"]) is not int or not 500 <= args["interval_ms"] <= 5000):
            return failure("invalid_request")
        if any(key in args and type(args[key]) is not bool for key in ("live_push", "privacy_mask")):
            return failure("invalid_request")
        async with self.config_lock:
            control = {k: v for k, v in args.items() if k != "privacy_mask"}
            reply = await self._request("set_config", control)
            if not reply["ok"]:
                return reply
            new = self.config | {k: v for k, v in args.items() if k != "live_push"}
            if new != self.config:
                try:
                    await asyncio.to_thread(settings.save, self.settings_path, new)
                except OSError:
                    await self._request("set_config", {"interval_ms": self.config["interval_ms"]})
                    return failure("settings_write_failed")
                self.config = new
            return reply

    async def export_summary(self):
        reply = await self.get_device_info()
        if not reply["ok"]:
            return reply
        # Whitelist, rather than regex-redacting arbitrary process/device data.
        safe = {k: reply["data"].get(k, "unknown") for k in (
            "monitor_version", "os_name", "os_version", "os_build", "kernel", "arch", "profile", "decky_version")}
        return {"ok": True, "data": {"text": "DeckScope environment\n" + "\n".join(f"{k}: {v}" for k, v in safe.items())}}

    async def unload(self):
        self.stopping = True
        if self.channel:
            await self.channel.request("flush")
            await self.channel.close()
        if self.supervisor:
            self.supervisor.cancel()
            await asyncio.gather(self.supervisor, return_exceptions=True)
        if self.server:
            self.server.close()
            await self.server.wait_closed()
        for task in list(self.accept_tasks):
            task.cancel()
        await asyncio.gather(*self.accept_tasks, return_exceptions=True)
        if getattr(self, "socket_path", None) and self.socket_path.is_socket():
            self.socket_path.unlink()
