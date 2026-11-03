#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    load 'test_helper/pty'
    WORK="$BATS_TEST_TMPDIR/vendored"
    mkdir -p "$WORK"
    cp "$TUIN_SH" "$WORK/tuin.sh"
}

colored() {
    bash -c "source '$1'; _TUIN_CYAN=\$'\\033[36m'; _TUIN_RESET=\$'\\033[0m'; tuin_logo"
}

@test "logo: with no assets beside tuin.sh it prints the embedded tulip" {
    run bash -c "source '$WORK/tuin.sh'; tuin_logo"
    assert_success
    [ "${#lines[@]}" -ge 4 ]
    [ "${#lines[@]}" -le 6 ]
}

@test "logo: assets/logo.txt beside tuin.sh beats the embedded tulip" {
    mkdir "$WORK/assets"
    printf 'FROM-ASSETS\n' > "$WORK/assets/logo.txt"
    run bash -c "source '$WORK/tuin.sh'; tuin_logo"
    assert_output 'FROM-ASSETS'
}

@test "logo: TUIN_LOGO beats assets/logo.txt" {
    mkdir "$WORK/assets"
    printf 'FROM-ASSETS\n' > "$WORK/assets/logo.txt"
    printf 'FROM-ENV\n' > "$BATS_TEST_TMPDIR/mine.txt"
    export TUIN_LOGO="$BATS_TEST_TMPDIR/mine.txt"
    run bash -c "source '$WORK/tuin.sh'; tuin_logo"
    assert_output 'FROM-ENV'
}

@test "logo: a missing TUIN_LOGO falls through to assets" {
    mkdir "$WORK/assets"
    printf 'FROM-ASSETS\n' > "$WORK/assets/logo.txt"
    export TUIN_LOGO="$BATS_TEST_TMPDIR/missing.txt"
    run bash -c "source '$WORK/tuin.sh'; tuin_logo"
    assert_output 'FROM-ASSETS'
}

@test "logo: an unreadable TUIN_LOGO falls through to assets" {
    [[ "$EUID" -ne 0 ]] || skip "root reads mode-000 files"
    mkdir "$WORK/assets"
    printf 'FROM-ASSETS\n' > "$WORK/assets/logo.txt"
    printf 'FROM-ENV\n' > "$BATS_TEST_TMPDIR/locked.txt"
    chmod 000 "$BATS_TEST_TMPDIR/locked.txt"
    export TUIN_LOGO="$BATS_TEST_TMPDIR/locked.txt"
    run bash -c "source '$WORK/tuin.sh'; tuin_logo"
    chmod 600 "$BATS_TEST_TMPDIR/locked.txt"
    assert_output 'FROM-ASSETS'
}

@test "logo: a caller's cd function does not corrupt the assets path" {
    mkdir "$WORK/assets"
    printf 'FROM-ASSETS\n' > "$WORK/assets/logo.txt"
    run bash -c "cd() { echo noise; builtin cd \"\$@\"; }; source '$WORK/tuin.sh'; tuin_logo"
    assert_output 'FROM-ASSETS'
}

@test "logo: assets are found after the caller changes directory" {
    mkdir "$WORK/assets"
    printf 'FROM-ASSETS\n' > "$WORK/assets/logo.txt"
    run bash -c "cd '$WORK' && source ./tuin.sh && cd / && tuin_logo"
    assert_output 'FROM-ASSETS'
}

@test "logo: assets are found when tuin.sh is sourced by bare name from its directory" {
    mkdir "$WORK/assets"
    printf 'FROM-ASSETS\n' > "$WORK/assets/logo.txt"
    run bash -c "cd '$WORK' && PATH=/nonexistent source tuin.sh && cd / && tuin_logo"
    assert_output 'FROM-ASSETS'
}

