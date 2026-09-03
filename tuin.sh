#!/usr/bin/env bash
#
# tuin.sh — pure-bash TUI primitives, MIT-licensed
# Version: 0.1.0
# Home: https://github.com/ikidnapmyself/tuin
#
# Public API:
#   tuin_choose <opt1> <opt2> ...    Arrow-key menu; type-ahead when >=10 items
#   tuin_confirm <prompt> [default]  Single-keypress y/n
#   tuin_input <prompt> [default] [regex]   Read with default + regex validation
#   tuin_spin <label> -- <cmd> [args ...]   Run command with spinner
#   tuin_banner <title>              Boxed banner
#   tuin_section <heading>           Section divider
#   tuin_version                     Print version string and return 0
#   tuin_unpriv                      Refuse to run as root / via sudo
#   tuin_guard <cmd> [args ...]      Reject privilege-escalating commands
#
# Contract:
#   - Primitives degrade gracefully when stdout or stdin is not a TTY.
#   - Respects NO_COLOR (https://no-color.org).
#   - Bash 3.2+ compatible (macOS default shell).
#   - Zero external dependencies beyond bash, printf, read, stty, tput.
#
# License: MIT (see LICENSE)
#   Copyright (c) 2026 Burak
#

[[ -n "${_TUIN_LOADED:-}" ]] && return 0
_TUIN_LOADED=1

_TUIN_VERSION="0.1.0"

_TUIN_INTERRUPTED=0
_TUIN_REDRAW=0
_TUIN_TTY_ACTIVE=0
_TUIN_OWN_EXIT=0
_TUIN_TRAPPED=0
_TUIN_STTY_SAVED=""
_TUIN_MENU_LAST_TITLE=""
_TUIN_MENU_LAST_INDEX=0
_tuin_key=""

# ---------------------------------------------------------------------------
# Helpers (private)
# ---------------------------------------------------------------------------

_tuin_is_tty() {
    [[ -t 1 && -t 0 && -n "${TERM:-}" && "$TERM" != "dumb" ]]
}

_tuin_use_color() {
    _tuin_is_tty && [[ -z "${NO_COLOR:-}" ]]
}

_tuin_is_utf8() {
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *[Uu][Tt][Ff]-8 | *[Uu][Tt][Ff]8) return 0 ;;
        *) return 1 ;;
    esac
}

# euid as a function so tests can redefine it to simulate root.
_tuin_euid() {
    printf '%s\n' "${EUID:-0}"
}

# Source-time color detection. Vars stay empty if not using color.
_TUIN_CYAN=""
_TUIN_BOLD=""
_TUIN_REV=""
_TUIN_DIM=""
_TUIN_RESET=""
if _tuin_use_color; then
    if command -v tput >/dev/null 2>&1; then
        _TUIN_CYAN=$(tput setaf 6 2>/dev/null  || printf '\033[36m')
        _TUIN_BOLD=$(tput bold     2>/dev/null || printf '\033[1m')
        _TUIN_REV=$(tput rev       2>/dev/null || printf '\033[7m')
        _TUIN_DIM=$(tput dim       2>/dev/null || printf '\033[2m')
        _TUIN_RESET=$(tput sgr0    2>/dev/null || printf '\033[0m')
    else
        _TUIN_CYAN=$'\033[36m'
        _TUIN_BOLD=$'\033[1m'
        _TUIN_REV=$'\033[7m'
        _TUIN_DIM=$'\033[2m'
        _TUIN_RESET=$'\033[0m'
    fi
fi

_tuin_detect_esc_delay() {
    local REPLY
    if read -r -t 0.05 <<< '' 2>/dev/null; then
        printf '0.05\n'
    else
        printf '1\n'
    fi
}
_TUIN_ESC_DELAY="${TUIN_ESC_DELAY:-$(_tuin_detect_esc_delay)}"

_tuin_bytelen() {
    local LC_ALL=C
    printf '%d\n' "${#1}"
}

_tuin_ord() {
    local LC_ALL=C n
    n=$(printf '%d' "'$1")
    (( n < 0 )) && n=$((n + 256))
    printf '%d\n' "$n"
}

