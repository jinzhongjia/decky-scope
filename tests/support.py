import json
import os
import socket
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("MONITOR_BINARY", ROOT / "monitor/zig-out/bin/deckscope-monitor"))


def put(root, name, text):
    path = Path(root) / name.lstrip("/")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(str(text))


def fixture(root, board="Galileo", cpus=8, battery="BAT1", gpu=True):
    put(root, "sys/class/dmi/id/board_name", board)
    put(root, "sys/class/dmi/id/bios_version", "TEST-BIOS")
    put(root, "proc/sys/kernel/osrelease", "6.16-test")
    put(root, "etc/os-release", 'ID=steamos\nPRETTY_NAME="SteamOS"\nVERSION_ID=3.8\nBUILD_ID=fixture\n')
    update_cpu(root, cpus, 1)
    put(root, "proc/meminfo", "MemTotal: 16384000 kB\nMemAvailable: 8192000 kB\nSwapTotal: 2048000 kB\nSwapFree: 1024000 kB\n")
    for idx in range(cpus):
        put(root, f"sys/devices/system/cpu/cpu{idx}/cpufreq/scaling_cur_freq", "2400000\n")
    for item in ("cpu", "memory", "io"):
        put(root, f"proc/pressure/{item}", "some avg10=0.00 total=0\nfull avg10=0.00 total=0\n")
    name = "acpitz" if board in ("Jupiter", "Galileo") else "coretemp"
    put(root, "sys/class/hwmon/hwmon9/name", name)
    put(root, "sys/class/hwmon/hwmon9/temp1_input", 48000)
    if gpu:
        put(root, "sys/class/drm/card3/device/gpu_busy_percent", 17)
        put(root, "sys/class/drm/card3/device/hwmon/hwmon14/name", "amdgpu")
        put(root, "sys/class/drm/card3/device/hwmon/hwmon14/temp1_input", 51000)
        put(root, "sys/class/drm/card3/device/hwmon/hwmon14/power1_average", 8500000)
        put(root, "sys/class/drm/card3/device/hwmon/hwmon14/freq1_input", 600000000)
    if battery:
        base = f"sys/class/power_supply/{battery}"
        for key, value in {"type": "Battery", "present": 1, "capacity": 72, "power_now": 14000000, "status": "Discharging"}.items():
            put(root, f"{base}/{key}", value)


def update_cpu(root, cpus, factor):
    row = f"{100 * factor} 0 {100 * factor} {800 * factor} 0 0 0 0 50 0"
    put(root, "proc/stat", "cpu  " + row + "\n" + "\n".join(f"cpu{i} {row}" for i in range(cpus)) + "\n")


class Monitor:
    def __init__(self, directory, fixture_root=None):
        self.path = Path(directory)
        self.socket_path = self.path / "monitor.sock"
        self.socket_path.unlink(missing_ok=True)
        self.server = socket.socket(socket.AF_UNIX)
        self.server.bind(str(self.socket_path))
        self.server.listen(1)
        self.server.settimeout(5)
        self.log = tempfile.TemporaryFile()
        args = [str(BINARY), str(self.socket_path), str(self.path / "history")]
        if fixture_root:
            args.append(str(fixture_root))
        self.process = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=self.log)
        self.conn, _ = self.server.accept()
        self.conn.settimeout(5)
        self.buffer = b""
        self.events = []
        self.rid = 0

    def read(self):
        while b"\n" not in self.buffer:
            data = self.conn.recv(65536)
            if not data:
                raise EOFError("monitor disconnected")
            self.buffer += data
        line, self.buffer = self.buffer.split(b"\n", 1)
        return json.loads(line)

    def request(self, method, args=None):
        self.rid += 1
        self.conn.sendall((json.dumps({"type": "request", "id": self.rid, "method": method, "args": args or {}}) + "\n").encode())
        while True:
            msg = self.read()
            if msg.get("type") == "event":
                self.events.append(msg)
                continue
            return msg

    def close(self):
        self.conn.close()
        self.server.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
            raise
        self.log.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
