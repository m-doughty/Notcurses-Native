/*
 * copy-cells-uaf.c — AddressSanitizer driver for the perf shim's
 * notcurses_native_copy_cells (src/notcurses_native_shim.c).
 *
 * Built and run by xxt/01-asan-copy-cells.rakutest, which compiles this
 * file together with the shim source, both with -fsanitize=address, and
 * links them against the staged libnotcurses-core. ASan intercepts
 * malloc/realloc/free for the whole process, notcurses included, so a
 * read through a pointer into an egcpool that notcurses has since
 * realloc'd is reported as a heap-use-after-free at the exact line —
 * whether or not the allocator would have moved the block without ASan.
 *
 * Scenarios (argv[1]):
 *
 *   base       B2. The source plane's base cell holds a cluster longer
 *              than four bytes, so it lives in the source egcpool. The
 *              copy reads one long cell (its duplicate may grow that
 *              pool) and then one empty cell, which takes the base
 *              cluster. A shim that kept the base as a pool pointer
 *              reads freed memory there.
 *
 *   sameplane  B1. Copy a long cell to another column of the SAME
 *              plane. The write stashes into the pool the cluster was
 *              read from; ncplane_putstr_yx re-reads its string after
 *              that stash, so a shim writing straight from the pool
 *              pointer reads freed memory there.
 *
 *   selftest   A deliberate heap-use-after-free. It must be reported;
 *              if it is not, the toolchain is not instrumenting and a
 *              clean run of the other scenarios would prove nothing.
 *
 * Each real scenario sweeps k, the number of long clusters already in
 * the pool, over 0..SWEEP_MAX. The pool starts at BUFSIZ bytes and grows
 * once less than 10% is free; stepping k by one cluster at a time puts
 * the growth at the dangerous moment for exactly one k per BUFSIZ, and
 * the sweep covers BUFSIZ 512 (MinGW), 1024 (macOS) and 8192 (glibc).
 * No knowledge of notcurses's internal struct layout is needed.
 *
 * Exit status: 0 clean; 1 wrong output from copy_cells; 2 setup failure;
 * 3 selftest not detected; 4 no UTF-8 locale; 64 usage. ASan itself
 * exits non-zero (1 by default) with its report on stderr.
 */
#define _GNU_SOURCE

#include <locale.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef _WIN32
#include <unistd.h>
#endif
#include <notcurses/notcurses.h>

int notcurses_native_copy_cells(struct ncplane* src, struct ncplane* dst,
                                int src_y, int src_x, int dst_y, int dst_x,
                                unsigned rows, unsigned cols);

/* Five-byte clusters: a letter plus two combining marks with no
 * precomposed form, so they always spill into the egcpool. The base
 * cluster must be at least as long as the fill cluster for the sweep to
 * be guaranteed to hit the growth window (see the header). */
static const char FILL[] = "x\xcc\x81\xcc\x82";  /* x U+0301 U+0302 */
static const char BASE[] = "q\xcc\x80\xcc\x83";  /* q U+0300 U+0303 */

#define SWEEP_MAX 1700

static struct ncplane*
make_plane(struct notcurses* nc, unsigned cols){
  struct ncplane_options opts;
  memset(&opts, 0, sizeof(opts));
  opts.rows = 1;
  opts.cols = cols;
  return ncplane_create(notcurses_stdplane(nc), &opts);
}

static int
fill(struct ncplane* n, int k){
  for(int i = 0 ; i < k ; ++i){
    if(ncplane_putstr_yx(n, 0, i, FILL) <= 0){
      fprintf(stderr, "fill: put %d of %d failed\n", i, k);
      return -1;
    }
  }
  return 0;
}

/* 1 when cell (0, x) of n reads back as `want`, else 0 with a note. */
static int
expect(struct ncplane* n, int x, const char* want, const char* scenario, int k){
  uint16_t styles;
  uint64_t channels;
  char* got = ncplane_at_yx(n, 0, x, &styles, &channels);
  int ok = got != NULL && strcmp(got, want) == 0;
  if(!ok){
    fprintf(stderr, "%s: k=%d column %d: got [%s], want [%s]\n",
            scenario, k, x, got ? got : "(null)", want);
  }
  free(got);
  return ok;
}

