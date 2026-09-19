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

---

# Round 5 -- fixed

Two independent problems, not one.

## 1. The sensor: use the rear ALS

The front ALS is unfixable (see round 4). The rear `sip2326lr1n` works perfectly
-- verified by driving the torch from `/sys/class/leds/yellow:flash-0/brightness`
and watching lux swing 0.7 <-> 9200 on a held subscription.

Fixed in `hardware/xiaomi` by promoting `xiaomi.sensor.back_lux` to
`android.sensor.light` in the multihal and dropping the dead front sensor.

## 2. `auto_brightness_one_shot` was enabled

This one masked the fix for a long time. LineageOS has a setting
`LineageSettings.System.AUTO_BRIGHTNESS_ONE_SHOT` (Settings -> Display ->
Adaptive brightness) which was set to **1** on this device. With it on,
`AutomaticBrightnessController` takes a single reading when the screen turns on
and then calls `unregisterListener`:

```java
// AutomaticBrightnessController.updateAutoBrightness()
if (mAutoBrightnessOneShot) {
    mSensorManager.unregisterListener(mLightSensorListener);
}
```

Symptoms, all of which look like a broken sensor but are not:
- `mAmbientLux` frozen at one stale value, `mAmbientLightRingBuffer` holding a
  single sample many seconds old.
- `mLightSensorEnabled=true` while SensorService shows no matching connection.
- A `+` and a `-` registration for `AutomaticBrightnessController$2` at the same
  second, every time the display is configured.

Check it with:
```
content query --uri content://lineagesettings/system --where "name='auto_brightness_one_shot'"
```
Distinguish it from a dead sensor by the *sampling period* in
`dumpsys sensorservice`: AutomaticBrightnessController subscribes at 250 ms,
BrightnessTracker and the biometrics ALSProbe at 200 ms. If only 200 ms
subscribers are listed, auto-brightness itself is not listening.

With it set to 0, the full chain works: lux 0.79 -> 7248 moves
`mScreenAutoBrightness` 0.003 -> 0.705 and the panel backlight 71 -> 11954.

## Corrections to earlier rounds

- The on-change sensors (0x33, 0x60f) **do** stream to a held subscription. The
  earlier "one event then silence" reading was an artefact of subscribing and
  exiting repeatedly, not a sensor fault.
- `maxRange=1.0` on the promoted sensor is harmless; nothing in
  AutomaticBrightnessController or BrightnessMappingStrategy reads it.
- The 46-51 lux computed from front raw channels in round 4 was measuring the
  screen, not the room. At minimum backlight the front sensor reads 0 +/- 3 in a
  ~50 lux room, so there is no recoverable ambient signal to compute from.

## Remaining limitation

The rear sensor faces away from the user, so with the phone face-up on a desk it
reads ~0 and the screen dims. Xiaomi fuses front and rear (`xiaomi.sensor.dual_cct`
exposes both halves); we could do the same if this proves annoying.

---

# Round 6 -- the front pipeline is closer than round 4 claimed

Round 4 said the panel-compensation feed was unavailable to us because it needed
MIUI display code. **That was wrong on two counts**, found by reading strings out
of `citsensorservice`:

```
als_cwb_buffer_   startCalculateLux   syncRgbByBrightness   setBrightness
panel_Info_cali_r/g/b/w   collectAls
persist.vendor.sensors.run_als_model      ro.vendor.sensor.maxbrightness
```

1. **The algorithm is userspace, not DSP firmware.** `libsensor-boledalgo` and
   `libsensor-parseRGB` live inside `vendor.xiaomi.sensor.citsensorservice.aidl`,
   which we already run.
2. **CWB works on our build.** Setting
   `persist.vendor.sensors.run_als_model=1` and restarting citsensorservice
   produces:
   ```
   libsensor-boledalgo: size of cwb length 15, center 705, 190
   SDM: CWB config passed by cwb_client: CWB_ROI : (604, 89, 805, 290) display-0
   SDM: NotifyCWBStatus: ... status 0
   libsensor-parseRGB: onCwbSuccess, mRequestDisplayId 0
   ```
   SurfaceFlinger serves the screen region above the sensor and the service reads
   it successfully. `ro.vendor.sensor.maxbrightness=7800` is already set and
   matches the top row of `panel_Info_cali`.

With the model enabled the algorithm streams continuously (~5 Hz,
`the value of sensorData <4 channels>`), and `xiaomi.sensor.front_cct` (0x759),
which had produced **zero** events, comes alive.

