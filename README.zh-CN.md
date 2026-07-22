# 联想 Yoga Pro 9 16IMH9 ES Linux 音频修复

本仓库记录了一台工程样机在 Arch Linux 下恢复四扬声器原厂音质和内置四通道数字麦克风的最终方案。机器的 DMI `product_name` 是 ES 占位值 `0000`，`product_family` 和 `product_version` 为 `YOGA Pro 16s IMH9`，对应 Yoga Pro 9 / Yoga Pro 16s IMH9。

## 已验证硬件

- Intel Meteor Lake-P HD Audio：`8086:7e28`，子系统 `17aa:3811`
- Realtek ALC287：子系统 `17aa:38d6`
- TI TAS2781 智能功放：ACPI `TIAS2781`，子系统 `17aa:38d6`
- 验证内核：`7.1.4-arch1-1`

这些固件带有明确的机型和子系统绑定。其他子系统 ID 不要直接安装。

## 根因

1. Arch 提供的 Intel 签名版和 community SOF 固件都会在 DSP ROM 的 `VALIDATE_PUB_KEY` 阶段失败，IPC4 状态为 `0x97`。这台 ES 样机只能启动原厂 Windows 镜像中的 Intel DSP 固件。
2. Arch 的通用四通道拓扑引用了原厂固件没有内置的 EQIIR、EQFIR、DRC 和 TDFB 模块，导致声卡创建失败。
3. 保留下来的 SOF DMIC Gain 控制仍与原厂固件不兼容。最终拓扑删除该控制，直接提供 48 kHz、32 位、四通道原始 DMIC。
4. 扬声器能响但声音单薄、失真时，实际是 TAS2781 没有应用 `38D6` 原厂调音。安装匹配固件并触发一次强制加载即可恢复。

## Arch Linux 安装

先安装标准音频栈：

```sh
sudo pacman -S sof-firmware alsa-utils pipewire pipewire-audio \
  pipewire-pulse wireplumber
```

克隆并检查仓库后执行：

```sh
./scripts/install.sh
```

把以下参数加入实际使用的内核命令行：

```text
snd_sof_pci.fw_path=intel/sof-ipc4/mtl/es-windows
snd_sof_pci.tplg_path=intel/sof-ipc4-tplg/es-custom
snd_sof_pci.tplg_filename=sof-hda-generic-4ch-es-minimal.tplg
```

如果之前有 `snd_intel_dspcfg.dsp_driver=1`，需要移除。然后按自己的启动方式重建 initramfs/UKI 和引导配置。标准 Arch `mkinitcpio` preset 使用 UKI 时可执行：

```sh
sudo mkinitcpio -P
```

第一次测试前务必保留一个带 `snd_intel_dspcfg.dsp_driver=1` 的 HDA 备用启动项。重启进入 SOF 后执行：

```sh
./scripts/verify.sh
```

如果扬声器有声音但音质单薄或失真：

```sh
./scripts/reload-tas2781.sh
```

## 正常结果

- ALSA 声卡名称为 `sof-hda-dsp`
- 四路内置扬声器应用 TAS2781 原厂调音
- ALSA 内置麦克风为 48 kHz、`S32_LE`、四通道
- PipeWire/WirePlumber 中出现 `Digital Microphone`

## 文件说明

- `firmware/sof-mtl.ri`：原厂 Intel DSP 固件，版本 `20.40.1393.0`
- `firmware/TAS2XXX38D6.bin`：`17aa:38d6` 对应的 TAS2781 调音固件
- `topology/sof-hda-generic-4ch-es-minimal.tplg`：实机验证通过的精简 IPC4 拓扑
- `tools/rewrite-sof-topology.c`：诊断时使用的拓扑重写工具，用于说明具体删改；SOF 拓扑会随版本变化，因此安装时固定使用实测二进制，不现场重新生成

厂商二进制不适用本仓库的 MIT 许可证，详见 [FIRMWARE-NOTICE.md](FIRMWARE-NOTICE.md)。

## 回退

使用以下参数启动即可回到传统 HDA：

```text
snd_intel_dspcfg.dsp_driver=1
```

HDA 通常可以恢复扬声器和耳机，但无法提供依赖 Intel DSP 的内置数字麦克风。`scripts/uninstall.sh` 只删除哈希与本仓库完全一致的文件；内核参数需按所用引导器单独移除。
