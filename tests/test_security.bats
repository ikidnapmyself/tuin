#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    load 'test_helper/pty'
}

@test "security: tuin.sh contains no eval / sh -c / indirect expansion" {
    run grep -nE '(^|[^a-zA-Z_])eval[[:space:]]|[[:space:]](sh|bash|zsh)[[:space:]]+-c[[:space:]]|\$\{![a-zA-Z_]' "$TUIN_SH"
    [ "$status" -ne 0 ] || fail "forbidden construct in tuin.sh:
$output"
}

@test "security: every \$@ / \$* in tuin.sh is quoted" {
    run grep -nE '[^"]\$[@*]([^"]|$)' "$TUIN_SH"
    [ "$status" -ne 0 ] || fail "unquoted \$@ or \$* in tuin.sh:
$output"
}

@test "security: no shell-escape key in any primitive" {
    tuin_pty '!\r'  -- 'tuin_choose a b';        [ "$pty_out" = a ]
    tuin_pty ':\r'  -- 'tuin_choose a b';        [ "$pty_out" = a ]
    tuin_pty '!q'   -- 'tuin_confirm Go?; echo "rc=$?"'; [ "$pty_out" = rc=1 ]
    tuin_pty '!\r' -- 'tuin_menu T A; echo "rc=$? reply=$TUIN_REPLY"'
    [ "$pty_out" = 'rc=0 reply=A' ]
}

@test "security: menu labels and titles with escapes never reach the terminal raw" {
    local clear=$'\033[2J' bel=$'\007'
    tuin_pty '\r' -- "tuin_menu \$'T\\033[2J' \$'A\\007'; printf '%s' \"\$TUIN_REPLY\""
    [ "$pty_out" = $'A\007' ]
    [[ "$pty_tty" != *"$clear"* ]]
    [[ "$pty_tty" != *"$bel"* ]]
    [[ "$pty_tty" == *"T[2J"* ]]
}

@test "security: tuin_spin runs argv only, no word splitting" {
    run bash -c "source '$TUIN_SH'; tuin_spin Label -- printf '%s|' 'a b' 'c;d' </dev/null"
    assert_output "a b|c;d|"
}
