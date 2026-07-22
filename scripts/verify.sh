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
