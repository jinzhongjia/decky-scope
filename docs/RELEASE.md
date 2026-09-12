# Release Preparation

**rc.3 acceptance gate:** grouped charts and system details are locally tested and their native snapshot works on Galileo. The revised candidate is installed and passes QAM rendering and CEF directional-key acceptance; exact hashes and remaining limitations are in [device acceptance](RC3-ACCEPTANCE.md). See [feature notes](FEATURES-RC3.md).

**Current private candidate: `0.1.0-rc.3`. No public release or store submission has been made.** The current repository is self-contained for local development and sideloading, but that is not a license grant, a completed store-build adaptation, or production certification.

## Product and acceptance status

DeckScope is a QAM-only SteamOS system-information and monitoring tool. CPU/GPU and APU/battery power charts use real history and live data. IP is masked by default; summary export uses a whitelist. Closing QAM leaves native recording active. The native rc.2 UI and all-view/control directional navigation are the accepted interface baseline. Touchscreen investigation was stopped; the reported problem is not marked resolved.[1]

The historical OLED runs demonstrate specific startup, functional and input behavior on one device. They do not establish Stable/Beta coverage, other-device compatibility, electrical accuracy, endurance or a game-frametime/P99 budget. Use the dated acceptance documents for exact artifact identities, not for blanket release approval.

## Public-release blockers

| Area | Outstanding requirement |
| --- | --- |
| Main license and reference rights | There is no project LICENSE. The user-supplied reference package had no identified license. Confirm provenance and authorization; do not assign a license on the owner's behalf. |
| Third-party notices | Dependency metadata lists LGPL-2.1 for `@decky/api` and `@decky/ui`, and MIT for `react-icons`. Verify actual redistributed code/icons and required notices; metadata alone is not a legal review. |
| Destination and authority | Confirm repository, visibility, publishing account and channel. No remote is configured at this review point. Connecting an account or viewing a README is not permission to push or publish. |
| Official backend build | The official template describes custom-backend builds through Decky CLI/Docker, with source under `backend/src` and output under `backend/out`. This project uses `monitor/` and local Zig 0.16; the official build adaptation is not implemented or tested.[2] |
| Package manager | The official template explicitly recommends pnpm 9 for submission CI. This repository pins pnpm 11.3.0. Validate and reconcile the target environment rather than assuming local success proves store compatibility.[2] |
| Showcase image | `plugin.json.publish.image` remains empty. Existing private screenshots have not been uploaded as public release assets. |
| Validation matrix | SteamOS Stable/Beta, additional hardware, actual suspend/network transitions, physical controls, endurance and performance evidence remain incomplete. Follow the database's actual submission checklist.[3] |
| Stable identity and external actions | The current version remains an RC. A stable version, tag, push, public upload and store submission need their own reviewed payload and authorization. |

The official plugin database describes first submission as a pull request adding the plugin as a submodule, with later updates changing the version/submodule reference. The template also describes URL-distributed plugin ZIPs. A working private sideload ZIP and an approved store entry are different outcomes. The official README pages were read again on 2026-09-12; they are not a substitute for the linked wiki or the current review checklist.[2] [3]

## Local candidate commands

```bash
bash scripts/check.sh
python3 scripts/release-check.py
python3 scripts/package-candidate.py

# Strict public preflight intentionally fails while the blockers remain:
python3 scripts/release-check.py --public
```

The preflight checks mechanical artifact and metadata consistency only. It cannot grant redistribution rights or approve a store submission. Candidate archiving produces a version-named ZIP, SHA-256 file and preflight JSON under `outputs/`. A source/developer archive is not an installable plugin ZIP; do not sideload it.

## Upgrade and rollback

The old `/deckscope` fullscreen route is retired. History remains schema v1, and installation/rollback preserve settings and stored history rather than erasing them. Abrupt process loss can still discard a pending minute-record batch. Follow [Deployment](DEPLOYMENT.md) for complete-package installation, backup selection and safe rollback. A file restore does not itself verify that Loader or the plugin is healthy.

## References

[1]: UI-INPUT-ACCEPTANCE.md "rc.2 native UI, input acceptance and scope decision"
[2]: https://github.com/SteamDeckHomebrew/decky-plugin-template "Official Decky Plugin Template build and ZIP distribution README, read 2026-09-12"
[3]: https://github.com/SteamDeckHomebrew/decky-plugin-database "Official Decky Plugin Database submission README, read 2026-09-12"
