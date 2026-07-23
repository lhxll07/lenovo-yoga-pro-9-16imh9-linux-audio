#!/usr/bin/env bash
set -euo pipefail

card="${1:-0}"
target="alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Speaker__sink"
control="iface=CARD,name='Speaker Force Firmware Load'"
sound=/usr/share/sounds/freedesktop/stereo/audio-test-signal.oga

if ! amixer -c "$card" controls | grep -q "Speaker Force Firmware Load"; then
    printf 'TAS2781 firmware-load control was not found on card %s.\n' "$card" >&2
    exit 1
fi

if [[ ! -r "$sound" ]]; then
    printf 'Test sound is missing: %s\n' "$sound" >&2
    exit 1
fi

force_off() {
    amixer -c "$card" cset "$control" off >/dev/null 2>&1 || true
}
trap force_off EXIT INT TERM

# Recreate the ALSA node so the next stream executes the TAS2781 playback-open
# hook. The keepalive rule then prevents another close/open cycle.
systemctl --user restart wireplumber.service pipewire.service pipewire-pulse.service
for _ in {1..50}; do
    wpctl status --name 2>/dev/null | grep -qF "$target" && break
    sleep 0.1
done
if ! wpctl status --name 2>/dev/null | grep -qF "$target"; then
    printf 'Internal speaker PipeWire node did not appear.\n' >&2
    exit 1
fi

amixer -c "$card" cset "$control" on >/dev/null
pw-play --target "$target" --volume 0.22 "$sound"
force_off
trap - EXIT INT TERM

amixer -c "$card" cget iface=CARD,name='Speaker Program Id'
amixer -c "$card" cget iface=CARD,name='Speaker Config Id'

printf '%s\n' 'TAS2781 tuning reloaded once; Force Firmware Load is off.'
