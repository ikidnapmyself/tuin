# Fullscreen mode and logo (0.3.0)

## Goal

Let any bash CLI that wraps its commands with tuin run as a fullscreen,
branded screen. tuin stays app agnostic. It supplies the screen, the logo, and
list and menu primitives that fit. The wrapping CLI supplies the data and the
actions.

This reverses the roadmap deferral of an alternate-screen mode. It stays
primitives, not a framework.

## Scope

In:
- `tuin_fullscreen on|off|clear`
- `tuin_logo`
- Row budget for `tuin_choose` and `tuin_menu`
- `TUIN_LOGO` env knob
- Tulip logo as `assets/logo.svg` and `assets/logo.txt`
- `examples/dashboard.sh` with generic placeholder data

Out, and staying rejected:
- Live auto-refresh and timers
- Split panes and a layout engine
- Per-item detail lines. Callers format columns into the label.
- Declarative screens or menu trees

## Interaction model

One screen at a time. The caller clears, prints the logo, shows a list with
`tuin_choose`, then actions with `tuin_menu`. Data loads when a screen opens.

```bash
source tuin.sh
tuin_fullscreen on
while :; do
    tuin_fullscreen clear
    tuin_logo
    item=$(tuin_choose "${items[@]}") || break
    tuin_menu "$item" "Open" "Acknowledge" || continue
    ...
    [[ -t 0 ]] || break
done
tuin_fullscreen off
```

## tuin_fullscreen

- `on` enters the alternate screen, clears it, homes the cursor.
- `off` leaves it. The user's scrollback is untouched.
- `clear` blanks the screen and homes the cursor.
- `on` and `off` are idempotent. `off` without `on` does nothing.
- The first `on` in a process probes once whether the terminal answers a
  cursor-position query. See Row budget.
- Escapes go to `/dev/tty`, so `$(...)` capture keeps working.
- Non-TTY, CI, `TERM=dumb`: silent no-op, return 0.
- Cursor visibility stays with the existing primitives.
- `on` sets an `EXIT` trap running `off`, only if the caller has none. tuin
  never overwrites or chains a caller's trap. Callers with their own `EXIT`
  trap add `tuin_fullscreen off` themselves. Documented in the README.

## tuin_logo

- Prints to stdout. Returns 0. The caller decides where it goes.
- Source order:
  1. File named by `TUIN_LOGO`, if readable.
  2. `assets/logo.txt` beside `tuin.sh`, resolved from `BASH_SOURCE`.
  3. A 4 to 6 line tulip embedded in `tuin.sh`.
- Each source is read up to 24 lines.
- The embedded fallback keeps single-file vendoring working.
- The default tulip is colored unless `NO_COLOR`. A `TUIN_LOGO` file is
  printed as plain text with control bytes stripped, per the existing rule
  against ANSI in labels.
- Centered when the width is known, left-aligned otherwise. ASCII fallback on
  non-UTF-8 locales.
- Wrapping CLIs point `TUIN_LOGO` at their own art. tuin never copies, writes,
  or merges it, so it stays outside tuin's tree and untracked by tuin's repo.

## Row budget

`tuin_choose` currently sizes its window as terminal height minus 3
(`tuin.sh`, `max_rows`). Anything printed above it, such as a logo, makes a
long list overflow and breaks in-place redraw.

- Only while fullscreen is on, each list sends `ESC[6n` to `/dev/tty` when it
  opens and reads the `row;col` reply. Inline lists keep height minus 3.
- Window rows = height minus cursor row, minus the filter and hint lines.
- No re-query after resize or `fg`. The list keeps its start row. Each query
  risks eating keys typed meanwhile, and terminals disagree on where the
  cursor lands after a shrink.
- The "does it answer?" probe runs once per process inside `tuin_fullscreen
  on`. `tuin_choose` usually runs in a `$(...)` subshell, so a flag set there
  wouldn't persist. If the terminal stays silent, lists fall back to height
  minus 3 and skip the query. The bash 3.2 whole-second `read -t` makes that
  one stall cost up to 1s, paid at most once.

## Logo assets

- `assets/logo.svg`: tulip mark for the README.
- `assets/logo.txt`: the same mark as text for `tuin_logo`.
- Two or three tulip drafts are produced during implementation. The owner
  picks one.

## Docs

- README: fullscreen section, logo override, SVG embedded, `TUIN_LOGO` in the
  env table. A test enforces the table entry.
- `AGENTS.md`: API table rows and a fullscreen snippet.
- `docs/ROADMAP.md`: fullscreen moves to landed. Live refresh and split panes
  stay rejected.
- `CHANGELOG.md`: a 0.3.0 entry with the `tuin.sh` SHA-256. Version bumped
  with `make bump` on this branch. Tagging waits for the owner.
- All examples and docs use placeholders. No third-party names.

## Tests

Existing bats and pty harness:
- Non-TTY: `tuin_fullscreen` is a silent no-op returning 0.
- `on` and `off` emit the expected escapes to the tty.
- `off` without `on` emits nothing. Double `on` emits once.
- EXIT trap is set when absent and left alone when present.
- Logo source order: override, assets file, embedded.
- Override is sanitized. `NO_COLOR` yields zero ANSI.
- Row budget with a scripted cursor reply, and the silent-terminal fallback.
- README env table lists `TUIN_LOGO`.
- bash 3.2 compatibility: no bash 4 features.
