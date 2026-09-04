#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
}

# ---- _tuin_is_tty -----------------------------------------------------------

@test "_tuin_is_tty returns false when stdin/stdout piped" {
    run bash -c "source '$TUIN_SH' && _tuin_is_tty"
    assert_failure
}

@test "_tuin_is_tty returns false when TERM=dumb" {
    run bash -c "TERM=dumb; source '$TUIN_SH' && _tuin_is_tty"
    assert_failure
}

# ---- _tuin_is_utf8 ----------------------------------------------------------

@test "_tuin_is_utf8 detects UTF-8 from LC_ALL" {
    run bash -c "LC_ALL=en_US.UTF-8 LC_CTYPE= LANG= ; source '$TUIN_SH' && _tuin_is_utf8"
    assert_success
}

@test "_tuin_is_utf8 detects UTF-8 from LANG" {
    run bash -c "LC_ALL= LC_CTYPE= LANG=en_US.UTF-8 ; source '$TUIN_SH' && _tuin_is_utf8"
    assert_success
}

@test "_tuin_is_utf8 returns false for LC_ALL=C" {
    run bash -c "LC_ALL=C LC_CTYPE= LANG= ; source '$TUIN_SH' && _tuin_is_utf8"
    assert_failure
}

# ---- _tuin_use_color --------------------------------------------------------

@test "_tuin_use_color returns false when NO_COLOR is set" {
    run bash -c "NO_COLOR=1 ; source '$TUIN_SH' && _tuin_use_color"
    assert_failure
}

@test "_tuin_use_color returns false when not a TTY" {
    run bash -c "source '$TUIN_SH' && _tuin_use_color"
    assert_failure
}

# ---- tuin_version -----------------------------------------------------------

@test "tuin_version prints a semver string" {
    run bash -c "source '$TUIN_SH' && tuin_version"
    assert_success
    [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || fail "tuin_version printed a non-semver string: $output"
}

@test "tuin_version agrees with both version locations in tuin.sh" {
    local reported header assigned
    reported=$(bash -c "source '$TUIN_SH' && tuin_version")
    header=$(sed -n 's/^# Version: //p' "$TUIN_SH")
    assigned=$(sed -n 's/^_TUIN_VERSION="\(.*\)"$/\1/p' "$TUIN_SH")
    [ "$reported" = "$header" ] \
        || fail "tuin_version ($reported) != '# Version:' header ($header)"
    [ "$reported" = "$assigned" ] \
        || fail "tuin_version ($reported) != _TUIN_VERSION ($assigned)"
}
