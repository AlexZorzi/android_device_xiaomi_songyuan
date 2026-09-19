# KernelSU-Next + SUSFS kernel for songyuan (unfinished)

Builds clean, produces the exact vermagic the device needs, passes the module
CRC check — but **hangs at the POCO logo**. Preserved so the work isn't lost.

## Exact recipe

    repo init -u https://android.googlesource.com/kernel/manifest -b common-android16-6.12
    repo sync -c --depth=1
    cd common && git checkout android16-6.12.69_r00

Pinned pair (from WildKernels/GKI_KernelSU_SUSFS release r20 — latest-of-each
does NOT work, the halves must match):

  KernelSU-Next  pershoot/KernelSU-Next @ 19d9e1f255d4afedb85eb7032f4725cda6d25d36
  SUSFS          gitlab.com/simonpunk/susfs4ksu, branch gki-android16-6.12,
                 commit 7d91da2d2ce056d1abf378d9199aaf1072d37ab0

pershoot's fork already ships SUSFS, so do NOT apply
kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch.

## Steps

1. Copy susfs4ksu kernel_patches/fs/susfs.c -> common/fs/
   and kernel_patches/include/linux/susfs*.h -> common/include/linux/
2. Apply 0001-susfs-kernel-side.patch (this is 50_add_susfs_in_gki-android16-6.12
   already applied, including the security/selinux/hooks.c hunk that has to be
   hand-placed after `struct selinux_state selinux_state;` — susfs4ksu tracks the
   6.12.92 branch tip and that context drifted).
3. Copy pershoot's kernel/ -> common/drivers/kernelsu AND its uapi/ ->
   common/drivers/kernelsu/uapi  (Kbuild does -I$(srctree)/$(src), so uapi must
   sit inside the driver dir; the upstream symlink layout leaves it unreachable).
   Add `obj-$(CONFIG_KSU) += kernelsu/` to drivers/Makefile and
   `source "drivers/kernelsu/Kconfig"` to drivers/Kconfig.
   Use a REAL directory, not a symlink -- bazel globs only under common/.
4. Apply 0002-selinux_hide-external-linkage.patch: three forward declarations are
   `static` while their definitions are not, so hooks.c/selinuxfs.c cannot link.
5. Do NOT touch CONFIG_LOCALVERSION. gki_defconfig already has "-4k" and kleaf
   composes "-android16-6-maybe-dirty", giving exactly
   6.12.69-android16-6-maybe-dirty-4k. All KSU/SUSFS configs are `default y`;
   adding them to gki_defconfig breaks the savedefconfig check.
6. tools/bazel run //common:kernel_aarch64_dist -- --destdir=out/dist

## Status

Module CRC check passed: 2627 kernel-exported symbols, 0 mismatches against all
398 songyuan vendor modules. Still hangs at the logo, cause unknown -- candidates
are module signature enforcement, or a SUSFS runtime hook stalling early
userspace. Recovery is `fastboot flash boot` with the stock boot.img.
