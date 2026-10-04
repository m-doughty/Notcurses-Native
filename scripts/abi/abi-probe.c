/*
 * abi-probe.c — print the shim's ABI table (see the "ABI table" block in
 * src/notcurses_native_shim.c) as `key<TAB>value` lines, one entry per
 * line, in table order.
 *
 * It compiles the shim source itself with NOTCURSES_NATIVE_ABI_TABLE_ONLY
 * defined, which keeps the table and drops the rest of the shim, so it
 * needs nothing but a C compiler and the pinned notcurses headers — no
 * libnotcurses to link against. scripts/abi/regenerate-fixture.raku
 * builds and runs it to (re)write t/fixtures/abi-table.tsv, the table
 * t/42-abi-guard falls back to when no shim carrying the table is
 * installed, and to check that the committed fixture is current.
 *
 *   cc -I <notcurses>/include -o abi-probe scripts/abi/abi-probe.c
 */
#define NOTCURSES_NATIVE_ABI_TABLE_ONLY 1
#include "../../src/notcurses_native_shim.c"

#include <inttypes.h>
#include <stdio.h>

int main(void) {
    size_t count = notcurses_native_abi_count();
    for (size_t i = 0; i < count; i++) {
        if (printf("%s\t%" PRId64 "\n", notcurses_native_abi_key(i),
                   notcurses_native_abi_value(i)) < 0) {
            return 1;
        }
    }
    return fflush(stdout) == 0 ? 0 : 1;
}
