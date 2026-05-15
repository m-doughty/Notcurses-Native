/*
 * codec-probe.c — release gate. Loads the bundle's libavcodec +
 * libavutil at runtime via dlopen / LoadLibrary, then performs two
 * categories of check:
 *
 *   1. Accelerated decoder registration. avcodec_find_decoder_by_name
 *      must return non-NULL for "libdav1d", "libvpx", "libvpx-vp9",
 *      "libopus". Catches the regression class where ffmpeg's
 *      configure silently dropped --enable-libfoo (pkg-config probe
 *      failed at build time and ffmpeg fell back to internal-only
 *      decoders) — the bundle's size + linkage look correct but
 *      AV1 video would silently use the ~10× slower internal
 *      decoder.
 *
 *   2. Actual decode of PNG, JPEG, BMP fixtures. Reads
 *      $WORKSPACE_DIR/vendor/notcurses/data/{chunli44.png,
 *      tetris-background.jpg, warmech.bmp} into memory, feeds each
 *      to libavcodec's internal decoder for that format, requires
 *      a frame back. Catches:
 *        * ABI mismatch between bundled libavcodec / libavutil
 *          (decoders load but crash / error on actual decode).
 *        * Missing transitive deps that the registration check
 *          can't spot (e.g. zlib for PNG): bundle-audit catches
 *          this earlier but here is a second line of defense.
 *        * The general "bundle compiles + bundles + loads but
 *          can't actually decode anything" failure mode.
 *      GIF + WebP are not tested separately — if PNG / JPEG / BMP
 *      decode works, ffmpeg's internal decoders for similar simple
 *      image formats can be assumed working.
 *
 * Cross-platform: Linux (.so), macOS (.dylib), Windows (.dll).
 * Enumerates the CWD (bundle/) to find libavcodec + libavutil
 * regardless of versioning — the bundled files may be
 * libavcodec.62.28.100.dylib (no SONAME symlinks) or
 * libavcodec.so.60 (Linux SONAME-named) or avcodec-62.dll
 * (Windows). We dlopen whatever matches the prefix.
 *
 * Built standalone (no libavcodec headers required) — opaque
 * pointer types + dlsym for every function we need. AVPacket
 * data/size fields are set via av_packet_from_data() (an API
 * call) rather than direct struct access.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#ifdef _WIN32
#  include <windows.h>
   typedef HMODULE dlh_t;
#  define DL_OPEN(p)    LoadLibraryA(p)
#  define DL_SYM(h, s)  ((void *)GetProcAddress(h, s))
#  define DL_CLOSE(h)   (void)FreeLibrary(h)
#else
#  include <dlfcn.h>
#  include <dirent.h>
   typedef void *dlh_t;
#  define DL_OPEN(p)    dlopen(p, RTLD_NOW | RTLD_GLOBAL)
#  define DL_SYM(h, s)  dlsym(h, s)
#  define DL_CLOSE(h)   (void)dlclose(h)
#endif

/* ---------- forward-declared opaque types ---------- */
typedef struct AVCodec AVCodec;
typedef struct AVCodecContext AVCodecContext;
typedef struct AVPacket AVPacket;
typedef struct AVFrame AVFrame;
typedef struct AVDictionary AVDictionary;

/* ---------- function pointer types ---------- */
typedef const AVCodec    *(*fn_find_decoder_by_name_t)(const char *);
typedef AVCodecContext   *(*fn_alloc_context3_t)(const AVCodec *);
typedef int               (*fn_open2_t)(AVCodecContext *, const AVCodec *, AVDictionary **);
typedef void              (*fn_free_context_t)(AVCodecContext **);
typedef int               (*fn_send_packet_t)(AVCodecContext *, const AVPacket *);
typedef int               (*fn_receive_frame_t)(AVCodecContext *, AVFrame *);
typedef AVPacket         *(*fn_packet_alloc_t)(void);
typedef void              (*fn_packet_free_t)(AVPacket **);
typedef int               (*fn_packet_from_data_t)(AVPacket *, uint8_t *, int);
typedef AVFrame          *(*fn_frame_alloc_t)(void);
typedef void              (*fn_frame_free_t)(AVFrame **);
typedef void             *(*fn_av_malloc_t)(size_t);

