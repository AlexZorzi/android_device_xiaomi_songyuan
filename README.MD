#  Device Tree for Redmi K100 Pro Max / Poco F9 Ultra (songyuan)

## Spec Sheet

| Feature                 | Specification                                                              |
| :---------------------- | :--------------------------------                                          |
| CPU                     | 2x4.6 GHz Oryon V3 Phoenix L + 6x3.62 GHz Oryon V3 Phoenix M               |
| Chipset                 | Qualcomm SM8850-AC Snapdragon 8 Elite Gen 5 (3 nm)                         |
| GPU                     | Adreno 840                                                                 |
| Memory                  | 12 GB / 16 GB                                                              |
| Shipped Software        | Android 16, HyperOS 3                                                      |
| Storage                 | 256 GB / 512 GB / 1 TB, UFS 4.1                                            |
| Battery                 | Si/C Li-Ion 8050 mAh                                                       |
| Dimensions              | 163.5 x 77.9 x 8.7 mm                                                      |
| Display                 | 6.9 inches, 1200 x 2608, AMOLED, 116.6 cm2 (~91.6% screen-to-body ratio)   |
| Rear Camera             | 200 MP, f/1.7, 24mm (wide), 0.5µm, PDAF, OIS                               |
|                         | 50 MP, f/3.0, 120mm (periscope telephoto), 1/2.75", 0.64µm, PDAF, OIS, 5x optical zoom |
|                         | 50 MP, f/2.4, 17mm, 102˚ (ultrawide), 1/2.88", 0.61µm                      |
| Front Camera            | 32 MP, f/2.2, 21mm (wide), 1/3.44", 0.64µm                                 |
| Release Date            | September 2026                                                             |

## Building

`lineage.dependencies` can't express this tree: roomservice hardcodes the
`LineageOS/` org for every project and only honours a custom `remote` when it
starts with `aosp-`. The forks below are therefore shipped as a local manifest
instead.

```bash
repo init -u https://github.com/LineageOS/android.git -b lineage-24.0 --git-lfs
mkdir -p .repo/local_manifests
curl -o .repo/local_manifests/songyuan.xml \
  https://raw.githubusercontent.com/AlexZorzi/android_device_xiaomi_songyuan/songyuan/songyuan.xml
repo sync -c --no-clone-bundle --optimized-fetch --prune -j$(nproc)
```

`hardware/xiaomi` must stay on the fork's `songyuan-support` branch: it carries
the Euicc device mapping and the EsimSwitcher `setSimSlotMapping` change, and
syncing it to upstream `lineage-24.0` silently breaks eSIM.

No kernel source is published for songyuan, so the prebuilt kernel headers have
to be exported in the shell as well as in `BoardConfig.mk`:

```bash
export TARGET_PREBUILT_KERNEL_HEADERS=device/xiaomi/songyuan-kernel/kernel-headers.tar.gz
```

Then extract the blobs from a stock dump and build:

```bash
device/xiaomi/songyuan/extract-files.py <path to stock dump>
source build/envsetup.sh
lunch lineage_songyuan-cp2a-userdebug
mka bacon
```
