#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  fetchTargets,
  formatTargets,
  openSession,
  evaluate,
  runtimeValue,
  captureScreenshot,
  dispatchKey,
  sleep,
} from "./lib/cdp.mjs";

const directory = path.dirname(fileURLToPath(import.meta.url));
const help = `DeckScope CDP tooling (Node 22+; SSH loopback tunnel required)
  node scripts/cdp.mjs targets
  node scripts/cdp.mjs qam open|close
  node scripts/cdp.mjs keys qam ArrowDown ArrowRight Enter
  node scripts/cdp.mjs screenshot qam .work/debug/qam.png
  node scripts/cdp.mjs eval shared path/to/explicit-probe.js
  node scripts/cdp.mjs rpc get_status
  node scripts/cdp.mjs rpc query_history '[{"from":0,"to":1,"max_points":10,"metric":"gpu_pct"}]'
  node scripts/cdp.mjs rpc set_config '[{"privacy_mask":true}]' --allow-write
Environment: DECK_CDP_URL=http://127.0.0.1:8080 (loopback only).
Screenshots, arbitrary eval, clipboard/config changes and UI input require task authorization.
No command enables CEF, changes its bind address, or reconnects Decky's event map.`;

async function using(target, work) {
  const session = await openSession(target);
  try {
    return await work(session);
  } finally {
    session.close();
  }
}
const probe = (name) =>
  fs.readFileSync(path.join(directory, "probes", name + ".js"), "utf8");
async function main(args) {
  const [command, ...rest] = args;
  if (!command || ["--help", "-h", "help"].includes(command)) {
    console.log(help);
    return;
  }
  if (command === "targets") {
    console.log(formatTargets(await fetchTargets()));
    return;
  }
  if (command === "qam") {
    const action = rest[0];
    if (!["open", "close"].includes(action))
      throw Error("Expected qam open|close");
    const result = await using("shared", async (s) =>
      runtimeValue(await evaluate(s, probe("qam-" + action))),
    );
    if (
      result !== (action === "open" ? "opened Decky QAM" : "closed side menus")
    )
      throw Error(
        "Steam QAM navigation API unavailable; inspect the current host before retrying",
      );
    if (action === "open") {
      await sleep(750);
      const selected = await using("qam", async (s) =>
        runtimeValue(
          await evaluate(
            s,
            "document.querySelector('.ds[data-deckscope=\"qam-only\"]') ? 'selected DeckScope' : " +
              probe("qam-select"),
          ),
        ),
      );
      if (selected !== "selected DeckScope")
        throw Error(
          "DeckScope entry missing. Open the Decky plugin list or confirm installation.",
        );
      await sleep(350);
    }
    console.log(action === "open" ? "DeckScope QAM opened" : "QAM closed");
    return;
  }
  if (command === "rpc") {
    const [method, input = "[]", flag] = rest;
    const writes = ["set_config"];
    if (
      ![
        "get_status",
        "get_device_info",
        "get_connectivity",
        "query_history",
        "export_summary",
        ...writes,
      ].includes(method)
    )
      throw Error("RPC method is not in the project tool allowlist");
    if (writes.includes(method) && flag !== "--allow-write")
      throw Error("Write RPC requires explicit --allow-write");
    const params = JSON.parse(input);
    if (!Array.isArray(params))
      throw Error("RPC arguments must be a JSON array");
    const expression = `DeckyBackend.call('loader/call_plugin_method','DeckScope',${JSON.stringify(method)},...${JSON.stringify(params)})`;
    const value = await using("shared", async (s) =>
      runtimeValue(await evaluate(s, expression)),
    );
    console.log(JSON.stringify(value, null, 2));
    if (value?.ok === false) throw Error("Plugin RPC returned an error");
    return;
  }
  const [target, ...values] = rest;
  if (!target) throw Error("Target required");
  if (command === "keys") {
    if (!values.length || values.length > 100)
      throw Error("Supply 1..100 explicit keys");
    await using(target, async (s) => {
      for (const key of values) await dispatchKey(s, key);
    });
    return;
  }
  if (command === "screenshot") {
    const destination = values[0];
    if (!destination || !destination.endsWith(".png"))
      throw Error("Output .png path required");
    const image = await using(target, captureScreenshot);
    fs.mkdirSync(path.dirname(path.resolve(destination)), { recursive: true });
    fs.writeFileSync(destination, image);
    console.log(path.resolve(destination));
    return;
  }
  if (command === "eval") {
    if (!values[0]) throw Error("Explicit JavaScript file required");
    const source = fs.readFileSync(values[0], "utf8");
    console.log(
      JSON.stringify(
        await using(target, async (s) =>
          runtimeValue(await evaluate(s, source)),
        ),
        null,
        2,
      ),
    );
    return;
  }
  throw Error("Unknown command; use --help");
}
main(process.argv.slice(2)).catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