/* AV_INPUT_BUFFER_PADDING_SIZE: documented constant, ffmpeg
 * requires this much zero-padding past the end of any packet data
 * buffer to allow optimized bitstream readers to read past the
 * end without segfaulting. ffmpeg 6.x: 64 bytes. */
#define AV_INPUT_BUFFER_PADDING_SIZE 64

/* AVERROR(EAGAIN) — decoder needs more input before producing a
 * frame. Single-image formats (PNG/JPEG/BMP) shouldn't return
 * EAGAIN since the entire image is one packet, but treat it as
 * neither success nor terminal failure. */

/* ---------- function pointer table ---------- */
struct ff_api {
    fn_find_decoder_by_name_t find_decoder_by_name;
    fn_alloc_context3_t       alloc_context3;
    fn_open2_t                open2;
    fn_free_context_t         free_context;
    fn_send_packet_t          send_packet;
    fn_receive_frame_t        receive_frame;
    fn_packet_alloc_t         packet_alloc;
    fn_packet_free_t          packet_free;
    fn_packet_from_data_t     packet_from_data;
    fn_frame_alloc_t          frame_alloc;
    fn_frame_free_t           frame_free;
    fn_av_malloc_t            av_malloc;
};

/* ---------- enumerate CWD for libavcodec / libavutil ----------
 *
 * The bundle's filenames vary by platform / build system:
 *   - macOS source-built ffmpeg: libavcodec.62.28.100.dylib (no
 *     SONAME symlink — full versioned name only).
 *   - macOS brew bottle: libavcodec.61.dylib (SONAME-named real file).
 *   - Linux: libavcodec.so.60 (SONAME-named real file).
 *   - Windows: avcodec-62.dll.
 * Enumerate CWD to find whichever name matches. */
static int starts_with(const char *s, const char *prefix) {
    return strncmp(s, prefix, strlen(prefix)) == 0;
}

static char enum_buf[512];

#ifdef _WIN32
static const char *find_lib(const char *prefix) {
    WIN32_FIND_DATAA fd;
    char pattern[256];
    snprintf(pattern, sizeof(pattern), "%s*.dll", prefix);
    HANDLE h = FindFirstFileA(pattern, &fd);
    if (h == INVALID_HANDLE_VALUE) return NULL;
    snprintf(enum_buf, sizeof(enum_buf), "%s", fd.cFileName);
    FindClose(h);
    return enum_buf;
}
#else
static const char *find_lib(const char *prefix) {
    DIR *d = opendir(".");
    if (!d) return NULL;
    struct dirent *e;
    const char *match = NULL;
    while ((e = readdir(d))) {
        if (starts_with(e->d_name, prefix)) {
            snprintf(enum_buf, sizeof(enum_buf), "%s", e->d_name);
            match = enum_buf;
            break;
        }
    }
    closedir(d);
    return match;
}
#endif

/* Platform-specific prefixes that uniquely identify each library
 * (with disambiguation against `libavutil` for libav, `libavcodec`
 * for libavcodec, etc. — `libav` alone would match both libavcodec
 * and libavutil ambiguously). */
#ifdef _WIN32
#  define AVCODEC_PREFIX "avcodec-"
#  define AVUTIL_PREFIX  "avutil-"
#elif defined(__APPLE__)
#  define AVCODEC_PREFIX "libavcodec."
#  define AVUTIL_PREFIX  "libavutil."
#else
#  define AVCODEC_PREFIX "libavcodec.so"
#  define AVUTIL_PREFIX  "libavutil.so"
#endif

