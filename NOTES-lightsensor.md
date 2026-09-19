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

## Round 3 findings — with a real subscriber (tools/alstest)

`cmd sensorservice` cannot subscribe and the stock `test-nusensors` segfaults, so
`device/xiaomi/songyuan/tools/alstest` was written for this (NDK ASensorManager,
subscribes by handle, prints all 8 event fields). Not in PRODUCT_PACKAGES;
build with `m alstest`, push to /data/local/tmp.

**The factory stream is the useful one.** 0x42f carries the computed lux AND the
raw channels in one event:

    h=0x42f  1.022  1.022  32.000  2000.000  271.984  151.579
             ^lux^                           ^^^raw channels^^^

Over 25s with the light changing, raw ch4 swept 143.667 -> 274.198 while the
computed lux stayed at exactly **1.022** for every one of 168 events.

    0x33  (front processed)  3 events at subscribe, then silence forever
    0x42f (front factory)    168 events, lux constant, raw varying
    0x60f (rear processed)   1 event, 0.000
    0x73b (rear factory)     166 events, all fields 0.000
    0x83f (front raw)        streams fine, ~260 varying

So **both** processed outputs are broken, not just the front. The earlier theory
that the front needed the rear as a reference is **disproved** — enabling the rear
changes nothing, and the rear is equally dead.

The DSP algorithm is running (it streams at the right rate, carries correct gain
and integration-time fields, and passes the raw channels through) but its lux
output is a constant regardless of input.

## Realistic fix options

1. **Compute lux in userspace.** We have everything needed: the raw channels
   stream live on 0x83f/0x42f, and the coefficients are all readable --
   `lux_coef` (alsTranma matrix, thresholds), `ch_fac_cal` (per-channel scales),
   and `panel_Info_cali` (23-row RGBW panel emission table). A small service could
   read raw, apply the transform, and publish android.sensor.light. Substantial
   but tractable, and it sidesteps the signed DSP firmware entirely.
2. Find the enable/mode that makes the DSP algorithm actually compute. Nothing
   found so far; would need SSC logging.
3. Ask whoever ships a working GLS6151 device.

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

---

# Round 4 -- root cause found

## What the sensor actually does

`android.sensor.light` (0x33) and the Xiaomi factory ALS (0x42f) both emit a
hard constant **1.022 lux**. Sweeping the screen backlight 1 -> 255 swings the
raw channels **25x** (ch0 280 -> 7093) and the reported lux does not move a
single bit, and 0x33 stays silent throughout. That is a fallback constant, not
a computation. (The 38.36 seen in round 3 was a stale cached on-change value,
not a live reading.)

The front ALS is **under the display**, so that 25x swing is panel light: ~96%
of what the sensor sees is the screen, not the room.

## How stock compensates

`/odm/etc/sensors/config/lightSensorConfig.json` holds `Cct.panel_Info_cali_ori`
-- a 23-row table indexed by panel DBV (0, 50, 200, ... 7800, matching
`collectAls.setBrightness`), with independent r/g/b/w sets of 10 channel values
each. Alongside it `cwbInfo` (Center "705,190", a radius list) identifies the
screen region directly above the sensor: stock samples the displayed content
there via **concurrent writeback**, weights the r/g/b/w tables by it, scales by
the current DBV, and subtracts that from the raw channels before applying the
lux transform.

The transform itself is confirmed: `channel_coef` in that JSON is bit-identical
to `lux_coef` in the sensor registry (threshold 0.7, then `alsTranma1` and
`alsTranma3`). Applying it to live raw channels gives **46-51 lux**, plausible
and tracking the channels -- so the maths is right and the inputs are there.

## Everything static is already correct

- `/odm/etc/sensors/config` is **byte-identical to stock** (`diff -rq`, clean).
- The registry parsed every `glsx` group; `dark_cal` (-6..-18), `ch_fac_cal`
  (~0.88), `als_delay`, `misc_info`, `sensor_reg_patch` all hold sane factory
  values.
- No SELinux denials anywhere near the sensor stack.
- `panel-info-sh` ran and set `vendor.panel.*` correctly (vendor 23, display 12).

So nothing we ship is wrong. The gap is **runtime**: nothing on our build feeds
the DSP the live DBV and screen-content colour. On stock that comes from MIUI's
display stack, plus the AON services `miaon_frame` / `misensor_camera`, which
are both absent here -- `xiaomi.sensor.virtual_als_aon` (0x91b) yields no events
at all. Starved of that feed the algorithm over-subtracts and clamps to its floor.

This is **not patchable**: the algorithm lives in signed ADSP firmware and the
feed is MIUI framework code.

## New find: there is a second ALS chip

`sip2326lr1n` ("SI IN"), rear-facing, with its own registry coefficients:

| handle | type | notes |
|--------|------|-------|
| 0x60f / 0x610 | `xiaomi.sensor.back_lux` | on-change / wakeup |
| 0x73b | `xiaomi.sensor.back_lux_strm` | streaming |
| 0x623 / 0x62d | `xiaomi.sensor.back_cct*` | colour temperature |
| 0x619 | `xiaomi.sensor.flicker` | reports 666.016 |
| 0x821 | `xiaomi.sensor.dual_cct` | fuses front + back |

It currently reads 0 lux -- but every test so far has been with the phone
face-up on a desk, where a rear-facing sensor seeing darkness is the *correct*
answer. **Untested with the back actually exposed to light.** If it works it is
a panel-free ambient source and a far better input than the front sensor.

## Where this leaves us

1. **Test the rear ALS properly** (back pointed at a lamp). Cheap, decisive.
2. **Userspace lux daemon.** Read front raw (0x83f), subtract panel emission
   from `panel_Info_cali_ori` indexed by DBV, apply `channel_coef`, publish as
   `android.sensor.light`. All inputs are available; the hard part is the
   screen-content colour that stock gets from CWB -- approximating with the
   white table will misread dark-mode vs white-page content.
3. **Fuse both**, the way Xiaomi's own `dual_cct` does, if the rear works.
