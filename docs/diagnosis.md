# Diagnosis notes

## Platform

The affected engineering sample identifies its audio components as follows:

```text
Intel Meteor Lake-P HD Audio Controller  8086:7e28 / 17aa:3811
Realtek ALC287 codec                     10ec:0287 / 17aa:38d6
TI smart amplifiers                     ACPI TIAS2781 / 17aa:38d6
```

The Windows recovery image maps `38D6` to `Yoga Pro 9 IMH-16 DIS` and installs
the Intel SST/OED/DMIC stack plus `TAS2XXX38D6.bin`.

## DSP firmware

The stock Intel-signed and community `sof-mtl.ri` files from Arch both reached
the Meteor Lake DSP ROM but failed at `VALIDATE_PUB_KEY`:

```text
IPC4 status: 0x97
SOF probe:   -110
```

This is consistent with an ES DSP whose accepted signing key differs from the
production key. The recovery image's `dsp_fw_release.bin` is also an IPC4
`$AE1/ADSP.man` container. Installed as a separate `sof-mtl.ri`, it passed ROM
validation and reported firmware version `20.40.1393.0`.

## Topology

The generic `sof-hda-generic-4ch.tplg` could not instantiate because the OEM
firmware lacks modules referenced by the production SOF topology. The tested
rewrite removes these widgets:

```text
eqiir.2.1  eqfir.2.1  drc.2.1  eqiir.4.1
tdfb.11.1  drc.11.1   eqiir.12.1  gain.12.1
```

It also removes their twelve routes and adds four direct replacement routes:

```text
gain.2.1                    -> dai-copier.HDA.Analog.playback
dai-copier.HDA.Analog.capture -> module-copier.4.2
dai-copier.DMIC.dmic01.capture -> module-copier.12.2
module-copier.12.2          -> host-copier.6.capture
```

The final DMIC path deliberately has no SOF gain component. ALSA direct capture
and PipeWire capture were both verified at 48 kHz, `S32_LE`, four channels.

`tools/rewrite-sof-topology.c` records this transformation. SOF topology binary
layout and contents change between package releases; the tested output is
therefore committed directly and identified by SHA-256 rather than regenerated
during installation.

## Smart-amplifier tuning

The upstream firmware package contains another `TAS2XXX38D6.bin`, but it does
not match this machine's recovery image. The known-working OEM file has SHA-256:

```text
014c2689267436b7b2f03fe472c38beee02c730c9a2c818c657e8ac05adc7366
```

With the OEM file, Linux exposes one program, two configurations and two
profiles. The normal tested selection is Program 0, Config 0, Profile 0. Do not
blindly select Profile 1; firmware strings indicate that the second profile is
associated with calibration.

After a live audio-controller rebind, the TAS2781 controls can exist while the
four amplifiers have not yet received the tuning data. The audible symptom is
thin, distorted output rather than merely low volume. The following control
arms a forced load on the next playback power-up:

```sh
amixer -c 0 cset name='Speaker Force Firmware Load' on
```

The fix was confirmed again after a normal reboot.

## Tested hashes

```text
ab570de158e5002ce998fb7e85396ea592b85bd526c733245b51ed99a1f06a0f  sof-mtl.ri
014c2689267436b7b2f03fe472c38beee02c730c9a2c818c657e8ac05adc7366  TAS2XXX38D6.bin
56a65e7da8610b333c3df1786f7aafb75dbb8925c2e94b2e567c7bfb9291c304  sof-hda-generic-4ch-es-minimal.tplg
```
