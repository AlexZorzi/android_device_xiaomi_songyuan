// alstest - list sensors and stream chosen ones, including vendor-custom types.
//
// Built for diagnosing songyuan's ambient light sensor: the SSC declares a
// healthy ambient_light sensor but never emits, while ambient_light_raw streams
// fine. The theory under test is that the idle rear ALS (xiaomi.sensor.back_lux,
// type 33171055) has to be streaming before the under-display front sensor will
// publish.
//
//   alstest                  list every sensor
//   alstest <h> [h...]       stream those handles until Ctrl-C
//
#include <android/sensor.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <csignal>
#include <unistd.h>
#include <vector>

static volatile sig_atomic_t g_stop = 0;
static void on_sigint(int) { g_stop = 1; }

int main(int argc, char** argv) {
    signal(SIGINT, on_sigint);

    ASensorManager* mgr = ASensorManager_getInstanceForPackage("alstest");
    if (!mgr) mgr = ASensorManager_getInstance();
    if (!mgr) { fprintf(stderr, "no sensor manager\n"); return 1; }

    ASensorList list = nullptr;
    int n = ASensorManager_getSensorList(mgr, &list);
    if (n <= 0) { fprintf(stderr, "no sensors (%d)\n", n); return 1; }

    if (argc < 2) {
        printf("%-8s %-12s %-46s %-14s %10s %10s\n",
               "HANDLE", "TYPE", "NAME", "VENDOR", "MAXRANGE", "RESOLUTION");
        for (int i = 0; i < n; i++) {
            const ASensor* s = list[i];
            printf("0x%-6x %-12d %-46.46s %-14.14s %10.3f %10.4f\n",
                   ASensor_getHandle(s), ASensor_getType(s), ASensor_getName(s),
                   ASensor_getVendor(s), ASensor_getMinDelay(s) ? 0.0 : 0.0,
                   ASensor_getResolution(s));
        }
        printf("\n%d sensors. Pass handles (decimal or 0x..) to stream.\n", n);
        return 0;
    }

    std::vector<int> want;
    for (int a = 1; a < argc; a++) want.push_back((int)strtol(argv[a], nullptr, 0));

    ALooper* looper = ALooper_forThread();
    if (!looper) looper = ALooper_prepare(ALOOPER_PREPARE_ALLOW_NON_CALLBACKS);
    ASensorEventQueue* q = ASensorManager_createEventQueue(mgr, looper, 3, nullptr, nullptr);
    if (!q) { fprintf(stderr, "createEventQueue failed\n"); return 1; }

    int enabled = 0;
    for (int h : want) {
        const ASensor* target = nullptr;
        for (int i = 0; i < n; i++) if (ASensor_getHandle(list[i]) == h) { target = list[i]; break; }
        if (!target) { fprintf(stderr, "handle 0x%x not found\n", h); continue; }
        int rc = ASensorEventQueue_enableSensor(q, target);
        int rc2 = ASensorEventQueue_setEventRate(q, target, 100000); // 100ms
        fprintf(stderr, "enable 0x%x (%s) -> %d, rate -> %d\n",
                h, ASensor_getName(target), rc, rc2);
        if (rc == 0) enabled++;
    }
    if (!enabled) { fprintf(stderr, "nothing enabled\n"); return 1; }

    fprintf(stderr, "streaming, Ctrl-C to stop\n");
    while (!g_stop) {
        int id = ALooper_pollOnce(2000, nullptr, nullptr, nullptr);
        (void)id;
        ASensorEvent ev[64];
        ssize_t got;
        while ((got = ASensorEventQueue_getEvents(q, ev, 64)) > 0) {
            for (ssize_t i = 0; i < got; i++) {
                printf("h=0x%-5x t=%-5d ", ev[i].sensor, ev[i].type);
                for (int k = 0; k < 8; k++) printf("%10.3f ", ev[i].data[k]);
                printf("\n");
                fflush(stdout);
            }
        }
    }
    ASensorManager_destroyEventQueue(mgr, q);
    return 0;
}