_tuin_readkey() {
    local k s c seq n ord rc t0 idle=0
    while :; do
        t0=$SECONDS
        IFS= read -rsn1 -t 1 k <&3
        rc=$?
        (( _TUIN_INTERRUPTED )) && { _tuin_key=interrupt; return 0; }
        (( rc == 0 )) && break
        (( _TUIN_REDRAW )) && { _tuin_key=redraw; return 0; }
        if (( rc > 128 )) || (( SECONDS != t0 )); then
            idle=0
            continue
        fi
        idle=$((idle + 1))
        (( idle >= 2 )) && return 1
    done

    case "$k" in
        ''|$'\r') _tuin_key=enter; return 0 ;;
        $'\t')    _tuin_key=tab;   return 0 ;;
        $'\177'|$'\b') _tuin_key=bs; return 0 ;;
        $'\033')
            if ! IFS= read -rsn1 -t "$_TUIN_ESC_DELAY" s <&3 2>/dev/null; then
                _tuin_key=esc; return 0
            fi
            case "$s" in
                '[')
                    seq=""; n=0
                    while (( n < 8 )); do
                        IFS= read -rsn1 -t "$_TUIN_ESC_DELAY" c <&3 2>/dev/null || break
                        seq="$seq$c"; n=$((n + 1))
                        case "$c" in [0-9\;]) ;; *) break ;; esac
                    done
                    case "$seq" in
                        A) _tuin_key=up ;;    B) _tuin_key=down ;;
                        C) _tuin_key=right ;; D) _tuin_key=left ;;
                        H|1~|7~) _tuin_key=home ;;
                        F|4~|8~) _tuin_key=end ;;
                        5~) _tuin_key=pgup ;;  6~) _tuin_key=pgdn ;;
                        Z)  _tuin_key=shift-tab ;;
                        *)  _tuin_key=unknown ;;
                    esac
                    return 0 ;;
                'O')
                    IFS= read -rsn1 -t "$_TUIN_ESC_DELAY" c <&3 2>/dev/null || c=""
                    case "$c" in
                        A) _tuin_key=up ;;   B) _tuin_key=down ;;
                        C) _tuin_key=right ;; D) _tuin_key=left ;;
                        H) _tuin_key=home ;; F) _tuin_key=end ;;
                        *) _tuin_key=unknown ;;
                    esac
                    return 0 ;;
                *)
                    if [[ "$s" == [[:print:]] ]]; then
                        _tuin_key="alt-$s"
                    else
                        _tuin_key=unknown
                    fi
                    return 0 ;;
            esac ;;
    esac

    if (( $(_tuin_bytelen "$k") > 1 )); then
        _tuin_key="char:$k"; return 0
    fi

    ord=$(_tuin_ord "$k")
    if (( ord >= 1 && ord <= 26 )); then
        local letters=abcdefghijklmnopqrstuvwxyz
        _tuin_key="ctrl-${letters:$((ord - 1)):1}"; return 0
    fi
    if (( ord >= 194 && ord <= 244 )); then
        n=1; (( ord >= 224 )) && n=2; (( ord >= 240 )) && n=3
        IFS= read -rsn"$n" -t "$_TUIN_ESC_DELAY" s <&3 2>/dev/null || s=""
        _tuin_key="char:$k$s"; return 0
    fi
    if (( ord >= 32 && ord <= 126 )); then
        _tuin_key="char:$k"; return 0
    fi
    _tuin_key=unknown
    return 0
}

_tuin_tty_raw() {
    stty -icanon -echo min 1 time 0 <&3 2>/dev/null
    printf '\033[?25l' >&3
}

_tuin_tty_cooked() {
    printf '\033[?25h' >&3
    stty "$_TUIN_STTY_SAVED" <&3 2>/dev/null
}

_tuin_tty_enter() {
    (( _TUIN_TTY_ACTIVE )) && return 0
    exec 3<>/dev/tty 2>/dev/null || return 1
    _TUIN_STTY_SAVED=$(stty -g <&3 2>/dev/null) || { exec 3<&-; return 1; }
    _TUIN_TTY_ACTIVE=1
    _TUIN_INTERRUPTED=0
    _TUIN_REDRAW=0
    _tuin_tty_raw
    _TUIN_TRAPPED=1
    trap '_tuin_tty_onsignal' INT TERM
    trap '_tuin_tty_suspend' TSTP
    trap '_tuin_tty_resume' CONT
    trap '_TUIN_REDRAW=1' WINCH
    if [[ -z "$(trap -p EXIT)" ]]; then
        _TUIN_OWN_EXIT=1
        trap '_tuin_tty_leave' EXIT
    fi
    return 0
}

_tuin_tty_onsignal() {
    _TUIN_INTERRUPTED=1
    return 0
}

