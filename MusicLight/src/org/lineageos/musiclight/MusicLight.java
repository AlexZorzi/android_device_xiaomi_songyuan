/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.musiclight;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

import java.util.Collections;
import java.util.Set;

final class MusicLight {
    private static final String PREFS = "state";
    private static final String KEY_ENABLED = "enabled";
    private static final String KEY_LIT = "lit";
    private static final String KEY_SELECTED_ONLY = "selected_only";
    private static final String KEY_APPS = "apps";

    private MusicLight() {}

    private static SharedPreferences prefs(Context context) {
        return context.createDeviceProtectedStorageContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static boolean isEnabled(Context context) {
        return prefs(context).getBoolean(KEY_ENABLED, false);
    }

    /* Only light up for the apps picked in settings instead of any media */
    static boolean isSelectedOnly(Context context) {
        return prefs(context).getBoolean(KEY_SELECTED_ONLY, false);
    }

    static Set<String> getApps(Context context) {
        return prefs(context).getStringSet(KEY_APPS, Collections.emptySet());
    }

    static void setFilter(Context context, boolean selectedOnly, Set<String> apps) {
        prefs(context).edit()
                .putBoolean(KEY_SELECTED_ONLY, selectedOnly)
                .putStringSet(KEY_APPS, apps)
                .apply();
        // Restart so the running service picks up the new filter
        if (isEnabled(context)) {
            context.stopService(new Intent(context, MusicLightService.class));
            apply(context);
        }
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
