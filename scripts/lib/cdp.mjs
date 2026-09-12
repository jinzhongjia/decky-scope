// Dependency-free CDP helpers for driving Steam's CEF (Chrome DevTools Protocol).
// Adapted from prior local development tooling; now maintained within this repository.
// Uses Node >= 22 globals: fetch + WebSocket.

export function localBaseUrl(
  value = process.env.DECK_CDP_URL || "http://127.0.0.1:8080",
) {
  const url = new URL(value);
  if (
    url.protocol !== "http:" ||
    !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname) ||
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    url.pathname !== "/"
  )
    throw new Error(
      "CDP must use a credential-free HTTP loopback URL; create an SSH tunnel first",
    );
  return url.origin;
}
export function websocketUrl(target, baseUrl) {
  const url = new URL(target.webSocketDebuggerUrl);
  if (
    !url.pathname.startsWith("/devtools/") ||
    !["ws:", "wss:"].includes(url.protocol)
  )
    throw new Error("Invalid CDP WebSocket path");
  url.protocol = "ws:";
  url.host = new URL(localBaseUrl(baseUrl)).host;
  url.username = "";
  url.password = "";
  return url.href;
}

const ALIAS_MATCHERS = {
  // "大屏" matches the localized gamepad-UI window title on zh-locale Steam
  bp: (target) => includesAny(titleOf(target), ["big picture", "大屏"]),
  bigpicture: (target) => includesAny(titleOf(target), ["big picture", "大屏"]),
  qam: (target) =>
    includesAny(titleOf(target), ["quickaccess", "quick access"]),
  quickaccess: (target) =>
    includesAny(titleOf(target), ["quickaccess", "quick access"]),
  shared: (target) => includesAny(titleOf(target), ["sharedjscontext"]),
  sjc: (target) => includesAny(titleOf(target), ["sharedjscontext"]),
  mainmenu: (target) => includesAny(titleOf(target), ["mainmenu"]),
};

const KEY_CODES = {
  ArrowUp: 38,
  ArrowDown: 40,
  ArrowLeft: 37,
  ArrowRight: 39,
  Enter: 13,
  Escape: 27,
  Space: 32,
  Tab: 9,
  Backspace: 8,
  Home: 36,
  End: 35,
  PageUp: 33,
  PageDown: 34,
};

const KEY_NAMES = {
  Space: " ",
};

function targetAlias(spec) {
  const key = String(spec || "").toLowerCase();
  return Object.hasOwn(ALIAS_MATCHERS, key) ? key : null;
}

export function resolveTarget(targets, spec) {
  if (!spec) throw new Error("target required");
  const usable = targets.filter((target) => target?.webSocketDebuggerUrl);
  const alias = targetAlias(spec);
  const needle = String(spec).toLowerCase();

  const match = alias
    ? usable.find(ALIAS_MATCHERS[alias])
    : usable.find(
        (target) => String(target.id || "").toLowerCase() === needle,
      ) ||
      usable.find((target) =>
        String(target.id || "")
          .toLowerCase()
          .startsWith(needle),
      ) ||
      usable.find((target) => titleOf(target).includes(needle));

  if (match) return match;

  const available = targets
    .map((target) => target.title || target.id || "?")
    .filter(Boolean)
    .join(", ");
  throw new Error(
    `no target matching "${spec}". Available: ${available || "(none)"}`,
  );
}

