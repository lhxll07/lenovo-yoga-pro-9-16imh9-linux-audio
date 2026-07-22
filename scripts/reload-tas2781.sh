#!/usr/bin/env bash
set -euo pipefail

card="${1:-0}"

if ! amixer -c "$card" controls | grep -q "Speaker Force Firmware Load"; then
    printf 'TAS2781 firmware-load control was not found on card %s.\n' "$card" >&2
    exit 1
fi

amixer -c "$card" cset name='Speaker Force Firmware Load' on
sleep 2
amixer -c "$card" cget iface=CARD,name='Speaker Program Id'
amixer -c "$card" cget iface=CARD,name='Speaker Config Id'

printf '%s\n' 'TAS2781 firmware reload is armed. Start playback and check sound quality.'
