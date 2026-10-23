# Contributing to Relentless Dead

Bug reports and ideas are welcome as GitHub issues. What the mod does, its settings and its API for other mods are in the [README](README.md), and so is what to put in an issue: [Reporting problems](README.md#reporting-problems).

## Repository layout

- `Contents/mods/RelentlessDead/`: the mod, as the Workshop item holds it. `42/` has `mod.info`, `poster.png`, `media/sandbox-options.txt` and the Lua in `media/lua/` (`shared/`, `client/` and `server/`); `common/` has the English translations.
- `workshop.txt`: the Workshop page: the item's `id=`, title, description, tags and visibility.
- `preview.png`: the Workshop preview image.
- `publish.py` and `.github/workflows/publish.yml`: the release workflow.
- `.gitignore`: a whitelist. A new top-level file or folder is ignored until it has its own `!/path` rule.

## Commit messages

Releases are made from the commit messages, so they follow [Conventional Commits](https://www.conventionalcommits.org/). The type decides what the next release is:

| Type | For | Version |
|---|---|---|
| `fix:` | a bug fix | patch |
| `feat:` | a new feature or setting | minor |
| `feat!:` (any type with `!`), or a `BREAKING CHANGE:` footer | a change that breaks existing settings or saves | major (minor while the version is 0.x) |
| `docs:`, `chore:`, `ci:`, `refactor:` and others | everything else | none |

A scope is fine (`fix(fog): ...`).

## Changes

- The Lua runs in the game's Kahlua, a Lua 5.1 implementation, so later Lua features such as `goto`, `//` and bitwise operators aren't available.
- New player-facing texts go in the English translations under `common/`.
