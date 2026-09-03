#!/usr/bin/env bash

_tuin_pty_script() {
    if script --version >/dev/null 2>&1; then
        script -qec "$2" "$1"
    else
        script -q "$1" "$2"
    fi
}

tuin_pty() {
    local keys="$1"; shift
    [[ "${1:-}" == "--" ]] && shift
    local snippet="$1"
    local dir="$BATS_TEST_TMPDIR"
    local wrapper="$dir/wrapper.sh"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        "source '$TUIN_SH'" \
        "( $snippet ) > '$dir/out'" \
        "echo \$? > '$dir/status'" > "$wrapper"
    chmod +x "$wrapper"
    : > "$dir/out"; : > "$dir/status"; : > "$dir/tty"

    (
        sleep 0.3
        # shellcheck disable=SC2059  # keys is deliberately a printf format
        printf "$keys"
        sleep "${TUIN_PTY_TAIL:-1.5}"
    ) | TERM=xterm NO_COLOR=1 _tuin_pty_script "$dir/tty" "$wrapper" >/dev/null 2>&1 || true

    pty_status=$(cat "$dir/status")
    pty_out=$(cat "$dir/out")
    pty_tty=$(cat "$dir/tty")
}
