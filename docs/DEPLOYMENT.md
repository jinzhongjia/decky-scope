# Deployment and Rollback

**Sideloading is a device mutation, not a build check.** The project deployer rebuilds the complete candidate, installs it with sudo, retains the previous plugin, and restarts `plugin_loader`. That restart can briefly affect other Decky plugins. Use a currently authorized device and scope; `--confirm` is an operator intent flag, not permission to ignore task boundaries.[1]

## Preflight

Read [Development](DEVELOPMENT.md) for the local toolchain. On the device, confirm the intended SSH user, SteamOS model and an existing Decky installation. The standard layout is resolved from that user's `$HOME/homebrew/plugins`; the scripts do not assume the username is `deck`. Custom Decky directory layouts require reviewed adaptation rather than guessing a destination.

```bash
bash scripts/discover.sh steamdeck.local
export DECK_HOST=user@host
bash scripts/device-check.sh
```

A missing DeckScope installation makes the device check fail on a first install; distinguish that from an inactive Loader or the wrong target. Do not change SSH, CEF, power, fan or account settings to make a check pass. For a longer session, follow [Debugging](DEBUGGING.md) to attach a temporary bounded sleep inhibitor and an owned tunnel first.

## Build and sideload

```bash
bash scripts/check.sh
DECK_HOST=user@host bash scripts/deploy.sh --confirm
bash scripts/device-check.sh
bash scripts/logs.sh
```

`deploy.sh` performs a fresh `package.sh` build before copying anything. The complete ZIP contains Python modules, frontend and the static Zig binary; it does not rely on remote binary downloads. The installer validates the archive, stages files beside the plugins directory, and uses rename-based replacement. It sets the sideload-only `dev_mode` marker and restarts Loader. It does not delete settings or history.[1]

| Location relative to the SSH user's home | Purpose |
| --- | --- |
| `homebrew/plugins/DeckScope` | Installed plugin, normally root-owned after sudo installation |
| `homebrew/deckscope-backups/DeckScope-TIMESTAMP` | Previous versions; deliberately outside the plugin scan directory |
| `homebrew/deckscope-backups/DeckScope-failed-TIMESTAMP` | Failed replacement retained for inspection |
| `homebrew/logs/DeckScope` | Decky-managed plugin logs |
| Decky runtime/data/settings directories | Private history, IPC and configuration; supplied by Decky at runtime |

The script removes only its validated `/tmp/deckscope-deploy.*` upload directory. A cleanup error is reported, not silently ignored. Never work around root-owned files with broad permission changes or direct frontend writes. SSH/sudo use an existing key/agent or interactive prompts; no password is accepted as a script flag.

## Verify the installed version

A successful restart is not full functional acceptance. Compare installed `bin/deckscope-monitor` and `dist/index.js` hashes from `device-check.sh` with local `sha256sum` output, and inspect the current plugin log for `monitor ready` or errors. `get_status` through the CDP tool reads the actual bridge; it must not be replaced by a fixture or a second client on the private monitor socket.

When UI operation is authorized, run the QAM and D-pad checks in [Debugging](DEBUGGING.md). Preserve the existing user settings, distinguish synthetic keys from physical controls, and do not revive touchscreen investigation. Finish with `debug-session.py stop` if a session was started.

## Restore a specific backup

List the directory names before choosing a backup. This command reads metadata only:

```bash
ssh "$DECK_HOST" 'ls -1 "$HOME/homebrew/deckscope-backups"'
```

After choosing the exact timestamped backup and confirming that a Loader restart is authorized:

```bash
bash scripts/rollback.sh --confirm DeckScope-TIMESTAMP
bash scripts/device-check.sh
bash scripts/logs.sh
```

Replace `TIMESTAMP` with the actual numeric suffix. The rollback script refuses path traversal and symlink roots. It preserves the displaced version as another timestamped backup. If the Loader restart fails, the installer attempts to restore the pre-operation files and restart that version. **File rollback is not a guarantee that the service is healthy**: a failed recovery is reported and still requires inspection. Offline tests exercise successful and failed restore transactions; do not describe them as a real-device rollback drill.[1]

Rollback preserves data rather than reverting it. Never restore a binary that cannot read the current history/settings schema without a separately reviewed migration plan. Schema v1's minute records are batched, so abrupt loss of the native process may lose unflushed records.[2]

## Public distribution is a separate gate

The development ZIP is for private testing. A sideload does not prove that the official Decky store build, release ZIP, license obligations or supported-system matrix is valid. See [Release preparation](RELEASE.md) before tagging, pushing, uploading or submitting anything publicly.

## References

[1]: ../scripts/install-remote.py "Archive installation and rollback transaction implementation"
[2]: PROTOCOL.md "History schema, retention and durability boundaries"