export async function fetchTargets(baseUrl = localBaseUrl()) {
  const response = await fetch(`${localBaseUrl(baseUrl)}/json`, {
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok)
    throw new Error(
      `target list failed: ${response.status} ${response.statusText}`,
    );
  return response.json();
}

export async function openSession(spec, options = {}) {
  const baseUrl = localBaseUrl(options.baseUrl);
  const target =
    typeof spec === "object"
      ? spec
      : resolveTarget(await fetchTargets(baseUrl), spec);
  const ws = new WebSocket(websocketUrl(target, baseUrl));
  const eventListeners = new Set();
  const pending = new Map();
  let nextId = 0;
  let closed = false;

  const failPending = (error) => {
    for (const { reject, timer } of pending.values()) {
      clearTimeout(timer);
      reject(error);
    }
    pending.clear();
  };

  ws.addEventListener("message", (event) => {
    let message;
    try {
      message = JSON.parse(event.data);
    } catch {
      failPending(new Error("Malformed CDP frame"));
      ws.close();
      return;
    }
    if (typeof message.id === "number" && pending.has(message.id)) {
      const { resolve, reject, timer } = pending.get(message.id);
      pending.delete(message.id);
      clearTimeout(timer);
      if (message.error)
        reject(
          new Error(message.error.message || JSON.stringify(message.error)),
        );
      else resolve(message.result || {});
      return;
    }
    for (const listener of eventListeners) {
      try {
        listener(message);
      } catch {
        /* Observer errors cannot break the session. */
      }
    }
  });

  ws.addEventListener("close", () => {
    closed = true;
    failPending(new Error("cdp websocket closed"));
  });
  ws.addEventListener("error", () => {
    failPending(new Error("cdp websocket failed"));
  });
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      ws.close();
      reject(new Error("CDP connection timed out"));
    }, options.timeoutMs ?? 8000);
    ws.addEventListener(
      "open",
      () => {
        clearTimeout(timer);
        resolve();
      },
      { once: true },
    );
    ws.addEventListener(
      "error",
      () => {
        clearTimeout(timer);
        reject(new Error("cdp websocket failed"));
      },
      { once: true },
    );
    ws.addEventListener(
      "close",
      () => {
        clearTimeout(timer);
        reject(new Error("cdp websocket closed before connection"));
      },
      { once: true },
    );
  });

  const call = (method, params = {}, callOptions = {}) => {
    if (closed) return Promise.reject(new Error("cdp websocket closed"));
    const id = ++nextId;
    const timeoutMs = callOptions.timeoutMs ?? options.timeoutMs ?? 15000;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`${method} timed out after ${timeoutMs}ms`));
      }, timeoutMs);
      pending.set(id, { resolve, reject, timer });
      ws.send(JSON.stringify({ id, method, params }));
    });
  };

  const session = {
    target,
    call,
    onEvent(listener) {
      eventListeners.add(listener);
      return () => eventListeners.delete(listener);
    },
    close() {
      closed = true;
      failPending(new Error("CDP session closed"));
      try {
        ws.close();
      } catch {}
    },
  };

  return session;
}

export async function evaluate(session, expression, options = {}) {
  if (options.enableRuntime !== false) await session.call("Runtime.enable", {});
  return session.call("Runtime.evaluate", {
    expression,
    returnByValue: options.returnByValue !== false,
    awaitPromise: options.awaitPromise !== false,
  });
}

export function runtimeValue(result) {
  if (result?.exceptionDetails)
    throw new Error(
      result.exceptionDetails.exception?.description ||
        result.exceptionDetails.text ||
        "Evaluation failed",
    );
  const value = result?.result?.value;
  if (value !== undefined) return value;
  const unserializable = result?.result?.unserializableValue;
  if (unserializable !== undefined) return unserializable;
  return result?.result?.description ?? result;
}

export async function captureScreenshot(session) {
  await session.call("Page.enable", {});
  const result = await session.call("Page.captureScreenshot", {
    format: "png",
  });
  if (!result.data)
    throw new Error(
      `no screenshot data: ${JSON.stringify(result).slice(0, 200)}`,
    );
  return Buffer.from(result.data, "base64");
}

export function keyEventParams(key) {
  if (Object.hasOwn(KEY_CODES, key)) {
    return {
      key: KEY_NAMES[key] || key,
      code: key,
      windowsVirtualKeyCode: KEY_CODES[key],
      nativeVirtualKeyCode: KEY_CODES[key],
    };
  }

  if (key.length === 1) {
    const upper = key.toUpperCase();
    const code = /[A-Z]/.test(upper)
      ? `Key${upper}`
      : /[0-9]/.test(key)
        ? `Digit${key}`
        : key;
    const keyCode = upper.charCodeAt(0);
    return {
      key,
      code,
      text: key,
      windowsVirtualKeyCode: keyCode,
      nativeVirtualKeyCode: keyCode,
    };
  }

  throw new Error(`unsupported key "${key}"`);
}

export async function dispatchKey(session, key, options = {}) {
  const params = keyEventParams(key);
  await session.call("Input.dispatchKeyEvent", { ...params, type: "keyDown" });
  if (options.holdMs) await sleep(options.holdMs);
  await session.call("Input.dispatchKeyEvent", { ...params, type: "keyUp" });
  if (options.settleMs !== 0) await sleep(options.settleMs ?? 120);
}

export function formatTargets(targets) {
  return targets
    .map((target) => {
      const alias =
        Object.entries(ALIAS_MATCHERS).find(([name, match]) => {
          if (["bigpicture", "quickaccess", "sjc"].includes(name)) return false;
          return target.webSocketDebuggerUrl && match(target);
        })?.[0] || "-";
      return `${alias.padEnd(8)} ${(target.id || "?").padEnd(34)} ${target.title || ""}`;
    })
    .join("\n");
}

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function titleOf(target) {
  return String(target?.title || "").toLowerCase();
}

function includesAny(value, needles) {
  return needles.some((needle) => value.includes(needle));
}

function trimTrailingSlash(value) {
  return String(value).replace(/\/+$/, "");
}
