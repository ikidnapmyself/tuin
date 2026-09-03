#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$TUIN_SH"
}

key() {
    _tuin_readkey 3< <(printf "$1") && printf '%s' "$_tuin_key"
}

@test "readkey: enter on CR and LF" {
    [ "$(key '\r')" = enter ]
    [ "$(key '\n')" = enter ]
}

@test "readkey: bare ESC" {
    [ "$(key '\033')" = esc ]
}

@test "readkey: CSI arrows" {
    [ "$(key '\033[A')" = up ]
    [ "$(key '\033[B')" = down ]
    [ "$(key '\033[C')" = right ]
    [ "$(key '\033[D')" = left ]
}

@test "readkey: SS3 arrows (application mode)" {
    [ "$(key '\033OA')" = up ]
    [ "$(key '\033OD')" = left ]
}

@test "readkey: home/end in all common encodings" {
    [ "$(key '\033[H')" = home ]
    [ "$(key '\033[F')" = end ]
    [ "$(key '\033[1~')" = home ]
    [ "$(key '\033[4~')" = end ]
    [ "$(key '\033[7~')" = home ]
    [ "$(key '\033[8~')" = end ]
    [ "$(key '\033OH')" = home ]
    [ "$(key '\033OF')" = end ]
}

@test "readkey: page keys, shift-tab" {
    [ "$(key '\033[5~')" = pgup ]
    [ "$(key '\033[6~')" = pgdn ]
    [ "$(key '\033[Z')" = shift-tab ]
}

@test "readkey: unknown CSI is consumed whole, not leaked" {
    _tuin_readkey 3< <(printf '\033[15~')
    [ "$_tuin_key" = unknown ]
    run bash -c "source '$TUIN_SH'; { _tuin_readkey; _tuin_readkey; echo rc=\$?; } 3< <(printf '\033[15~')"
    [[ "$output" == *"rc=1"* ]]
}

@test "readkey: alt chords" {
    [ "$(key '\033x')" = alt-x ]
}

@test "readkey: backspace, tab, control letters" {
    [ "$(key '\177')" = bs ]
    [ "$(key '\b')" = bs ]
    [ "$(key '\t')" = tab ]
    [ "$(key '\001')" = ctrl-a ]
    [ "$(key '\016')" = ctrl-n ]
    [ "$(key '\020')" = ctrl-p ]
    [ "$(key '\025')" = ctrl-u ]
    [ "$(key '\027')" = ctrl-w ]
}

@test "readkey: printable chars, including space and digits" {
    [ "$(key 'j')" = char:j ]
    [ "$(key '3')" = char:3 ]
    [ "$(key ' ')" = 'char: ' ]
}

@test "readkey: multi-byte UTF-8 arrives as one char" {
    local loc=""
    for cand in en_US.UTF-8 C.UTF-8; do
        if locale -a 2>/dev/null | grep -qx -i "$(printf '%s' "$cand" | tr 'A-Z' 'a-z')" \
           || locale -a 2>/dev/null | grep -qx "$cand"; then
            loc="$cand"; break
        fi
    done
    [ -n "$loc" ] || skip "no UTF-8 locale available"
    LC_ALL="$loc" run bash -c "source '$TUIN_SH'; _tuin_readkey 3< <(printf '\303\251') && printf '%s' \"\$_tuin_key\""
    [ "$output" = 'char:é' ]
}

@test "readkey: EOF returns 1" {
    run bash -c "source '$TUIN_SH'; _tuin_readkey 3< /dev/null; echo rc=\$?"
    [ "$output" = rc=1 ]
}

@test "readkey: ESC delay is probed at source time" {
    [[ "$_TUIN_ESC_DELAY" == 1 || "$_TUIN_ESC_DELAY" == 0.05 ]]
}

@test "readkey: TUIN_ESC_DELAY overrides the probe" {
    TUIN_ESC_DELAY=2 run bash -c "source '$TUIN_SH'; echo \$_TUIN_ESC_DELAY"
    [ "$output" = 2 ]
}
