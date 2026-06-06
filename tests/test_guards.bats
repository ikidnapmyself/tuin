#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
}

# ---- tuin_unpriv ------------------------------------------------------------

@test "tuin_unpriv returns 0 when unprivileged" {
    run bash -c "unset SUDO_USER SUDO_UID; source '$TUIN_SH'; _tuin_euid() { echo 1000; }; tuin_unpriv"
    assert_success
    assert_output ""
}

@test "tuin_unpriv returns non-zero when SUDO_USER is set" {
    run bash -c "source '$TUIN_SH'; unset SUDO_USER SUDO_UID; _tuin_euid() { echo 1000; }; SUDO_USER=alice tuin_unpriv"
    assert_failure
}

@test "tuin_unpriv returns non-zero when SUDO_UID is set" {
    run bash -c "source '$TUIN_SH'; unset SUDO_USER SUDO_UID; _tuin_euid() { echo 1000; }; SUDO_UID=1000 tuin_unpriv"
    assert_failure
}

@test "tuin_unpriv returns non-zero when euid is 0 (simulated root)" {
    run bash -c "unset SUDO_USER SUDO_UID; source '$TUIN_SH'; _tuin_euid() { echo 0; }; tuin_unpriv"
    assert_failure
}

@test "tuin_unpriv writes a notice to stderr when privileged" {
    run bash -c "unset SUDO_USER SUDO_UID; source '$TUIN_SH'; _tuin_euid() { echo 0; }; tuin_unpriv 2>&1 1>/dev/null"
    assert_output --partial "tuin:"
}

# ---- tuin_guard -------------------------------------------------------------

@test "tuin_guard returns 0 for a safe command" {
    run bash -c "source '$TUIN_SH'; tuin_guard ls -la"
    assert_success
    assert_output ""
}

@test "tuin_guard returns 0 for echo" {
    run bash -c "source '$TUIN_SH'; tuin_guard echo hello"
    assert_success
}

@test "tuin_guard rejects sudo" {
    run bash -c "source '$TUIN_SH'; tuin_guard sudo apt update"
    assert_failure
}

@test "tuin_guard rejects doas" {
    run bash -c "source '$TUIN_SH'; tuin_guard doas reboot"
    assert_failure
}

@test "tuin_guard rejects su" {
    run bash -c "source '$TUIN_SH'; tuin_guard su -"
    assert_failure
}

@test "tuin_guard rejects pkexec" {
    run bash -c "source '$TUIN_SH'; tuin_guard pkexec id"
    assert_failure
}

@test "tuin_guard rejects run0" {
    run bash -c "source '$TUIN_SH'; tuin_guard run0 id"
    assert_failure
}

@test "tuin_guard rejects sudoedit" {
    run bash -c "source '$TUIN_SH'; tuin_guard sudoedit /etc/hosts"
    assert_failure
}

@test "tuin_guard rejects an absolute path to sudo (basename match)" {
    run bash -c "source '$TUIN_SH'; tuin_guard /usr/bin/sudo id"
    assert_failure
}

@test "tuin_guard allows 'sudo' as a non-leading argument" {
    run bash -c "source '$TUIN_SH'; tuin_guard echo sudo"
    assert_success
}

@test "tuin_guard writes a notice to stderr when rejecting" {
    run bash -c "source '$TUIN_SH'; tuin_guard sudo id 2>&1 1>/dev/null"
    assert_output --partial "tuin:"
}

@test "tuin_guard rejects an empty invocation (no command)" {
    run bash -c "source '$TUIN_SH'; tuin_guard"
    assert_failure
}

@test "tuin_guard writes a notice to stderr on an empty invocation" {
    run bash -c "source '$TUIN_SH'; tuin_guard 2>&1 1>/dev/null"
    assert_output --partial "tuin:"
}