_tuin_tty_untrap() {
    (( _TUIN_TRAPPED )) || return 0
    _TUIN_TRAPPED=0
    trap - INT TERM TSTP CONT WINCH
    if (( _TUIN_OWN_EXIT )); then
        trap - EXIT
        _TUIN_OWN_EXIT=0
    fi
    return 0
}

_tuin_tty_leave() {
    if (( _TUIN_TTY_ACTIVE )); then
        _tuin_tty_cooked
        exec 3<&-
        _TUIN_TTY_ACTIVE=0
    fi
    _tuin_tty_untrap
    return 0
}

_tuin_tty_suspend() {
    _tuin_tty_cooked
    trap - TSTP
    kill -TSTP $$
}

_tuin_tty_resume() {
    (( _TUIN_TTY_ACTIVE )) || return 0
    _tuin_tty_raw
    trap '_tuin_tty_suspend' TSTP
    _TUIN_REDRAW=1
}

_tuin_tty_rows() {
    local r c
    read -r r c < <(stty size <&3 2>/dev/null)
    [[ "$r" =~ ^[0-9]+$ ]] && (( r > 0 )) || r=24
    printf '%d\n' "$r"
}

# ---------------------------------------------------------------------------
# Public API — stubs (filled in by later tasks)
# ---------------------------------------------------------------------------

tuin_version() {
    printf '%s\n' "$_TUIN_VERSION"
}

# Refuse to run elevated. Returns non-zero (and warns on stderr) when the
# process is root or was launched via sudo; returns 0 otherwise.
# Idiom:  tuin_unpriv || exit 1
tuin_unpriv() {
    if [[ "$(_tuin_euid)" -eq 0 ]] || [[ -n "${SUDO_USER:-}${SUDO_UID:-}" ]]; then
        printf 'tuin: refusing to run with elevated privileges (root/sudo)\n' >&2
        return 1
    fi
    return 0
}

# Screen a command for privilege escalation. Inspects only the basename of
# argv[0] against a small denylist. Returns non-zero (and warns on stderr)
# for an escalating command, or when called with no command at all; returns 0
# otherwise.
# Idiom:  tuin_guard "$@" && tuin_spin "Running" -- "$@"
tuin_guard() {
    if [[ $# -eq 0 ]]; then
        printf 'tuin: guard called with no command\n' >&2
        return 1
    fi
    local cmd_base="${1:-}"
    cmd_base="${cmd_base##*/}"
    case "$cmd_base" in
        sudo|doas|su|pkexec|run0|sudoedit)
            printf 'tuin: refusing to run escalating command: %s\n' "$cmd_base" >&2
            return 1
            ;;
    esac
    return 0
}

tuin_banner() {
    local title="$1"
    local width=$(( ${#title} + 4 ))
    local i bar=""
    if _tuin_is_utf8; then
        for (( i=0; i<width; i++ )); do bar="${bar}═"; done
        printf '%s╔%s╗%s\n' "$_TUIN_CYAN" "$bar" "$_TUIN_RESET"
        printf '%s║  %s  ║%s\n' "$_TUIN_CYAN" "$title" "$_TUIN_RESET"
        printf '%s╚%s╝%s\n' "$_TUIN_CYAN" "$bar" "$_TUIN_RESET"
    else
        for (( i=0; i<width; i++ )); do bar="${bar}-"; done
        printf '%s+%s+%s\n' "$_TUIN_CYAN" "$bar" "$_TUIN_RESET"
        printf '%s|  %s  |%s\n' "$_TUIN_CYAN" "$title" "$_TUIN_RESET"
        printf '%s+%s+%s\n' "$_TUIN_CYAN" "$bar" "$_TUIN_RESET"
    fi
}

tuin_section() {
    local heading="$1"
    if _tuin_is_utf8; then
        printf '%s═══ %s%s%s ═══%s\n' \
            "$_TUIN_CYAN" "$_TUIN_BOLD" "$heading" "$_TUIN_RESET" "$_TUIN_RESET"
    else
        printf '=== %s ===\n' "$heading"
    fi
}

tuin_confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local indicator key rc

    if [[ "$default" == "y" || "$default" == "Y" ]]; then
        indicator="[Y/n]"
    else
        indicator="[y/N]"
    fi

    if ! _tuin_choose_interactive || ! _tuin_tty_enter; then
        IFS= read -r key || key=""
        case "$key" in
            y*|Y*) return 0 ;;
            "")
                [[ "$default" == "y" || "$default" == "Y" ]] && return 0
                return 1
                ;;
            *) return 1 ;;
        esac
    fi

    printf '%s %s ' "$prompt" "$indicator" >&3
    rc=1
    while :; do
        if ! _tuin_readkey; then
            rc=1
            break
        fi
        if (( _TUIN_INTERRUPTED )); then
            rc=130
            break
        fi
        case "$_tuin_key" in
            char:y|char:Y) rc=0; break ;;
            char:n|char:N|char:q|esc) rc=1; break ;;
            enter)
                if [[ "$default" == "y" || "$default" == "Y" ]]; then
                    rc=0
                else
                    rc=1
                fi
                break
                ;;
        esac
    done
    printf '\n' >&3
    _tuin_tty_leave
    return "$rc"
}

