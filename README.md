# Lenovo Yoga Pro 9 16IMH9 ES Linux audio fix

This repository contains the audio files and the Arch Linux procedure that
restored both the internal speakers and the four-channel digital microphone on
an engineering-sample Lenovo Yoga Pro 9 / Yoga Pro 16s IMH9.

中文说明见 [README.zh-CN.md](README.zh-CN.md).

## Scope

The tested machine reports:

- DMI product name: `0000` (ES placeholder)
- DMI product family/version: `YOGA Pro 16s IMH9`
- Intel Meteor Lake-P HD Audio: `8086:7e28`, subsystem `17aa:3811`
- Realtek ALC287: subsystem `17aa:38d6`
- TI TAS2781 smart amplifiers: ACPI `TIAS2781`, subsystem `17aa:38d6`
- Arch Linux kernel: `7.1.4-arch1-1`

Do not install these machine-specific files on a different codec subsystem.

## What was wrong

1. Both the Intel-signed and community SOF firmware shipped by Arch failed at
   `VALIDATE_PUB_KEY` with IPC4 status `0x97`. The ES DSP accepts the OEM Windows
   firmware instead.
2. The generic four-channel SOF topology references EQIIR, EQFIR, DRC and TDFB
   modules that are absent from that OEM firmware.
3. The remaining SOF DMIC gain control is incompatible with the OEM firmware.
   The supplied topology removes it and exposes raw 48 kHz, 32-bit, four-channel
   DMIC capture.
4. The TAS2781 driver needs the matching `38D6` tuning file. If the speakers
   sound thin or distorted after an audio-controller rebind, forcing one
   firmware reload restores the tuning.

## Install on Arch Linux

Install the normal Linux audio stack first:

```sh
sudo pacman -S sof-firmware alsa-utils pipewire pipewire-audio \
  pipewire-pulse wireplumber
```

Clone this repository, inspect the files, then install the firmware and
topology:

```sh
./scripts/install.sh
```

Add these kernel parameters to your boot entry:

```text
snd_sof_pci.fw_path=intel/sof-ipc4/mtl/es-windows
snd_sof_pci.tplg_path=intel/sof-ipc4-tplg/es-custom
snd_sof_pci.tplg_filename=sof-hda-generic-4ch-es-minimal.tplg
```

Remove `snd_intel_dspcfg.dsp_driver=1` if it was previously used to force the
legacy HDA driver. Rebuild the initramfs/UKI and bootloader configuration using
the method appropriate for your installation. For the standard Arch
`mkinitcpio` preset with a UKI:

```sh
sudo mkinitcpio -P
```

Keep a known-good HDA fallback boot entry while testing. Reboot, then run:

```sh
./scripts/verify.sh
```

If the speakers work but sound thin or distorted:

```sh
./scripts/reload-tas2781.sh
```

The stock driver also runs `PRE_SHUTDOWN` when the speaker PCM closes, but can
skip restoring the full configuration on the next open because its cache is
stale. The installer therefore keeps only the internal audio path alive: the
HDA/SOF and TAS2781 power domains stay active, and WirePlumber does not close
the Speaker PCM after five seconds. This avoids both repeated firmware reloads
and stalls on first playback or timeline seeks.

This is a stability-first tradeoff and raises idle power. With the current
stock driver, zero additional idle power, zero wake latency and persistent
tuning cannot all be achieved at once.

## Expected result

- ALSA card: `sof-hda-dsp`
- Internal speakers: all four TAS2781-backed channels with OEM tuning
- Internal microphone: 48 kHz, `S32_LE`, four channels
- PipeWire/WirePlumber source: `Digital Microphone`
- Speaker node after first playback: `idle` or `running`, not `suspended`

## Files

- `firmware/sof-mtl.ri`: OEM Intel DSP firmware, version `20.40.1393.0`
- `firmware/TAS2XXX38D6.bin`: OEM TAS2781 tuning for subsystem `17aa:38d6`
- `topology/sof-hda-generic-4ch-es-minimal.tplg`: tested reduced IPC4 topology
- `config/audio-keepalive.rules`: keeps the HDA/SOF and TAS2781 power domains active
- `config/51-yoga-pro-9-speaker-keepalive.conf`: disables WirePlumber's suspend timeout only for the internal Speaker node
- `tools/rewrite-sof-topology.c`: documents the topology rewrite used during
  diagnosis; topology input formats are version-sensitive, so the installer
  uses the tested binary instead of regenerating it

See [FIRMWARE-NOTICE.md](FIRMWARE-NOTICE.md) before redistributing vendor
binaries.

## Rollback

Boot the fallback entry with this parameter to return to legacy HDA output:

```text
snd_intel_dspcfg.dsp_driver=1
```

That restores speaker/headphone output but normally cannot expose the internal
DMIC. `scripts/uninstall.sh` only removes files whose hashes match this
repository and the audio keepalive rules; kernel parameters must be removed
separately.

## License

The original scripts and C utility in this repository are MIT licensed. Vendor
firmware binaries are not covered by the MIT license; see
[FIRMWARE-NOTICE.md](FIRMWARE-NOTICE.md).
