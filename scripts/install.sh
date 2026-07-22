#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
force=0
[[ "${1:-}" == "--force" ]] && force=1

check_hash() {
    local expected="$1" file="$2" actual
    actual="$(sha256sum "$file" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        printf 'Hash mismatch: %s\nexpected %s\nactual   %s\n' \
            "$file" "$expected" "$actual" >&2
        exit 1
    fi
}

machine="$(for field in product_name product_version product_family product_sku; do
    tr -d '\0' <"/sys/class/dmi/id/$field" 2>/dev/null || true
    printf ' '
done)"
if [[ "$machine" != *"YOGA Pro 16s IMH9"* && \
      "$machine" != *YOGAPro16sIMH9* && "$force" -ne 1 ]]; then
    printf 'Unsupported DMI identity: %s\n' "${machine:-unknown}" >&2
    printf 'Use --force only after confirming codec subsystem 17aa:38d6.\n' >&2
    exit 1
fi

check_hash ab570de158e5002ce998fb7e85396ea592b85bd526c733245b51ed99a1f06a0f \
    "$repo_dir/firmware/sof-mtl.ri"
check_hash 014c2689267436b7b2f03fe472c38beee02c730c9a2c818c657e8ac05adc7366 \
    "$repo_dir/firmware/TAS2XXX38D6.bin"
check_hash 56a65e7da8610b333c3df1786f7aafb75dbb8925c2e94b2e567c7bfb9291c304 \
    "$repo_dir/topology/sof-hda-generic-4ch-es-minimal.tplg"

if [[ "$EUID" -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

install -Dm0644 "$repo_dir/firmware/sof-mtl.ri" \
    /usr/lib/firmware/intel/sof-ipc4/mtl/es-windows/sof-mtl.ri
install -Dm0644 "$repo_dir/firmware/TAS2XXX38D6.bin" \
    /usr/lib/firmware/TAS2XXX38D6.bin
install -Dm0644 "$repo_dir/topology/sof-hda-generic-4ch-es-minimal.tplg" \
    /usr/lib/firmware/intel/sof-ipc4-tplg/es-custom/sof-hda-generic-4ch-es-minimal.tplg
install -Dm0644 "$repo_dir/config/audio-runtime-pm.conf" \
    /etc/modprobe.d/yoga-pro-9-16imh9-audio.conf

printf '%s\n' \
    'Files installed and verified.' \
    'Add the three snd_sof_pci parameters documented in README.md,' \
    'rebuild the initramfs/UKI and reboot.'
