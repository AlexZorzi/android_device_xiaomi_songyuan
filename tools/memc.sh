#!/system/bin/sh
# Novatek NT72336 ("Dual DPU") test switch, run as root on the phone:
#   on [fps] | video | videomemc | sr | hdr | off | status
# Sends FrameMaster.setParameter(feature, status, value, cmd, "null"):
# feature 3 = game MEMC, 2 = video (MEMC/LDSR/SDR2HDR). The panel must run at 120 Hz.
# "status" needs the stock odm/bin/nvt_test_hal in /data/local/tmp and only
# reports MEMC scenes (super resolution runs in a different kernel state).
FM=vendor.xiaomi.hardware.framemaster.IFrameMaster/default
fm() { service call $FM 1 i32 "$1" i32 "$2" i32 "$3" s16 "$4" s16 null >/dev/null; }
case "$1" in
  on)
    IN=${2:-60}
    fm 3 1 120 "\"Category:0,InputFPS:$IN,TargetFPS:120,MEMC:1,MEMCMode:0x2214\""
    echo "game MEMC on (${IN} -> 120 fps)";;
  video)
    # Stock YouTube profile (odm/etc/display/ui_service_cloud_config.xml)
    fm 2 1 120 '"Category:1,MEMC:1,MEMCMode:2,TargetFPS:60,LDSR:1,LDSRMode:3,LDSRV2Mode:0x22,SDR2HDR:1,SDR2HDRMode:0x636"'
    echo "video MEMC on (stock YouTube profile: MEMC + super resolution + SDR2HDR)";;
  videomemc)
    # Same, frame insertion only
    fm 2 1 120 '"Category:1,MEMC:1,MEMCMode:2,TargetFPS:60"'
    echo "video MEMC on (frame insertion only)";;
  sr)
    # Upscaler only: super resolution from the stock YouTube profile, no MEMC
    fm 2 1 120 '"Category:1,MEMC:0,TargetFPS:60,LDSR:1,LDSRMode:3,LDSRV2Mode:0x22"'
    echo "video super resolution on (no frame insertion)";;
  hdr)
    # SDR to HDR only, from the stock YouTube profile
    fm 2 1 120 '"Category:1,MEMC:0,TargetFPS:60,SDR2HDR:1,SDR2HDRMode:0x636"'
    echo "video SDR2HDR on (no frame insertion)";;
  off)
    fm 3 0 120 '"SceneID:0000"'
    fm 2 0 120 '"SceneID:0000"'
    echo "MEMC off";;
  status)
    cd /data/local/tmp && printf '1\n5\n0\n0\n' | LD_LIBRARY_PATH=/odm/lib64:/system/lib64:/vendor/lib64 ./nvt_test_hal 2>/dev/null | grep -o 'ret = 0x[0-9a-fA-F-]*' | sed 's/ret = 0x00000000/scene 0x0 (bypass, OFF)/; s/ret = 0x/scene 0x/'
    dumpsys SurfaceFlinger 2>/dev/null | grep -m1 -o 'vsyncRate=[0-9.]* Hz' | sed 's/^/display output /';;
  *) echo "usage: memc.sh on [inputfps] | video | videomemc | off | status";;
esac
