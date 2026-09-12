#!/usr/bin/env node
import fs from "node:fs";
import assert from "node:assert/strict";
import {
  openSession,
  evaluate,
  runtimeValue,
  dispatchKey,
  sleep,
} from "./lib/cdp.mjs";
const args = process.argv.slice(2);
if (args.includes("--help") || !args.includes("--confirm")) {
  console.log(
    "Usage: node scripts/check-dpad.mjs --confirm [--out path.json]\nOpen DeckScope first with cdp.mjs qam open. Sends bounded directional/Enter input; does not exercise touchscreen or activate configuration actions.",
  );
  process.exit(args.includes("--help") ? 0 : 2);
}
const output = args.includes("--out")
  ? args[args.indexOf("--out") + 1]
  : new URL("../.work/debug/dpad.json", import.meta.url);
if (!output) throw Error("--out requires a file path");
const s = await openSession("qam");
async function ev(code) {
  const r = await evaluate(s, code);
  if (r.exceptionDetails) throw Error(r.exceptionDetails.text);
  return runtimeValue(r);
}
const key = (k) => dispatchKey(s, k, { settleMs: 70 });
const state = () =>
  ev(
    `(()=>{const focus=document.querySelector('.ds .gpfocus');const nodes=[...document.querySelectorAll('.ds button:not([disabled]), .ds .ds-kv, .ds [role="switch"], .ds .Focusable')];const node=focus&&(focus.closest('button,.ds-kv,[role="switch"]')||focus);const nav=[...document.querySelectorAll('.ds-nav button')];return {index:nodes.indexOf(node),nav:nav.findIndex(n=>n===node||n.contains(node)),label:node?.textContent?.trim().slice(0,70),group:node?.closest('.ds-actions,.ds-ranges,.ds-power-modes,.ds-monitor-toolbar')?.className};})()`,
  );
const result = [];
try {
  assert.equal(
    await ev("!!document.querySelector('.ds')"),
    true,
    "DeckScope must already be open",
  );
  await ev("document.querySelector('.ds-nav button').focus()");
  await key("ArrowRight");
  await key("ArrowLeft");
  for (let view = 0; view < 3; view++) {
    let current = await state();
    for (let i = 0; current.nav < 0 && i < 65; i++) {
      await key("ArrowUp");
      current = await state();
    }
    assert.ok(current.nav >= 0, "header reachable from page body");
    for (let n = 0; current.nav !== view && n < 6; n++) {
      await key(current.nav < view ? "ArrowRight" : "ArrowLeft");
      current = await state();
    }
    assert.equal(current.nav, view, "requested view header reachable");
    await key("Enter");
    await sleep(500);
    const selected = await ev(
      "document.querySelector('.ds-nav button[aria-pressed=true]')?.textContent.trim()",
    );
    assert.equal(
      await ev(
        "[...document.querySelectorAll('.ds-nav button')].findIndex(e=>e.getAttribute('aria-pressed')==='true')",
      ),
      view,
    );
    const visited = [],
      seen = new Set();
    let repeat = 0;
    for (let step = 0; step < 60; step++) {
      await key("ArrowDown");
      let p = await state();
      if (p.index < 0) break;
      if (seen.has(p.index)) {
        if (++repeat >= 2) break;
      } else repeat = 0;
      if (!seen.has(p.index)) {
        seen.add(p.index);
        visited.push(p);
      }
      if (p.group) {
        let previous = p;
        for (let r = 0; r < 4; r++) {
          await key("ArrowRight");
          const next = await state();
          if (next.index === previous.index || next.group !== p.group) break;
          if (!seen.has(next.index)) {
            seen.add(next.index);
            visited.push(next);
          }
          previous = next;
        }
        // Return left within this group before the next downward step.
        for (let l = 0; l < 4; l++) {
          const a = await state();
          await key("ArrowLeft");
          const b = await state();
          // Native groups can remember their right-hand entry point.
          if (b.group === p.group && !seen.has(b.index)) {
            seen.add(b.index);
            visited.push(b);
          }
          if (a.index === b.index) break;
          if (b.group !== p.group) {
            await key("ArrowRight");
            break;
          }
        }
      }
    }
    const required = await ev(
      `(()=>{const out=[];for(const e of document.querySelectorAll('.ds button:not([disabled])')){if(e.closest('.ds-nav'))continue;const nodes=[...document.querySelectorAll('.ds button:not([disabled]),.ds .ds-kv,.ds [role="switch"], .ds .Focusable')];out.push({index:nodes.indexOf(e),label:e.textContent.trim()});}return out;})()`,
    );
    const missing = required.filter((x) => !seen.has(x.index));
    result.push({ view: selected, visited, missing });
    assert.equal(
      missing.length,
      0,
      JSON.stringify({ view: selected, missing }),
    );
  }
  fs.mkdirSync(new URL("../.work/debug/", import.meta.url), {
    recursive: true,
  });
  fs.writeFileSync(
    output,
    JSON.stringify(
      {
        version: 1,
        method:
          "CEF directional keys; not physical-controller or touch acceptance",
        views: result,
      },
      null,
      2,
    ) + "\n",
  );
  console.log(
    JSON.stringify(
      result.map((x) => ({
        view: x.view,
        visited: x.visited.map((n) => n.label),
        missing: x.missing,
      })),
      null,
      2,
    ),
  );
} finally {
  s.close();
}
