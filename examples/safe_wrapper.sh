#!/usr/bin/env bash
#
# safe_wrapper.sh — a tiny manage.py-style command wrapper showing the
# safety guards: refuse to run elevated, and screen each action for privilege
# escalation before running it.
#
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # path resolves at runtime via SCRIPT_DIR
source "$SCRIPT_DIR/../tuin.sh"

# 1. Refuse to run the whole tool elevated.
tuin_unpriv || exit 1

tuin_banner "safe wrapper demo"
tuin_section "Pick an action"

action=$(tuin_choose "List files (ls -la)" "Show date (date)" "Escalate (sudo id)")

case "$action" in
    "List files"*) cmd=(ls -la) ;;
    "Show date"*)  cmd=(date) ;;
    *)             cmd=(sudo id) ;;
esac

# 2. Screen the chosen command before running it.
if tuin_guard "${cmd[@]}"; then
    tuin_spin "Running ${cmd[*]}" -- "${cmd[@]}"
else
    echo "Declined: that action would escalate privileges." >&2
    exit 1
fi
