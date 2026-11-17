#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    const char *libraries[] = {
        "libnotcurses-core.dylib",
        "libnotcurses.dylib",
        "libnotcurses-ffi.dylib",
        "libnotcurses_native_shim.dylib",
    };
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <absolute bundle directory>\n", argv[0]);
        return EXIT_FAILURE;
    }

    // Keep core globally available for the shim's dynamic lookup, as
    // ensure-shim-loadable does via the binding's notcurses_version.
    for (size_t i = 0; i < sizeof(libraries) / sizeof(libraries[0]); i++) {
        char path[4096];
        int length = snprintf(path, sizeof(path), "%s/%s", argv[1], libraries[i]);
        if (length < 0 || (size_t)length >= sizeof(path)) {
            fprintf(stderr, "Dylib path is too long: %s/%s\n", argv[1], libraries[i]);
            return EXIT_FAILURE;
        }
        void *handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
        if (!handle) {
            fprintf(stderr, "dlopen failed for %s: %s\n", path, dlerror());
            return EXIT_FAILURE;
        }
        printf("Loaded %s\n", path);
    }

    // The executable is image zero. All other images must come from
    // the extracted archive or the operating system.
    size_t prefix_length = strlen(argv[1]);
    for (uint32_t i = 1; i < _dyld_image_count(); i++) {
        const char *path = _dyld_get_image_name(i);
        if ((strncmp(path, argv[1], prefix_length) == 0 && path[prefix_length] == '/') ||
            strncmp(path, "/usr/lib/", sizeof("/usr/lib/") - 1) == 0 ||
            strncmp(path, "/System/Library/", sizeof("/System/Library/") - 1) == 0) {
            continue;
        }
        fprintf(stderr, "Loaded dylib from outside the archive or OS: %s\n", path);
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