tuin_input() {
    local prompt="$1"
    local default="${2:-}"
    local regex="${3:-}"
    local built_prompt value

    if [[ -n "$default" ]]; then
        built_prompt="$prompt [$default]: "
    else
        built_prompt="$prompt: "
    fi

    if ! _tuin_is_tty; then
        IFS= read -r value || value=""
        [[ -z "$value" ]] && value="$default"
        printf '%s\n' "$value"
        return 0
    fi

    while :; do
        IFS= read -r -p "$built_prompt" value
        [[ -z "$value" ]] && value="$default"
        if [[ -z "$regex" ]] || [[ "$value" =~ $regex ]]; then
            printf '%s\n' "$value"
            return 0
        fi
        printf '  invalid; expected match /%s/\n' "$regex" >&2
    done
}

tuin_spin() {
    local label="$1"
    shift
    if [[ "${1:-}" == "--" ]]; then
        shift
    fi

    if ! _tuin_is_tty; then
        "$@"
        return $?
    fi

    local frames i pid rc
    if _tuin_is_utf8; then
        frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    else
        # shellcheck disable=SC1003  # intentional literal backslash spinner frame
        frames='|/-\'
    fi

    printf '\033[?25l'  # hide cursor
    trap 'printf "\r\033[K\033[?25h"; trap - INT TERM; return 130' INT TERM
    "$@" &
    pid=$!
    i=0
    while kill -0 "$pid" 2>/dev/null; do
        if _tuin_is_utf8; then
            printf '\r%s %s' "${frames:$((i % 10)):1}" "$label"
        else
            printf '\r%s %s' "${frames:$((i % 4)):1}" "$label"
        fi
        sleep 0.1
        i=$((i + 1))
    done
    wait "$pid"
    rc=$?
    printf '\r\033[K\033[?25h'  # clear line, show cursor
    trap - INT TERM
    return $rc
}

# True when a human is at stdin (-t 0) and /dev/tty is usable for the UI.
# Note: deliberately does NOT require stdout to be a TTY, so the selected value
# can be captured (choice=$(tuin_choose ...)) while the UI still renders.
_tuin_choose_interactive() {
    [[ -t 0 ]] \
        && [[ -n "${TERM:-}" ]] && [[ "$TERM" != "dumb" ]] \
        && [[ -r /dev/tty && -w /dev/tty ]]
}

