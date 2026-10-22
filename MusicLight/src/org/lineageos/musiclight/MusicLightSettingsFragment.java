/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.musiclight;

import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.os.Bundle;

import androidx.preference.ListPreference;
import androidx.preference.PreferenceCategory;
import androidx.preference.PreferenceFragmentCompat;
import androidx.preference.SwitchPreferenceCompat;

import java.text.Collator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public class MusicLightSettingsFragment extends PreferenceFragmentCompat {
    private static final String KEY_ENABLED = "music_light_enabled";
    private static final String KEY_APPS_MODE = "music_light_apps_mode";
    private static final String KEY_APPS = "music_light_apps";
    private static final String MODE_ALL = "all";
    private static final String MODE_SELECTED = "selected";

    private final Set<String> mSelected = new HashSet<>();
    private boolean mSelectedOnly;

    @Override
    public void onCreatePreferences(Bundle savedInstanceState, String rootKey) {
        setPreferencesFromResource(R.xml.settings_music_light, rootKey);
        Context context = requireContext();
        mSelectedOnly = MusicLight.isSelectedOnly(context);
        mSelected.addAll(MusicLight.getApps(context));

        SwitchPreferenceCompat enabled = findPreference(KEY_ENABLED);
        enabled.setChecked(MusicLight.isEnabled(context));
        enabled.setOnPreferenceChangeListener((preference, value) -> {
            MusicLight.setEnabled(context, (Boolean) value);
            return true;
        });

        PreferenceCategory apps = findPreference(KEY_APPS);
        apps.setVisible(mSelectedOnly);
        addAppSwitches(context, apps);

        ListPreference mode = findPreference(KEY_APPS_MODE);
        mode.setEntries(new CharSequence[] {
            getString(R.string.music_light_apps_mode_all),
            getString(R.string.music_light_apps_mode_selected),
        });
        mode.setEntryValues(new CharSequence[] { MODE_ALL, MODE_SELECTED });
        mode.setValue(mSelectedOnly ? MODE_SELECTED : MODE_ALL);
        mode.setOnPreferenceChangeListener((preference, value) -> {
            mSelectedOnly = MODE_SELECTED.equals(value);
            apps.setVisible(mSelectedOnly);
            saveFilter();
            return true;
        });
    }

    /* One switch per launcher app, sorted by name; each change is saved right away */
    private void addAppSwitches(Context context, PreferenceCategory apps) {
        PackageManager pm = context.getPackageManager();
        Intent launcher = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        List<ResolveInfo> activities = pm.queryIntentActivities(launcher, 0);
        Collator collator = Collator.getInstance();
        activities.sort((a, b) -> collator.compare(
                a.loadLabel(pm).toString(), b.loadLabel(pm).toString()));
        Set<String> added = new HashSet<>();
        for (ResolveInfo info : activities) {
            String pkg = info.activityInfo.packageName;
            if (!added.add(pkg)) {
                continue;
            }
            SwitchPreferenceCompat app = new SwitchPreferenceCompat(context);
            app.setKey(KEY_APPS + ":" + pkg);
            app.setPersistent(false);
            app.setTitle(info.loadLabel(pm));
            app.setIcon(info.loadIcon(pm));
            app.setChecked(mSelected.contains(pkg));
            app.setOnPreferenceChangeListener((preference, value) -> {
                if ((Boolean) value) {
                    mSelected.add(pkg);
                } else {
                    mSelected.remove(pkg);
                }
                saveFilter();
                return true;
            });
            apps.addPreference(app);
        }
    }

    private void saveFilter() {
        MusicLight.setFilter(requireContext(), mSelectedOnly, new HashSet<>(mSelected));
    }
}
