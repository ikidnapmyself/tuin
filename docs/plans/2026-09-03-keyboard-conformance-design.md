# tuin v0.2.0 — Keyboard conformance design

**Date:** 2026-09-03
**Status:** Approved.
**Target version:** `v0.2.0`

## 1. Goal

Make the four interactive primitives behave the way terminal users already
expect. The terminal is a settled environment: readline keys in text fields,
emacs and vi navigation in lists, instant ESC, clean Ctrl-C / Ctrl-Z, and a
tty that is always restored. tuin conforms to those conventions. It invents
nothing.

Non-goals: new public functions, new dependencies, screen clearing, mouse.

## 2. Constraints

- Pure bash 3.2+, builtins only, plus `stty` (already required) and optional
  `tput` for colors. Escape sequences are hardcoded ANSI / ECMA-48.
- Small surface, low maintenance. Every new line must carry a test.
- tuin is a UX layer only. It never executes text. No `eval`, no `sh -c`, no
  indirect expansion, no shell-escape key. `tuin_spin` runs only the argv it
  is handed.
- Rendered labels are sanitized (control bytes stripped) so caller data can
  not inject terminal escapes. The stdout value is always the original string.

## 3. Architecture

Two private helpers, everything interactive built on them.

### `_tuin_readkey`

Reads one keystroke from fd 3, prints one token:

| Bytes | Token |
|---|---|
| `\r`, `\n` | `enter` |
| `\033` with nothing following within the ESC delay | `esc` |
| `\033[A/B/C/D`, `\033OA..D` | `up` `down` `right` `left` |
| `\033[H` `\033[F` `\033[1~` `\033[4~` `\033[7~` `\033[8~` | `home` `end` |
| `\033[5~` `\033[6~` | `pgup` `pgdn` |
| `\033[Z` | `shift-tab` |
| `\033` + printable | `alt-x` |
| `\177`, `\b` | `bs` |
| `\t` | `tab` |
| 0x01..0x1A | `ctrl-a` .. `ctrl-z` |
| UTF-8 lead byte | reads continuation bytes, `char:<char>` |
| other printable | `char:<c>` |
| anything else | `unknown` (callers ignore) |

CSI parsing follows ECMA-48: after `\033[`, read bytes until one in
`@`..`~`, capped at 8. ESC delay: probe `read -t 0.05` once at source time;
use 0.05 s when supported, else 1 s (bash 3.2). `TUIN_ESC_DELAY` overrides.

### `_tuin_tty_enter` / `_tuin_tty_leave`

- enter: open fd 3 on `/dev/tty`, save `stty -g`, set raw-ish mode, hide
  cursor, install traps. Saves any caller EXIT/INT/TERM trap.
- leave: show cursor, restore stty, close fd 3, restore caller traps.
  Idempotent.
- INT/TERM: set flag, leave. Key loops poll with `read -t 1` and check the
  flag on every return, which removes the bash 3.2 double Ctrl-C.
- TSTP: leave, `kill -TSTP $$`. CONT: enter, set redraw flag.
- WINCH: set redraw flag. Callers re-clamp viewport and redraw.
- EXIT: leave.

## 4. Primitives

### `tuin_choose`

- Navigation: `up`/`down`, `k`/`j`, `ctrl-p`/`ctrl-n`, `tab`/`shift-tab`,
  `home`/`end`, `g`/`G`, `pgup`/`pgdn`. Wraps at both ends.
- Accept: `enter`. Cancel: `esc`, `q` (return 1), Ctrl-C (130).
- Under 10 items: rows render `1) Label`; digit picks instantly.
- 10+ items (or `TUIN_FILTER=1`): filter mode. Printable keys type into the
  filter, so `j`/`k`/`q`/digits are not hotkeys there. `ctrl-u` clears,
  `ctrl-w` deletes a word, `bs` deletes a char. `esc` clears a non-empty
  filter first, then cancels. Row shows `filter: xyz  (n/N)`.
  `TUIN_FILTER=0` forces filter off.
- Viewport: rows capped at `LINES - 3` (fallback `tput lines`, then 24).
  Window scrolls with the cursor.
- Hint line, dim, below the list. `TUIN_HINTS=0` disables.
- Labels sanitized on render only.

### `tuin_menu`

- Remembers cursor per title across loop iterations, in a private variable.
- Back also on `q`, `left`, `bs`.
- No screen clearing; scrollback stays intact.

### `tuin_confirm`

- Uses the key reader. `y`/`n`; `enter` takes default; `esc`/`q` mean no;
  Ctrl-C returns 130 with a clean tty.

### `tuin_input`

- `read -e -r -p` on a tty, so readline and the user's inputrc apply.
  Default shown in the prompt (`-i` is bash 4).
- Ctrl-D / EOF returns 1 with empty output. Ctrl-C returns 130.
- Non-TTY path unchanged.

## 5. Compatibility

Public signatures, stdout contract, and non-TTY behavior are unchanged.
Two strict changes, both bug fixes: `tuin_input` returns 1 on EOF instead
of 0 with the default; control bytes in labels are no longer rendered.
Ship as 0.2.0.

Env-var surface becomes documented API: `NO_COLOR`, `TUIN_MENU_BACK`,
`TUIN_FILTER`, `TUIN_HINTS`, `TUIN_ESC_DELAY`.

## 6. Testing

- PTY harness `tests/test_helper/pty.bash`: `tuin_pty <keys> -- <snippet>`
  runs the snippet under `script` with a real pty, feeds key bytes, captures
  tty stream and stdout separately. Handles the Linux and macOS `script`
  flag differences once.
- Key reader unit tests feed byte sequences on fd 3 without a pty.
- Every key, wrap, viewport, filter op, stty round trip, cursor restore,
  EXIT-trap restore, and TSTP round trip gets a bats test.
- Security tests: grep for `eval`, `sh -c`, `bash -c`, `${!`, unquoted `$@`;
  escape-bearing label renders stripped and returns byte-exact; `!` and `:`
  do nothing in every primitive; caller traps survive.
- CI: macOS job runs `/bin/bash` and asserts 3.2; Ubuntu job adds a bash 3.2
  container step.

## 7. Order of work

1. PTY harness and CI bash pin, green on current code.
2. `_tuin_readkey` with unit tests.
3. tty helpers, port `tuin_choose`, remove the known-limitation header note.
4. `tuin_menu` cursor memory and Back keys.
5. `tuin_confirm` on the key reader.
6. `tuin_input` readline and EOF.
7. Viewport and WINCH.
8. README env-var table, CHANGELOG, roadmap in `docs/`, `make bump` target
   that edits both version locations and refuses a dirty tree.

One commit per step, tests first.
