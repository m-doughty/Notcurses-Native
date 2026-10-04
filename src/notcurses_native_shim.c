/*
 * notcurses_native_shim.c — high-throughput batched primitives that
 * are too slow to express call-per-cell over the Raku NativeCall
 * boundary.
 *
 * The headline primitive is `notcurses_native_copy_cells`, a direct
 * port of Selkie::Widget::ViewportedCardList's per-cell read+write
 * loop. ViewportedCardList copies a slice of one ncplane onto
 * another (its visible self.plane) once per visible card-subtree
 * widget per frame; with five visible cards, each composed of five
 * widget planes averaging 30 rows × 100 cols, the Raku version
 * makes ~75,000 NativeCall trips per render. ncplane_mergedown
 * looks like a one-call replacement but composites at absolute
 * pile coordinates rather than at the scroll-translated dst we
 * need (see ViewportedCardList.rakumod's !copy-cells Pod6 for the
 * full investigation), so the path is C with the loop in C.
 *
 * The other resident is the terminal restore guard
 * (`notcurses_native_arm_terminal_guard` and its disarm), which is
 * here for a different reason: it has to be C because it runs from
 * an atexit(3) handler, the one cleanup hook that still fires when
 * the VM exits without running a line of Raku. Its own comment block
 * below has the full story.
 *
 * The third is the ABI table (`notcurses_native_abi_*`): the sizes,
 * offsets and constant values the Raku bindings mirror, as the compiler
 * sees them in the headers this shim is built against, for t/42 to hold
 * the bindings to. Its own comment block has the details.
 *
 * Symbols are prefixed `notcurses_native_` to stay out of
 * notcurses's namespace.
 *
 * Build: two paths compile this file, and they agree on flags.
 * Build.rakumod's !try-compile-shim builds it on the installing
 * machine; CI builds it into the published bundle, on macOS and
 * Windows from a workflow step and on Linux from the tail of
 * scripts/ci/build-linux-{glibc,musl}.sh, inside the container.
 *
 * Only macOS leaves notcurses unresolved at link time
 * (-undefined dynamic_lookup), so there the symbols bind at
 * runtime against whatever libnotcurses the host process has
 * already loaded through Notcurses::Native's FFI bindings.
 * Linux and Windows both link the core library: Linux with
 * -lnotcurses-core plus an $ORIGIN runpath so NEEDED resolves to
 * the patched core shipped beside it, Windows against the
 * import lib because neither MinGW nor MSVC has an equivalent of
 * dynamic_lookup. Do not "simplify" Linux to the macOS model —
 * resolving against the pack's own core rather than the host's
 * is the point, and an earlier attempt using
 * -Wl,--unresolved-symbols=ignore-in-shared-libs is recorded in
 * Build.rakumod as not doing what it looks like it does.
 */

/*
 * notcurses.h's inline functions (NCCELL_INITIALIZER,
 * ncplane_putwstr_aligned, etc.) call wcwidth() / wcswidth() from
 * <wchar.h>. glibc only exposes those when _GNU_SOURCE,
 * _XOPEN_SOURCE >= 500, or _POSIX_C_SOURCE >= 200809L is defined
 * before any system header is pulled in. Without one, gcc 14+ now
 * errors on the implicit declaration (gcc 14 promoted
 * -Wimplicit-function-declaration to error by default as part of
 * its C23 conformance push). Define _GNU_SOURCE up-front so every
 * consumer compile path (CI prebuilt + Build.rakumod's
 * source-build fallback + manual user builds) sees wcwidth
 * declared. No-op on musl / macOS libc / Windows MSVCRT-UCRT.
 */
#define _GNU_SOURCE

#include <stddef.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <notcurses/notcurses.h>

/* The terminal restore guard's platform halves (see its block below).
 * Both sides need only libc / kernel32, so the shim keeps its
 * link-time independence from libnotcurses. */
#ifdef _WIN32
#include <windows.h>
#else
#include <errno.h>
#include <fcntl.h>
#include <termios.h>
#include <unistd.h>
#endif

/* ------------------------------------------------------------------
 * ABI table.
 *
 * Notcurses::Native mirrors notcurses's structs as Raku CStruct classes
 * and its #defines and enums as Raku constants, all written out by hand.
 * Nothing but a test ties them to the headers, and until 0.6.7 nothing
 * did: NCSTYLE_STRUCK was a bit notcurses does not define,
 * NCOPTION_CLI_MODE the wrong mask, and Timespec the wrong layout on
 * Windows, each for several releases.
 *
 * This table is that test's ground truth, computed by the compiler from
 * the headers the shim is built against: every mirrored struct's size,
 * and every mirrored field's offset and width, and the value of every
 * mirrored constant. t/42-abi-guard compares the Raku side against it
 * entry by entry and fails on any difference — and on any Raku struct,
 * field or constant the table does not cover, so a new binding cannot
 * land unguarded.
 *
 * Three fixed-arity accessors (no varargs, no structs by value, nothing
 * for the caller to free):
 *
 *   size_t      notcurses_native_abi_count(void)
 *   const char* notcurses_native_abi_key(size_t i)    static; NULL past the end
 *   int64_t     notcurses_native_abi_value(size_t i)  INT64_MIN past the end
 *
 * Keys:
 *   size:<struct>                 sizeof(struct <struct>)
 *   offset:<struct>.<member>      offsetof(struct <struct>, <member>)
 *   width:<struct>.<member>       sizeof the member
 *   width-long:<struct>.<member>  the same, for a member C declares
 *                                 `long` (4 bytes on Windows, 8 elsewhere)
 *   const:<NAME>                  the constant's value, as int64_t
 *   platform:sizeof-long          sizeof(long), for reading width-long
 *
 * <member> is a C member designator: `utf8[3]`, `shortcut.eff_text[1]`.
 *
 * Compiling this file with NOTCURSES_NATIVE_ABI_TABLE_ONLY defined keeps
 * this section and drops everything after it, so the table builds with
 * nothing but the notcurses headers: scripts/abi/abi-probe.c includes it
 * that way to regenerate t/fixtures/abi-table.tsv, which t/42 checks
 * against when no shim carrying the table is installed.
 * ------------------------------------------------------------------ */

#include <notcurses/direct.h>

struct notcurses_native_abi_entry {
    const char* key;
    int64_t value;
};

