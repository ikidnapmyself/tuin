# Building with tuin — agent guide

`tuin` is a single-file, zero-dependency, pure-bash TUI primitives library
(bash 3.2+). It gives bash scripts drop-in replacements for `select`, `read -p`,
and y/n prompts, plus a spinner, banners, and privilege guards — with graceful
fallbacks on non-TTY pipes, CI, and `TERM=dumb`.

**Use it when** you're writing bash anyway (installers, VPS/bootstrap, CI glue,
ops runbooks) and can't assume a richer runtime. **Don't use it when** you're
already in Python/Node (use questionary/rich/etc.) or need full-screen/mouse
UIs (use an ncurses framework).

## Load

```bash
source tuin.sh
```

Sourcing is idempotent (`_TUIN_LOADED` guard). The only global tuin writes is
`$TUIN_REPLY`, and only when `tuin_menu` picks an action — nothing leaks at
source time.

## API contract

All public functions are prefixed `tuin_`; internal helpers are `_tuin_`.

| Function | Signature | stdout | Return codes |
|---|---|---|---|
| `tuin_version` | `tuin_version` | version string | `0` |
| `tuin_unpriv` | `tuin_unpriv` | — (notice on stderr) | `0` ok; non-zero if root/sudo |
| `tuin_guard` | `tuin_guard <cmd> [args…]` | — (notice on stderr) | `0` ok; non-zero if argv[0] is an escalation tool or no cmd |
| `tuin_banner` | `tuin_banner <title>` | boxed banner | `0` |
| `tuin_section` | `tuin_section <heading>` | divider line | `0` |
| `tuin_confirm` | `tuin_confirm <prompt> [y\|n]` | — | `0` yes; `1` no; `130` Ctrl-C |
| `tuin_input` | `tuin_input <prompt> [default] [regex]` | the entered line | `0` |
| `tuin_spin` | `tuin_spin <label> -- <cmd> [args…]` | inner cmd's stdout/stderr pass through | exit code of inner cmd |
| `tuin_choose` | `tuin_choose <opt1> <opt2> [opt3…]` | selected option | `0` chosen; `1` filtered to none; `2` no options; `130` Ctrl-C |
| `tuin_menu` | `tuin_menu <title> <opt1> [opt2…]` | — (sets `$TUIN_REPLY`) | `0` action picked; non-zero on Back/ESC/Ctrl-C/EOF |

## Rules you must follow (gotchas)

1. **Capture interactive output with `$(…)`.** `tuin_choose` and `tuin_input`
   draw their UI on `/dev/tty`; only the result reaches stdout. So
   `choice=$(tuin_choose A B C)` works *and* keeps arrow keys. Do **not** pipe
   into them expecting interactivity.
2. **`tuin_spin` requires the `--` separator:** `tuin_spin "Building" -- make all`.
   The `--` lets the label contain spaces; omitting it is a bug.
3. **`tuin_menu` loops and auto-appends a Back entry.** Drive it with a `while`
   loop and switch on `$TUIN_REPLY`; the loop ends (non-zero) on Back/ESC/
   Ctrl-C. Override the Back label with `TUIN_MENU_BACK`.
4. **bash 3.2 only.** No `mapfile`/`readarray`, no associative arrays, no
   bash-4+ features (tuin targets macOS's default shell). Generated scripts
   that source tuin must stay 3.2-compatible too.
5. **Guards `return`, they don't `exit`.** `tuin_unpriv` and `tuin_guard` print
   a notice to stderr and return non-zero; the *caller* decides what to do
   (`tuin_unpriv || exit 1`). They are guard rails, not a sandbox.
6. **Everything degrades on non-TTY / CI / `TERM=dumb`.** `tuin_choose`/
   `tuin_menu` read a line from stdin (1-indexed number); `tuin_confirm`/
   `tuin_input` read stdin and honor defaults; `tuin_spin` runs the command
   without animation. So piped/CI callers work unchanged.
7. **`NO_COLOR` and UTF-8 are automatic.** tuin emits zero ANSI escapes under
   `NO_COLOR`, and falls back to ASCII box-drawing when the locale isn't UTF-8.
   Don't reimplement color/Unicode handling around it.

## Canonical snippets

### Captured arrow-key menu

```bash
source tuin.sh
fruit=$(tuin_choose Apple Banana Cherry) || exit 1
echo "You picked: $fruit"
```

### Input + confirm form

```bash
source tuin.sh
tuin_banner "Setup"
name=$(tuin_input "Your name" "World" '^[A-Za-z ]+$')
tuin_confirm "Proceed as $name?" y || exit 1
```

### Guarded native-CLI wrapper

```bash
source tuin.sh
tuin_unpriv || exit 1            # refuse a root/sudo launch
tuin_guard "$@" || exit 1        # refuse an escalation command
tuin_spin "Running" -- "$@"
```

### Cascading drill-down menu

```bash
source tuin.sh
while tuin_menu "Health" "Run all checks" "List checkers"; do
    case $TUIN_REPLY in
        "Run all checks") tuin_spin "Checking" -- ./run-checks ;;
        "List checkers")  ./list-checkers ;;
    esac
done   # falls through here on Back / ESC / Ctrl-C
```

## Anti-patterns

- ❌ `tuin_choose A B C | grep …` — piping breaks interactivity; capture with
  `$(…)` instead.
- ❌ `tuin_spin "Building" make all` — missing `--`.
- ❌ Relying on a guard to halt the script — they `return`, you must act on it.
- ❌ Using bash-4 features (`declare -A`, `mapfile`) in scripts that source tuin.
- ❌ Adding a dependency (jq, gum, …) to "improve" output — tuin's whole value
  is zero dependencies.

## Full reference

See [`README.md`](README.md) for the complete behavior contract, non-TTY
fallback details per primitive, and runnable [`examples/`](examples/).