@test "logo: control bytes in an override are stripped" {
    printf 'A\033[2JB\007\n' > "$BATS_TEST_TMPDIR/evil.txt"
    export TUIN_LOGO="$BATS_TEST_TMPDIR/evil.txt"
    run bash -c "source '$WORK/tuin.sh'; tuin_logo"
    assert_output 'A[2JB'
}

@test "logo: the default tulip uses the accent color and an override does not" {
    run colored "$WORK/tuin.sh"
    [[ "$output" == *$'\033[36m'* ]] || false
    printf 'PLAIN\n' > "$BATS_TEST_TMPDIR/mine.txt"
    export TUIN_LOGO="$BATS_TEST_TMPDIR/mine.txt"
    run colored "$WORK/tuin.sh"
    assert_output 'PLAIN'
}

@test "logo: the repo's assets/logo.txt is non-empty, short and ASCII only" {
    [ -s "$TUIN_REPO_ROOT/assets/logo.txt" ]
    local n
    n=$(wc -l < "$TUIN_REPO_ROOT/assets/logo.txt" | tr -d ' ')
    [ "$n" -le 12 ]
    run env LC_ALL=C grep -n '[^[:print:]]' "$TUIN_REPO_ROOT/assets/logo.txt"
    assert_failure
}

@test "logo: tuin.sh run from the repo prints assets/logo.txt" {
    run bash -c "source '$TUIN_SH'; tuin_logo"
    assert_success
    assert_output "$(cat "$TUIN_REPO_ROOT/assets/logo.txt")"
}

@test "logo: centers on a terminal of known width" {
    printf 'ab\n' > "$BATS_TEST_TMPDIR/two.txt"
    tuin_pty '' -- "export TUIN_LOGO='$BATS_TEST_TMPDIR/two.txt'; _tuin_tty_cols() { echo 21; }; tuin_logo >/dev/tty"
    local pad
    printf -v pad '%9s' ''
    [[ "$pty_tty" == "${pad}ab"$'\r'* || "$pty_tty" == *$'\n'"${pad}ab"$'\r'* ]] || false
}

@test "logo: does not center when the width is unknown" {
    printf 'ab\n' > "$BATS_TEST_TMPDIR/two.txt"
    tuin_pty '' -- "export TUIN_LOGO='$BATS_TEST_TMPDIR/two.txt'; _tuin_tty_cols() { echo 0; }; tuin_logo >/dev/tty"
    [[ "$pty_tty" == "ab"$'\r'* || "$pty_tty" == *$'\n'"ab"$'\r'* ]] || false
    [[ "$pty_tty" != *" ab"* ]] || false
}

@test "logo: prints at most 24 lines" {
    local i
    for (( i = 1; i <= 100; i++ )); do echo "line $i"; done > "$BATS_TEST_TMPDIR/huge.txt"
    export TUIN_LOGO="$BATS_TEST_TMPDIR/huge.txt"
    run bash -c "source '$WORK/tuin.sh'; tuin_logo"
    assert_success
    [ "${#lines[@]}" -eq 24 ]
    assert_line --index 23 'line 24'
}

@test "logo: always returns 0" {
    export TUIN_LOGO="$BATS_TEST_TMPDIR/missing.txt"
    run bash -c "source '$WORK/tuin.sh'; tuin_logo; echo rc=\$?"
    assert_line 'rc=0'
}

@test "logo: sourcing twice under set -eu is quiet and does not abort" {
    run bash -c "set -eu; source '$WORK/tuin.sh'; source '$WORK/tuin.sh'; tuin_logo >/dev/null; echo ok"
    assert_success
    assert_output 'ok'
}

@test "logo: an empty override prints nothing and survives set -u" {
    : > "$BATS_TEST_TMPDIR/empty.txt"
    export TUIN_LOGO="$BATS_TEST_TMPDIR/empty.txt"
    run bash -c "set -eu; source '$WORK/tuin.sh'; tuin_logo; echo rc=\$?"
    assert_success
    assert_output 'rc=0'
}
