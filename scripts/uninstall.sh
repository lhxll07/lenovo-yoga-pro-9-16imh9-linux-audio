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

printf '%s\n' \
    'Repository files removed.' \
    'Remove the three snd_sof_pci kernel parameters before rebuilding your boot entry.'
