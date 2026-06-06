# tuin examples

Each script demonstrates one primitive. They source `../tuin.sh` and exit
cleanly when invoked from a real terminal.

| Script | Primitive(s) |
|---|---|
| `menu.sh` | `tuin_choose` |
| `form.sh` | `tuin_input` + `tuin_confirm` + `tuin_banner` |
| `progress.sh` | `tuin_spin` + `tuin_section` |
| `full_demo.sh` | All six TUI primitives |
| `safe_wrapper.sh` | `tuin_unpriv` + `tuin_guard` + `tuin_choose` + `tuin_spin` |
| `cascading_menu.sh` | `tuin_menu` (drill-down + never-dying) + `tuin_banner` + `tuin_section` |

Run any of them from the repo root:

    bash examples/menu.sh
