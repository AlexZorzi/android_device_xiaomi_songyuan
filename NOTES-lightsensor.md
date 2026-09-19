# Auto-brightness / ALS on songyuan — investigation notes (2026-09-19)

## Symptom

`android.sensor.light` (handle 0x33) emits a **fixed 38.36 lux** and never tracks.
The raw sensor (handle 0x83f) works perfectly:

    covering the sensor:  raw ch0  145 -> 350 -> 109 -> 43 -> 39 -> 28
                          processed  38.36 every single sample

Earlier in the session this was mis-reported as "always reads 0.00" — that was a
misread of the trailing padding fields in the event tuple. It is a *frozen*
value, not a dead sensor.

## Hardware

Two ambient light sensors:

    0x33 / 0x34 / 0x42f   glsx (goodix GLS6151)   front, UNDER the display
    0x60f / 0x610 / 0x73b sip2326lr1n (SI IN)     xiaomi.sensor.back_lux, REAR

Conversion runs as `sns_glsx` on the SSC (Snapdragon Sensor Core / ADSP), not in
userspace. No library or binary in the dump references the calibration files —
only `odm/etc/init/init.boled.lightsensor.rc`, which just chowns one file.
The ADSP firmware is signed, so the algorithm itself cannot be patched.

## What is ruled out (all verified identical to stock)

- `odm/etc/sensors/config/sm8850_gls6151.json` — shipped, byte-identical
- `sensors.qsh.so` — byte-identical (md5 2ad609bd)
- `/mnt/vendor/persist/sensors/lightSensorCali.json` — present, 11610 bytes,
  system:system, and fully populated:
    Cct.channel_scale     0.884, 0.910497, 0.943964, 0.868065, 0.883923
    Cct.panel_Info_cali   data_r/g/b/w, 23 rows each, 22 populated
    Cct.Center            710,190
- sensor registry `glsx_platform.als.lux_coef` — real transform matrix
  (alsTranma1_0..4 = 0.0314508, 0.247569, -0.0555664, 0.0493835, -0.023455;
  Thre_1/2 = 0.7, lowAlsGThre = 48, lowAlsCoef = 0.315)
- registry `ch_fac_cal` matches the cali file exactly
- `vendor.xiaomi.hardware.displayfeature_aidl-service`, `citsensorservice`,
  `xiaomi-multihal` all running
- framework correctly subscribed (AutomaticBrightnessController, BrightnessTracker)

So every *static* input the driver needs is present and correct.

## Prime suspect: the rear ALS is idle

    Ambient Light Back Sensor: 0 events, 0 subscribers

Xiaomi ships BOTH `Lux_F_channel_data.txt` (front, 7 values) and
`Lux_B_channel_data.txt` (back, 4 values) in persist. The front sensor sits under
the panel, so it needs an unobstructed reference plus the panel emission table
(indexed by current backlight) to subtract the screen's own light — note the
per-refresh-rate sync delays in the config (als_sync_delay_30/60/90/120/144/165/185hz).

A frozen output is exactly what you would expect if that live reference never
arrives and the algorithm falls back to a constant.

## Round 2 findings (same day, with adb root)

**The DSP sensor itself is healthy.** `ssc_sensor_info` (pushed from the stock
dump to /data/local/tmp) reports:

    NAME = glsx   VENDOR = goodix   TYPE = ambient_light
    AVAILABLE = true
    RANGES = [0.000000, 65535.000000]      <- full lux range, not a stub
    RESOLUTIONS = 0.100000
    STREAM_TYPE = on_change

**The 38.36 is a cached value, not a live one.** `android.sensor.light` is an
on-change sensor, so sensorservice caches the last event and re-delivers it to
every new subscriber. The "events" visible in dumpsys with advancing timestamps
are re-deliveries, not new samples. Proof: sweeping the backlight 5 -> 120 -> 255
and covering the sensor both leave the value at exactly 38.36.

So the SSC `ambient_light` stream emits **nothing at all**, while
`ambient_light_raw` streams fine at 50ms.

Also checked and ruled out:
- `odm/etc/sensors` 54/54 files identical to stock (incl. lightSensorConfig.json)
- `vendor/etc/sensors` gaps are camera-AON configs for sensors this device does
  not have (imx688/ov32c4c/s5kjn5) and sm8845 variants -- irrelevant
- No userspace library references alsTranma/lux_coef/panel_Info_cali, confirming
  the conversion is entirely DSP-side and cannot be patched
- `vendor.qti.hardware.sensorscalibrate-service` is shipped and present; its rc is
  `disabled`+`oneshot` (lazy HAL), so not running is by design

SSC sensors that exist but are idle:
    ambient_light_cal_strm, ambient_light_back, ambient_light_back_strm

`test-nusensors` from the stock dump segfaults on this platform -- to subscribe to
custom sensor types you need a small NDK binary or an app.

## Next steps

1. Get the rear ALS streaming (custom type 33171055) and see whether the front
   unfreezes. Needs an app that can subscribe to a non-standard sensor type, or
   Xiaomi's citsensorservice test interface.
2. Enable SSC logging and read what `sns_glsx` says at init.
   `/vendor/etc/sensors/sns_reg_config` is the config entry point.
3. Trace how stock feeds the live backlight level to the SSC.

## Useful facts

- **`adb root` works** on this build despite `ro.debuggable=0` — no KernelSU
  needed for any of the above.
- Sensors freeze in doze; use `adb shell svc power stayon usb` before testing, or
  readings look "stuck" when they are merely suspended.
- Auto-brightness ships disabled (`screen_brightness_mode=0`). Enabling it does
  drive the backlight (11 -> 22 observed), so the framework side is fine.
