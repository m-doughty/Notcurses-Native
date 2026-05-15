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
 * Symbols are prefixed `notcurses_native_` to stay out of
 * notcurses's namespace.
 *
 * Build: see Build.rakumod's !try-compile-shim. Compiled with
 * -undefined dynamic_lookup (macOS) or unresolved-at-link
 * (Linux) so the shim has no link-time dependency on
 * libnotcurses; the symbols resolve at runtime against whatever
 * libnotcurses the host process has already loaded via
 * Notcurses::Native's existing FFI bindings.
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
#include <string.h>
#include <notcurses/notcurses.h>

/*
 * Copy `rows × cols` cells from `src` starting at (src_y, src_x)
 * to `dst` starting at (dst_y, dst_x). Empty source cells take the
 * source plane's base cell content (matching the per-cell behaviour
 * of ncplane_at_yx), so e.g. a Border's interior empty cells carry
 * the theme background through the copy.
 *
 * Returns 0 on success. Negative ncplane_at_yx_cell results (cells
 * out of bounds) are skipped silently — same as the Raku loop.
 */
int notcurses_native_copy_cells(
    struct ncplane* src,
    struct ncplane* dst,
    int src_y, int src_x,
    int dst_y, int dst_x,
    unsigned rows, unsigned cols
) {
    nccell base = NCCELL_TRIVIAL_INITIALIZER;
    ncplane_base(src, &base);
    const char* base_egc      = nccell_extended_gcluster(src, &base);
    uint16_t    base_styles   = base.stylemask;
    uint64_t    base_channels = base.channels;

    for (unsigned r = 0; r < rows; r++) {
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
                write_egc      = egc;
                write_styles   = cell.stylemask;
                write_channels = cell.channels;
            }

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

            nccell_release(src, &cell);
        }
    }

    nccell_release(src, &base);
    return 0;
}
