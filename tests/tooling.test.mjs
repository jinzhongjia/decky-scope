import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  localBaseUrl,
  websocketUrl,
  resolveTarget,
  keyEventParams,
  runtimeValue,
  openSession,
} from "../scripts/lib/cdp.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
test("CDP accepts only credential-free loopback endpoints", () => {
  assert.equal(localBaseUrl("http://127.0.0.1:8123/"), "http://127.0.0.1:8123");
  for (const url of [
    "https://localhost:8080",
    "http://example.test",
    "http://user:password@localhost",
    "http://localhost/path",
    "http://localhost/?secret=1",
  ])
    assert.throws(() => localBaseUrl(url));
  assert.equal(
    websocketUrl(
      { webSocketDebuggerUrl: "ws://remote-host:8080/devtools/page/abc" },
      "http://127.0.0.1:9123",
    ),
    "ws://127.0.0.1:9123/devtools/page/abc",
  );
  assert.throws(() =>
    websocketUrl(
      { webSocketDebuggerUrl: "ws://localhost/not-cdp" },
      "http://127.0.0.1:8123",
    ),
  );
});
test("CDP target aliases and key parameters support Steam windows", () => {
  const targets = [
    {
      id: "q",
      title: "QuickAccess",
      webSocketDebuggerUrl: "ws://localhost/devtools/q",
    },
    {
      id: "b",
      title: "Steam 大屏模式",
      webSocketDebuggerUrl: "ws://localhost/devtools/b",
    },
  ];
  assert.equal(resolveTarget(targets, "qam").id, "q");
  assert.equal(resolveTarget(targets, "bp").id, "b");
  assert.throws(() => resolveTarget(targets, "absent"));
  assert.equal(keyEventParams("ArrowLeft").windowsVirtualKeyCode, 37);
  assert.throws(() => keyEventParams("UnknownKey"));
  assert.throws(
    () => runtimeValue({ exceptionDetails: { text: "bad probe" } }),
    /bad probe/,
  );
  assert.equal(runtimeValue({ result: { value: false } }), false);
});
test("CDP correlates replies and rejects errors, timeouts and pending close", async () => {
  const original = globalThis.WebSocket;
  class FakeSocket extends EventTarget {
    constructor(url) {
      super();
      this.url = url;
      queueMicrotask(() => this.dispatchEvent(new Event("open")));
    }
    send(text) {
      const m = JSON.parse(text);
      if (m.method === "hang") return;
      queueMicrotask(() =>
        this.dispatchEvent(
          new MessageEvent("message", {
            data: JSON.stringify(
              m.method === "fail"
                ? { id: m.id, error: { message: "refused" } }
                : { id: m.id, result: { echo: m.params } },
            ),
          }),
        ),
      );
    }
    close() {
      queueMicrotask(() => this.dispatchEvent(new Event("close")));
    }
  }
  globalThis.WebSocket = FakeSocket;
  try {
    const s = await openSession(
      { id: "test", webSocketDebuggerUrl: "ws://localhost/devtools/page/test" },
      { timeoutMs: 50 },
    );
    const [a, b] = await Promise.all([
      s.call("one", { n: 1 }),
      s.call("two", { n: 2 }),
    ]);
    assert.equal(a.echo.n, 1);
    assert.equal(b.echo.n, 2);
    await assert.rejects(s.call("fail"), /refused/);
    await assert.rejects(s.call("hang", {}, { timeoutMs: 5 }), /timed out/);
    const pending = s.call("hang");
    const rejected = assert.rejects(pending, /closed/);
    s.close();
    await rejected;
    await assert.rejects(s.call("one"), /closed/);
  } finally {
    globalThis.WebSocket = original;
  }
});
test("developer CLI help works offline and write RPCs require explicit intent", () => {
  for (const script of ["scripts/cdp.mjs", "scripts/check-dpad.mjs"]) {
    const text = execFileSync(process.execPath, [script, "--help"], {
      cwd: root,
      encoding: "utf8",
    });
    assert.ok(text.includes("DeckScope"));
  }
  assert.throws(
    () =>
      execFileSync(
        process.execPath,
        ["scripts/cdp.mjs", "rpc", "set_config", "[]"],
        { cwd: root, stdio: "pipe" },
      ),
    (error) => error.stderr.toString().includes("--allow-write"),
  );
  assert.throws(
    () =>
      execFileSync(
        process.execPath,
        ["scripts/cdp.mjs", "rpc", "set_consumer_state"],
        { cwd: root, stdio: "pipe" },
      ),
    (error) => error.stderr.toString().includes("allowlist"),
  );
});
