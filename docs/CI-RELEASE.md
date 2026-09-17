# GitHub CI and Release Packaging

**Repository: [jinzhongjia/decky-scope](https://github.com/jinzhongjia/decky-scope).** The [workflow](../.github/workflows/ci.yml) builds an installable, self-contained Linux x86_64 Decky ZIP from tested source. GitHub distribution is separate from Decky Store approval. The initial CI setup does not create a version tag or release.

## Triggers

| Event | Build and tests | Distribution |
| --- | --- | --- |
| Push to `main` | Full regression and package verification | Downloadable Actions artifact; no Release mutation |
| Pull request targeting `main` | Same read-only checks, including fork PRs | Actions artifact; no release token |
| Push a matching `vX.Y.Z` or `vX.Y.Z-prerelease` tag | Verify package/native versions and exact tag commit, then run full checks | Create a Release draft, upload assets, publish last; prerelease versions remain prereleases |
| Publish a GitHub Release | Build that release's tag and run the same gates | Attach missing assets; identical existing assets are skipped |
| Manual workflow dispatch | Same checks for the selected ref | Actions artifact only; never publishes |

The `published` Release event covers stable and prerelease publication. Releases created by the workflow's `GITHUB_TOKEN` do not recursively trigger another ordinary Release workflow. Concurrent runs for the same tag are serialized. No personal token, device password or Steam Deck connection is required.[1] [2]

## Release procedure

Set **both** `package.json.version` and `monitor/src/model.zig`'s `version` constant to the same desired version. A release tag must equal `v` followed by that version. The workflow does not silently rewrite source versions or create/move tags. Review the [compatibility limits](COMPATIBILITY.md), [third-party notices](../THIRD-PARTY-NOTICES.md), and unresolved licensing/store questions in [Release Preparation](RELEASE.md).

The first public alpha used the following version/tag commands. Do not replay its tag creation; choose a new version for later releases:

```bash
bash scripts/check.sh
python3 ci/release.py metadata --tag v0.1.0-alpha.1  # after creating the matching local tag
```

The complete publication sequence is:

```bash
# Commit the reviewed version/source changes first, if any.
git push origin main
git tag -a v0.1.0-alpha.1 -m "DeckScope 0.1.0-alpha.1"
python3 ci/release.py metadata --tag v0.1.0-alpha.1
git push origin v0.1.0-alpha.1
```

**Pushing that tag is a publication action.** Replace the example version when preparing a different release. Do not reuse or force-move an already published version. Alternatively, publish a Release through GitHub's UI using a matching version tag; the workflow then attaches the built files. If immutable Releases are enabled, prefer the tag-push route so assets upload before publication; already immutable releases cannot accept missing/replaced assets.[3]

## Downloadable assets

| File | Purpose |
| --- | --- |
| `DeckScope-<version>-linux-x86_64.zip` | Installable plugin with one `DeckScope/` top-level directory, frontend, Python bridge, native monitor and notices |
| `SHA256SUMS` | SHA-256 checksums for the plugin ZIP and build manifest |
| `build-manifest.json` | Source commit, version/tag, pinned toolchains, target and artifact/runtime hashes |

GitHub's automatic **Source code (zip)** and **Source code (tar.gz)** downloads are source archives, not plugin installers. Actions wraps the above assets in an outer artifact download; extract that outer archive and sideload the inner DeckScope ZIP. The inner ZIP preserves the executable bit on the native monitor, even though Actions artifact downloads do not preserve arbitrary file permissions.[4]

Verify files from their download directory:

```bash
sha256sum -c SHA256SUMS
```

Actions packages are retained for 30 days and test logs for 14 days. Release assets are not subject to those Actions retention limits.

## Build gates and security

`ci/toolchains.json` pins Node, Python, pnpm and Zig. Zig is downloaded from the official distribution and verified against a checked-in SHA-256 checksum before extraction/execution. All third-party Action references are pinned to full commit hashes. Dependencies install with `pnpm install --frozen-lockfile`; no privileged dependency cache is restored.

The build runs Zig tests, Python tests against both ReleaseSmall and ReleaseSafe, frontend/tooling tests, TypeScript, Rollup, document checks and the package allowlist. ELF checks reject dynamic runtime dependencies, non-x86_64 binaries and a native monitor at or above 256 KiB. Package checks reject extra/duplicate entries, symlinks, wrong permissions, empty files and stale source content. Git must remain unchanged after the build.

Only the dependent publication job receives `contents: write`. It runs only for release/tag events in the designated repository, not PRs or manual dispatch. It downloads artifacts from its own successful build, verifies checksums, verifies the remote tag still points to the built commit, then publishes. It never uses `--clobber`, force-pushes tags, deletes release assets or replaces the user's Release notes. Existing assets with differing bytes cause a failure rather than a silent replacement.

A user-created draft stays a draft. A draft created by this CI contains a commit-specific marker so a rerun can resume an interrupted upload and publish after completion. If a conflict remains, choose a new version or investigate the exact asset difference; do not delete assets merely to make CI green.

Draft discovery uses the authenticated release list, not `releases/tags/<tag>`: the latter returns 404 for an unpublished draft. The build exports the uploaded artifact ID and the publisher downloads that exact ID. Do not reconstruct its name from the publishing job's `github.run_attempt`; a failed-job-only rerun reuses the successful build's earlier artifact.

The `v0.1.0-alpha.1` tag predates these two publication fixes and remains unchanged. Its build succeeded, but the initial draft lookup failed; the verified artifact from that run was recovered with `ci/publish.py` and published without replacing bytes. The subsequent [Release-event workflow](https://github.com/jinzhongjia/decky-scope/actions/runs/35192962047) passed both jobs. For that historical tag, rerun the entire workflow rather than only its failed publication job, or recover the exact successful build artifact as above. See [validation](VALIDATION.md) for identity and checksum evidence.

## Local verification and maintenance

```bash
bash scripts/check.sh
python3 ci/release.py metadata
# Use a fresh directory; the command refuses to overwrite previous artifacts.
python3 ci/release.py package --output outputs/ci-local
(cd outputs/ci-local && sha256sum -c SHA256SUMS)
```

The initial local implementation was checked with the official Zig distribution, frozen dependency installation and `actionlint`. After the alpha publication fixes, `bash scripts/check.sh` passes Zig tests/builds, 54 Python tests per native build and 28 frontend/tooling tests. Twelve Python tests cover release identity, unsafe/stale packages, reproducibility, checksums, tag movement, duplicate assets and draft handling; the draft fixture now reproduces GitHub's unpublished-tag 404. A source-text workflow assertion was removed; the revised workflow passes `actionlint` 1.7.12. Hosted alpha build/publication and public-asset download checks are recorded in [validation](VALIDATION.md).

Do not confuse the existence of a ZIP with permission to redistribute all contents, actual SteamOS UI acceptance or official-store compliance. The project owner has not selected a main license. No new license grant or stable-release certification is implied by enabling packaging CI.

## References

[1]: https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows "GitHub Actions event triggers"
[2]: https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow "GITHUB_TOKEN event recursion rules"
[3]: https://cli.github.com/manual/gh_release_create "GitHub CLI release creation and immutable Releases"
[4]: https://github.com/actions/upload-artifact "Actions artifact upload, retention and permission semantics"
