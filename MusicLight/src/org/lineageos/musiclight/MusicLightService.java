/*
 * Copyright (C) 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.musiclight;

import android.app.Service;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.media.AudioPlaybackConfiguration;
import android.media.audiofx.AudioEffect;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.util.Log;

import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/*
 * Pulses the rear LED with whatever is playing, like stock HyperOS. The
 * analysis runs in the audio HAL (libmusiclightaidl, the stock algorithm),
 * which sets the LED level; this service powers the LED up while media plays,
 * keeps the effect on the player's session and switches the LED off after.
 *
 * The effect goes on the player's session rather than the output mix:
 * AudioFlinger suspends output mix effects whenever any session effect (like
 * MiSound) is enabled, and the stock V3 effect HAL can't opt out of that.
 */
public class MusicLightService extends Service {
    private static final String TAG = "MusicLight";
    private static final String LED = "/sys/class/leds/aw21024_led/";
    private static final int SEGMENTS = 8;
    // The driver only applies "brightness" on a "run" write, which reloads the
    // whole chip. The effect dims every LED at once with the global current.
    private static final String GLOBAL_CURRENT_REG = "6e";

    private static final UUID EFFECT_TYPE = UUID.fromString("1a8feafc-486d-4fea-9e19-9a5f583f1c91");
    private static final UUID EFFECT_IMPL = UUID.fromString("7e1bef4c-45d6-4672-8070-25a8a4d230a7");

    private HandlerThread mThread;
    private Handler mHandler;
    private AudioManager mAudioManager;
    private AudioEffect mEffect;
    private int mSession;
    private boolean mLit;

    private final AudioManager.AudioPlaybackCallback mPlaybackCallback =
            new AudioManager.AudioPlaybackCallback() {
                @Override
                public void onPlaybackConfigChanged(List<AudioPlaybackConfiguration> configs) {
                    update(configs);
                }
            };

    @Override
    public void onCreate() {
        mThread = new HandlerThread(TAG);
        mThread.start();
        mHandler = new Handler(mThread.getLooper());
        MusicLight.releaseIfLeftLit(this);
        mAudioManager = getSystemService(AudioManager.class);
        mAudioManager.registerAudioPlaybackCallback(mPlaybackCallback, mHandler);
        mHandler.post(() -> update(mAudioManager.getActivePlaybackConfigurations()));
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        mAudioManager.unregisterAudioPlaybackCallback(mPlaybackCallback);
        mHandler.post(() -> {
            stop();
            mThread.quitSafely();
        });
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void update(List<AudioPlaybackConfiguration> configs) {
        boolean selectedOnly = MusicLight.isSelectedOnly(this);
        Set<String> apps = MusicLight.getApps(this);
        int session = AudioManager.AUDIO_SESSION_ID_GENERATE;
        for (AudioPlaybackConfiguration config : configs) {
            if (config.isActive() && isWanted(config, selectedOnly, apps)) {
                session = config.getSessionId();
                break;
            }
        }
        if (session == AudioManager.AUDIO_SESSION_ID_GENERATE) {
            stop();
        } else if (!mLit) {
            start(session);
        } else if (mEffect == null || session != mSession) {
            if (mEffect != null) {
                mEffect.release();
                mEffect = null;
            }
            attach(session);
        }
    }

    /*
     * Any media playback, or with an app selection, any playback of the
     * selected apps that isn't a call or a system sound (so WhatsApp voice
     * messages count).
     */
    private boolean isWanted(AudioPlaybackConfiguration config, boolean selectedOnly,
            Set<String> apps) {
        int usage = config.getAudioAttributes().getUsage();
        if (!selectedOnly) {
            return usage == AudioAttributes.USAGE_MEDIA;
        }
        if (usage != AudioAttributes.USAGE_MEDIA && usage != AudioAttributes.USAGE_GAME
                && usage != AudioAttributes.USAGE_UNKNOWN) {
            return false;
        }
        String[] packages = getPackageManager().getPackagesForUid(config.getClientUid());
        if (packages == null) {
            return false;
        }
        for (String pkg : packages) {
            if (apps.contains(pkg)) {
                return true;
            }
        }
        return false;
    }

    private void start(int session) {
        MusicLight.setLit(this, true);
        mLit = true;
        write("hwen", "1");
        write("color", "FFFFFF");
        for (int segment = 0; segment < SEGMENTS; segment++) {
            write("rgbcolor", segment + " FFFFFF");
        }
        write("brightness", "255");
        write("run", "1");
        write("reg", GLOBAL_CURRENT_REG + " 0");
        attach(session);
        if (mEffect == null) {
            stop();
        }
    }

    private void attach(int session) {
        try {
            mEffect = new AudioEffect(EFFECT_TYPE, EFFECT_IMPL, 0, session);
            mEffect.setEnabled(true);
            mSession = session;
        } catch (RuntimeException e) {
            Log.e(TAG, "Failed to attach the music light effect to session " + session, e);
            if (mEffect != null) {
                mEffect.release();
                mEffect = null;
            }
        }
    }

    private void stop() {
        if (mEffect != null) {
            mEffect.release();
            mEffect = null;
        }
        if (mLit) {
            release();
            MusicLight.setLit(this, false);
            mLit = false;
        }
    }

    static void release() {
        write("reg", GLOBAL_CURRENT_REG + " 0");
        write("run", "0");
        write("hwen", "0");
    }

    private static void write(String node, String value) {
        try (FileOutputStream out = new FileOutputStream(LED + node)) {
            out.write(value.getBytes(StandardCharsets.US_ASCII));
        } catch (IOException e) {
            Log.w(TAG, "Failed to write " + node, e);
        }
    }
}
