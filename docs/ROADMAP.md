# Roadmap

What is deliberately not in tuin, and what might be, in rough order of how
likely a real consumer is to need it. Nothing here is promised.

## Landed since v0.1.0

These were on the v0.1.0 deferred list and are now done:

- Single-Ctrl-C cancel of `tuin_choose`.
- SIGTSTP / Ctrl-Z recovery.
- Windowing for menus longer than the terminal.
- A CI job that runs the suite under a real bash 3.2.

The ~1s ESC delay on bash 3.2 remains. Telling a bare `esc` from the start of
an escape sequence means waiting for a following byte, and bash 3.2's `read -t`
takes whole seconds only. The termios route out, `stty min 0 time 1` for a
100 ms read, does not work either: bash's `read -n` installs its own cbreak
mode and overrides `VMIN`/`VTIME`. Every alternative costs a dependency, so the
delay stands. `q`, `←` and `backspace` cancel instantly instead, and
`TUIN_ESC_DELAY` tunes the wait down to bash 3.2's one-second floor.

## Still deferred

| Feature | Why deferred |
|---|---|
| Per-title cursor memory in `tuin_menu` | The current single-slot memory covers the common case, one menu in a loop, without a hand-rolled map. Revisit if someone alternates between two menus and notices. |
| Mouse events | Bash + mouse is a rabbit hole. |
| Alternate-screen "fullscreen TUI" mode | Scope creep. tuin is primitives, not a framework. |
| Multi-select in `tuin_choose` | Defer until a real consumer needs it. |
| Async progress bars with passing-through output | `tuin_spin` covers the 80%. |
| Declarative menu trees / a menu engine | Framework territory. Rejected. |
| Audit / command logging; a `tuin_run` safe runner | Surface discipline. Rejected. |
| Configurable color themes | `NO_COLOR` is the contract. Theming is upstream. |
| Auto-completion in `tuin_input` | Different problem space. |
| i18n / localization of labels | The library has no labels, only decorations. |
| A Linux bash 3.2 CI job | macOS covers 3.2 today. A Linux 3.2 image would catch libc-level differences, at the cost of a Docker build. |
| An MCP server, a separate `llms.txt`, a standalone `docs/` cookbook | Conflict with the zero-dep, low-maintenance identity. Revisit only under real adoption pressure. |
