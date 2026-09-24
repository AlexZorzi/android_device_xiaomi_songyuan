#
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/xiaomi/songyuan
KERNEL_PATH := $(DEVICE_PATH)-kernel

KERNEL_RELEASE := 6.12.69-android16-6-g0d80ee00f747-ab15461283-4k

# Inherit from sm8650-common
include device/xiaomi/sm8850-common/BoardConfigCommon.mk

# NFC (ST54L). Our own manifest, not the stock odm one: that also declares
# ISecureElement/eSE1, which manifest_canoe.xml already declares and
# secure_element-service.qti already provides.
ODM_MANIFEST_FILES := \
    $(DEVICE_PATH)/configs/vintf/android.hardware.contexthub-service.qmi.xml \
    $(DEVICE_PATH)/configs/vintf/nfc-service-st.xml

# Display
TARGET_SCREEN_DENSITY := 420

# Dtb/o
BOARD_PREBUILT_DTBOIMAGE := $(KERNEL_PATH)/dtbo.img
BOARD_PREBUILT_DTBIMAGE_DIR := $(KERNEL_PATH)/dtb

TARGET_NO_KERNEL_OVERRIDE := true
# Kernel headers: no kernel source is published for songyuan, so ship the QTI
# UAPI headers (IPA) that in-tree code needs. This assignment feeds the
# prebuilt_kernel_includes genrule, but cc.go reads the same name with Getenv,
# which a makefile cannot set (export is rejected by the build system). So it
# must ALSO be exported in the shell, or libipanat fails on linux/msm_ipa.h:
#   export TARGET_PREBUILT_KERNEL_HEADERS=device/xiaomi/songyuan-kernel/kernel-headers.tar.gz
TARGET_PREBUILT_KERNEL_HEADERS := $(KERNEL_PATH)/kernel-headers.tar.gz
PRODUCT_COPY_FILES += \
	$(KERNEL_PATH)/kernel:kernel

# Kernel modules
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := $(strip $(shell cat $(KERNEL_PATH)/vendor_ramdisk/modules.load))
BOARD_VENDOR_RAMDISK_RECOVERY_KERNEL_MODULES_LOAD := $(strip $(shell cat $(KERNEL_PATH)/vendor_ramdisk/modules.load.recovery))
BOARD_VENDOR_KERNEL_MODULES_LOAD := $(strip $(shell cat $(KERNEL_PATH)/vendor_dlkm/modules.load))

PRODUCT_COPY_FILES += \
    $(call find-copy-subdir-files,*,$(KERNEL_PATH)/vendor_dlkm/,$(TARGET_COPY_OUT_VENDOR_DLKM)/lib/modules) \
    $(call find-copy-subdir-files,*,$(KERNEL_PATH)/vendor_ramdisk/,$(TARGET_COPY_OUT_VENDOR_RAMDISK)/lib/modules) \
    $(call find-copy-subdir-files,*,$(KERNEL_PATH)/system_dlkm_flatten/,$(TARGET_COPY_OUT_SYSTEM_DLKM)/flatten/lib/modules) \
    $(call find-copy-subdir-files,*,$(KERNEL_PATH)/system_dlkm/,$(TARGET_COPY_OUT_SYSTEM_DLKM)/lib/modules/$(KERNEL_RELEASE))

TARGET_ODM_PROP += $(DEVICE_PATH)/configs/properties/odm.prop
TARGET_VENDOR_PROP += $(DEVICE_PATH)/configs/properties/vendor.prop

# Partitions
BOARD_SUPER_PARTITION_SIZE := 16642998272
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 16632512512

# Security
BOOT_SECURITY_PATCH := 2026-08-01
VENDOR_SECURITY_PATCH := $(BOOT_SECURITY_PATCH)

# Inherit from the proprietary version
include vendor/xiaomi/songyuan/BoardConfigVendor.mk

# MIUI Camera
ifneq ($(wildcard vendor/xiaomi/songyuan-miuicamera/BoardConfigVendor.mk),)
include device/xiaomi/songyuan-miuicamera/BoardConfig.mk
endif
