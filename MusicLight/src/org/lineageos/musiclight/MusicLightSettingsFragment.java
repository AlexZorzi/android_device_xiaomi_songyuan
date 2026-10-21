/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.musiclight;

import android.os.Bundle;

import androidx.preference.PreferenceFragmentCompat;
import androidx.preference.SwitchPreferenceCompat;

public class MusicLightSettingsFragment extends PreferenceFragmentCompat {
    private static final String KEY_ENABLED = "music_light_enabled";

    @Override
    public void onCreatePreferences(Bundle savedInstanceState, String rootKey) {
        setPreferencesFromResource(R.xml.settings_music_light, rootKey);
        SwitchPreferenceCompat enabled = findPreference(KEY_ENABLED);
        enabled.setChecked(MusicLight.isEnabled(requireContext()));
        enabled.setOnPreferenceChangeListener((preference, value) -> {
            MusicLight.setEnabled(requireContext(), (Boolean) value);
            return true;
        });
    }
}
