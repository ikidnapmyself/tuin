#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # path resolves at runtime via SCRIPT_DIR
source "$SCRIPT_DIR/../tuin.sh"

fruit_menu() {
    while tuin_menu "Fruit > pick one" "Apple" "Banana" "Cherry"; do
        tuin_section "You chose: $TUIN_REPLY"
    done
}

veg_menu() {
    while tuin_menu "Veg > pick one" "Carrot" "Pea" "Spinach"; do
        tuin_section "You chose: $TUIN_REPLY"
    done
}

tuin_banner "cascading menu demo"
while tuin_menu "Main" "Fruit" "Vegetables"; do
    case $TUIN_REPLY in
        "Fruit")      fruit_menu ;;
        "Vegetables") veg_menu ;;
    esac
done
echo "Bye."