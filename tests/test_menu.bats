#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
}

@test "tuin_menu with no options returns 2" {
    run bash -c "source '$TUIN_SH' && tuin_menu 'Title'"
    assert_failure 2
}

@test "tuin_menu non-TTY numbered pick sets TUIN_REPLY and returns 0" {
    run bash -c "source '$TUIN_SH' && echo 1 | { tuin_menu 'Pick' alpha bravo; echo \"rc=\$? reply=\$TUIN_REPLY\"; }"
    assert_success
    assert_output --partial "rc=0 reply=alpha"
}

@test "tuin_menu non-TTY second option" {
    run bash -c "source '$TUIN_SH' && echo 2 | { tuin_menu 'Pick' alpha bravo; echo \"reply=\$TUIN_REPLY\"; }"
    assert_output --partial "reply=bravo"
}

@test "tuin_menu selecting the auto Back entry returns non-zero" {
    # alpha, bravo, then Back is option 3
    run bash -c "source '$TUIN_SH' && echo 3 | tuin_menu 'Pick' alpha bravo"
    assert_failure
}

@test "tuin_menu EOF (closed stdin) returns non-zero so loops terminate" {
    run bash -c "source '$TUIN_SH' && tuin_menu 'Pick' alpha bravo </dev/null"
    assert_failure
}

@test "tuin_menu empty input returns non-zero" {
    run bash -c "source '$TUIN_SH' && printf '\n' | tuin_menu 'Pick' alpha bravo"
    assert_failure
}

@test "tuin_menu out-of-range input returns non-zero" {
    run bash -c "source '$TUIN_SH' && echo 9 | tuin_menu 'Pick' alpha bravo"
    assert_failure
}

@test "tuin_menu renders the title and a numbered list to stderr" {
    run bash -c "source '$TUIN_SH' && echo 1 | tuin_menu 'My Title' alpha bravo 2>&1 1>/dev/null"
    assert_output --partial "My Title"
    assert_output --partial "1) alpha"
}

@test "tuin_menu auto-appends a Back entry (default label)" {
    run bash -c "source '$TUIN_SH' && echo 1 | tuin_menu 'Pick' alpha 2>&1 1>/dev/null"
    assert_output --partial "Back"
}

@test "tuin_menu honors TUIN_MENU_BACK override" {
    run bash -c "source '$TUIN_SH' && echo 1 | TUIN_MENU_BACK=Return tuin_menu 'Pick' alpha 2>&1 1>/dev/null"
    assert_output --partial "Return"
}

@test "tuin_menu loop terminates on Back without consuming the universe" {
    # Feed one real pick (1=alpha → body iteration) then Back (option 2);
    # the loop body runs once, then exits.
    run bash -c "source '$TUIN_SH' && printf '1\n2\n' | { count=0; while tuin_menu 'Pick' alpha; do count=\$((count+1)); done; echo \"iterations=\$count\"; }"
    assert_output --partial "iterations=1"
}