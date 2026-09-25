
#
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Audio (above the common inherit: the first PRODUCT_COPY_FILES entry for a
# destination wins, and common installs the AOSP volume tables)
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/audio/default_volume_tables.xml:$(TARGET_COPY_OUT_VENDOR)/etc/default_volume_tables.xml

# Inherit from sm8650-common
$(call inherit-product, device/xiaomi/sm8850-common/common.mk)

# Get non-open-source specific aspects
$(call inherit-product, vendor/xiaomi/songyuan/songyuan-vendor.mk)

# Camera
PRODUCT_PACKAGES += \
    android.hardware.graphics.allocator-V1-ndk.vendor \
    vendor.qti.hardware.camera.offlinecamera-V2-ndk.vendor

# Display
# songyuan's composer-service links composer3-V4-ndk; sm8850-common installs
# V1, which is what popsicle's build of the same service needs.
PRODUCT_PACKAGES += \
    vendor.qti.hardware.display.composer3-V4-ndk.vendor

# Euicc
# XiaomiEsimSwitcher provides the only path that powers the eSIM on: its toggle
# calls onHookUimPowerReqEx + onSetEsimStatus, which write the enable state to
# modem EFS and bring up the chip's PMIC rail. The eUICC is otherwise unpowered,
# which is why every slot reports mIsEuicc=false with an empty EID and no LPA
# can find it. See the local patch in hardware/xiaomi: the status *getter* hangs
# on this device and had to be kept off the settings screen's load path.
PRODUCT_PACKAGES += \
    XiaomiEuicc \
    XiaomiEsimSwitcher

# OpenEUICC, built from source (packages/apps/OpenEUICC). It ships its own
# privapp allowlist and liblpac-jni.
PRODUCT_PACKAGES += \
    OpenEUICC

# Declare the eUICC features so EuiccManager exists and the EuiccGoogle LPA can
# start (TelephonyFrameworkInitializer gates EUICC_SERVICE on this). The LPA
# then reports "Cannot find Euicc on device" because no slot is exposed as an
# eUICC -- a graceful error rather than a reboot.
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.telephony.euicc.mep.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.telephony.euicc.mep.xml

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/permissions/privapp-permissions-euiccgoogle.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/permissions/privapp-permissions-euiccgoogle.xml


# Properties
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/properties/odm_CN.prop:$(TARGET_COPY_OUT_ODM)/etc/odm_CN.prop \
    $(LOCAL_PATH)/configs/properties/odm_GL.prop:$(TARGET_COPY_OUT_ODM)/etc/odm_GL.prop

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH)

# Overlays
PRODUCT_PACKAGES += \
    ApertureOverlaySongyuan \
    FrameworksResSongyuan \
    NfcOverlaySongyuan \
    SongyuanEuiccOverlay \
    SettingsOverlaySongyuan \
    SystemUIResSongyuan