tuin_choose() {
    if [[ "$#" -eq 0 ]]; then
        return 2
    fi
    local options=("$@")
    local count="${#options[@]}"

    if ! _tuin_choose_interactive || ! _tuin_tty_enter; then
        local pick
        IFS= read -r pick || pick=""
        if [[ "$pick" =~ ^[1-9][0-9]*$ ]] && [[ "$pick" -le "$count" ]]; then
            printf '%s\n' "${options[$((pick - 1))]}"
        else
            printf '%s\n' "${options[0]}"
        fi
        return 0
    fi

    local filter="" filter_enabled=0 numbered=0 hints=1
    case "${TUIN_FILTER:-}" in
        1) filter_enabled=1 ;;
        0) filter_enabled=0 ;;
        *) (( count >= 10 )) && filter_enabled=1 ;;
    esac
    (( ! filter_enabled && count < 10 )) && numbered=1
    [[ "${TUIN_HINTS:-1}" == 0 ]] && hints=0

    local selected=0 top=0 rows=0 max_rows=0 last_height=0
    local filtered_indices=() visible_count i
    for (( i=0; i<count; i++ )); do
        filtered_indices+=("$i")
    done
    visible_count=$count
    if [[ "${_TUIN_CHOOSE_START:-}" =~ ^[0-9]+$ ]] && (( _TUIN_CHOOSE_START < count )); then
        selected=$_TUIN_CHOOSE_START
    fi

    local hint
    if _tuin_is_utf8; then
        hint='↑↓/jk move · enter pick · esc cancel'
    else
        hint='up/down/jk move, enter pick, esc cancel'
    fi
    (( filter_enabled )) && hint="${hint/\/jk/} · type to filter"
    (( numbered )) && hint="${hint/enter pick/1-9 or enter pick}"

    _tuin_choose_draw

    local c
    while :; do
        if ! _tuin_readkey; then
            _tuin_tty_leave
            return 1
        fi
        if (( _TUIN_INTERRUPTED )); then
            _tuin_tty_leave
            return 130
        fi
        case "$_tuin_key" in
            up|ctrl-p|shift-tab) _tuin_choose_move -1 1 ;;
            down|ctrl-n|tab)     _tuin_choose_move 1 1 ;;
            home) selected=0 ;;
            end)  selected=$((visible_count - 1)) ;;
            pgup) _tuin_choose_move "-$rows" 0 ;;
            pgdn) _tuin_choose_move "$rows" 0 ;;
            enter)
                _tuin_tty_leave
                (( visible_count == 0 )) && return 1
                printf '%s\n' "${options[${filtered_indices[$selected]}]}"
                return 0 ;;
            esc)
                if (( filter_enabled )) && [[ -n "$filter" ]]; then
                    filter=""; _tuin_choose_apply_filter
                else
                    _tuin_tty_leave; return 1
                fi ;;
            left) _tuin_tty_leave; return 1 ;;
            bs)
                if (( filter_enabled )) && [[ -n "$filter" ]]; then
                    filter="${filter%?}"; _tuin_choose_apply_filter
                else
                    _tuin_tty_leave; return 1
                fi ;;
            ctrl-u)
                (( filter_enabled )) && { filter=""; _tuin_choose_apply_filter; } ;;
            ctrl-w)
                if (( filter_enabled )); then
                    while [[ "$filter" == *' ' ]]; do filter="${filter% }"; done
                    if [[ "$filter" == *' '* ]]; then
                        filter="${filter% *} "
                    else
                        filter=""
                    fi
                    _tuin_choose_apply_filter
                fi ;;
            char:*)
                c="${_tuin_key#char:}"
                if (( filter_enabled )); then
                    filter="$filter$c"; _tuin_choose_apply_filter
                elif (( numbered )) && [[ "$c" == [1-9] ]] && (( c <= count )); then
                    _tuin_tty_leave
                    printf '%s\n' "${options[$((c - 1))]}"
                    return 0
                else
                    case "$c" in
                        j) _tuin_choose_move 1 1 ;;
                        k) _tuin_choose_move -1 1 ;;
                        g) selected=0 ;;
                        G) selected=$((visible_count - 1)) ;;
                        q) _tuin_tty_leave; return 1 ;;
                    esac
                fi ;;
        esac
        (( selected < 0 )) && selected=0
        _tuin_choose_draw
    done
}

_tuin_choose_move() {
    local delta=$1 wrap=$2
    (( visible_count == 0 )) && { selected=0; return 0; }
    selected=$((selected + delta))
    if (( wrap )); then
        (( selected < 0 )) && selected=$((visible_count - 1))
        (( selected >= visible_count )) && selected=0
    else
        (( selected < 0 )) && selected=0
        (( selected >= visible_count )) && selected=$((visible_count - 1))
    fi
    return 0
}

_tuin_choose_apply_filter() {
    filtered_indices=()
    if [[ -z "$filter" ]]; then
        local j
        for (( j=0; j<count; j++ )); do
            filtered_indices+=("$j")
        done
    else
        local line
        while IFS= read -r line; do
            filtered_indices+=("$line")
        done < <(_tuin_choose_filter "$filter" "${options[@]}")
    fi
    visible_count="${#filtered_indices[@]}"
    if (( visible_count == 0 )); then
        selected=0
    elif (( selected >= visible_count )); then
        selected=$((visible_count - 1))
    fi
    return 0
}

