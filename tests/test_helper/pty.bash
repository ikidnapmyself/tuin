#!/usr/bin/env bash

_tuin_pty_script() {
    if script --version >/dev/null 2>&1; then
        script -qec "$2" "$1"
    else
        script -q "$1" "$2"
    fi
}

_TUIN_PTY_STTY_NORM='
tuin_stty_norm() {
    local g lf
    g=$(stty -g) || return 1
    case "$g" in
        *lflag=*)
            lf=${g#*lflag=}; lf=${lf%%:*}
            printf "%s" "${g/lflag=$lf/lflag=$(printf "%x" $(( 0x$lf & ~0x20000000 )))}"
            ;;
        *) printf "%s" "$g" ;;
    esac
}'

tuin_pty() {
    local keys="$1"; shift
    [[ "${1:-}" == "--" ]] && shift
    local snippet="$1"
    local dir="$BATS_TEST_TMPDIR"
    local wrapper="$dir/wrapper.sh"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        "source '$TUIN_SH'" \
        "$_TUIN_PTY_STTY_NORM" \
        "trap ':' INT TERM" \
        "( $snippet ) > '$dir/out'" \
        "echo \$? > '$dir/status'" > "$wrapper"
    chmod +x "$wrapper"
    : > "$dir/out"; : > "$dir/status"; : > "$dir/tty"

    (
        sleep "${TUIN_PTY_LEAD:-0.6}"
        local chunk rest="$keys"
        while [[ "$rest" == *'%PAUSE%'* ]]; do
            chunk="${rest%%\%PAUSE\%*}"
            rest="${rest#*%PAUSE%}"
            # shellcheck disable=SC2059  # chunk is deliberately a printf format
            printf "$chunk"
            sleep 1.3
        done
        # shellcheck disable=SC2059  # keys is deliberately a printf format
        printf "$rest"
        sleep "${TUIN_PTY_TAIL:-1.5}"
    ) | TERM=xterm NO_COLOR=1 _tuin_pty_script "$dir/tty" "$wrapper" >/dev/null 2>&1 || true

    pty_status=$(cat "$dir/status")
    pty_out=$(cat "$dir/out")
    pty_tty=$(cat "$dir/tty")
}
