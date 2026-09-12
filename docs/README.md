# Documentation

**This repository contains everything needed to build, sideload and debug DeckScope.** No sibling repository, external Agent Skill, pre-existing `.work/` directory, or saved device credential is required. Start with the current guides below; historical records are evidence, not instructions to replay an old workflow.

## Current guides

| Document | Purpose |
| --- | --- |
| [Development](DEVELOPMENT.md) | Toolchain, source map, local checks and contribution workflow |
| [Deployment and rollback](DEPLOYMENT.md) | Explicit target selection, full-package sideload, backups and recovery |
| [Debugging](DEBUGGING.md) | Owned SSH/CDP sessions, QAM commands, logs and D-pad acceptance |
| [Architecture](DESIGN.md) | Product boundaries and process responsibilities |
| [Protocol](PROTOCOL.md) | Public/native APIs, units, freshness and disk format |
| [Compatibility and limitations](COMPATIBILITY.md) | Supported capabilities versus tested hardware and deferred work |
| [Validation](VALIDATION.md) | Current verification entry points and historical milestones |
| [Release preparation](RELEASE.md) | Private candidate versus public/store release requirements |

## Historical acceptance records

| Record | Version and scope |
| --- | --- |
| [Early device acceptance](DEVICE-ACCEPTANCE.md) | `2bb2daa`; includes the retired fullscreen UI |
| [QAM-only acceptance](QAM-ACCEPTANCE.md) | `0.1.0-rc.1`; initial QAM layout and lifecycle checks |
| [Native UI and input](UI-INPUT-ACCEPTANCE.md) | `0.1.0-rc.2`; approved appearance, horizontal navigation and the decision to stop touch investigation |

The `acceptance/`, `qam/` and `native-ui/` directories retain original screenshots and machine-readable evidence. Their hashes and counts describe those particular runs. Local scratch files are not prerequisites and are excluded from distribution. The latest accepted product is QAM-only; the old `/deckscope` route is not available.[1]

## Language and maintenance

Maintain operational documentation, help text and diagnostic messages in English first. The plugin UI separately supports Simplified Chinese and English. Chinese text inside historical screenshots or evidence is original observation data, not an untranslated operational instruction. Keep existing evidence links stable when reorganizing documentation.

## References

[1]: ../AGENTS.md "DeckScope product and development rules"