static int
run_base(struct notcurses* nc){
  int bad = 0;
  for(int k = 0 ; k <= SWEEP_MAX ; ++k){
    struct ncplane* src = make_plane(nc, (unsigned)k + 4);
    struct ncplane* dst = make_plane(nc, 8);
    if(src == NULL || dst == NULL){
      fprintf(stderr, "base: ncplane_create failed at k=%d\n", k);
      return 2;
    }
    if(ncplane_set_base(src, BASE, 0, 0) < 0 || fill(src, k)){
      fprintf(stderr, "base: source setup failed at k=%d\n", k);
      return 2;
    }
    const int from = k ? k - 1 : 0;
    if(notcurses_native_copy_cells(src, dst, 0, from, 0, 0, 1, 2) != 0){
      fprintf(stderr, "base: copy_cells failed at k=%d\n", k);
      ++bad;
    }
    bad += !expect(dst, 0, k ? FILL : BASE, "base", k);
    bad += !expect(dst, 1, BASE, "base", k);
    ncplane_destroy(dst);
    ncplane_destroy(src);
  }
  return bad ? 1 : 0;
}

static int
run_sameplane(struct notcurses* nc){
  int bad = 0;
  for(int k = 1 ; k <= SWEEP_MAX ; ++k){
    struct ncplane* n = make_plane(nc, (unsigned)k + 12);
    if(n == NULL || fill(n, k)){
      fprintf(stderr, "sameplane: setup failed at k=%d\n", k);
      return 2;
    }
    const int target = k + 5;
    if(notcurses_native_copy_cells(n, n, 0, k - 1, 0, target, 1, 1) != 0){
      fprintf(stderr, "sameplane: copy_cells failed at k=%d\n", k);
      ++bad;
    }
    bad += !expect(n, k - 1, FILL, "sameplane", k);
    bad += !expect(n, target, FILL, "sameplane", k);
    /* a stale re-read in ncplane_putstr_yx would spill past the target */
    bad += !expect(n, target + 1, "", "sameplane", k);
    ncplane_destroy(n);
  }
  return bad ? 1 : 0;
}

static int
run_selftest(void){
  char* volatile p = malloc(64);
  if(p == NULL){
    return 2;
  }
  memset(p, 'a', 64);
  free(p);
  volatile char c = p[8]; /* deliberate heap-use-after-free */
  (void)c;
  fprintf(stderr, "selftest: the use-after-free was NOT detected — "
                  "this toolchain is not instrumenting with ASan\n");
  return 3;
}

int main(int argc, char** argv){
  if(argc != 2){
    fprintf(stderr, "usage: %s base|sameplane|selftest\n", argv[0]);
    return 64;
  }
  if(strcmp(argv[1], "selftest") == 0){
    return run_selftest();
  }
  int (*scenario)(struct notcurses*) = NULL;
  if(strcmp(argv[1], "base") == 0){
    scenario = run_base;
  }else if(strcmp(argv[1], "sameplane") == 0){
    scenario = run_sameplane;
  }else{
    fprintf(stderr, "unknown scenario '%s'\n", argv[1]);
    return 64;
  }

  setlocale(LC_ALL, "");
#ifndef _WIN32
  /* No controlling terminal: notcurses would otherwise open /dev/tty and
   * block on terminal replies. A process spawned by the runner never
   * leads its process group, so this succeeds. */
  if(setsid() < 0){
    perror("setsid");
    return 2;
  }
  FILE* out = fopen("/dev/null", "w");
#else
  FILE* out = fopen("NUL", "w");
#endif
  if(out == NULL){
    perror("fopen null device");
    return 2;
  }
  struct notcurses_options opts;
  memset(&opts, 0, sizeof(opts));
  opts.loglevel = NCLOGLEVEL_SILENT;
  opts.flags = NCOPTION_SUPPRESS_BANNERS | NCOPTION_NO_ALTERNATE_SCREEN
             | NCOPTION_NO_QUIT_SIGHANDLERS | NCOPTION_NO_WINCH_SIGHANDLER
             | NCOPTION_DRAIN_INPUT;
  struct notcurses* nc = notcurses_core_init(&opts, out);
  if(nc == NULL){
    fprintf(stderr, "notcurses_core_init failed (TERM=%s)\n",
            getenv("TERM") ? getenv("TERM") : "(unset)");
    return 2;
  }
  if(!notcurses_canutf8(nc)){
    fprintf(stderr, "no UTF-8 locale: the scenarios write multi-byte clusters\n");
    notcurses_stop(nc);
    return 4;
  }
  int rc = scenario(nc);
  if(notcurses_stop(nc)){
    fprintf(stderr, "notcurses_stop failed\n");
    rc = rc ? rc : 2;
  }
  if(rc == 0){
    printf("%s: clean across the k = 0..%d sweep\n", argv[1], SWEEP_MAX);
  }
  return rc;
}
