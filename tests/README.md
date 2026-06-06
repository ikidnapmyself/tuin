# tuin tests

BATS suite. Run via `make test` from the repo root.

## Vendored helpers

| Component | Pinned to |
|---|---|
| `bats-core` | v1.11.0 |
| `bats-support` | v0.3.0 |
| `bats-assert` | v2.1.0 |

All three are MIT-licensed git submodules under `test_helper/`. After cloning
the repo, hydrate them with:

    git submodule update --init --recursive

## What's covered

- Pure-helper unit tests (`_tuin_is_tty`, `_tuin_is_utf8`, `_tuin_use_color`,
  `_tuin_choose_filter`).
- Non-TTY contract tests for every primitive.

Interactive (TTY) behavior is covered by the manual checklist in the
top-level design doc (§ 10) — BATS can't drive a real PTY in CI.
