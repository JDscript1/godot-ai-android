/* Small PIE executable packaged as a native library for the Android exec probe.
 * This does not contain PRoot or Blender. Keep output bounded for the IPC reply. */
#include <stdio.h>
#include <sys/utsname.h>
#include <unistd.h>

int main(void) {
    struct utsname system;
    if (uname(&system) != 0) {
        return 2;
    }
    printf("AI_RUNTIME_PROBE_V1 pid=%ld uid=%ld arch=%s\n",
            (long)getpid(), (long)getuid(), system.machine);
    return 0;
}
