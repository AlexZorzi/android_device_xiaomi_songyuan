#
# Copyright (C) 2024 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit some common Lineage stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Inherit from songyuan device.
$(call inherit-product, device/xiaomi/songyuan/device.mk)

# MIUI Camera. Activates once its blobs are extracted:
#   device/xiaomi/songyuan-miuicamera/extract-files.py <stock dump>
ifneq ($(wildcard vendor/xiaomi/songyuan-miuicamera/songyuan-miuicamera-vendor.mk),)
$(call inherit-product, device/xiaomi/songyuan-miuicamera/device.mk)
endif

## Device identifier
PRODUCT_DEVICE := songyuan
PRODUCT_NAME := lineage_songyuan
PRODUCT_BRAND := POCO
PRODUCT_MODEL := POCO F9 Ultra
PRODUCT_MANUFACTURER := xiaomi

BUILD_FINGERPRINT := POCO/songyuan_eea/songyuan:16/BQ2A.260225.001-BP2A.250705.008/OS3.0.305.0.WGNEUXM:user/release-keys
