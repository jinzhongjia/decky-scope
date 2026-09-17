# Release Preparation

**rc.3 acceptance gate:** grouped charts and system details are locally tested and their native snapshot works on Galileo. The revised candidate is installed and passes QAM rendering and CEF directional-key acceptance; exact hashes and remaining limitations are in [device acceptance](RC3-ACCEPTANCE.md). See [feature notes](FEATURES-RC3.md).

**Current version: `0.1.0-alpha.1`, the first public alpha packaging target.** On September 17, 2026, the maintainer authorized an alpha package and GitHub prerelease. The previous `0.1.0-rc.3` label was an unpublished development candidate; the public alpha label does not remove its functionality or establish stable readiness. No store submission is included. This publication does not select a main license or certify redistribution rights, official-store builds, or production suitability.

## Product and acceptance status

DeckScope is a QAM-only SteamOS system-information and monitoring tool. CPU/GPU and APU/battery power charts use real history and live data. IP is masked by default; summary export uses a whitelist. Closing QAM leaves native recording active. The native rc.2 UI and all-view/control directional navigation are the accepted interface baseline. Touchscreen investigation was stopped; the reported problem is not marked resolved.[1]

The historical OLED runs demonstrate specific startup, functional and input behavior on one device. They do not establish Stable/Beta coverage, other-device compatibility, electrical accuracy, endurance or a game-frametime/P99 budget. Use the dated acceptance documents for exact artifact identities, not for blanket release approval.

## GitHub packages versus official-store readiness

The user authorized the public GitHub destination and source/CI push on September 12 at 18:51. [GitHub CI](CI-RELEASE.md) handles versioned sideload packages independently of Decky Store requirements. A future matching tag push is the trigger for automatic Release publication; the setup itself does not publish a version. The legacy `release-check.py --public` checks conservative stable/store readiness, not GitHub packaging eligibility.

## Remaining licensing, stable and store requirements

| Area | Outstanding requirement |
| --- | --- |
| Main license and reference rights | There is no project LICENSE. The user-supplied reference package had no identified license. Confirm provenance and authorization; do not assign a license on the owner's behalf. |
| Third-party notices | The [dependency inventory](../THIRD-PARTY-NOTICES.md) and upstream license texts are included in packages. Review redistribution obligations and prototype provenance; this inventory is not a legal certification. |
| Destination and authority | `origin` is the user-designated public [GitHub repository](https://github.com/jinzhongjia/decky-scope). The September 17 request authorizes the alpha package and GitHub prerelease, not a stable release or store submission. |
| Official backend build | The official template describes custom-backend builds through Decky CLI/Docker, with source under `backend/src` and output under `backend/out`. This project uses `monitor/` and local Zig 0.16; the official build adaptation is not implemented or tested.[2] |
| Package manager | The official template explicitly recommends pnpm 9 for submission CI. This repository pins pnpm 11.3.0. Validate and reconcile the target environment rather than assuming local success proves store compatibility.[2] |
| Showcase image | `plugin.json.publish.image` remains empty. Existing private screenshots have not been uploaded as public release assets. |
| Validation matrix | SteamOS Stable/Beta, additional hardware, actual suspend/network transitions, physical controls, endurance and performance evidence remain incomplete. Follow the database's actual submission checklist.[3] |
| Stable identity and external actions | The public version is an alpha prerelease. A maintainer deliberately pushing its matching version tag activates automatic publication. Stable certification and store submission remain independent decisions. |

The official plugin database describes first submission as a pull request adding the plugin as a submodule, with later updates changing the version/submodule reference. The template also describes URL-distributed plugin ZIPs. A working private sideload ZIP and an approved store entry are different outcomes. The official README pages were read again on 2026-09-12; they are not a substitute for the linked wiki or the current review checklist.[2] [3]

## Local candidate commands

```bash
bash scripts/check.sh
python3 scripts/release-check.py
python3 scripts/package-candidate.py

# Conservative stable/store preflight remains separate from GitHub packaging:
python3 scripts/release-check.py --public
```

The preflight checks mechanical artifact and metadata consistency only. It cannot grant redistribution rights or approve a store submission. Candidate archiving produces a version-named ZIP, SHA-256 file and preflight JSON under `outputs/`. A source/developer archive is not an installable plugin ZIP; do not sideload it.

## Upgrade and rollback

The old `/deckscope` fullscreen route is retired. History remains schema v1, and installation/rollback preserve settings and stored history rather than erasing them. Abrupt process loss can still discard a pending minute-record batch. Follow [Deployment](DEPLOYMENT.md) for complete-package installation, backup selection and safe rollback. A file restore does not itself verify that Loader or the plugin is healthy.

## References

[1]: UI-INPUT-ACCEPTANCE.md "rc.2 native UI, input acceptance and scope decision"
[2]: https://github.com/SteamDeckHomebrew/decky-plugin-template "Official Decky Plugin Template build and ZIP distribution README, read 2026-09-12"
[3]: https://github.com/SteamDeckHomebrew/decky-plugin-database "Official Decky Plugin Database submission README, read 2026-09-12"