## Why it still is not usable

Front lux stays at exactly `0.000` on both 0x33 and 0x42f even with strong light
on the front of the phone -- verified with raw `ch0` swinging 273 -> 11102 while
lux never moved. The fallback constant changes from 1.022 to 0.000 when the model
is enabled, so the property definitely reaches the pipeline, but the computed
result never reaches the Android sensor. citsensorservice logs its *input*
continuously and never logs an output.

The likely explanation is that the result is delivered to a MIUI-side consumer
(its own AIDL, consumed by MIUI's display/brightness service) rather than being
published as `android.sensor.light`.

**Next step if anyone wants to pick this up:** reverse-engineer the
citsensorservice AIDL to find where the computed lux is delivered, then bridge it
into the sensor framework. Open-ended, and it may dead-end on a MIUI-only
interface.

The property is left at **0**: with it on, the service does a CWB readback and
runs the algorithm several times a second, which costs power for a result we do
not currently consume.

---

# Round 7 -- the citsensorservice AIDL, mapped

The service is `vendor.xiaomi.sensor.citsensorservice.ICitSensorService/default`
(AIDL V1), registered on the normal binder -- `service check` finds it, so it can
be driven straight from the shell with `service call`.

Transaction codes, recovered by disassembling the `Bp` proxies in
`vendor/lib64/vendor.xiaomi.sensor.citsensorservice-V1-ndk.so` and reading the
`mov w1, #N` before each `AIBinder_transact`:

| code | method | signature |
|------|--------|-----------|
| 1 | initHallSocket | |
| 2 | getHallEvent | |
| 3 | **calibrate** | (int, int, int*) -- **do not call** |
| 4 | **channelCalibrate** | -- **do not call, overwrites factory cal** |
| 5 | getConfig | (int, vector<float>*, int, int, int*) -- read-only |
| 6 | setConfig | (int, int, float, int*) |
| 7 | selftest | (int, int, int*) |
| 8 | collectData | |
| 9 | triggerCwbDump | (int, int, bool, int*) |
| 10 | enableCitSensorServiceLog | |
| 11 | getCalibrated | read-only |
| 12 | **setBrightness** | (int, int*) |
| 13 | setArrayConfig | |
| 14 | getSensorSn | |
| 15 | getRegData | |
| 16 | misCheck | |

`setBrightness` and `triggerCwbDump` are *inbound*: on stock, MIUI's display
service tells citsensorservice the panel state. Nothing on our build ever calls
them, which was the obvious candidate for the missing link.

## It is not the missing link

Tested the full stock-like configuration:

- `persist.vendor.sensors.run_als_model=1`, citsensorservice restarted
- `service call ... 12 i32 <DBV>` driven continuously at 2 Hz from the live
  backlight value
- strong light on the *front* of the phone

`setBrightness` returns status 0. Front lux stayed at exactly **0.000** the whole
time while raw `ch0` sat at a healthy ~1218. Also ruled out:

- **SELinux is not the blocker.** With `setenforce 0` the only denials are
  citsensorservice reading an unlabelled `default_prop`, and behaviour is
  unchanged.
- Calling `triggerCwbDump` changes nothing.

## myron comparison

myron (POCO F8 Ultra) ships **only** `sm8850_gls6151.json` -- no rear ALS at all,
where songyuan has `sm8850_sip2326lr1n.json` as well. myron's device tree has no
ALS/light/brightness files and no commit ever touching them.

So either myron's front ALS works out of the box, or auto-brightness is dead on
the F8 Ultra too. **Worth asking its maintainer** -- the answer decides whether
the front sensor is solvable at all on LineageOS.

That songyuan has a second ALS at all is itself a hint: Xiaomi may have added it
precisely because the under-display one is unreliable, in which case stock's own
`android.sensor.light` may lean on the rear sensor too -- which is what we now do.

## Next leads, if picked up again

1. `setArrayConfig` (13) is the likely route by which the `panel_Info_cali` table
   reaches the DSP. Nothing calls it on our build. Needs the array format.
2. Disassemble `libaidlcitsensorservice-impl.so` to see what it does with the CWB
   result -- it logs its input every ~200 ms and never logs an output.

---

# Round 8 -- narrowed to a single fact

F8 Ultra (myron) is **also broken on LineageOS**, confirmed by its maintainer's
users. So nobody has made the under-display GLS6151 work on LineageOS on any
sm8850 Xiaomi device. songyuan is only fixable because it has a rear ALS that
myron does not.

## The algorithm's own log strings

`odm/bin/hw/vendor.xiaomi.sensor.citsensorservice.aidl` contains:

```
CWB_ALS: dbv:%.0f,lux:%.1f,cct:%.1f,hsv:%.1f,CWB R:%.1f,G:%.1f,B:%.1f
         Event R,G,B,C,W  Cali R,G,B,C,W
##### the value of lux: %f, cct: %f
##### the value of High brightness lux: %f, cct: %f, brightness: %f
startCalculateLux: drop some sensordata screen on!!!
transfer lux  to type %d failed: %d
parseRgbData: para setting error!
underoled_lux_calibrate brightness matching check failed
```

Verbose logging can be switched on at runtime:
`service call <ICitSensorService/default> 10 i32 1` (returns OK).

## The finding

With verbose logging on, the model enabled, the front ALS subscribed, and
brightness fed continuously, the service logs **only** `the value of sensorData
<R,G,B,W>` at ~5 Hz. **`startCalculateLux` is never invoked** -- not once. None
of `CWB_ALS:`, `the value of lux:`, `transfer lux`, or `parseRgbData` ever
appears. CWB fires exactly once, at service start, and never again.

So the lux calculation is not failing; it is never being *entered*.

## Ruled out

- **SELinux** -- `setenforce 0` changes nothing; only denials are an unlabelled
  `default_prop` read.
- **`sync_stream`** -- 0 in our json, and identically 0 in myron's.
- **`setBrightness`** (txn 12) -- returns OK, driven at 2 Hz from live DBV, no effect.
- **`triggerCwbDump`** (txn 9) -- returns OK on four argument combinations, no
  CWB activity follows. Probably only writes `Lux_F_center_data.txt`.
- **Properties** -- `persist.vendor.sensors.used.framebuffer` is already 1;
  setting `parsedalgo.debug`, `parsedalgo.streaming.report` changes nothing.
  Full list of properties the binary reads is in the strings dump.

## What is left

Find what invokes `startCalculateLux`. It is gated on something MIUI's display
stack does that we have not identified -- plausibly a display-state callback
registration rather than a method call, since none of the inbound AIDL methods
trigger it. Answering this means disassembling a stripped ARM64 binary around
that symbol to recover its call sites and guard conditions. Hours of work, no
guarantee.

---

# Round 9 -- disassembly: the exact gate

Disassembled `odm/bin/hw/vendor.xiaomi.sensor.citsensorservice.aidl` (stripped
ARM64, .text 0x84000+0x5068c). Method addresses recovered by locating the log
strings in .rodata (mapped 1:1 to file offsets) and resolving `adrp`/`add` pairs.

## Call graph

| what | address |
|------|---------|
| `startCalculateLux` | **0xaca74** |
| its only caller | 0x93e74, inside the handler at **0x93e48** |
| lux output + `transfer lux` | 0x894dc |
| sensorData ingest | 0xb3ed4 |
| constructor | 0x92ec0, called once from `main` at 0xa6e20 |

The handler at 0x93e48 takes `(this, int, int, bool, int*)` -- that is
**`triggerCwbDump`**, and it is the *only* path to `startCalculateLux`:

```asm
93e60: cbnz w1, 0x93e78      ; arg1 != 0  -> skip
93e64: ldr  x0, [x0, #0x78]  ; this+0x78 = the "Als" handler
93e68: cbz  x0, 0x93e78      ; NULL       -> skip
93e74: bl   0xaca74          ; startCalculateLux(handler, 0, arg2, bool)
93e78: str  wzr, [x20]
93e7c: bl   AStatus_newOk    ; returns OK either way
```

It returns success whether or not it did anything, which is why every
`service call ... 9` gave `Parcel(00000000 00000000)`.

## The VTS guard (real, but not our problem)

The constructor contains:

```c
w21 = property_get_bool("persist.vendor.debug.cwb.disable", false);
property_get("ro.product.system.manufacturer", buf, "unknown");
if (strcasecmp(buf, "Android") == 0) {      // AOSP/LineageOS default!
    ALOGE("disable cwb for vts");
    flag = true;
}
if (!flag) { <CWB/ALS init at 0x85010> }
```

**Any build reporting `ro.product.system.manufacturer=Android` has CWB disabled
outright.** Worth knowing for other devices/ports. Ours reports `xiaomi`,
matching stock, and `persist.vendor.debug.cwb.disable` is unset, so neither
branch fires and the init does run.

## Where it actually stops

After init the constructor allocates a 0x28-byte object into `this+0x70`, then
looks up the key **`"Als"`** through a factory at 0x94b78 and stores
`result+0x28` into `this+0x78`. That value is what `triggerCwbDump` requires, and
it is NULL on our build.

Verified dynamically: with the model enabled, verbose logging on
(`service call ... 10 i32 1`), the front ALS subscribed, brightness fed, and
`triggerCwbDump` called with four argument combinations, the binder transactions
arrive but the service emits **no** internal log lines at all. Early return,
every time.

**The open question is now sharp: why is the `"Als"` handler never registered?**
Whatever populates that entry is the last missing piece.

## Useful runtime handles discovered

- `service call <ICitSensorService/default> 10 i32 1` -- enable verbose logging
- `service call ... 12 i32 <dbv>` -- setBrightness
- `service call ... 9 i32 0 i32 0 i32 1` -- triggerCwbDump
- Torch for controlled light: `/sys/class/leds/yellow:flash-0/brightness` (0-255)

---

# Round 10 -- SOLVED: the front ALS works

**The under-display GLS6151 works. It needs `triggerCwbDump` called periodically.**

Nothing in AOSP/LineageOS ever calls it; on stock, MIUI's display service does.
Without it the algorithm never runs and the sensor reports a fixed constant.

## The mechanism, correctly understood

`persist.vendor.sensors.run_als_model` is **not** an enable switch. It selects a
mode inside the handler factory at 0x85010:

```c
switch (atoi(property_get("persist.vendor.sensors.run_als_model", "0"))) {
  case 1:  /* collectAls / collect_data -- FACTORY CALIBRATION collection */
  case 0:  /* normal: registers the "Cct" handler (the real ALS algorithm) */
}
```

Round 6 had this backwards: setting it to 1 puts the service into factory
calibration mode and *stops* the normal handler being registered, which is why
`this+0x78` was null and `triggerCwbDump` silently no-oped. **Leave it at 0.**

The constructor prefers a handler named `"Als"` and falls back to `"Cct"`:

```asm
931b8: this+0x78 = lookup("Als")
931d4: cbnz -> done
931d8: this+0x78 = lookup("Cct")     ; the one registered in normal mode
```

## The driver

```sh
N=vendor.xiaomi.sensor.citsensorservice.ICitSensorService/default
while true; do
  DBV=$(cat /sys/class/backlight/panel0-backlight/brightness)
  service call $N 12 i32 $DBV        # setBrightness
  service call $N 9 i32 0 i32 0 i32 1 # triggerCwbDump
  sleep 0.3
done
```

`triggerCwbDump`'s first argument **must be 0** (`cbnz w1 -> skip`).

## Verified results

Algorithm log with it running:

```
CWB_ALS: More:brightness:14; CWB R:6.9,G:8.1,B:9.1;
         EVENT R:235.41,G:133.38,B:31.95,C:414.96,W:496.83; lux:42.4, cct:2892.2
CWB_ALS: maxBrightness:7800, curBightness:14.000000
```

**Panel compensation works** -- front lux across a 50x backlight sweep, ambient
held constant (raw ch0 moves ~25x over the same range):

| screen_brightness | front lux |
|---|---|
| 5 | 50.8 |
| 100 | 42.7 |
| 255 | 49.5 |
| 5 | 51.2 |

**Responds to real light** -- lamp on the front of the phone:

| condition | lux | raw ch0 |
|---|---|---|
| baseline | 51.9 | 1212 |
| lit | 924-1173 | 4758-6206 |

## Applies to myron and nezha

myron has only the GLS6151 and no rear ALS, and its light sensor is broken on
LineageOS. This should fix it there too -- same chip, same service, same missing
call.

## Still to do

- Replace the shell loop with a proper vendor daemon (`service call` in a loop
  forks two processes every 300 ms). The AIDL transaction codes are in round 7,
  so a small native client is straightforward.
- Decide the trigger cadence, and whether to stop triggering when the screen is
  off.
- With the front sensor working, the rear-ALS multihal patch is no longer needed.

## Note for other ports

The constructor also disables CWB outright when
`ro.product.system.manufacturer` reads `"Android"` (the AOSP default) --
it logs `disable cwb for vts`. Ours reports `xiaomi`, matching stock.
