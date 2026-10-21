/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.musiclight;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

final class MusicLight {
    private static final String PREFS = "state";
    private static final String KEY_ENABLED = "enabled";
    private static final String KEY_LIT = "lit";

    private MusicLight() {}

    private static SharedPreferences prefs(Context context) {
        return context.createDeviceProtectedStorageContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static boolean isEnabled(Context context) {
        return prefs(context).getBoolean(KEY_ENABLED, false);
    }

    static void setEnabled(Context context, boolean enabled) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply();
        apply(context);
    }

    static void apply(Context context) {
        Intent service = new Intent(context, MusicLightService.class);
        if (isEnabled(context)) {
            context.startService(service);
        } else {
            context.stopService(service);
            releaseIfLeftLit(context);
        }
    }

    /* Remembered across process deaths: a killed service can't switch the LED off. */
    static void setLit(Context context, boolean lit) {
        prefs(context).edit().putBoolean(KEY_LIT, lit).commit();
    }

    static void releaseIfLeftLit(Context context) {
        if (prefs(context).getBoolean(KEY_LIT, false)) {
            MusicLightService.release();
            setLit(context, false);
        }
    }
}
