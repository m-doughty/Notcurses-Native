/*
 * codec-probe.c — release gate that verifies the just-built bundle's
 * libavcodec was actually configured with the accelerated codec libs
 * we depend on (libdav1d, libvpx, libopus). Catches the silent
 * regression class where ffmpeg's configure dropped --enable-libfoo
 * (e.g. a pkg-config lookup failed at build time and ffmpeg fell
 * back to its internal-decoder-only build), shipping a bundle whose
 * size + linkage looks correct but whose AV1 video decode is ~10x
 * slower because libdav1d isn't actually wired in.
 *
 * Approach: dlopen libavcodec from the bundle path, then for each
 * required decoder name call avcodec_find_decoder_by_name(). That
 * function returns NULL when the decoder isn't compiled in, even
 * if the codec_id is recognized by libavcodec — which is exactly
 * the failure mode we want to catch.
 *
 * Why dlopen (not link-time): we'd need libavcodec headers + the
 * versioned dylib import lib to compile. dlopen lets the probe
 * link nothing and find the lib at runtime via the bundle's
 * directory. The probe runs cross-platform (Linux .so, macOS .dylib,
 * Windows .dll) with one source file.
 *
 * Run: scripts/ci/run-codec-probe.sh handles compile + LIBPATH env.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#  include <windows.h>
   typedef HMODULE dlh_t;
#  define DL_OPEN(p)    LoadLibraryA(p)
#  define DL_SYM(h,s)   ((void *)GetProcAddress(h, s))
#  define DL_CLOSE(h)   FreeLibrary(h)
#else
#  include <dlfcn.h>
   typedef void *dlh_t;
#  define DL_OPEN(p)    dlopen(p, RTLD_NOW | RTLD_GLOBAL)
#  define DL_SYM(h,s)   dlsym(h, s)
#  define DL_CLOSE(h)   dlclose(h)
#endif

/* Forward-declare libavcodec's AVCodec opaquely; we only need a
 * non-NULL/NULL test on the find_decoder_by_name return. */
typedef struct AVCodec AVCodec;
typedef const AVCodec *(*find_decoder_fn)(const char *);

/* Required accelerated decoders. If any is missing, ffmpeg was
 * built without the matching --enable-libfoo and AV1/VP8/VP9/Opus
 * fall back to internal decoders (functional but ~10× slower for
 * AV1 specifically). */
static const char *REQUIRED_DECODERS[] = {
    "libdav1d",
    "libvpx_vp8",
    "libvpx_vp9",
    "libopus",
    NULL,
};

/* Try multiple candidate filenames — bundling tools may produce
 * versioned-only files (libavcodec.60.dylib) without symlinks. */
static const char *CANDIDATES[] = {
#if defined(_WIN32)
    "avcodec-62.dll", "avcodec-61.dll", "avcodec-60.dll",
    "libavcodec-62.dll", "libavcodec-61.dll", "libavcodec-60.dll",
    "avcodec.dll", "libavcodec.dll",
#elif defined(__APPLE__)
    "libavcodec.dylib",
    "libavcodec.62.dylib", "libavcodec.61.dylib", "libavcodec.60.dylib",
#else  /* Linux + everything else */
    "libavcodec.so",
    "libavcodec.so.62", "libavcodec.so.61", "libavcodec.so.60",
#endif
    NULL,
};

static const char *dl_error(void) {
#ifdef _WIN32
    static char buf[256];
    DWORD code = GetLastError();
    FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM, NULL, code, 0,
                   buf, sizeof(buf), NULL);
    return buf;
#else
    return dlerror();
#endif
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;

    /* Try each candidate name until one loads. Note we prefix with
     * "./" so dlopen / LoadLibrary searches CWD specifically rather
     * than walking system paths (where a host-installed libavcodec
     * could mask the bundled one and produce a green probe against
     * the wrong lib). The wrapper script chdir's into bundle/. */
    dlh_t handle = NULL;
    const char *loaded_name = NULL;
    for (int i = 0; CANDIDATES[i]; i++) {
        char path[512];
        snprintf(path, sizeof(path), "./%s", CANDIDATES[i]);
        handle = DL_OPEN(path);
        if (handle) { loaded_name = CANDIDATES[i]; break; }
    }
    if (!handle) {
        fprintf(stderr, "FAIL: couldn't load libavcodec from CWD.\n");
        fprintf(stderr, "  Last dlopen error: %s\n", dl_error());
        fprintf(stderr, "  Tried: ");
        for (int i = 0; CANDIDATES[i]; i++) fprintf(stderr, "%s ", CANDIDATES[i]);
        fprintf(stderr, "\n  Check that run-codec-probe.sh chdir'd into bundle/\n");
        fprintf(stderr, "  and that the bundle contains libavcodec.\n");
        return 2;
    }
    printf("Loaded libavcodec via: %s\n", loaded_name);

    find_decoder_fn find = (find_decoder_fn)DL_SYM(handle, "avcodec_find_decoder_by_name");
    if (!find) {
        fprintf(stderr, "FAIL: dlsym(avcodec_find_decoder_by_name) returned NULL.\n");
        fprintf(stderr, "  Error: %s\n", dl_error());
        fprintf(stderr, "  This is a corrupted libavcodec or a major ABI mismatch.\n");
        DL_CLOSE(handle);
        return 3;
    }

    int fail = 0;
    for (int i = 0; REQUIRED_DECODERS[i]; i++) {
        const char *name = REQUIRED_DECODERS[i];
        const AVCodec *c = find(name);
        if (!c) {
            fprintf(stderr, "❌ MISSING: decoder '%s'\n", name);
            fail = 1;
        } else {
            printf("✅ present:  decoder '%s'\n", name);
        }
    }

    DL_CLOSE(handle);

    if (fail) {
        fprintf(stderr, "\n────────────────────────────────────────────────────────\n");
        fprintf(stderr, "Bundle's libavcodec is missing one or more accelerated\n");
        fprintf(stderr, "decoders. Do NOT publish this artefact.\n\n");
        fprintf(stderr, "Likely cause: ffmpeg's configure stage dropped one of\n");
        fprintf(stderr, "  --enable-libdav1d / --enable-libvpx / --enable-libopus\n");
        fprintf(stderr, "because the corresponding pkg-config probe failed.\n");
        fprintf(stderr, "Inspect ffmpeg's config.log for `ERROR: <lib> not found`.\n");
        fprintf(stderr, "Also confirm scripts/ci/build-{libdav1d,libvpx,libopus}.sh\n");
        fprintf(stderr, "ran successfully before scripts/ci/build-ffmpeg.sh.\n");
        return 1;
    }

    printf("\n✅ All required accelerated decoders registered. Bundle is releasable.\n");
    return 0;
}