static const char *dl_error_str(void) {
#ifdef _WIN32
    static char buf[256];
    DWORD code = GetLastError();
    FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                   NULL, code, 0, buf, sizeof(buf), NULL);
    return buf;
#else
    const char *e = dlerror();
    return e ? e : "(no error)";
#endif
}

/* Path prefix character. On Unix dlopen("foo") searches LD_LIBRARY_PATH
 * etc. but dlopen("./foo") strictly uses the relative path — what we
 * want to ensure we load from CWD. On Windows LoadLibrary("./foo")
 * also works but cwd-relative load needs CWD to be on the search
 * path; the wrapper script handles CWD setup. */
static dlh_t dlopen_cwd(const char *name) {
    char path[640];
#ifdef _WIN32
    /* Windows LoadLibrary searches via DLL search order; CWD is
     * included (Safe DLL Search mode notwithstanding, our wrapper
     * cd's into bundle/ before invoking the probe, and there are
     * no conflicting system avcodec/avutil DLLs to mask the
     * bundled ones). Pass the bare name. */
    snprintf(path, sizeof(path), "%s", name);
#else
    snprintf(path, sizeof(path), "./%s", name);
#endif
    return DL_OPEN(path);
}

/* ---------- decode test ---------- */
struct fixture {
    const char *display_name;
    const char *workspace_relpath;
    const char *decoder_name;  /* libavcodec internal decoder .name */
};

static int decode_fixture(struct ff_api *api, const struct fixture *fx,
                          const char *workspace_dir) {
    char full_path[1024];
    snprintf(full_path, sizeof(full_path), "%s/%s", workspace_dir, fx->workspace_relpath);

    FILE *f = fopen(full_path, "rb");
    if (!f) {
        fprintf(stderr, "    cannot open %s\n", full_path);
        return -1;
    }
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return -1; }
    long sz = ftell(f);
    if (sz <= 0) { fclose(f); return -1; }
    rewind(f);

    /* av_malloc so av_packet_from_data can take ownership and
     * av_packet_free can av_free it back. Heap allocated with
     * AV_INPUT_BUFFER_PADDING_SIZE bytes of zero padding past
     * the end — required by libavcodec's bitstream readers. */
    uint8_t *buf = (uint8_t *)api->av_malloc((size_t)sz + AV_INPUT_BUFFER_PADDING_SIZE);
    if (!buf) { fclose(f); return -1; }
    size_t read_n = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    if ((long)read_n != sz) return -1;
    memset(buf + sz, 0, AV_INPUT_BUFFER_PADDING_SIZE);

    const AVCodec *codec = api->find_decoder_by_name(fx->decoder_name);
    if (!codec) {
        fprintf(stderr, "    decoder '%s' not found\n", fx->decoder_name);
        /* buf is now owned by us; we never handed it to a packet. */
        /* No av_free dlsym'd; the leak is intentional, the probe
         * is a short-lived process. */
        return -1;
    }

    AVCodecContext *ctx = api->alloc_context3(codec);
    if (!ctx) return -1;
    if (api->open2(ctx, codec, NULL) < 0) {
        api->free_context(&ctx);
        return -1;
    }

    AVPacket *pkt = api->packet_alloc();
    AVFrame  *frame = api->frame_alloc();
    if (!pkt || !frame) {
        if (pkt) api->packet_free(&pkt);
        if (frame) api->frame_free(&frame);
        api->free_context(&ctx);
        return -1;
    }

    /* av_packet_from_data wraps buf into pkt. After this, pkt owns
     * buf; av_packet_free will av_free it. */
    if (api->packet_from_data(pkt, buf, (int)sz) < 0) {
        api->packet_free(&pkt);
        api->frame_free(&frame);
        api->free_context(&ctx);
        return -1;
    }

    int rc = api->send_packet(ctx, pkt);
    int got_frame = 0;
    if (rc >= 0) {
        rc = api->receive_frame(ctx, frame);
        if (rc >= 0) got_frame = 1;
    }

    api->packet_free(&pkt);
    api->frame_free(&frame);
    api->free_context(&ctx);
    return got_frame ? 0 : -1;
}

