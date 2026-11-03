#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # path resolves at runtime via SCRIPT_DIR
source "$SCRIPT_DIR/../tuin.sh"

items=(
    "HIGH  item-01  queue backlog above threshold"
    "MED   item-02  certificate expires in 6 days"
    "LOW   item-03  disk at 71 percent"
)

open_item() {
    local item=$1
    while tuin_menu "$item" "Show details" "Acknowledge" "Escalate"; do
        case $TUIN_REPLY in
            "Show details")
                tuin_section "Details"
                printf '%s\n' "$item"
                tuin_confirm "Back to actions?" y || return 0
                ;;
            "Acknowledge"|"Escalate")
                tuin_spin "$TUIN_REPLY" -- sleep 1
                return 0
                ;;
        esac
    done
    return 0
}

tuin_fullscreen on
while :; do
    tuin_fullscreen clear
    tuin_logo
    tuin_section "Open items"
    item=$(tuin_choose "${items[@]}") || break
    open_item "$item"
    [[ -t 0 ]] || break
done
tuin_fullscreen off