_tuin_choose_draw() {
    if (( max_rows == 0 || _TUIN_REDRAW )); then
        max_rows=$(( $(_tuin_tty_rows) - 3 ))
        (( max_rows < 1 )) && max_rows=1
        _TUIN_REDRAW=0
    fi
    rows=$visible_count
    (( rows > max_rows )) && rows=$max_rows
    (( selected < top )) && top=$selected
    (( selected >= top + rows )) && top=$((selected - rows + 1))
    (( top + rows > visible_count )) && top=$((visible_count - rows))
    (( top < 0 )) && top=0

    local height=$((rows + filter_enabled + hints))
    (( last_height > 0 )) && printf '\033[%dA' "$last_height" >&3
    _tuin_choose_render >&3
    if (( height < last_height )); then
        local extras=$((last_height - height)) x
        for (( x=0; x<extras; x++ )); do
            printf '\r\033[K\n' >&3
        done
        printf '\033[%dA' "$extras" >&3
    fi
    last_height=$height
    return 0
}

_tuin_choose_render() {
    local pos idx label prefix
    for (( pos=top; pos<top+rows; pos++ )); do
        idx="${filtered_indices[$pos]}"
        label="${options[$idx]//[[:cntrl:]]/}"
        prefix=""
        (( numbered )) && prefix="$((idx + 1))) "
        printf '\r\033[K'
        if (( pos == selected )); then
            printf '%s>%s %s%s%s%s\n' \
                "$_TUIN_CYAN" "$_TUIN_RESET" \
                "$_TUIN_REV" "$prefix" "$label" "$_TUIN_RESET"
        else
            printf '  %s%s\n' "$prefix" "$label"
        fi
    done
    if (( filter_enabled )); then
        printf '\r\033[K  filter: %s  (%d/%d)\n' "${filter//[[:cntrl:]]/}" "$visible_count" "$count"
    fi
    if (( hints )); then
        printf '\r\033[K%s%s%s\n' "$_TUIN_DIM" "$hint" "$_TUIN_RESET"
    fi
    return 0
}

_tuin_choose_filter() {
    local filter="$1"
    shift
    local i=0 item
    shopt -s nocasematch
    for item in "$@"; do
        if [[ -z "$filter" ]] || [[ "$item" == *"$filter"* ]]; then
            printf '%d\n' "$i"
        fi
        i=$((i + 1))
    done
    shopt -u nocasematch
}

# tuin_menu <title> <option1> [option2 ...]
#
# A looping menu. Renders <title> + options plus an auto-appended Back entry
# (label via ${TUIN_MENU_BACK:-Back}). On an action pick, sets $TUIN_REPLY to
# the chosen label and returns 0 (so a `while tuin_menu ...; do` loop repeats —
# "never dying"). Returns non-zero on Back / ESC / q / left / backspace /
# Ctrl-C (interactive) or on empty input / EOF / out-of-range
# (non-interactive), which ends the loop. Consecutive calls with the same
# title reopen on the last picked entry.
# shellcheck disable=SC2034  # TUIN_REPLY is the output global, read by callers
tuin_menu() {
    if [[ "$#" -lt 2 ]]; then
        return 2
    fi
    local title="$1"; shift
    local back="${TUIN_MENU_BACK:-Back}"
    local opts=("$@" "$back")

    if _tuin_choose_interactive; then
        printf '%s\n' "$title" >/dev/tty 2>/dev/null
        local sel rc start=0 i
        [[ "$title" == "$_TUIN_MENU_LAST_TITLE" ]] && start=$_TUIN_MENU_LAST_INDEX
        _TUIN_CHOOSE_START=$start
        sel=$(tuin_choose "${opts[@]}"); rc=$?
        unset _TUIN_CHOOSE_START
        (( rc != 0 )) && return 1
        [[ "$sel" == "$back" ]] && return 1
        _TUIN_MENU_LAST_TITLE="$title"
        for (( i=0; i<${#opts[@]}; i++ )); do
            [[ "${opts[$i]}" == "$sel" ]] && { _TUIN_MENU_LAST_INDEX=$i; break; }
        done
        TUIN_REPLY="$sel"
        return 0
    fi

    local i
    printf '%s\n' "$title" >&2
    for (( i=0; i<${#opts[@]}; i++ )); do
        printf '  %d) %s\n' "$((i + 1))" "${opts[$i]}" >&2
    done
    local pick
    IFS= read -r pick || return 1
    [[ -z "$pick" ]] && return 1
    if [[ "$pick" =~ ^[1-9][0-9]*$ ]] && (( pick <= ${#opts[@]} )); then
        local sel="${opts[$((pick - 1))]}"
        [[ "$sel" == "$back" ]] && return 1
        TUIN_REPLY="$sel"
        return 0
    fi
    return 1
}
