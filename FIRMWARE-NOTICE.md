# Firmware notice

The files below were extracted from the Lenovo Windows recovery image supplied
for the affected machine and are included for hardware interoperability and
archival testing:

- `firmware/sof-mtl.ri` (Intel DSP firmware)
- `firmware/TAS2XXX38D6.bin` (Texas Instruments amplifier tuning)

They remain vendor binaries. No copyright ownership or additional license is
claimed or granted by this repository. The MIT license applies only to the
original scripts, documentation and source code. If redistribution is not
permitted in your jurisdiction, extract the same files from your own licensed
recovery image and verify the SHA-256 values listed in `SHA256SUMS`.

The supplied topology is a machine-specific derivative of the topology shipped
by the SOF project. Its source transformation is documented in
`tools/rewrite-sof-topology.c`.
