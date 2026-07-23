#!/usr/bin/env bash
set -euo pipefail

failed=0

check_hash() {
    local expected="$1" file="$2" actual
    if [[ ! -f "$file" ]]; then
        printf 'MISSING  %s\n' "$file"
        failed=1
        return
    fi
    actual="$(sha256sum "$file" | awk '{print $1}')"
    if [[ "$actual" == "$expected" ]]; then
        printf 'OK       %s\n' "$file"
    else
        printf 'BAD HASH %s\n' "$file"
        failed=1
    fi
}

check_hash ab570de158e5002ce998fb7e85396ea592b85bd526c733245b51ed99a1f06a0f \
    /usr/lib/firmware/intel/sof-ipc4/mtl/es-windows/sof-mtl.ri
check_hash 014c2689267436b7b2f03fe472c38beee02c730c9a2c818c657e8ac05adc7366 \
    /usr/lib/firmware/TAS2XXX38D6.bin
check_hash 56a65e7da8610b333c3df1786f7aafb75dbb8925c2e94b2e567c7bfb9291c304 \
    /usr/lib/firmware/intel/sof-ipc4-tplg/es-custom/sof-hda-generic-4ch-es-minimal.tplg
check_hash b07d4c90ad15d8fde2e855ae89f814327f55f9c8c04995e5ae4eafc0380d47bc \
    /etc/udev/rules.d/90-yoga-pro-9-audio-keepalive.rules
check_hash acf37debe0245ef9480ea62ba6b4cce3ffc602c3cf12ded0f040192ab75cb656 \
    /etc/wireplumber/wireplumber.conf.d/51-yoga-pro-9-speaker-keepalive.conf

tas_power=/sys/bus/i2c/devices/i2c-TIAS2781:00/power/control
hda_power=/sys/bus/pci/devices/0000:00:1f.3/power/control
for label_and_path in "TAS2781:$tas_power" "HDA/SOF:$hda_power"; do
    label="${label_and_path%%:*}"
    path="${label_and_path#*:}"
    if [[ -r "$path" && "$(<"$path")" == on ]]; then
        printf 'OK       %s runtime PM pinned on\n' "$label"
    else
        printf 'MISSING  %s runtime PM pinned on\n' "$label"
        failed=1
    fi
done

speaker_node="$(wpctl status --name 2>/dev/null | sed -n \
    's/.*[[:space:]]\([0-9][0-9]*\)\. alsa_output\..*HiFi__Speaker__sink.*/\1/p' | head -n1)"
if [[ -n "$speaker_node" ]] && pw-cli info "$speaker_node" 2>/dev/null | \
        grep -q 'session.suspend-timeout-seconds = "0"'; then
    printf '%s\n' 'OK       WirePlumber speaker suspend timeout disabled'
else
    printf '%s\n' 'MISSING  WirePlumber speaker suspend timeout disabled'
    failed=1
fi

if amixer -c 0 cget "iface=CARD,name='Speaker Force Firmware Load'" 2>/dev/null | \
        grep -q 'values=off'; then
    printf '%s\n' 'OK       TAS2781 Force Firmware Load off'
else
    printf '%s\n' 'BAD      TAS2781 Force Firmware Load is not off'
    failed=1
fi

for arg in \
    snd_sof_pci.fw_path=intel/sof-ipc4/mtl/es-windows \
    snd_sof_pci.tplg_path=intel/sof-ipc4-tplg/es-custom \
    snd_sof_pci.tplg_filename=sof-hda-generic-4ch-es-minimal.tplg; do
    if grep -qw "$arg" /proc/cmdline; then
        printf 'OK       kernel parameter %s\n' "$arg"
    else
        printf 'MISSING  kernel parameter %s\n' "$arg"
        failed=1
    fi
done

if grep -q 'sof-hda-dsp' /proc/asound/cards; then
    printf '%s\n' 'OK       ALSA card sof-hda-dsp'
else
    printf '%s\n' 'MISSING  ALSA card sof-hda-dsp'
    failed=1
fi

printf '\nPlayback devices:\n'
aplay -l
printf '\nCapture devices:\n'
arecord -l
printf '\nPipeWire audio nodes:\n'
wpctl status | sed -n '/Audio/,/Video/p'

exit "$failed"
