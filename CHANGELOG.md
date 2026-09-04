# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- CI status and latest-release badges in the README.
- `tuin_choose` keyboard conformance: `j`/`k`, `ctrl-n`/`ctrl-p`,
  `tab`/`shift-tab`, `home`/`end`, `g`/`G` and `pgup`/`pgdn` all move; `q`,
  `←` and `backspace` cancel alongside `esc`.
- `tuin_choose` digit hotkeys: `1`-`9` pick instantly when the list has fewer
  than 10 items, and rows are numbered to match.
- `tuin_choose` wraps at both ends, scrolls when the list is taller than the
  terminal, and redraws on resize.
- `tuin_choose` filter editing with `backspace`, `ctrl-u` and `ctrl-w`; `esc`
  clears a non-empty filter before it cancels.
- A key hint line under `tuin_choose`, hidden with `TUIN_HINTS=0`. It names
  `q` before `esc`, since `esc` lags a second on bash 3.2.
- `tuin_input` readline editing on a terminal: arrow keys, `ctrl-a`/`ctrl-e`/
  `ctrl-w` and history.
- `tuin_menu` reopens on the last entry picked when called again with the same
  title.
- `TUIN_FILTER`, `TUIN_HINTS` and `TUIN_ESC_DELAY` environment variables, all
  documented in the README.
- `fg` after a Ctrl-Z re-enters raw mode and redraws the menu.
- A PTY test suite driving every interactive primitive through a real
  pseudo-terminal, plus security tests that fail the build on `eval`, a shell
  escape or an unquoted `$@`.
- A macOS CI job that asserts it is running under a real bash 3.2.
- `make bump V=X.Y.Z` and `docs/ROADMAP.md`.

### Changed
- Release checklist (`RELEASING.md`) now includes a step to move the `stable`
  ref to each new tag, so the moving "always-the-latest-stable" `curl -O` URL
  stays in sync with releases.
- `tuin_input` returns `1` on EOF (Ctrl-D) instead of reprompting forever.
- `tuin_confirm` treats `q` and `esc` as no, and ignores any other key rather
  than counting it as a no.
- `tuin_confirm` and `tuin_input` decide whether to prompt from stdin and
  `/dev/tty` rather than from stdout, matching `tuin_choose`. Capturing the
  result no longer disables the interactive prompt.
- Rendered labels and `tuin_menu` titles have control bytes stripped, so a
  label carrying ANSI cannot repaint the terminal. Returned values stay
  byte-exact.

### Fixed
- An escape sequence tuin does not recognise is now consumed to its final
  byte. Previously parsing stopped at the first non-numeric parameter byte, so
  `ESC[?25h` left `25h` in the buffer and the `2` silently picked the second
  menu entry. Mouse reports leaked the same way.
- Ctrl-C in `tuin_choose` now exits on the first press and returns `130`. On
  bash 3.2 it previously needed two.
- An interactive primitive left idle no longer cancels itself after one second
  on bash 3.2, where `read -t` reports a timeout and EOF identically.
- Ctrl-Z no longer stops the process twice, which made every `fg`
  immediately re-suspend. bash's `read` already stops cleanly, so tuin no
  longer traps `TSTP` at all.
- A caller's own `EXIT` trap is no longer clobbered.

## [0.1.0] - 2026-06-06

Initial public release.

`tuin.sh` SHA-256:

```
4ae0b1372f3653154f1d8bb1e0ecf6c610156c731352234f1a77d17d253be13f  tuin.sh
```

### Added

#### TUI primitives
- `tuin_choose` — arrow-key menu with type-ahead filter when item count ≥ 10.
  Draws its UI and reads keys via `/dev/tty`, printing only the selected value
  to stdout, so `choice=$(tuin_choose …)` keeps arrow-key navigation.
- `tuin_menu` — looping ("never-dying") menu primitive for cascading,
  drill-down interfaces; auto-appends a Back entry, sets `$TUIN_REPLY`, and
  returns non-zero to end the loop. Back label overridable via `TUIN_MENU_BACK`.
- `tuin_confirm` — single-keypress y/n with default support.
- `tuin_input` — read with default + optional regex validation.
- `tuin_spin` — animated spinner with non-TTY pass-through (requires the `--`
  separator).
- `tuin_banner` — boxed banner (Unicode / ASCII).
- `tuin_section` — section divider (Unicode / ASCII).
- `tuin_version` — print library version.

#### Safety guards
- `tuin_unpriv` — refuse a privileged (root / sudo) launch.
- `tuin_guard` — screen a command's `argv[0]` for privilege escalation
  (`sudo`, `doas`, `su`, `pkexec`, `run0`, `sudoedit`) before running it.
- The guards are safe-by-default rails, not an enforced security boundary —
  see the README for the contract.

#### Supply-chain trust model
- `examples/vendor.sh` — verified, fail-closed vendoring (zero-dependency,
  bash 3.2-safe: fetch → verify SHA-256 → atomic install).
- A "Vendoring tuin safely" README section, the `make checksum` target, and
  `RELEASING.md`. Each release publishes the `tuin.sh` SHA-256 digest.

#### Docs & tooling
- `AGENTS.md` — canonical agent-shaped guide; `CLAUDE.md` / `GEMINI.md` thin
  pointers to it.
- BATS test suite covering helpers, non-TTY contracts, guards, docs, and the
  vendoring snippet.
- GitHub Actions CI on Ubuntu + macOS, plus shellcheck.
- Examples for every primitive.

### Contract
- Non-TTY fallback for every primitive (CI / pipes / `TERM=dumb`).
- `NO_COLOR` compliance; automatic UTF-8 → ASCII decoration fallback.
- Bash 3.2+ compatibility (macOS default shell).

### Known limitations
- Pressing Ctrl-C in `tuin_choose` requires a second Ctrl-C to fully exit on
  bash 3.2. Cursor + stty are always restored on the first press; the second
  press is needed because bash 3.2's `read` builtin auto-restarts after a
  signal-triggered trap returns.
- Pressing bare ESC to cancel `tuin_choose` takes ~1 second to register (bash
  3.2 only supports integer-second timeouts for arrow-key sequence detection).

[Unreleased]: https://github.com/ikidnapmyself/tuin/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ikidnapmyself/tuin/releases/tag/v0.1.0