/* ---------- registration check ---------- */
static const char *REQUIRED_DECODERS[] = {
    "libdav1d",
    "libvpx",
    "libvpx-vp9",
    "libopus",
    NULL,
};

/* ---------- decode fixtures ---------- */
static const struct fixture FIXTURES[] = {
    { "PNG",  "vendor/notcurses/data/chunli44.png",          "png"   },
    { "JPEG", "vendor/notcurses/data/tetris-background.jpg", "mjpeg" },
    { "BMP",  "vendor/notcurses/data/warmech.bmp",           "bmp"   },
    { NULL, NULL, NULL }
};

int main(int argc, char **argv) {
    (void)argc;
    const char *workspace_dir = getenv("WORKSPACE_DIR");
    if (argc > 1) workspace_dir = argv[1];
    if (!workspace_dir || !*workspace_dir) {
        fprintf(stderr, "FAIL: WORKSPACE_DIR not set (and no argv[1] either).\n");
        fprintf(stderr, "  run-codec-probe.sh is supposed to set it to the\n");
        fprintf(stderr, "  workspace root before invoking the probe.\n");
        return 2;
    }

    /* ----- load libavcodec ----- */
    const char *avcodec_name = find_lib(AVCODEC_PREFIX);
    if (!avcodec_name) {
        fprintf(stderr, "FAIL: no libavcodec.* in CWD (\"%s\" prefix).\n",
                AVCODEC_PREFIX);
        fprintf(stderr, "  Wrapper script should have cd'd into bundle/.\n");
        return 2;
    }
    dlh_t avcodec_h = dlopen_cwd(avcodec_name);
    if (!avcodec_h) {
        fprintf(stderr, "FAIL: dlopen %s failed: %s\n", avcodec_name, dl_error_str());
        return 2;
    }
    printf("Loaded libavcodec via: %s\n", avcodec_name);

    /* ----- load libavutil (for av_malloc, av_frame_*) ----- */
    const char *avutil_name = find_lib(AVUTIL_PREFIX);
    if (!avutil_name) {
        fprintf(stderr, "FAIL: no libavutil.* in CWD (\"%s\" prefix).\n",
                AVUTIL_PREFIX);
        return 2;
    }
    dlh_t avutil_h = dlopen_cwd(avutil_name);
    if (!avutil_h) {
        fprintf(stderr, "FAIL: dlopen %s failed: %s\n", avutil_name, dl_error_str());
        return 2;
    }
    printf("Loaded libavutil  via: %s\n", avutil_name);

    /* ----- resolve symbols. On Linux/macOS RTLD_GLOBAL puts
     * everything in the default namespace so either handle works,
     * but on Windows GetProcAddress is strictly per-DLL — use the
     * right handle for each symbol. ----- */
    struct ff_api api = {0};
    api.find_decoder_by_name = (fn_find_decoder_by_name_t) DL_SYM(avcodec_h, "avcodec_find_decoder_by_name");
    api.alloc_context3       = (fn_alloc_context3_t)       DL_SYM(avcodec_h, "avcodec_alloc_context3");
    api.open2                = (fn_open2_t)                DL_SYM(avcodec_h, "avcodec_open2");
    api.free_context         = (fn_free_context_t)         DL_SYM(avcodec_h, "avcodec_free_context");
    api.send_packet          = (fn_send_packet_t)          DL_SYM(avcodec_h, "avcodec_send_packet");
    api.receive_frame        = (fn_receive_frame_t)        DL_SYM(avcodec_h, "avcodec_receive_frame");
    api.packet_alloc         = (fn_packet_alloc_t)         DL_SYM(avcodec_h, "av_packet_alloc");
    api.packet_free          = (fn_packet_free_t)          DL_SYM(avcodec_h, "av_packet_free");
    api.packet_from_data     = (fn_packet_from_data_t)     DL_SYM(avcodec_h, "av_packet_from_data");
    api.frame_alloc          = (fn_frame_alloc_t)          DL_SYM(avutil_h,  "av_frame_alloc");
    api.frame_free           = (fn_frame_free_t)           DL_SYM(avutil_h,  "av_frame_free");
    api.av_malloc            = (fn_av_malloc_t)            DL_SYM(avutil_h,  "av_malloc");

#define CHECK_SYM(field, name) \
    do { if (!api.field) { \
        fprintf(stderr, "FAIL: dlsym(%s) returned NULL\n", name); return 3; } } while (0)
    CHECK_SYM(find_decoder_by_name, "avcodec_find_decoder_by_name");
    CHECK_SYM(alloc_context3,       "avcodec_alloc_context3");
    CHECK_SYM(open2,                "avcodec_open2");
    CHECK_SYM(free_context,         "avcodec_free_context");
    CHECK_SYM(send_packet,          "avcodec_send_packet");
    CHECK_SYM(receive_frame,        "avcodec_receive_frame");
    CHECK_SYM(packet_alloc,         "av_packet_alloc");
    CHECK_SYM(packet_free,          "av_packet_free");
    CHECK_SYM(packet_from_data,     "av_packet_from_data");
    CHECK_SYM(frame_alloc,          "av_frame_alloc");
    CHECK_SYM(frame_free,           "av_frame_free");
    CHECK_SYM(av_malloc,            "av_malloc");
#undef CHECK_SYM

    int fail = 0;

    /* ----- check 1: accelerated decoder registration ----- */
    printf("\n── Check 1: accelerated decoder registration ──\n");
    for (int i = 0; REQUIRED_DECODERS[i]; i++) {
        const AVCodec *c = api.find_decoder_by_name(REQUIRED_DECODERS[i]);
        if (!c) {
            fprintf(stderr, "❌ MISSING decoder: %s\n", REQUIRED_DECODERS[i]);
            fail = 1;
        } else {
            printf("✅ registered: %s\n", REQUIRED_DECODERS[i]);
        }
    }

    /* ----- check 2: actual decode of common image formats ----- */
    printf("\n── Check 2: decode common image formats ──\n");
    for (int i = 0; FIXTURES[i].display_name; i++) {
        printf("  decoding %s (%s)...\n", FIXTURES[i].display_name,
               FIXTURES[i].workspace_relpath);
        if (decode_fixture(&api, &FIXTURES[i], workspace_dir) == 0) {
            printf("  ✅ %s decoded successfully\n", FIXTURES[i].display_name);
        } else {
            fprintf(stderr, "  ❌ %s FAILED to decode\n", FIXTURES[i].display_name);
            fail = 1;
        }
    }

    DL_CLOSE(avcodec_h);
    DL_CLOSE(avutil_h);

    if (fail) {
        fprintf(stderr, "\n────────────────────────────────────────────────────────\n");
        fprintf(stderr, "Bundle is NOT releasable. Investigate failures above.\n");
        fprintf(stderr, "\nCommon causes:\n");
        fprintf(stderr, "  * Decoder missing → ffmpeg's configure dropped\n");
        fprintf(stderr, "    --enable-libfoo. Check scripts/ci/build-ffmpeg.sh\n");
        fprintf(stderr, "    flags and that build-{libdav1d,libvpx,libopus}.sh\n");
        fprintf(stderr, "    ran successfully before it.\n");
        fprintf(stderr, "  * Decode failed → ABI mismatch between bundled\n");
        fprintf(stderr, "    libavcodec / libavutil (mixed source-build +\n");
        fprintf(stderr, "    cached versions). Wipe _ci-cache/ and rebuild.\n");
        return 1;
    }

    printf("\n✅ All checks passed — bundle is releasable.\n");
    return 0;
}