#define NN_ABI_SIZE(st) \
    { "size:" #st, (int64_t)sizeof(struct st) }
#define NN_ABI_FIELD(st, member) \
    { "offset:" #st "." #member, (int64_t)offsetof(struct st, member) }, \
    { "width:" #st "." #member, (int64_t)sizeof(((struct st*)0)->member) }
#define NN_ABI_FIELD_CLONG(st, member) \
    { "offset:" #st "." #member, (int64_t)offsetof(struct st, member) }, \
    { "width-long:" #st "." #member, (int64_t)sizeof(((struct st*)0)->member) }
#define NN_ABI_CONST(name) \
    { "const:" #name, (int64_t)(name) }

static const struct notcurses_native_abi_entry notcurses_native_abi_table[] = {
    { "platform:sizeof-long", (int64_t)sizeof(long) },

    /* struct notcurses_options */
    NN_ABI_SIZE(notcurses_options),
    NN_ABI_FIELD(notcurses_options, termtype),
    NN_ABI_FIELD(notcurses_options, loglevel),
    NN_ABI_FIELD(notcurses_options, margin_t),
    NN_ABI_FIELD(notcurses_options, margin_r),
    NN_ABI_FIELD(notcurses_options, margin_b),
    NN_ABI_FIELD(notcurses_options, margin_l),
    NN_ABI_FIELD(notcurses_options, flags),
    /* struct ncplane_options */
    NN_ABI_SIZE(ncplane_options),
    NN_ABI_FIELD(ncplane_options, y),
    NN_ABI_FIELD(ncplane_options, x),
    NN_ABI_FIELD(ncplane_options, rows),
    NN_ABI_FIELD(ncplane_options, cols),
    NN_ABI_FIELD(ncplane_options, userptr),
    NN_ABI_FIELD(ncplane_options, name),
    NN_ABI_FIELD(ncplane_options, resizecb),
    NN_ABI_FIELD(ncplane_options, flags),
    NN_ABI_FIELD(ncplane_options, margin_b),
    NN_ABI_FIELD(ncplane_options, margin_r),
    /* struct nccell */
    NN_ABI_SIZE(nccell),
    NN_ABI_FIELD(nccell, gcluster),
    NN_ABI_FIELD(nccell, gcluster_backstop),
    NN_ABI_FIELD(nccell, width),
    NN_ABI_FIELD(nccell, stylemask),
    NN_ABI_FIELD(nccell, channels),
    /* struct ncinput */
    NN_ABI_SIZE(ncinput),
    NN_ABI_FIELD(ncinput, id),
    NN_ABI_FIELD(ncinput, y),
    NN_ABI_FIELD(ncinput, x),
    NN_ABI_FIELD(ncinput, utf8[0]),
    NN_ABI_FIELD(ncinput, utf8[1]),
    NN_ABI_FIELD(ncinput, utf8[2]),
    NN_ABI_FIELD(ncinput, utf8[3]),
    NN_ABI_FIELD(ncinput, utf8[4]),
    NN_ABI_FIELD(ncinput, alt),
    NN_ABI_FIELD(ncinput, shift),
    NN_ABI_FIELD(ncinput, ctrl),
    NN_ABI_FIELD(ncinput, evtype),
    NN_ABI_FIELD(ncinput, modifiers),
    NN_ABI_FIELD(ncinput, ypx),
    NN_ABI_FIELD(ncinput, xpx),
    NN_ABI_FIELD(ncinput, eff_text[0]),
    NN_ABI_FIELD(ncinput, eff_text[1]),
    NN_ABI_FIELD(ncinput, eff_text[2]),
    NN_ABI_FIELD(ncinput, eff_text[3]),
    /* struct timespec */
    NN_ABI_SIZE(timespec),
    NN_ABI_FIELD(timespec, tv_sec),
    /* C `long`: 4 bytes on Windows (LLP64), 8 elsewhere */
    NN_ABI_FIELD_CLONG(timespec, tv_nsec),
    /* struct nccapabilities */
    NN_ABI_SIZE(nccapabilities),
    NN_ABI_FIELD(nccapabilities, colors),
    NN_ABI_FIELD(nccapabilities, utf8),
    NN_ABI_FIELD(nccapabilities, rgb),
    NN_ABI_FIELD(nccapabilities, can_change_colors),
    NN_ABI_FIELD(nccapabilities, halfblocks),
    NN_ABI_FIELD(nccapabilities, quadrants),
    NN_ABI_FIELD(nccapabilities, sextants),
    NN_ABI_FIELD(nccapabilities, octants),
    NN_ABI_FIELD(nccapabilities, braille),
    /* struct ncstats */
    NN_ABI_SIZE(ncstats),
    NN_ABI_FIELD(ncstats, renders),
    NN_ABI_FIELD(ncstats, writeouts),
    NN_ABI_FIELD(ncstats, failed_renders),
    NN_ABI_FIELD(ncstats, failed_writeouts),
    NN_ABI_FIELD(ncstats, raster_bytes),
    NN_ABI_FIELD(ncstats, raster_max_bytes),
    NN_ABI_FIELD(ncstats, raster_min_bytes),
    NN_ABI_FIELD(ncstats, render_ns),
    NN_ABI_FIELD(ncstats, render_max_ns),
    NN_ABI_FIELD(ncstats, render_min_ns),
    NN_ABI_FIELD(ncstats, raster_ns),
    NN_ABI_FIELD(ncstats, raster_max_ns),
    NN_ABI_FIELD(ncstats, raster_min_ns),
    NN_ABI_FIELD(ncstats, writeout_ns),
    NN_ABI_FIELD(ncstats, writeout_max_ns),
    NN_ABI_FIELD(ncstats, writeout_min_ns),
    NN_ABI_FIELD(ncstats, cellelisions),
    NN_ABI_FIELD(ncstats, cellemissions),
    NN_ABI_FIELD(ncstats, fgelisions),
    NN_ABI_FIELD(ncstats, fgemissions),
    NN_ABI_FIELD(ncstats, bgelisions),
    NN_ABI_FIELD(ncstats, bgemissions),
    NN_ABI_FIELD(ncstats, defaultelisions),
    NN_ABI_FIELD(ncstats, defaultemissions),
    NN_ABI_FIELD(ncstats, refreshes),
    NN_ABI_FIELD(ncstats, sprixelemissions),
    NN_ABI_FIELD(ncstats, sprixelelisions),
    NN_ABI_FIELD(ncstats, sprixelbytes),
    NN_ABI_FIELD(ncstats, appsync_updates),
    NN_ABI_FIELD(ncstats, input_errors),
    NN_ABI_FIELD(ncstats, input_events),
    NN_ABI_FIELD(ncstats, hpa_gratuitous),
    NN_ABI_FIELD(ncstats, cell_geo_changes),
    NN_ABI_FIELD(ncstats, pixel_geo_changes),
    NN_ABI_FIELD(ncstats, fbbytes),
    NN_ABI_FIELD(ncstats, planes),
    /* struct ncvgeom */
    NN_ABI_SIZE(ncvgeom),
    NN_ABI_FIELD(ncvgeom, pixy),
    NN_ABI_FIELD(ncvgeom, pixx),
    NN_ABI_FIELD(ncvgeom, cdimy),
    NN_ABI_FIELD(ncvgeom, cdimx),
    NN_ABI_FIELD(ncvgeom, rpixy),
    NN_ABI_FIELD(ncvgeom, rpixx),
    NN_ABI_FIELD(ncvgeom, rcelly),
    NN_ABI_FIELD(ncvgeom, rcellx),
    NN_ABI_FIELD(ncvgeom, scaley),
    NN_ABI_FIELD(ncvgeom, scalex),
    NN_ABI_FIELD(ncvgeom, begy),
    NN_ABI_FIELD(ncvgeom, begx),
    NN_ABI_FIELD(ncvgeom, leny),
    NN_ABI_FIELD(ncvgeom, lenx),
    NN_ABI_FIELD(ncvgeom, maxpixely),
    NN_ABI_FIELD(ncvgeom, maxpixelx),
    NN_ABI_FIELD(ncvgeom, blitter),
    /* struct ncvisual_options */
    NN_ABI_SIZE(ncvisual_options),
    NN_ABI_FIELD(ncvisual_options, n),
    NN_ABI_FIELD(ncvisual_options, scaling),
    NN_ABI_FIELD(ncvisual_options, y),
    NN_ABI_FIELD(ncvisual_options, x),
    NN_ABI_FIELD(ncvisual_options, begy),
    NN_ABI_FIELD(ncvisual_options, begx),
    NN_ABI_FIELD(ncvisual_options, leny),
    NN_ABI_FIELD(ncvisual_options, lenx),
    NN_ABI_FIELD(ncvisual_options, blitter),
    NN_ABI_FIELD(ncvisual_options, flags),
    NN_ABI_FIELD(ncvisual_options, transcolor),
    NN_ABI_FIELD(ncvisual_options, pxoffy),
    NN_ABI_FIELD(ncvisual_options, pxoffx),
    /* struct ncreel_options */
    NN_ABI_SIZE(ncreel_options),
    NN_ABI_FIELD(ncreel_options, bordermask),
    NN_ABI_FIELD(ncreel_options, borderchan),
    NN_ABI_FIELD(ncreel_options, tabletmask),
    NN_ABI_FIELD(ncreel_options, tabletchan),
    NN_ABI_FIELD(ncreel_options, focusedchan),
    NN_ABI_FIELD(ncreel_options, flags),
    /* struct ncselector_item */
    NN_ABI_SIZE(ncselector_item),
    NN_ABI_FIELD(ncselector_item, option),
    NN_ABI_FIELD(ncselector_item, desc),
    /* struct ncselector_options */
    NN_ABI_SIZE(ncselector_options),
    NN_ABI_FIELD(ncselector_options, title),
    NN_ABI_FIELD(ncselector_options, secondary),
    NN_ABI_FIELD(ncselector_options, footer),
    NN_ABI_FIELD(ncselector_options, items),
    NN_ABI_FIELD(ncselector_options, defidx),
    NN_ABI_FIELD(ncselector_options, maxdisplay),
    NN_ABI_FIELD(ncselector_options, opchannels),
    NN_ABI_FIELD(ncselector_options, descchannels),
    NN_ABI_FIELD(ncselector_options, titlechannels),
    NN_ABI_FIELD(ncselector_options, footchannels),
    NN_ABI_FIELD(ncselector_options, boxchannels),
    NN_ABI_FIELD(ncselector_options, flags),
    /* struct ncmselector_item */
    NN_ABI_SIZE(ncmselector_item),
    NN_ABI_FIELD(ncmselector_item, option),
    NN_ABI_FIELD(ncmselector_item, desc),
    NN_ABI_FIELD(ncmselector_item, selected),
    /* struct ncmultiselector_options */
    NN_ABI_SIZE(ncmultiselector_options),
    NN_ABI_FIELD(ncmultiselector_options, title),
    NN_ABI_FIELD(ncmultiselector_options, secondary),
    NN_ABI_FIELD(ncmultiselector_options, footer),
    NN_ABI_FIELD(ncmultiselector_options, items),
    NN_ABI_FIELD(ncmultiselector_options, maxdisplay),
    NN_ABI_FIELD(ncmultiselector_options, opchannels),
    NN_ABI_FIELD(ncmultiselector_options, descchannels),
    NN_ABI_FIELD(ncmultiselector_options, titlechannels),
    NN_ABI_FIELD(ncmultiselector_options, footchannels),
    NN_ABI_FIELD(ncmultiselector_options, boxchannels),
    NN_ABI_FIELD(ncmultiselector_options, flags),
    /* struct nctree_item */
    NN_ABI_SIZE(nctree_item),
    NN_ABI_FIELD(nctree_item, curry),
    NN_ABI_FIELD(nctree_item, subs),
    NN_ABI_FIELD(nctree_item, subcount),
    /* struct nctree_options */
    NN_ABI_SIZE(nctree_options),
    NN_ABI_FIELD(nctree_options, items),
    NN_ABI_FIELD(nctree_options, count),
    NN_ABI_FIELD(nctree_options, nctreecb),
    NN_ABI_FIELD(nctree_options, indentcols),
    NN_ABI_FIELD(nctree_options, flags),
    /* struct ncmenu_item */
    NN_ABI_SIZE(ncmenu_item),
    NN_ABI_FIELD(ncmenu_item, desc),
    /* the embedded ncinput, flattened into shortcut_* on the Raku side */
    NN_ABI_FIELD(ncmenu_item, shortcut.id),
    NN_ABI_FIELD(ncmenu_item, shortcut.y),
    NN_ABI_FIELD(ncmenu_item, shortcut.x),
    NN_ABI_FIELD(ncmenu_item, shortcut.utf8[0]),
    NN_ABI_FIELD(ncmenu_item, shortcut.utf8[1]),
    NN_ABI_FIELD(ncmenu_item, shortcut.utf8[2]),
    NN_ABI_FIELD(ncmenu_item, shortcut.utf8[3]),
    NN_ABI_FIELD(ncmenu_item, shortcut.utf8[4]),
    NN_ABI_FIELD(ncmenu_item, shortcut.alt),
    NN_ABI_FIELD(ncmenu_item, shortcut.shift),
    NN_ABI_FIELD(ncmenu_item, shortcut.ctrl),
    NN_ABI_FIELD(ncmenu_item, shortcut.evtype),
    NN_ABI_FIELD(ncmenu_item, shortcut.modifiers),
    NN_ABI_FIELD(ncmenu_item, shortcut.ypx),
    NN_ABI_FIELD(ncmenu_item, shortcut.xpx),
    NN_ABI_FIELD(ncmenu_item, shortcut.eff_text[0]),
    NN_ABI_FIELD(ncmenu_item, shortcut.eff_text[1]),
    NN_ABI_FIELD(ncmenu_item, shortcut.eff_text[2]),
    NN_ABI_FIELD(ncmenu_item, shortcut.eff_text[3]),
    /* struct ncmenu_section */
    NN_ABI_SIZE(ncmenu_section),
    NN_ABI_FIELD(ncmenu_section, name),
    NN_ABI_FIELD(ncmenu_section, itemcount),
    NN_ABI_FIELD(ncmenu_section, items),
    /* the embedded ncinput, flattened into shortcut_* on the Raku side */
    NN_ABI_FIELD(ncmenu_section, shortcut.id),
    NN_ABI_FIELD(ncmenu_section, shortcut.y),
    NN_ABI_FIELD(ncmenu_section, shortcut.x),
    NN_ABI_FIELD(ncmenu_section, shortcut.utf8[0]),
    NN_ABI_FIELD(ncmenu_section, shortcut.utf8[1]),
    NN_ABI_FIELD(ncmenu_section, shortcut.utf8[2]),
    NN_ABI_FIELD(ncmenu_section, shortcut.utf8[3]),
    NN_ABI_FIELD(ncmenu_section, shortcut.utf8[4]),
    NN_ABI_FIELD(ncmenu_section, shortcut.alt),
    NN_ABI_FIELD(ncmenu_section, shortcut.shift),
    NN_ABI_FIELD(ncmenu_section, shortcut.ctrl),
    NN_ABI_FIELD(ncmenu_section, shortcut.evtype),
    NN_ABI_FIELD(ncmenu_section, shortcut.modifiers),
    NN_ABI_FIELD(ncmenu_section, shortcut.ypx),
    NN_ABI_FIELD(ncmenu_section, shortcut.xpx),
    NN_ABI_FIELD(ncmenu_section, shortcut.eff_text[0]),
    NN_ABI_FIELD(ncmenu_section, shortcut.eff_text[1]),
    NN_ABI_FIELD(ncmenu_section, shortcut.eff_text[2]),
    NN_ABI_FIELD(ncmenu_section, shortcut.eff_text[3]),
    /* struct ncmenu_options */
    NN_ABI_SIZE(ncmenu_options),
    NN_ABI_FIELD(ncmenu_options, sections),
    NN_ABI_FIELD(ncmenu_options, sectioncount),
    NN_ABI_FIELD(ncmenu_options, headerchannels),
    NN_ABI_FIELD(ncmenu_options, sectionchannels),
    NN_ABI_FIELD(ncmenu_options, flags),
    /* struct ncprogbar_options */
    NN_ABI_SIZE(ncprogbar_options),
    NN_ABI_FIELD(ncprogbar_options, ulchannel),
    NN_ABI_FIELD(ncprogbar_options, urchannel),
    NN_ABI_FIELD(ncprogbar_options, blchannel),
    NN_ABI_FIELD(ncprogbar_options, brchannel),
    NN_ABI_FIELD(ncprogbar_options, flags),
    /* struct nctabbed_options */
    NN_ABI_SIZE(nctabbed_options),
    NN_ABI_FIELD(nctabbed_options, selchan),
    NN_ABI_FIELD(nctabbed_options, hdrchan),
    NN_ABI_FIELD(nctabbed_options, sepchan),
    NN_ABI_FIELD(nctabbed_options, separator),
    NN_ABI_FIELD(nctabbed_options, flags),
    /* struct ncplot_options */
    NN_ABI_SIZE(ncplot_options),
    NN_ABI_FIELD(ncplot_options, maxchannels),
    NN_ABI_FIELD(ncplot_options, minchannels),
    NN_ABI_FIELD(ncplot_options, legendstyle),
    NN_ABI_FIELD(ncplot_options, gridtype),
    NN_ABI_FIELD(ncplot_options, rangex),
    NN_ABI_FIELD(ncplot_options, title),
    NN_ABI_FIELD(ncplot_options, flags),
    /* struct ncfdplane_options */
    NN_ABI_SIZE(ncfdplane_options),
    NN_ABI_FIELD(ncfdplane_options, curry),
    NN_ABI_FIELD(ncfdplane_options, follow),
    NN_ABI_FIELD(ncfdplane_options, flags),
    /* struct ncsubproc_options */
    NN_ABI_SIZE(ncsubproc_options),
    NN_ABI_FIELD(ncsubproc_options, curry),
    NN_ABI_FIELD(ncsubproc_options, restart_period),
    NN_ABI_FIELD(ncsubproc_options, flags),
    /* struct ncreader_options */
    NN_ABI_SIZE(ncreader_options),
    NN_ABI_FIELD(ncreader_options, tchannels),
    NN_ABI_FIELD(ncreader_options, tattrword),
    NN_ABI_FIELD(ncreader_options, flags),

    /* constants */
    NN_ABI_CONST(NCALIGN_BOTTOM),
    NN_ABI_CONST(NCALIGN_CENTER),
    NN_ABI_CONST(NCALIGN_LEFT),
    NN_ABI_CONST(NCALIGN_RIGHT),
    NN_ABI_CONST(NCALIGN_TOP),
    NN_ABI_CONST(NCALIGN_UNALIGNED),
    NN_ABI_CONST(NCALPHA_BLEND),
    NN_ABI_CONST(NCALPHA_HIGHCONTRAST),
    NN_ABI_CONST(NCALPHA_OPAQUE),
    NN_ABI_CONST(NCALPHA_TRANSPARENT),
    NN_ABI_CONST(NCBLIT_1x1),
    NN_ABI_CONST(NCBLIT_2x1),
    NN_ABI_CONST(NCBLIT_2x2),
    NN_ABI_CONST(NCBLIT_3x2),
    NN_ABI_CONST(NCBLIT_4x1),
    NN_ABI_CONST(NCBLIT_4x2),
    NN_ABI_CONST(NCBLIT_8x1),
    NN_ABI_CONST(NCBLIT_BRAILLE),
    NN_ABI_CONST(NCBLIT_DEFAULT),
    NN_ABI_CONST(NCBLIT_PIXEL),
    NN_ABI_CONST(NCBOXCORNER_MASK),
    NN_ABI_CONST(NCBOXCORNER_SHIFT),
    NN_ABI_CONST(NCBOXGRAD_BOTTOM),
    NN_ABI_CONST(NCBOXGRAD_LEFT),
    NN_ABI_CONST(NCBOXGRAD_RIGHT),
    NN_ABI_CONST(NCBOXGRAD_TOP),
    NN_ABI_CONST(NCBOXMASK_BOTTOM),
    NN_ABI_CONST(NCBOXMASK_LEFT),
    NN_ABI_CONST(NCBOXMASK_RIGHT),
    NN_ABI_CONST(NCBOXMASK_TOP),
    NN_ABI_CONST(NCDIRECT_OPTION_DRAIN_INPUT),
    NN_ABI_CONST(NCDIRECT_OPTION_INHIBIT_CBREAK),
    NN_ABI_CONST(NCDIRECT_OPTION_INHIBIT_SETLOCALE),
    NN_ABI_CONST(NCDIRECT_OPTION_NO_QUIT_SIGHANDLERS),
    NN_ABI_CONST(NCDIRECT_OPTION_VERBOSE),
    NN_ABI_CONST(NCDIRECT_OPTION_VERY_VERBOSE),
    NN_ABI_CONST(NCINPUT_MAX_EFF_TEXT_CODEPOINTS),
    NN_ABI_CONST(NCKEY_BACKSPACE),
    NN_ABI_CONST(NCKEY_BEGIN),
    NN_ABI_CONST(NCKEY_BUTTON1),
    NN_ABI_CONST(NCKEY_BUTTON10),
    NN_ABI_CONST(NCKEY_BUTTON11),
    NN_ABI_CONST(NCKEY_BUTTON2),
    NN_ABI_CONST(NCKEY_BUTTON3),
    NN_ABI_CONST(NCKEY_BUTTON4),
    NN_ABI_CONST(NCKEY_BUTTON5),
    NN_ABI_CONST(NCKEY_BUTTON6),
    NN_ABI_CONST(NCKEY_BUTTON7),
    NN_ABI_CONST(NCKEY_BUTTON8),
    NN_ABI_CONST(NCKEY_BUTTON9),
    NN_ABI_CONST(NCKEY_CANCEL),
    NN_ABI_CONST(NCKEY_CAPS_LOCK),
    NN_ABI_CONST(NCKEY_CENTER),
    NN_ABI_CONST(NCKEY_CLOSE),
    NN_ABI_CONST(NCKEY_CLS),
    NN_ABI_CONST(NCKEY_COMMAND),
    NN_ABI_CONST(NCKEY_COPY),
    NN_ABI_CONST(NCKEY_DEL),
    NN_ABI_CONST(NCKEY_DLEFT),
    NN_ABI_CONST(NCKEY_DOWN),
    NN_ABI_CONST(NCKEY_DRIGHT),
    NN_ABI_CONST(NCKEY_END),
    NN_ABI_CONST(NCKEY_ENTER),
    NN_ABI_CONST(NCKEY_EOF),
    NN_ABI_CONST(NCKEY_ESC),
    NN_ABI_CONST(NCKEY_EXIT),
    NN_ABI_CONST(NCKEY_F00),
    NN_ABI_CONST(NCKEY_F01),
    NN_ABI_CONST(NCKEY_F02),
    NN_ABI_CONST(NCKEY_F03),
    NN_ABI_CONST(NCKEY_F04),
    NN_ABI_CONST(NCKEY_F05),
    NN_ABI_CONST(NCKEY_F06),
    NN_ABI_CONST(NCKEY_F07),
    NN_ABI_CONST(NCKEY_F08),
    NN_ABI_CONST(NCKEY_F09),
    NN_ABI_CONST(NCKEY_F10),
    NN_ABI_CONST(NCKEY_F11),
    NN_ABI_CONST(NCKEY_F12),
    NN_ABI_CONST(NCKEY_F13),
    NN_ABI_CONST(NCKEY_F14),
    NN_ABI_CONST(NCKEY_F15),
    NN_ABI_CONST(NCKEY_F16),
    NN_ABI_CONST(NCKEY_F17),
    NN_ABI_CONST(NCKEY_F18),
    NN_ABI_CONST(NCKEY_F19),
    NN_ABI_CONST(NCKEY_F20),
    NN_ABI_CONST(NCKEY_F21),
    NN_ABI_CONST(NCKEY_F22),
    NN_ABI_CONST(NCKEY_F23),
    NN_ABI_CONST(NCKEY_F24),
    NN_ABI_CONST(NCKEY_F25),
    NN_ABI_CONST(NCKEY_F26),
    NN_ABI_CONST(NCKEY_F27),
    NN_ABI_CONST(NCKEY_F28),
    NN_ABI_CONST(NCKEY_F29),
    NN_ABI_CONST(NCKEY_F30),
    NN_ABI_CONST(NCKEY_F31),
    NN_ABI_CONST(NCKEY_F32),
    NN_ABI_CONST(NCKEY_F33),
    NN_ABI_CONST(NCKEY_F34),
    NN_ABI_CONST(NCKEY_F35),
    NN_ABI_CONST(NCKEY_F36),
    NN_ABI_CONST(NCKEY_F37),
    NN_ABI_CONST(NCKEY_F38),
    NN_ABI_CONST(NCKEY_F39),
    NN_ABI_CONST(NCKEY_F40),
    NN_ABI_CONST(NCKEY_F41),
    NN_ABI_CONST(NCKEY_F42),
    NN_ABI_CONST(NCKEY_F43),
    NN_ABI_CONST(NCKEY_F44),
    NN_ABI_CONST(NCKEY_F45),
    NN_ABI_CONST(NCKEY_F46),
    NN_ABI_CONST(NCKEY_F47),
    NN_ABI_CONST(NCKEY_F48),
    NN_ABI_CONST(NCKEY_F49),
    NN_ABI_CONST(NCKEY_F50),
    NN_ABI_CONST(NCKEY_F51),
    NN_ABI_CONST(NCKEY_F52),
    NN_ABI_CONST(NCKEY_F53),
    NN_ABI_CONST(NCKEY_F54),
    NN_ABI_CONST(NCKEY_F55),
    NN_ABI_CONST(NCKEY_F56),
    NN_ABI_CONST(NCKEY_F57),
    NN_ABI_CONST(NCKEY_F58),
    NN_ABI_CONST(NCKEY_F59),
    NN_ABI_CONST(NCKEY_F60),
    NN_ABI_CONST(NCKEY_HOME),
    NN_ABI_CONST(NCKEY_INS),
    NN_ABI_CONST(NCKEY_INVALID),
    NN_ABI_CONST(NCKEY_L3SHIFT),
    NN_ABI_CONST(NCKEY_L5SHIFT),
    NN_ABI_CONST(NCKEY_LALT),
    NN_ABI_CONST(NCKEY_LCTRL),
    NN_ABI_CONST(NCKEY_LEFT),
    NN_ABI_CONST(NCKEY_LHYPER),
    NN_ABI_CONST(NCKEY_LMETA),
    NN_ABI_CONST(NCKEY_LSHIFT),
    NN_ABI_CONST(NCKEY_LSUPER),
    NN_ABI_CONST(NCKEY_MEDIA_FF),
    NN_ABI_CONST(NCKEY_MEDIA_LVOL),
    NN_ABI_CONST(NCKEY_MEDIA_MUTE),
    NN_ABI_CONST(NCKEY_MEDIA_NEXT),
    NN_ABI_CONST(NCKEY_MEDIA_PAUSE),
    NN_ABI_CONST(NCKEY_MEDIA_PLAY),
    NN_ABI_CONST(NCKEY_MEDIA_PPAUSE),
    NN_ABI_CONST(NCKEY_MEDIA_PREV),
    NN_ABI_CONST(NCKEY_MEDIA_RECORD),
    NN_ABI_CONST(NCKEY_MEDIA_REV),
    NN_ABI_CONST(NCKEY_MEDIA_REWIND),
    NN_ABI_CONST(NCKEY_MEDIA_RVOL),
    NN_ABI_CONST(NCKEY_MEDIA_STOP),
    NN_ABI_CONST(NCKEY_MENU),
    NN_ABI_CONST(NCKEY_MOD_ALT),
    NN_ABI_CONST(NCKEY_MOD_CAPSLOCK),
    NN_ABI_CONST(NCKEY_MOD_CTRL),
    NN_ABI_CONST(NCKEY_MOD_HYPER),
    NN_ABI_CONST(NCKEY_MOD_META),
    NN_ABI_CONST(NCKEY_MOD_NUMLOCK),
    NN_ABI_CONST(NCKEY_MOD_SHIFT),
    NN_ABI_CONST(NCKEY_MOD_SUPER),
    NN_ABI_CONST(NCKEY_MOTION),
    NN_ABI_CONST(NCKEY_NUM_LOCK),
    NN_ABI_CONST(NCKEY_PAUSE),
    NN_ABI_CONST(NCKEY_PGDOWN),
    NN_ABI_CONST(NCKEY_PGUP),
    NN_ABI_CONST(NCKEY_PRINT),
    NN_ABI_CONST(NCKEY_PRINT_SCREEN),
    NN_ABI_CONST(NCKEY_RALT),
    NN_ABI_CONST(NCKEY_RCTRL),
    NN_ABI_CONST(NCKEY_REFRESH),
    NN_ABI_CONST(NCKEY_RESIZE),
    NN_ABI_CONST(NCKEY_RETURN),
    NN_ABI_CONST(NCKEY_RHYPER),
    NN_ABI_CONST(NCKEY_RIGHT),
    NN_ABI_CONST(NCKEY_RMETA),
    NN_ABI_CONST(NCKEY_RSHIFT),
    NN_ABI_CONST(NCKEY_RSUPER),
    NN_ABI_CONST(NCKEY_SCROLL_DOWN),
    NN_ABI_CONST(NCKEY_SCROLL_LOCK),
    NN_ABI_CONST(NCKEY_SCROLL_UP),
    NN_ABI_CONST(NCKEY_SEPARATOR),
    NN_ABI_CONST(NCKEY_SIGNAL),
    NN_ABI_CONST(NCKEY_SPACE),
    NN_ABI_CONST(NCKEY_TAB),
    NN_ABI_CONST(NCKEY_ULEFT),
    NN_ABI_CONST(NCKEY_UP),
    NN_ABI_CONST(NCKEY_URIGHT),
    NN_ABI_CONST(NCLOGLEVEL_DEBUG),
    NN_ABI_CONST(NCLOGLEVEL_ERROR),
    NN_ABI_CONST(NCLOGLEVEL_FATAL),
    NN_ABI_CONST(NCLOGLEVEL_INFO),
    NN_ABI_CONST(NCLOGLEVEL_PANIC),
    NN_ABI_CONST(NCLOGLEVEL_SILENT),
    NN_ABI_CONST(NCLOGLEVEL_TRACE),
    NN_ABI_CONST(NCLOGLEVEL_VERBOSE),
    NN_ABI_CONST(NCLOGLEVEL_WARNING),
    NN_ABI_CONST(NCMENU_OPTION_BOTTOM),
    NN_ABI_CONST(NCMENU_OPTION_HIDING),
    NN_ABI_CONST(NCMICE_ALL_EVENTS),
    NN_ABI_CONST(NCMICE_BUTTON_EVENT),
    NN_ABI_CONST(NCMICE_DRAG_EVENT),
    NN_ABI_CONST(NCMICE_MOVE_EVENT),
    NN_ABI_CONST(NCMICE_NO_EVENTS),
    NN_ABI_CONST(NCOPTION_CLI_MODE),
    NN_ABI_CONST(NCOPTION_DRAIN_INPUT),
    NN_ABI_CONST(NCOPTION_INHIBIT_SETLOCALE),
    NN_ABI_CONST(NCOPTION_NO_ALTERNATE_SCREEN),
    NN_ABI_CONST(NCOPTION_NO_CLEAR_BITMAPS),
    NN_ABI_CONST(NCOPTION_NO_FONT_CHANGES),
    NN_ABI_CONST(NCOPTION_NO_QUIT_SIGHANDLERS),
    NN_ABI_CONST(NCOPTION_NO_WINCH_SIGHANDLER),
    NN_ABI_CONST(NCOPTION_PRESERVE_CURSOR),
    NN_ABI_CONST(NCOPTION_SCROLLING),
    NN_ABI_CONST(NCOPTION_SUPPRESS_BANNERS),
    NN_ABI_CONST(NCPALETTESIZE),
    NN_ABI_CONST(NCPIXEL_ITERM2),
    NN_ABI_CONST(NCPIXEL_KITTY_ANIMATED),
    NN_ABI_CONST(NCPIXEL_KITTY_SELFREF),
    NN_ABI_CONST(NCPIXEL_KITTY_STATIC),
    NN_ABI_CONST(NCPIXEL_LINUXFB),
    NN_ABI_CONST(NCPIXEL_NONE),
    NN_ABI_CONST(NCPIXEL_SIXEL),
    NN_ABI_CONST(NCPLANE_OPTION_AUTOGROW),
    NN_ABI_CONST(NCPLANE_OPTION_FIXED),
    NN_ABI_CONST(NCPLANE_OPTION_HORALIGNED),
    NN_ABI_CONST(NCPLANE_OPTION_MARGINALIZED),
    NN_ABI_CONST(NCPLANE_OPTION_VERALIGNED),
    NN_ABI_CONST(NCPLANE_OPTION_VSCROLL),
    NN_ABI_CONST(NCPLOT_OPTION_DETECTMAXONLY),
    NN_ABI_CONST(NCPLOT_OPTION_EXPONENTIALD),
    NN_ABI_CONST(NCPLOT_OPTION_LABELTICKSD),
    NN_ABI_CONST(NCPLOT_OPTION_NODEGRADE),
    NN_ABI_CONST(NCPLOT_OPTION_PRINTSAMPLE),
    NN_ABI_CONST(NCPLOT_OPTION_VERTICALI),
    NN_ABI_CONST(NCPROGBAR_OPTION_RETROGRADE),
    NN_ABI_CONST(NCREADER_OPTION_CURSOR),
    NN_ABI_CONST(NCREADER_OPTION_HORSCROLL),
    NN_ABI_CONST(NCREADER_OPTION_NOCMDKEYS),
    NN_ABI_CONST(NCREADER_OPTION_VERSCROLL),
    NN_ABI_CONST(NCREEL_OPTION_CIRCULAR),
    NN_ABI_CONST(NCREEL_OPTION_INFINITESCROLL),
    NN_ABI_CONST(NCSCALE_NONE),
    NN_ABI_CONST(NCSCALE_NONE_HIRES),
    NN_ABI_CONST(NCSCALE_SCALE),
    NN_ABI_CONST(NCSCALE_SCALE_HIRES),
    NN_ABI_CONST(NCSCALE_STRETCH),
    NN_ABI_CONST(NCSTYLE_BOLD),
    NN_ABI_CONST(NCSTYLE_ITALIC),
    NN_ABI_CONST(NCSTYLE_MASK),
    NN_ABI_CONST(NCSTYLE_NONE),
    NN_ABI_CONST(NCSTYLE_STRUCK),
    NN_ABI_CONST(NCSTYLE_UNDERCURL),
    NN_ABI_CONST(NCSTYLE_UNDERLINE),
    NN_ABI_CONST(NCTABBED_OPTION_BOTTOM),
    NN_ABI_CONST(NCTYPE_PRESS),
    NN_ABI_CONST(NCTYPE_RELEASE),
    NN_ABI_CONST(NCTYPE_REPEAT),
    NN_ABI_CONST(NCTYPE_UNKNOWN),
    NN_ABI_CONST(NCVISUAL_OPTION_ADDALPHA),
    NN_ABI_CONST(NCVISUAL_OPTION_BLEND),
    NN_ABI_CONST(NCVISUAL_OPTION_CHILDPLANE),
    NN_ABI_CONST(NCVISUAL_OPTION_HORALIGNED),
    NN_ABI_CONST(NCVISUAL_OPTION_NODEGRADE),
    NN_ABI_CONST(NCVISUAL_OPTION_NOINTERPOLATE),
    NN_ABI_CONST(NCVISUAL_OPTION_VERALIGNED),
    NN_ABI_CONST(NC_BGDEFAULT_MASK),
    NN_ABI_CONST(NC_BG_ALPHA_MASK),
    NN_ABI_CONST(NC_BG_PALETTE),
    NN_ABI_CONST(NC_BG_RGB_MASK),
    NN_ABI_CONST(NC_NOBACKGROUND_MASK),

    /* notcurses_get and friends answer (uint32_t)-1 on error; the Raku
     * side names that NOTCURSES-GET-ERROR. */
    { "const:NOTCURSES-GET-ERROR", (int64_t)(uint32_t)-1 },

    /* The fork's bracketed-paste keys. Headers that predate them do not
     * define the names, so the fork's definition — preterunicode(300)
     * and (301) — stands in until the pinned headers carry it. */
#ifdef NCKEY_PASTE_BEGIN
    NN_ABI_CONST(NCKEY_PASTE_BEGIN),
    NN_ABI_CONST(NCKEY_PASTE_END),
#else
    { "const:NCKEY_PASTE_BEGIN", (int64_t)preterunicode(300) },
    { "const:NCKEY_PASTE_END", (int64_t)preterunicode(301) },
#endif
};

#undef NN_ABI_SIZE
#undef NN_ABI_FIELD
#undef NN_ABI_FIELD_CLONG
#undef NN_ABI_CONST

#define NOTCURSES_NATIVE_ABI_COUNT \
    (sizeof(notcurses_native_abi_table) / sizeof(notcurses_native_abi_table[0]))

size_t notcurses_native_abi_count(void) {
    return NOTCURSES_NATIVE_ABI_COUNT;
}

const char* notcurses_native_abi_key(size_t i) {
    return i < NOTCURSES_NATIVE_ABI_COUNT ? notcurses_native_abi_table[i].key : NULL;
}

int64_t notcurses_native_abi_value(size_t i) {
    return i < NOTCURSES_NATIVE_ABI_COUNT ? notcurses_native_abi_table[i].value : INT64_MIN;
}

#ifndef NOTCURSES_NATIVE_ABI_TABLE_ONLY

/*
 * An EGC copied out of a plane's egcpool into storage the shim owns.
 *
 * Why this exists: nccell_extended_gcluster() answers a pointer INTO
 * the plane's egcpool whenever the cluster is longer than the four
 * bytes a cell stores inline, and the pool is a realloc'd buffer. Any
 * later stash into the same pool can move it, and a pointer taken
 * before the move then reads freed memory. copy_cells stashes into the
 * source pool constantly (every ncplane_at_yx_cell duplicates the cell
 * it reads) and, when src == dst, stashes into it on every write too,
 * so it must never hold a pool pointer across another notcurses call.
 * Every cluster is copied here first and the pool reference released.
 *
 * Clusters that fit `inline_buf` (almost all of them — a long one is a
 * base letter under a stack of combining marks, or a ZWJ emoji
 * sequence) cost nothing; anything longer spills to a heap buffer that
 * is reused, and only ever grown, for the rest of the copy.
 */
#define NOTCURSES_NATIVE_EGC_INLINE 128

struct notcurses_native_egc_copy {
    char   inline_buf[NOTCURSES_NATIVE_EGC_INLINE];
    char*  heap;       /* NULL until a cluster outgrows inline_buf */
    size_t heap_cap;
};

static void notcurses_native_egc_copy_init(struct notcurses_native_egc_copy* b) {
    b->inline_buf[0] = '\0';
    b->heap = NULL;
    b->heap_cap = 0;
}

static void notcurses_native_egc_copy_fini(struct notcurses_native_egc_copy* b) {
    free(b->heap);
    b->heap = NULL;
    b->heap_cap = 0;
}

/* Copy the NUL-terminated `egc` into `b`. Answers the owned copy, or
 * NULL if a heap spill could not be allocated. `egc` must not point
 * into `b`. A simple (inline) cluster's bytes live in the nccell
 * itself and are terminated by its gcluster_backstop byte, so strlen
 * is safe on either kind. */
static const char* notcurses_native_egc_copy_take(
    struct notcurses_native_egc_copy* b,
    const char* egc
) {
    size_t len = strlen(egc);
    if (len < sizeof(b->inline_buf)) {
        memcpy(b->inline_buf, egc, len + 1);
        return b->inline_buf;
    }
    if (len + 1 > b->heap_cap) {
        /* realloc(NULL, n) is malloc(n) on every supported libc. On
         * failure the old buffer is left intact for _fini to free. */
        char* grown = realloc(b->heap, len + 1);
        if (grown == NULL) {
            return NULL;
        }
        b->heap = grown;
        b->heap_cap = len + 1;
    }
    memcpy(b->heap, egc, len + 1);
    return b->heap;
}

/*
 * Copy `rows × cols` cells from `src` starting at (src_y, src_x)
 * to `dst` starting at (dst_y, dst_x). Empty source cells take the
 * source plane's base cell content (matching the per-cell behaviour
 * of ncplane_at_yx), so e.g. a Border's interior empty cells carry
 * the theme background through the copy.
 *
 * `src` and `dst` may be the same plane.
 *
 * Returns 0 on success. Negative ncplane_at_yx_cell results (cells
 * out of bounds) are skipped silently — same as the Raku loop. If
 * the source's base cell cannot be read, empty cells are left
 * unwritten, which is what an empty base cell does anyway.
 *
 * Returns -1 only when copying a cluster longer than
 * NOTCURSES_NATIVE_EGC_INLINE - 1 bytes needs heap memory that cannot
 * be allocated; cells already written stay written.
 *
 * Every cluster is copied out of the source egcpool before the next
 * notcurses call (see struct notcurses_native_egc_copy), and each
 * ncplane_at_yx_cell duplicate is released before the write. Earlier
 * versions held the base cell's pool pointer for the whole copy and
 * wrote each cell straight from its pool pointer; both read freed
 * memory once the pool grew (the base case on any source whose base
 * cell holds a long cluster, the write case whenever src == dst).
 */
int notcurses_native_copy_cells(
    struct ncplane* src,
    struct ncplane* dst,
    int src_y, int src_x,
    int dst_y, int dst_x,
    unsigned rows, unsigned cols
) {
    struct notcurses_native_egc_copy base_copy;
    struct notcurses_native_egc_copy cell_copy;
    notcurses_native_egc_copy_init(&base_copy);
    notcurses_native_egc_copy_init(&cell_copy);
    int ret = 0;

    /* The base cell is needed for the whole copy, so own its cluster
     * outright and hand the pool its duplicate back straight away. */
    const char* base_egc      = NULL;
    uint16_t    base_styles   = 0;
    uint64_t    base_channels = 0;
    {
        nccell base = NCCELL_TRIVIAL_INITIALIZER;
        if (ncplane_base(src, &base) == 0) {
            base_egc      = notcurses_native_egc_copy_take(
                &base_copy, nccell_extended_gcluster(src, &base));
            base_styles   = base.stylemask;
            base_channels = base.channels;
            if (base_egc == NULL) {
                ret = -1;
            }
        }
        nccell_release(src, &base);
    }

    for (unsigned r = 0; ret == 0 && r < rows; r++) {
        for (unsigned c = 0; c < cols; c++) {
            nccell cell = NCCELL_TRIVIAL_INITIALIZER;
            int bytes = ncplane_at_yx_cell(
                src,
                src_y + (int)r,
                src_x + (int)c,
                &cell
            );
            if (bytes < 0) {
                continue;
            }
            const char* egc = nccell_extended_gcluster(src, &cell);

            const char* write_egc;
            uint16_t    write_styles;
            uint64_t    write_channels;
            if (egc == NULL || egc[0] == '\0') {
                write_egc      = base_egc;
                write_styles   = base_styles;
                write_channels = base_channels;
            } else {
                write_egc      = notcurses_native_egc_copy_take(&cell_copy, egc);
                write_styles   = cell.stylemask;
                write_channels = cell.channels;
                if (write_egc == NULL) {
                    nccell_release(src, &cell);
                    ret = -1;
                    break;
                }
            }
            /* `egc` is dead from here on: the release below, and the
             * write into dst when dst == src, may move the pool. */
            nccell_release(src, &cell);

            if (write_egc != NULL && write_egc[0] != '\0') {
                ncplane_set_styles(dst, write_styles);
                ncplane_set_channels(dst, write_channels);
                ncplane_putstr_yx(
                    dst,
                    dst_y + (int)r,
                    dst_x + (int)c,
                    write_egc
                );
            }
        }
    }

    notcurses_native_egc_copy_fini(&cell_copy);
    notcurses_native_egc_copy_fini(&base_copy);
    return ret;
}

/* ------------------------------------------------------------------
 * Terminal restore guard.
 *
 * A Raku TUI restores the terminal from Raku: an END phaser, a LEAVE,
 * a signal tap. Every one of those needs the VM to still be running.
 * A MoarVM panic ("Heap corruption detected: ...") does not give it
 * one: MVM_panic prints its line and calls C exit(3) directly, so no
 * Raku code whatsoever runs afterwards and the user is left in a raw-
 * mode terminal with no echo, the alternate screen still up and the
 * Kitty keyboard protocol still pushed — a shell they have to type
 * `reset` into blind.
 *
 * C atexit(3) handlers DO run on exit(3), and this shim is the only C
 * we own in the load path, so the guard lives here. Arm it with the
 * terminal's pre-TUI state and the cleanup escape sequence, and the
 * handler puts both back on any exit(3) the process takes, panic or
 * not.
 *
 * What it CANNOT catch, by construction:
 *   * SIGSEGV / SIGBUS / SIGILL and friends — the kernel tears the
 *     process down without running atexit handlers.
 *   * SIGKILL — same, and uncatchable besides.
 *   * _exit(2) / _Exit(3) / abort(3) — all deliberately skip atexit.
 * Best-effort signal handling belongs outside this guard; this covers
 * the exit(3) path the VM takes on its own panics.
 * ------------------------------------------------------------------ */

/* Bound on the cleanup string. Selkie's is ~90 bytes; 1 KiB leaves
 * room for a consumer that pushes more protocols without letting an
 * unbounded caller string into a static buffer. */
#define NOTCURSES_NATIVE_GUARD_CLEANUP_MAX 1024

/* Return codes for terminal guard operations. Anything non-zero from
 * an arm call means no new snapshot was armed. */
#define NOTCURSES_NATIVE_GUARD_OK              0
#define NOTCURSES_NATIVE_GUARD_ENULL           1 /* cleanup was NULL        */
#define NOTCURSES_NATIVE_GUARD_ETOOLONG        2 /* cleanup > MAX           */
#define NOTCURSES_NATIVE_GUARD_ENOTERM         3 /* no terminal             */
#define NOTCURSES_NATIVE_GUARD_ESTATE          4 /* state unreadable        */
#define NOTCURSES_NATIVE_GUARD_EATEXIT         5 /* atexit() refused        */
#define NOTCURSES_NATIVE_GUARD_EBUSY           6 /* another owner holds it  */
#define NOTCURSES_NATIVE_GUARD_EOWNER          7 /* token does not own it   */
#define NOTCURSES_NATIVE_GUARD_ETOKEN          8 /* invalid token           */

#define NOTCURSES_NATIVE_GUARD_STATE_EMPTY     0u
#define NOTCURSES_NATIVE_GUARD_STATE_RESERVED  1u
#define NOTCURSES_NATIVE_GUARD_STATE_PUBLISHED 2u
#define NOTCURSES_NATIVE_GUARD_STATE_EXITING   3u
#define NOTCURSES_NATIVE_GUARD_STATE_ARMING    4u
#define NOTCURSES_NATIVE_GUARD_STATE_CLOSING   5u
#define NOTCURSES_NATIVE_GUARD_LEGACY_OWNER    1ull
#define NOTCURSES_NATIVE_GUARD_STATE_BITS      3u
#define NOTCURSES_NATIVE_GUARD_STATE_MASK      0x7ull
#define NOTCURSES_NATIVE_GUARD_MAX_OWNER       0x1fffffffffffffffull

struct notcurses_native_terminal_guard_snapshot {
    char cleanup[NOTCURSES_NATIVE_GUARD_CLEANUP_MAX];
    size_t cleanup_len;
#ifdef _WIN32
    HANDLE in_handle;
    HANDLE out_handle;
    DWORD in_mode;
    DWORD out_mode;
    int have_in;
    int have_out;
#else
    int tty_fd;
    struct termios termios;
    int have_termios;
#endif
};

/* One immutable published snapshot. Mutators may only write it while
 * they have moved (owner, RESERVED) -> (owner, ARMING). The exit
 * handler first CASes (owner, PUBLISHED) -> (owner, EXITING); after
 * that no mutator may overwrite or close the snapshot it is reading.
 *
 * Owner and state live in one atomic word: low 3 bits state, upper
 * bits owner. That prevents ABA between a stale release and a new
 * reserve, and keeps the exit claim as a single non-blocking CAS.
 * Tokens are caller-generated, process-unique, non-zero, and limited
 * to 61 bits by that packing. */
static struct notcurses_native_terminal_guard_snapshot guard_snapshot;
static atomic_uint_fast64_t guard_word = NOTCURSES_NATIVE_GUARD_STATE_EMPTY;
static atomic_uint guard_atexit_state = 0; /* 0 none, 1 registering, 2 registered */

static void notcurses_native_terminal_guard_handler(void);

static uint_fast64_t notcurses_native_guard_word(uint64_t owner, unsigned state) {
    return (owner << NOTCURSES_NATIVE_GUARD_STATE_BITS)
        | ((uint64_t)state & NOTCURSES_NATIVE_GUARD_STATE_MASK);
}

static unsigned notcurses_native_guard_state(uint_fast64_t word) {
    return (unsigned)(word & NOTCURSES_NATIVE_GUARD_STATE_MASK);
}

static uint64_t notcurses_native_guard_owner(uint_fast64_t word) {
    return word >> NOTCURSES_NATIVE_GUARD_STATE_BITS;
}

static int notcurses_native_guard_valid_owner(uint64_t owner) {
    return owner > 0 && owner <= (uint64_t)NOTCURSES_NATIVE_GUARD_MAX_OWNER;
}

#ifdef _WIN32
static void notcurses_native_guard_close_snapshot(
    struct notcurses_native_terminal_guard_snapshot* snap
) {
    if (snap->have_in && snap->in_handle != NULL && snap->in_handle != INVALID_HANDLE_VALUE) {
        CloseHandle(snap->in_handle);
    }
    if (snap->have_out && snap->out_handle != NULL && snap->out_handle != INVALID_HANDLE_VALUE) {
        CloseHandle(snap->out_handle);
    }
    snap->in_handle = NULL;
    snap->out_handle = NULL;
    snap->have_in = 0;
    snap->have_out = 0;
}
#else
static void notcurses_native_guard_close_snapshot(
    struct notcurses_native_terminal_guard_snapshot* snap
) {
    if (snap->tty_fd >= 0) {
        close(snap->tty_fd);
    }
    snap->tty_fd = -1;
    snap->have_termios = 0;
}
#endif

static void notcurses_native_guard_init_snapshot(
    struct notcurses_native_terminal_guard_snapshot* snap
) {
    memset(snap, 0, sizeof(*snap));
#ifndef _WIN32
    snap->tty_fd = -1;
#endif
}

static int notcurses_native_guard_register_atexit(void) {
    unsigned expected = 2;
    if (atomic_load_explicit(&guard_atexit_state, memory_order_acquire) == 2) {
        return NOTCURSES_NATIVE_GUARD_OK;
    }
    expected = 0;
    if (atomic_compare_exchange_strong_explicit(&guard_atexit_state, &expected, 1,
            memory_order_acq_rel, memory_order_acquire)) {
        if (atexit(notcurses_native_terminal_guard_handler) != 0) {
            atomic_store_explicit(&guard_atexit_state, 0, memory_order_release);
            return NOTCURSES_NATIVE_GUARD_EATEXIT;
        }
        atomic_store_explicit(&guard_atexit_state, 2, memory_order_release);
        return NOTCURSES_NATIVE_GUARD_OK;
    }
    return expected == 2 ? NOTCURSES_NATIVE_GUARD_OK : NOTCURSES_NATIVE_GUARD_EATEXIT;
}

static int notcurses_native_guard_capture(
    struct notcurses_native_terminal_guard_snapshot* snap,
    const char* cleanup,
    size_t len
) {
    notcurses_native_guard_init_snapshot(snap);
    memcpy(snap->cleanup, cleanup, len);
    snap->cleanup[len] = '\0';
    snap->cleanup_len = len;

#ifdef _WIN32
    {
        HANDLE process = GetCurrentProcess();
        HANDLE hin  = GetStdHandle(STD_INPUT_HANDLE);
        HANDLE hout = GetStdHandle(STD_OUTPUT_HANDLE);
        DWORD in_mode = 0;
        DWORD out_mode = 0;
        int have_in = 0;
        int have_out = 0;

        if (hin != NULL && hin != INVALID_HANDLE_VALUE && GetConsoleMode(hin, &in_mode)) {
            if (!DuplicateHandle(process, hin, process, &snap->in_handle, 0, FALSE,
                                 DUPLICATE_SAME_ACCESS)) {
                notcurses_native_guard_close_snapshot(snap);
                return NOTCURSES_NATIVE_GUARD_ESTATE;
            }
            snap->in_mode = in_mode;
            snap->have_in = 1;
            have_in = 1;
        }
        if (hout != NULL && hout != INVALID_HANDLE_VALUE && GetConsoleMode(hout, &out_mode)) {
            if (!DuplicateHandle(process, hout, process, &snap->out_handle, 0, FALSE,
                                 DUPLICATE_SAME_ACCESS)) {
                notcurses_native_guard_close_snapshot(snap);
                return NOTCURSES_NATIVE_GUARD_ESTATE;
            }
            snap->out_mode = out_mode;
            snap->have_out = 1;
            have_out = 1;
        }
        if (!have_in && !have_out) {
            return NOTCURSES_NATIVE_GUARD_ENOTERM;
        }
        snap->have_in = have_in;
        snap->have_out = have_out;
    }
#else
    {
        struct termios captured;
        int rc;
        int flags;
        int fd = open("/dev/tty", O_RDWR | O_NOCTTY | O_NONBLOCK);
        if (fd < 0) {
            fd = open("/dev/tty", O_WRONLY | O_NOCTTY | O_NONBLOCK);
        }
        if (fd < 0) {
            return NOTCURSES_NATIVE_GUARD_ENOTERM;
        }
        do {
            rc = tcgetattr(fd, &captured);
        } while (rc != 0 && errno == EINTR);
        if (rc != 0) {
            close(fd);
            return NOTCURSES_NATIVE_GUARD_ESTATE;
        }
        flags = fcntl(fd, F_GETFL, 0);
        if (flags < 0 || !(flags & O_NONBLOCK) || fcntl(fd, F_SETFD, FD_CLOEXEC) != 0) {
            close(fd);
            return NOTCURSES_NATIVE_GUARD_ESTATE;
        }
        snap->tty_fd = fd;
        snap->termios = captured;
        snap->have_termios = 1;
    }
#endif
    return NOTCURSES_NATIVE_GUARD_OK;
}

int notcurses_native_reserve_terminal_guard(uint64_t owner) {
    uint_fast64_t expected;
    uint_fast64_t desired;
    uint_fast64_t current;
    if (!notcurses_native_guard_valid_owner(owner)) {
        return NOTCURSES_NATIVE_GUARD_ETOKEN;
    }
    expected = notcurses_native_guard_word(0, NOTCURSES_NATIVE_GUARD_STATE_EMPTY);
    desired = notcurses_native_guard_word(owner, NOTCURSES_NATIVE_GUARD_STATE_RESERVED);
    if (atomic_compare_exchange_strong_explicit(&guard_word, &expected, desired,
            memory_order_acq_rel, memory_order_acquire)) {
        return NOTCURSES_NATIVE_GUARD_OK;
    }
    current = atomic_load_explicit(&guard_word, memory_order_acquire);
    return notcurses_native_guard_owner(current) == owner
        ? NOTCURSES_NATIVE_GUARD_OK : NOTCURSES_NATIVE_GUARD_EBUSY;
}

int notcurses_native_arm_terminal_guard_owned(uint64_t owner, const char* cleanup) {
    size_t len;
    uint_fast64_t word;
    uint_fast64_t desired;
    int rc;
    struct notcurses_native_terminal_guard_snapshot next;

    if (!notcurses_native_guard_valid_owner(owner)) {
        return NOTCURSES_NATIVE_GUARD_ETOKEN;
    }
    if (cleanup == NULL) {
        return NOTCURSES_NATIVE_GUARD_ENULL;
    }
    for (len = 0; len < (size_t)NOTCURSES_NATIVE_GUARD_CLEANUP_MAX && cleanup[len]; ++len) { }
    if (len >= (size_t)NOTCURSES_NATIVE_GUARD_CLEANUP_MAX) {
        return NOTCURSES_NATIVE_GUARD_ETOOLONG;
    }

    word = atomic_load_explicit(&guard_word, memory_order_acquire);
    if (notcurses_native_guard_owner(word) != owner) {
        return NOTCURSES_NATIVE_GUARD_EOWNER;
    }
    if (notcurses_native_guard_state(word) == NOTCURSES_NATIVE_GUARD_STATE_PUBLISHED) {
        return NOTCURSES_NATIVE_GUARD_OK;
    }
    if (notcurses_native_guard_state(word) != NOTCURSES_NATIVE_GUARD_STATE_RESERVED) {
        return (notcurses_native_guard_state(word) == NOTCURSES_NATIVE_GUARD_STATE_EXITING
                || notcurses_native_guard_state(word) == NOTCURSES_NATIVE_GUARD_STATE_ARMING
                || notcurses_native_guard_state(word) == NOTCURSES_NATIVE_GUARD_STATE_CLOSING)
            ? NOTCURSES_NATIVE_GUARD_EBUSY : NOTCURSES_NATIVE_GUARD_EOWNER;
    }

    desired = notcurses_native_guard_word(owner, NOTCURSES_NATIVE_GUARD_STATE_ARMING);
    if (!atomic_compare_exchange_strong_explicit(&guard_word, &word, desired,
            memory_order_acq_rel, memory_order_acquire)) {
        return NOTCURSES_NATIVE_GUARD_EBUSY;
    }

    rc = notcurses_native_guard_capture(&next, cleanup, len);
    if (rc != NOTCURSES_NATIVE_GUARD_OK) {
        desired = notcurses_native_guard_word(owner, NOTCURSES_NATIVE_GUARD_STATE_RESERVED);
        atomic_store_explicit(&guard_word, desired, memory_order_release);
        return rc;
    }
    rc = notcurses_native_guard_register_atexit();
    if (rc != NOTCURSES_NATIVE_GUARD_OK) {
        notcurses_native_guard_close_snapshot(&next);
        desired = notcurses_native_guard_word(owner, NOTCURSES_NATIVE_GUARD_STATE_RESERVED);
        atomic_store_explicit(&guard_word, desired, memory_order_release);
        return rc;
    }

    guard_snapshot = next;
    desired = notcurses_native_guard_word(owner, NOTCURSES_NATIVE_GUARD_STATE_PUBLISHED);
    atomic_store_explicit(&guard_word, desired, memory_order_release);
    return NOTCURSES_NATIVE_GUARD_OK;
}

int notcurses_native_disarm_terminal_guard_owned(uint64_t owner) {
    uint_fast64_t word;
    uint_fast64_t desired;
    if (!notcurses_native_guard_valid_owner(owner)) {
        return NOTCURSES_NATIVE_GUARD_ETOKEN;
    }
    word = atomic_load_explicit(&guard_word, memory_order_acquire);
    if (notcurses_native_guard_owner(word) != owner) {
        return NOTCURSES_NATIVE_GUARD_EOWNER;
    }
    if (notcurses_native_guard_state(word) == NOTCURSES_NATIVE_GUARD_STATE_RESERVED) {
        return NOTCURSES_NATIVE_GUARD_OK;
    }
    if (notcurses_native_guard_state(word) != NOTCURSES_NATIVE_GUARD_STATE_PUBLISHED) {
        return (notcurses_native_guard_state(word) == NOTCURSES_NATIVE_GUARD_STATE_EXITING
                || notcurses_native_guard_state(word) == NOTCURSES_NATIVE_GUARD_STATE_ARMING
                || notcurses_native_guard_state(word) == NOTCURSES_NATIVE_GUARD_STATE_CLOSING)
            ? NOTCURSES_NATIVE_GUARD_EBUSY : NOTCURSES_NATIVE_GUARD_EOWNER;
    }
    desired = notcurses_native_guard_word(owner, NOTCURSES_NATIVE_GUARD_STATE_CLOSING);
    if (!atomic_compare_exchange_strong_explicit(&guard_word, &word, desired,
            memory_order_acq_rel, memory_order_acquire)) {
        return NOTCURSES_NATIVE_GUARD_EBUSY;
    }
    notcurses_native_guard_close_snapshot(&guard_snapshot);
    desired = notcurses_native_guard_word(owner, NOTCURSES_NATIVE_GUARD_STATE_RESERVED);
    atomic_store_explicit(&guard_word, desired, memory_order_release);
    return NOTCURSES_NATIVE_GUARD_OK;
}

int notcurses_native_release_terminal_guard(uint64_t owner) {
    uint_fast64_t word;
    uint_fast64_t desired;
    int rc;
    if (!notcurses_native_guard_valid_owner(owner)) {
        return NOTCURSES_NATIVE_GUARD_ETOKEN;
    }
    word = atomic_load_explicit(&guard_word, memory_order_acquire);
    if (notcurses_native_guard_owner(word) != owner) {
        return NOTCURSES_NATIVE_GUARD_EOWNER;
    }
    if (notcurses_native_guard_state(word) == NOTCURSES_NATIVE_GUARD_STATE_PUBLISHED) {
        rc = notcurses_native_disarm_terminal_guard_owned(owner);
        if (rc != NOTCURSES_NATIVE_GUARD_OK) {
            return rc;
        }
        word = atomic_load_explicit(&guard_word, memory_order_acquire);
    }
    if (notcurses_native_guard_owner(word) != owner) {
        return NOTCURSES_NATIVE_GUARD_EOWNER;
    }
    if (notcurses_native_guard_state(word) != NOTCURSES_NATIVE_GUARD_STATE_RESERVED) {
        return (notcurses_native_guard_state(word) == NOTCURSES_NATIVE_GUARD_STATE_EXITING
                || notcurses_native_guard_state(word) == NOTCURSES_NATIVE_GUARD_STATE_ARMING
                || notcurses_native_guard_state(word) == NOTCURSES_NATIVE_GUARD_STATE_CLOSING)
            ? NOTCURSES_NATIVE_GUARD_EBUSY : NOTCURSES_NATIVE_GUARD_EOWNER;
    }
    desired = notcurses_native_guard_word(0, NOTCURSES_NATIVE_GUARD_STATE_EMPTY);
    if (!atomic_compare_exchange_strong_explicit(&guard_word, &word, desired,
            memory_order_acq_rel, memory_order_acquire)) {
        return NOTCURSES_NATIVE_GUARD_EBUSY;
    }
    return NOTCURSES_NATIVE_GUARD_OK;
}

static void notcurses_native_terminal_guard_handler(void) {
    uint_fast64_t word = atomic_load_explicit(&guard_word, memory_order_acquire);
    uint_fast64_t desired;
    if (notcurses_native_guard_state(word) != NOTCURSES_NATIVE_GUARD_STATE_PUBLISHED) {
        return;
    }
    desired = notcurses_native_guard_word(notcurses_native_guard_owner(word),
                                         NOTCURSES_NATIVE_GUARD_STATE_EXITING);
    if (!atomic_compare_exchange_strong_explicit(&guard_word, &word, desired,
            memory_order_acq_rel, memory_order_acquire)) {
        return;
    }

#ifdef _WIN32
    {
        if (guard_snapshot.have_out && guard_snapshot.out_handle != NULL
                && guard_snapshot.out_handle != INVALID_HANDLE_VALUE) {
            if (guard_snapshot.cleanup_len > 0) {
                DWORD written = 0;
                if (!WriteConsoleA(guard_snapshot.out_handle, guard_snapshot.cleanup,
                                   (DWORD)guard_snapshot.cleanup_len, &written, NULL)) {
                    DWORD raw = 0;
                    WriteFile(guard_snapshot.out_handle, guard_snapshot.cleanup,
                              (DWORD)guard_snapshot.cleanup_len, &raw, NULL);
                }
            }
            SetConsoleMode(guard_snapshot.out_handle, guard_snapshot.out_mode);
        }
        if (guard_snapshot.have_in && guard_snapshot.in_handle != NULL
                && guard_snapshot.in_handle != INVALID_HANDLE_VALUE) {
            SetConsoleMode(guard_snapshot.in_handle, guard_snapshot.in_mode);
        }
    }
#else
    {
        if (guard_snapshot.tty_fd < 0) {
            return;
        }
        if (guard_snapshot.have_termios) {
            int rc;
            int attempts = 0;
            do {
                rc = tcsetattr(guard_snapshot.tty_fd, TCSANOW, &guard_snapshot.termios);
            } while (rc != 0 && errno == EINTR && ++attempts < 4);
        }
        {
            size_t off = 0;
            int attempts = 0;
            while (off < guard_snapshot.cleanup_len && attempts < 4) {
                ssize_t n = write(guard_snapshot.tty_fd, guard_snapshot.cleanup + off,
                                  guard_snapshot.cleanup_len - off);
                attempts++;
                if (n > 0) {
                    off += (size_t)n;
                    continue;
                }
                if (n < 0 && errno == EINTR) {
                    continue;
                }
                break;
            }
        }
    }
#endif
}

int notcurses_native_arm_terminal_guard(const char* cleanup) {
    int rc = notcurses_native_reserve_terminal_guard(NOTCURSES_NATIVE_GUARD_LEGACY_OWNER);
    if (rc != NOTCURSES_NATIVE_GUARD_OK) {
        return rc;
    }
    rc = notcurses_native_arm_terminal_guard_owned(NOTCURSES_NATIVE_GUARD_LEGACY_OWNER,
                                                  cleanup);
    if (rc != NOTCURSES_NATIVE_GUARD_OK) {
        (void)notcurses_native_release_terminal_guard(NOTCURSES_NATIVE_GUARD_LEGACY_OWNER);
    }
    return rc;
}

void notcurses_native_disarm_terminal_guard(void) {
    (void)notcurses_native_release_terminal_guard(NOTCURSES_NATIVE_GUARD_LEGACY_OWNER);
}

#endif /* NOTCURSES_NATIVE_ABI_TABLE_ONLY */
