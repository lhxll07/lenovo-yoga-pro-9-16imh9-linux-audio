#!/usr/bin/env bash
set -euo pipefail

remove_matching() {
    local expected="$1" file="$2" actual
    [[ -e "$file" ]] || return 0
    actual="$(sha256sum "$file" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        printf 'Refusing to remove modified file: %s\n' "$file" >&2
        exit 1
    fi
    rm -- "$file"
    printf 'Removed %s\n' "$file"
}

if [[ "$EUID" -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

remove_matching ab570de158e5002ce998fb7e85396ea592b85bd526c733245b51ed99a1f06a0f \
    /usr/lib/firmware/intel/sof-ipc4/mtl/es-windows/sof-mtl.ri
remove_matching 014c2689267436b7b2f03fe472c38beee02c730c9a2c818c657e8ac05adc7366 \
    /usr/lib/firmware/TAS2XXX38D6.bin
remove_matching 56a65e7da8610b333c3df1786f7aafb75dbb8925c2e94b2e567c7bfb9291c304 \
    /usr/lib/firmware/intel/sof-ipc4-tplg/es-custom/sof-hda-generic-4ch-es-minimal.tplg
remove_matching 1e46bb3a01c6ef39b290cb5f073237203c624f5a5373aeca6b1b2434ab7a25d2 \
    /etc/modprobe.d/yoga-pro-9-16imh9-audio.conf
remove_matching b07d4c90ad15d8fde2e855ae89f814327f55f9c8c04995e5ae4eafc0380d47bc \
    /etc/udev/rules.d/90-yoga-pro-9-audio-keepalive.rules
remove_matching acf37debe0245ef9480ea62ba6b4cce3ffc602c3cf12ded0f040192ab75cb656 \
    /etc/wireplumber/wireplumber.conf.d/51-yoga-pro-9-speaker-keepalive.conf
udevadm control --reload

for power in \
    /sys/bus/i2c/devices/i2c-TIAS2781:00/power/control \
    /sys/bus/pci/devices/0000:00:1f.3/power/control; do
    [[ -w "$power" ]] && printf auto >"$power"
done

printf '%s\n' \
    'Repository files and audio keepalive rules removed.' \
    'Remove the three snd_sof_pci kernel parameters before rebuilding your boot entry.'
