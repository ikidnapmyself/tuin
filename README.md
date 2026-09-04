# 🌷 tuin

> A tulip in the garden — single-file, zero-dependency pure-bash TUI primitives.

[![CI](https://github.com/ikidnapmyself/tuin/actions/workflows/ci.yml/badge.svg)](https://github.com/ikidnapmyself/tuin/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ikidnapmyself/tuin)](https://github.com/ikidnapmyself/tuin/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](#license)

`tuin` (Dutch for "garden") is a single-file, zero-dependency, MIT-licensed
pure-bash TUI primitives library. It gives bash scripts drop-in replacements
for `select`, `read -p`, and ad-hoc y/n prompts — plus a spinner and styled
banners — with graceful fallbacks on non-TTY pipes, CI, and `TERM=dumb`.

```bash
source tuin.sh

choice=$(tuin_choose "Apple" "Ban ana" "Cherry")
tuin_confirm "Eat the $choice?" y && echo "Enjoy."
```

## When to use tuin

**Reach for tuin when:**

- You're writing bash anyway — installers, VPS/bootstrap provisioning, CI glue, ops runbooks.
- You can't assume a language runtime on the box (no guaranteed Python, Node, …).
- You want menus, prompts, and spinners without adding a binary, a build step, or a dependency to maintain.

**Look elsewhere when:**

- You're already in a richer runtime — in Python, [questionary](https://github.com/tmbo/questionary) / [rich](https://github.com/Textualize/rich) give you
more (widgets, types, test tooling). tuin is for when you're in *bash*, not for competing inside Python.
- You need full-screen layouts, mouse support, or complex widgets — that's a different tool class (ncurses-based frameworks).
- You're choosing specifically between *bash-TUI* tools — see [Why tuin](#why-tuin) below.

tuin's niche is the shell-first middle: nicer-than-`read` interaction, zero install, runs wherever bash does.

> **Using an AI assistant?** See [`AGENTS.md`](AGENTS.md) for an agent-shaped
> quick reference (API contract, gotchas, copy-paste snippets).

## Why tuin

| Tool | License | Why not |
|---|---|---|
| [gum](https://github.com/charmbracelet/gum) | MIT | Go binary, ~6 MB; adds a runtime to maintain |
| [fzf](https://github.com/junegunn/fzf) | MIT | Narrower scope (fuzzy finder); awkward to pair with other UX |
| [dialog](https://invisible-island.net/dialog/) | LGPL | License doesn't fit MIT-only projects |
| [whiptail](https://newt.invisible-island.net/) | LGPL | Same |
| Pure bash + ANSI | — | **The niche `tuin` fills.** |

## Install

`tuin.sh` is a single file. Pick whichever hydration suits your project.

```bash
# Option A — single-file copy (simplest)
curl -O https://raw.githubusercontent.com/ikidnapmyself/tuin/main/tuin.sh
source tuin.sh

# Option B — git submodule
git submodule add https://github.com/ikidnapmyself/tuin.git deps/tuin
source deps/tuin/tuin.sh

# Option C — git subtree
git subtree add --prefix=deps/tuin https://github.com/ikidnapmyself/tuin.git main --squash
source deps/tuin/tuin.sh
```

Sourcing is idempotent (`_TUIN_LOADED` guard), so multiple `source` calls are
safe.

## Vendoring tuin safely

The safest way to depend on tuin is to **vendor** it — commit a copy into your
own tree — pinned to a release **version** and that release's **SHA-256
digest**, and verify the download before installing it. Four checkable links:

1. **Pin a version.** Depend on a tagged release, never a moving branch.
2. **Pin a digest.** Record the release's published SHA-256 next to the version.
3. **Verify on fetch, fail closed.** Check the download before placing it; a
   mismatch installs nothing.
4. **Vendor + review.** Commit the verified copy, so any change to the file or
   the pinned values shows up in a diff and is reviewed.

The digest protects the *download*; committing and reviewing protects the
*tree* — they cover different risks. Pin the digest from the release notes: a
hash you compute from the same file you are verifying only proves it has not
changed since *you* fetched it.

[`examples/vendor.sh`](examples/vendor.sh) is a ready-to-use, zero-dependency
(curl + `shasum`/`sha256sum`), bash 3.2-safe implementation. Pin three values
and run it:

```bash
TUIN_VERSION=vX.Y.Z                      # the release you trust
TUIN_SHA256=<64-hex digest>              # from that release's notes
TUIN_URL=<the release's tuin.sh URL>     # where to fetch it
```

It fetches to a temp file, verifies the SHA-256, and only then atomically moves
it into place. On a **checksum mismatch** it deletes the download and returns
non-zero (**fail closed**), so unverified bytes never reach your tree.

> Heavier signing (GPG/sigstore) is the next tier if your threat model needs it;
> for most adopters a published digest plus review is the right balance.

## Public API

Nine functions, all prefixed `tuin_`. Internal helpers are prefixed `_tuin_`.
The only global written by the library is `$TUIN_REPLY`, and only when
`tuin_menu` picks an action — nothing leaks at source time.

### `tuin_choose <option1> <option2> [option3 ...]`

Arrow-key navigable menu. The UI (menu, cursor, key reads) is drawn on
`/dev/tty`; only the selected option is written to stdout. That means you can
capture the choice without losing the interactive UI:

```bash
choice=$(tuin_choose Apple Banana Cherry)   # arrow keys still work
```

A type-ahead filter activates when the item count is ≥ 10. `TUIN_FILTER=1`
forces it on, `TUIN_FILTER=0` forces it off.

**Keys:**

| Action | Keys |
|---|---|
| Move | `↑` `↓`, `j` `k`, `ctrl-p` `ctrl-n`, `tab` `shift-tab` |
| Jump | `home` `end`, `g` `G`, `pgup` `pgdn` |
| Pick | `enter`, or `1`-`9` for an instant pick when the list has fewer than 10 items |
| Cancel | `q`, `←`, `backspace`, `esc` |
| Filter | printable keys type, `backspace` / `ctrl-u` / `ctrl-w` edit, `esc` clears the filter before it cancels |

In filter mode the letter keys type instead of navigating, so use the arrows or
`ctrl-n` / `ctrl-p` to move, and `esc` rather than `q` to cancel.

**`esc` lags about a second on bash 3.2**, which is macOS's default shell.
Telling a bare `esc` apart from the start of an arrow-key sequence means
waiting to see whether more bytes follow, and bash 3.2's `read -t` only accepts
whole seconds. Bash 4+ waits 50 ms and feels instant. `q`, `←` and `backspace`
cancel with no delay on every version, and are what the hint line names first.
`TUIN_ESC_DELAY` overrides the wait, but bash 3.2 rejects fractional values, so
one second is its floor. The list scrolls when it is taller than the
terminal, and redraws on resize. A hint line shows the main keys, hidden with
`TUIN_HINTS=0`.

Option labels are rendered with control bytes stripped, so a label carrying
ANSI cannot repaint your terminal. The value written to stdout is always the
original string, byte for byte.

| Return code | Meaning |
|---|---|
| `0` | User pressed Enter; selected option written to stdout |
| `1` | Filter eliminated all candidates; user dismissed |
| `2` | Programming error — no options passed |
| `130` | User pressed Ctrl-C |

**Non-TTY fallback:** when stdin is not a terminal (or `/dev/tty` is unusable),
reads one line from stdin as a 1-indexed integer and prints that option. Falls
back to the first option if input is empty / invalid / out-of-range. Matches
the behavior of bash's `select` builtin when stdin is a pipe, so existing
scripted callers keep working.

### `tuin_menu <title> <option1> [option2 ...]`

A looping ("never-dying") menu for building cascading, drill-down interfaces.
Renders `title` and the options plus an auto-appended **Back** entry. On an
action pick it sets `$TUIN_REPLY` and returns `0`; on Back / ESC / `q` / `←` /
`backspace` / Ctrl-C (or empty input / EOF when non-interactive) it returns
non-zero, ending the loop:

```bash
while tuin_menu "Health" "Run all checks" "List checkers"; do
    case $TUIN_REPLY in
        "Run all checks") tuin_spin "Checking" -- ./run-checks ;;
        "List checkers")  ./list-checkers ;;
    esac
done   # falls through here on Back / ESC / Ctrl-C
```

Cascade by nesting: a submenu is just a function with its own `tuin_menu` loop;
selecting Back returns control to the parent menu. See
[`examples/cascading_menu.sh`](examples/cascading_menu.sh).

| Return code | Meaning |
|---|---|
| `0` | An action was picked; label is in `$TUIN_REPLY` |
| non-zero | Back / ESC / Ctrl-C / EOF — leave the loop |

Consecutive calls with the same title reopen on the last entry you picked, so
a `while tuin_menu` loop does not send the cursor back to the top every time.

The Back label is overridable with `TUIN_MENU_BACK`. **Non-TTY fallback:**
prints a numbered list to stderr and reads one line from stdin; empty input or
EOF returns non-zero so piped/CI loops terminate.

### `tuin_confirm <prompt> [default]`

Single-keypress y/n confirmation. `default` is `y` or `n` (defaults to `n`).
The default indicator is shown in caps: `[Y/n]` vs `[y/N]`.

| Return code | Meaning |
|---|---|
| `0` | Yes |
| `1` | No, including `n`, `q` and `esc` |
| `130` | Ctrl-C |

Keys other than those are ignored, so a stray arrow key does not count as a no.

**Non-TTY fallback:** reads stdin. A line starting with `y` / `Y` returns `0`;
empty input uses the default; anything else returns `1`.

### `tuin_input <prompt> [default] [regex]`

Read a line of input with an optional default and optional regex validation.
Reprompts on regex mismatch — the validation hint goes to stderr, stdout stays
clean for capture:

```bash
name=$(tuin_input "Your name" "World" '^[A-Za-z ]+$')
```

On a terminal the prompt is a readline prompt, so arrow keys, `ctrl-a` /
`ctrl-e` / `ctrl-w` and history editing all work. Readline echoes to stderr,
leaving stdout for the value.

| Return code | Meaning |
|---|---|
| `0` | A value was read; written to stdout |
| `1` | EOF (Ctrl-D) |

**Non-TTY fallback:** reads the first line of stdin; falls back to `default`
if empty; ignores the regex (assumes pipe callers pass valid input).

### `tuin_spin <label> -- <cmd> [args ...]`

Run a command in the foreground with an animated spinner showing `label`.
The `--` separator is required so the label can contain spaces.

Returns the exit code of the inner command. The inner command's stdout and
stderr pass through to the parent unchanged.

```bash
tuin_spin "Building" -- make all
```

**Non-TTY fallback:** runs the command without any spinner output.

### `tuin_banner <title>`

Print a multi-line boxed banner. Uses Unicode box-drawing characters
(`╔ ═ ║ ╝`) when the locale supports UTF-8 and ASCII (`+ - |`) otherwise.

### `tuin_section <heading>`

Print a single-line section divider, styled `═══ heading ═══` (Unicode) or
`=== heading ===` (ASCII).

### `tuin_unpriv`

Guard against a privileged launch. Returns non-zero (and prints a notice to
stderr) when the process is running as root or was started via `sudo`; returns
`0` otherwise. Call it once at the top of a wrapper:

    source ./tuin.sh
    tuin_unpriv || exit 1

### `tuin_guard <cmd> [args ...]`

Screen a command for privilege escalation before running it. Returns non-zero
(and prints a notice to stderr) when the basename of the command is a known
escalation entry point (`sudo`, `doas`, `su`, `pkexec`, `run0`, `sudoedit`),
or when called with no command at all; returns `0` otherwise. Idiom:

    tuin_guard "$@" && tuin_spin "Running" -- "$@"

> **Guard rail, not a sandbox.** A sourced library cannot *enforce* a security
> boundary — a caller can skip the check, and `tuin_guard` only inspects the
> command it is handed (`argv[0]`), not what that command later spawns. These
> guards prevent the *accidental* footgun and make intent legible; they are not
> a substitute for OS-level access controls.

## Behavior contract

Every primitive obeys these rules:

- **TTY-aware.** Each primitive degrades on pipes, CI runners, and
  `TERM=dumb` / `TERM` unset. The interactive primitives key off stdin and
  `/dev/tty`, never stdout, so a captured result (`x=$(tuin_choose …)`,
  `x=$(tuin_input …)`) still gets a full interactive prompt. `tuin_spin` and
  the decorations check `[[ -t 1 && -t 0 ]]`.
- **`NO_COLOR` compliant.** Respects [no-color.org](https://no-color.org).
  When `NO_COLOR` is set, emits zero ANSI escapes.
- **UTF-8 aware.** Detects UTF-8 from `LC_ALL` / `LC_CTYPE` / `LANG`. Falls
  back to ASCII decorations when the locale isn't UTF-8. Labels stay ASCII
  regardless — `tuin` itself has no localization.
- **Cleanup-safe.** Cursor and `stty` state are restored on SIGINT, SIGTERM,
  and normal exit from any interactive primitive. Function-end cleanup is
  idempotent.
- **Input is never a command.** No `eval`, no `sh -c`, no indirect expansion.
  There is no shell-escape key in any primitive, and rendered labels have
  control bytes stripped so they cannot repaint your terminal.
- **Bash 3.2 compatible.** Targets macOS's default shell. No bash-4+ features.
- **Zero runtime dependencies** beyond `bash`, `printf`, `read`, `stty`,
  `tput` — all POSIX or standard.

### Signals

While an interactive primitive is running, tuin installs its own handlers for
`INT`, `TERM`, `CONT` and `WINCH`, and resets them to default when the
primitive returns. In `tuin_choose`, `tuin_menu` and `tuin_confirm`, Ctrl-C
returns `130` and hands the terminal back rather than killing your script.
Resizing the window redraws at the new height.

`tuin_input` is the exception. It hands the line to readline, so Ctrl-C there
behaves as it does at any bash `read -p` prompt rather than returning `130`.

Ctrl-Z is deliberately left to bash, whose `read` builtin already restores the
terminal and stops the process. tuin only takes `CONT`, to re-enter raw mode
and redraw when you `fg`.

Your own `EXIT` trap is left alone. tuin installs one only when you have none,
as a backstop for a caller that exits mid-prompt, and removes it on the way
out.

## Environment variables

| Variable | Effect |
|---|---|
| `NO_COLOR` | Any value: emit zero ANSI color escapes. See [no-color.org](https://no-color.org). |
| `TUIN_MENU_BACK` | Label for the auto-appended Back entry in `tuin_menu`. Default `Back`. |
| `TUIN_FILTER` | `1` forces the `tuin_choose` filter on, `0` forces it off. Unset: on at ≥ 10 items. |
| `TUIN_HINTS` | `0` hides the key hint line under `tuin_choose`. |
| `TUIN_ESC_DELAY` | Seconds to wait for the rest of an escape sequence before treating `esc` as a bare keypress. Overrides the probe, which picks `0.05` on bash 4+ and `1` on bash 3.2. |

## Examples

Runnable examples live under [`examples/`](examples/). Each script
demonstrates one or more primitives (`full_demo.sh` exercises all six TUI
primitives; `safe_wrapper.sh` composes the guards with a menu and spinner):

| Script | Primitives |
|---|---|
| [`examples/menu.sh`](examples/menu.sh) | `tuin_choose` |
| [`examples/form.sh`](examples/form.sh) | `tuin_input` + `tuin_confirm` + `tuin_banner` |
| [`examples/progress.sh`](examples/progress.sh) | `tuin_spin` + `tuin_section` |
| [`examples/full_demo.sh`](examples/full_demo.sh) | All six TUI primitives |
| [`examples/safe_wrapper.sh`](examples/safe_wrapper.sh) | `tuin_unpriv` + `tuin_guard` + `tuin_choose` + `tuin_spin` |
| [`examples/cascading_menu.sh`](examples/cascading_menu.sh) | `tuin_menu` (drill-down + never-dying) + `tuin_banner` + `tuin_section` |

Run any of them from the repo root:

    bash examples/menu.sh

## Versioning

Semver via git tags (`v0.1.0`, `v1.0.0`, …). Each tag has a `CHANGELOG.md`
entry. A `stable` ref pointing at the latest tagged release is provided for
`curl -O` consumers who want a moving "always-the-latest-stable" URL.

A `tuin_version` function is available so consumers can detect the loaded
version at runtime.

## What's not in tuin

Mouse events, an alternate-screen "fullscreen TUI" mode, multi-select,
async progress bars, color themes, completion in `tuin_input`, and label
localization are all intentionally out. [`docs/ROADMAP.md`](docs/ROADMAP.md)
carries the full list with the reasoning for each.

## License

MIT. See [`LICENSE`](LICENSE).

Copyright (c) 2026 Burak
