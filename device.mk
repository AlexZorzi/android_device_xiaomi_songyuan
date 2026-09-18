
#
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

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
# XiaomiEsimSwitcher (com.xiaomi.mtb) is deliberately NOT included: Settings
# routes the eSIM entry to its EsimSettingsActivity, which issues a synchronous
# Xiaomi OEM RIL hook (onGetEsimStatus, msg type 83) straight to the modem and
# blocks on a 5s timer. The modem does not service that vendor request here, so
# the blocked call takes down system_server. Without it, eSIM goes through the
# EuiccGoogle LPA instead.
PRODUCT_PACKAGES += \
    XiaomiEuicc

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/permissions/privapp-permissions-euiccgoogle.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/permissions/privapp-permissions-euiccgoogle.xml

# eUICC features. These MUST be declared together with the EuiccGoogle LPA blob
# (see proprietary-files.txt): TelephonyFrameworkInitializer only registers
# EuiccManager when FEATURE_TELEPHONY_EUICC is present, so without this the LPA
# NPEs on getSystemService(EuiccManager) and crash-loops at boot. Declaring it
# *without* an LPA is equally broken -- Settings then offers eSIM with nothing
# behind it and takes down system_server.
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.telephony.euicc.mep.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.telephony.euicc.mep.xml

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
    SongyuanEuiccOverlay \
    SettingsOverlaySongyuan \
    SystemUIResSongyuan

