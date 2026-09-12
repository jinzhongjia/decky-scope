# Debugging DeckScope

**Use the tools under this repository's `scripts/` directory.** This guide replaces the former dependency on sibling-project CDP helpers and local scratch scripts. It assumes an already-installed, authorized SteamOS device with SSH and CEF debugging available. It never enables those services or changes their network binding.[1]

## Boundaries

Device discovery and status reads are different from UI input, clipboard writes, plugin replacement and Loader restarts. Stay within the current task's authorization. Reconfirm if the target changes or the device is being used. Do not use an old recorded device address or password. Never record passwords in commands, source, environment files or logs. Prefer an existing SSH key/agent or an interactive SSH/sudo prompt.

Current UI acceptance is **D-pad reachability for all views and enabled controls**, retaining the approved rc.2 appearance. The user stopped touchscreen-specific investigation after observing similar behavior elsewhere. No host root cause was established. Do not revive touch testing or add workarounds unless requested.

## Start and verify an owned session

From the repository root, select and verify the actual target. `user@host` below is a placeholder, not a default:

```bash
bash scripts/discover.sh steamdeck.local
export DECK_HOST=user@host
bash scripts/device-check.sh

python3 scripts/debug-session.py start --ttl 1800
python3 scripts/debug-session.py status
export DECK_CDP_URL=http://127.0.0.1:8080
node scripts/cdp.mjs targets
```

`device-check.sh` reads the model, kernel, Loader status, installed hashes and Decky-managed directory modes. It does not connect to the monitor socket. The session manager creates a private local SSH control socket and forwards **127.0.0.1:8080** to the device's **127.0.0.1:8080**. It creates one uniquely named, user-owned systemd sleep inhibitor. Its default lifetime is 30 minutes; `--ttl` accepts 60–7200 seconds. A one-shot `status` check verifies the owned inhibitor; a successful `start` alone does not prove that CEF is listening.

State is kept at `.work/debug/session.json` with mode 0600. It contains the target and resource identifiers, not credentials. The private control socket uses a short temporary path to avoid UNIX-socket path limits. Never edit state manually or point it at another session. A second start refuses to replace existing state. To use another local port, pass `--port 8123` and use the printed `DECK_CDP_URL`. All project SSH commands reuse matching state automatically and reject a target mismatch.

For separate concurrent sessions, set `DECK_DEBUG_STATE` to a distinct state-file path and choose a different port. Pass the same environment to every associated command. A tunnel restart is not a reason to reconnect the plugin's Decky event map.

## CDP commands

Chrome DevTools Protocol (CDP) is used only by development scripts. Its module probes must never be copied into the shipped plugin.

| Command | Purpose |
| --- | --- |
| `node scripts/cdp.mjs targets` | List current CEF targets; resolve them again after a Steam restart |
| `node scripts/cdp.mjs qam open` | Open the Decky QAM and select DeckScope |
| `node scripts/cdp.mjs qam close` | Close the side menus |
| `node scripts/cdp.mjs keys qam ArrowDown ArrowRight Enter` | Send explicit, bounded native navigation keys |
| `node scripts/cdp.mjs screenshot qam .work/debug/qam.png` | Save the actual visible QAM window |
| `node scripts/cdp.mjs rpc get_status` | Read the installed plugin's real status |
| `node scripts/cdp.mjs rpc export_summary` | Read the plugin's redacted summary |
| `node scripts/cdp.mjs eval shared path/to/probe.js` | Execute an explicitly supplied diagnostic probe |
| `bash scripts/logs.sh` | Read only the latest DeckScope log, bounded to 150 lines |

Aliases are `qam`/`quickaccess`, `shared`/`sjc`, `bp`/`bigpicture`, and `mainmenu`. The main-window matcher includes the localized Chinese title. `shared` has no visible pixels; do not use it for screenshots. Screenshots and raw status/connectivity output can contain local information. Inspect and redact deliberately before public sharing; do not read the user's existing clipboard.

QAM opening uses a narrowly scoped read-only module lookup and the host's existing navigation API. If that API or the plugin entry is unavailable, the command fails rather than patching Steam. If another plugin is open, return to the Decky plugin list first. The target is QAM-only; do not navigate to the retired `/deckscope` route.

For a valid historical query, supply UTC millisecond bounds and the exact metric enum key. For example, generate a five-minute request locally:

```bash
args=$(python3 -c 'import json,time; t=int(time.time()*1000); print(json.dumps([{ "from":t-300000,"to":t,"metric":"gpu_pct","max_points":120 }]))')
node scripts/cdp.mjs rpc query_history "$args"
```

Only the six public callable methods are exposed by the RPC tool. `set_config` also requires `--allow-write`; use it only when authorized and restore the original configuration afterward. Requests go through `DeckyBackend.call('loader/call_plugin_method', 'DeckScope', ...)`. **Never call the loader's plugin `connect(...)` interface for ordinary probes**: it can replace the event-listener map and silently stop UI updates.[2]

## D-pad acceptance

With current authorization to operate the plugin UI:

```bash
node scripts/cdp.mjs qam open
node scripts/check-dpad.mjs --confirm --out .work/debug/dpad.json
node scripts/cdp.mjs qam close
```

The checker supports both UI languages by identifying the three navigation positions rather than matching translated titles. It walks views, returns from page bodies to their header, traverses horizontal groups and checks every enabled action button. It does not press configuration or copy actions and does not inject touch gestures. Its JSON records CEF-synthesized keys; do not describe that as physical-controller testing. A failed assertion may be a changed host or probe assumption, so inspect the evidence before modifying the UI.

A single screenshot proves only that a tree rendered. To establish liveness, compare changing status or UI values at measured times. Performance, monitor-exit injection, actual suspend/resume, network switching and electrical accuracy require separate scoped tests. Do not blindly replay historical acceptance scripts.

## Stop and recover

Always close the UI and release the owned resources:

```bash
node scripts/cdp.mjs qam close
python3 scripts/debug-session.py stop
```

`stop` affects only the recorded inhibitor and control socket. It is idempotent when no state exists. If SSH or remote cleanup fails, state is retained for a later retry and the inhibitor still has its hard lifetime. If the master tunnel has already ended, `stop` may use normal SSH authentication to release the recorded unit. The SSH master has a 600-second idle persistence limit, but this is not a substitute for explicit cleanup.

| Symptom | Safe next action |
| --- | --- |
| Local port already in use | Do not kill an unknown process; choose another `--port` |
| Host-key or authentication failure | Stop and resolve the identity/permission issue; do not disable host-key checks |
| CEF connection refused | Verify existing service availability; do not enable a new remote-debugging listener automatically |
| `DECK_HOST` differs from session state | Stop the old session or use distinct state; do not silently redirect it |
| Plugin not listed or `monitor ready` missing | Use `device-check.sh` and `logs.sh`; inspect frozen-Python namespace conflicts |
| UI no longer updates after a probe | Do not reconnect events; close/reopen the UI and investigate whether a prior probe replaced the listener map |
| Root-owned plugin files reject direct writes | Use the authorized full deploy workflow, not chmod or direct frontend writes |
| Inhibitor missing or expired | End the session or start a new bounded one only if debugging is still authorized |

## References

[1]: ../scripts/debug-session.py "Owned loopback tunnel and bounded inhibitor lifecycle"
[2]: PROTOCOL.md "Public Decky API and consumer lifecycle"
