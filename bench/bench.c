/*
 * asm-ssz benchmark. Bench code: the library itself is assembly.
 *
 * Usage:
 *   bench run VECTOR_DIR [--quick]   time the workload and print the results
 *   bench compare BASE NEW           compare two results files
 *
 * The workload, the results format and the compare rule are in bench/README.md.
 * Every call is checked against its case before it is timed.
 */
#if defined(__APPLE__)
#define _DARWIN_C_SOURCE
#elif !defined(_WIN32)
#define _GNU_SOURCE
#endif
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#if defined(_WIN32)
#include <windows.h>
#elif defined(__APPLE__)
#include <pthread.h>
#include <sys/qos.h>
#include <sys/sysctl.h>
#else
#include <sched.h>
#endif

#if defined(_WIN32) && defined(__x86_64__)
#define SSZ_ABI __attribute__((sysv_abi))
#else
#define SSZ_ABI
#endif

/* The library (docs/reference/) and the SHA-256 it depends on. */
SSZ_ABI uint64_t ssz_serialize(const void *type, const void *value, void *scratch, void *serialized);
SSZ_ABI uint64_t ssz_serialize_size(const void *type, const void *value, void *scratch, void *size);
SSZ_ABI uint64_t ssz_deserialize(const void *type, const void *serialized, void *scratch, void *value);
SSZ_ABI uint64_t ssz_deserialize_size(const void *type, const void *serialized, void *scratch, void *size);
SSZ_ABI uint64_t ssz_hash_tree_root(const void *type, const void *value, void *scratch, void *root);
SSZ_ABI uint64_t ssz_get_generalized_index(const void *type, const void *path, void *gindex);
SSZ_ABI uint64_t ssz_build_proof(const void *type, const void *value, const void *gindex, void *scratch,
                                 void *branch);
SSZ_ABI uint64_t ssz_verify_merkle_proof(const void *leaf, const void *branch, const void *gindex,
                                         const void *root, void *valid);
SSZ_ABI uint64_t crypto_sha256(const void *message, void *digest);

#if defined(_WIN32)
#define OS_NAME "windows"
#elif defined(__APPLE__)
#define OS_NAME "macos"
#else
#define OS_NAME "linux"
#endif
#if defined(__x86_64__)
#define ISA_NAME "x86_64"
#elif defined(__aarch64__)
#define ISA_NAME "arm64"
#else
#define ISA_NAME "riscv64"
#endif

/* The workload (bench/README.md). */
#define STATIC_FILE "mainnet-fulu-static.bin"
#define PROOF_FILE "mainnet-fulu-proof.bin"
#define VERIFY_FILE "mainnet-fulu-verify.bin"
#define GINDEX_FILE "gindex.bin"
static const char *const static_types[] = {"BeaconState", "SignedBeaconBlock", "Attestation", "Validator"};
#define STATIC_TYPES (sizeof static_types / sizeof static_types[0])

/* Each item gets ROUNDS rounds of SAMPLES_PER_ROUND samples, pooled. A round
 * times every item once, so drift between rounds widens each item's spread. */
#define ROUNDS 3
#define SAMPLES_PER_ROUND 7
#define SAMPLES (ROUNDS * SAMPLES_PER_ROUND)
#define QUICK_SAMPLES 3
#define SAMPLE_NS 2000000.0     /* each sample runs the call about this long */
#define QUICK_SAMPLE_NS 0.0
/* compare: a change counts only when the middle halves of the samples do not
 * overlap and the medians differ by at least this much. Runs of one build on
 * one machine differ by up to about 3%. */
#define MIN_CHANGE 0.03

static void die(const char *what) {
    fprintf(stderr, "bench: %s\n", what);
    exit(2);
}

static uint64_t rd64(const uint8_t *p) {
    uint64_t v = 0;
    for (int i = 7; i >= 0; i--) v = (v << 8) | p[i];
    return v;
}

static void wr64(uint8_t *p, uint64_t v) {
    for (int i = 0; i < 8; i++) p[i] = (uint8_t)(v >> (8 * i));
}

/* An 8-aligned buffer of n bytes, zeroed. */
static uint8_t *buffer(uint64_t n) {
    uint8_t *b = calloc(1, (size_t)(n ? n : 8));
    if (!b) die("out of memory");
    return b;
}

static uint64_t now_ns(void) {
#if defined(_WIN32)
    LARGE_INTEGER c, f;
    QueryPerformanceCounter(&c);
    QueryPerformanceFrequency(&f);
    return (uint64_t)(c.QuadPart / f.QuadPart) * 1000000000u
           + (uint64_t)(c.QuadPart % f.QuadPart) * 1000000000u / (uint64_t)f.QuadPart;
#elif defined(__APPLE__)
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
#else
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000u + (uint64_t)t.tv_nsec;
#endif
}

/* The CPU's name as the OS reports it, on one line. */
static void cpu_name(char *out, size_t size) {
    snprintf(out, size, "unknown");
#if defined(_WIN32)
    DWORD n = (DWORD)size;
    if (RegGetValueA(HKEY_LOCAL_MACHINE, "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
                     "ProcessorNameString", RRF_RT_REG_SZ, NULL, out, &n) != ERROR_SUCCESS)
        snprintf(out, size, "unknown");
#elif defined(__APPLE__)
    size_t n = size;
    if (sysctlbyname("machdep.cpu.brand_string", out, &n, NULL, 0) != 0) snprintf(out, size, "unknown");
#else
    FILE *f = fopen("/proc/cpuinfo", "r");
    char line[256], implementer[32] = "", part[32] = "", isa[64] = "";
    if (!f) return;
    while (fgets(line, sizeof line, f)) {
        char *v = strchr(line, ':');
        if (!v) continue;
        v++;
        while (*v == ' ' || *v == '\t') v++;
        v[strcspn(v, "\n")] = 0;
        if (!strncmp(line, "model name", 10)) {
            snprintf(out, size, "%s", v);
            fclose(f);
            return;
        }
        if (!strncmp(line, "CPU implementer", 15) && !*implementer) snprintf(implementer, sizeof implementer, "%s", v);
        if (!strncmp(line, "CPU part", 8) && !*part) snprintf(part, sizeof part, "%s", v);
        if (!strncmp(line, "isa", 3) && !*isa) snprintf(isa, sizeof isa, "%s", v);
    }
    fclose(f);
    if (*implementer) snprintf(out, size, "Arm implementer %s part %s", implementer, part);
    else if (*isa) snprintf(out, size, "RISC-V %s", isa);
#endif
    for (char *p = out; *p; p++)
        if (*p == '\n' || *p == '\r' || *p == '\t') *p = ' ';
    /* Some OSes pad the name with spaces: drop them at both ends. */
    size_t end = strlen(out), lead = strspn(out, " ");
    while (end > lead && out[end - 1] == ' ') end--;
    memmove(out, out + lead, end - lead);
    out[end - lead] = 0;
}

/* ---------------------------------------------------------------- Vector files */

typedef struct {
    uint8_t *data;
    uint64_t len, kind, ndesc, ncases;
    const uint8_t **desc;
    const uint8_t *cases;
    char sha256[65];
} vecfile;

typedef struct {
    const uint8_t *p, *end;
} cursor;

static const uint8_t *take(cursor *c, uint64_t n) {
    if ((uint64_t)(c->end - c->p) < n) die("vector file ends early");
    const uint8_t *r = c->p;
    c->p += n;
    return r;
}

static uint64_t take64(cursor *c) { return rd64(take(c, 8)); }

static void load(vecfile *v, const char *dir, const char *name) {
    char path[4096];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "bench: cannot read %s\n", path);
        exit(2);
    }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    /* Read it after a ByteList header, so crypto_sha256 can hash it in place. */
    uint8_t *b = buffer(24 + (uint64_t)n);
    if (fread(b + 24, 1, (size_t)n, f) != (size_t)n) die("short read");
    fclose(f);
    wr64(b, 24 + (uint64_t)n);
    wr64(b + 8, 24);
    wr64(b + 16, (uint64_t)n);
    uint8_t digest[32];
    crypto_sha256(b, digest);
    for (int i = 0; i < 32; i++) snprintf(v->sha256 + 2 * i, 3, "%02x", digest[i]);
    v->data = b + 24;
    v->len = (uint64_t)n;
    cursor c = {v->data, v->data + v->len};
    if (memcmp(take(&c, 8), "SSZVEC01", 8)) die("wrong magic");
    v->kind = take64(&c);
    v->ndesc = take64(&c);
    v->desc = calloc((size_t)v->ndesc + 1, sizeof *v->desc);
    for (uint64_t i = 0; i < v->ndesc; i++) {
        uint64_t len = take64(&c);
        /* Descriptors are read with 8-byte loads: copy each one to an aligned buffer. */
        uint8_t *d = buffer(len);
        memcpy(d, take(&c, len), (size_t)len);
        v->desc[i] = d;
    }
    v->ncases = take64(&c);
    v->cases = c.p;
}

static const uint8_t *root_node(const uint8_t *desc) { return desc + rd64(desc + 8) + 72 * rd64(desc + 40); }

/* ---------------------------------------------------------------- Timed calls */

enum { F_DE_SIZE, F_DE, F_SER_SIZE, F_SER, F_ROOT, F_PROOF, F_GINDEX, F_VERIFY };
static const char *const fn_name[] = {
    "ssz_deserialize_size", "ssz_deserialize", "ssz_serialize_size", "ssz_serialize",
    "ssz_hash_tree_root",   "ssz_build_proof", "ssz_get_generalized_index", "ssz_verify_merkle_proof",
};

typedef struct {
    int fn;
    char name[256];
    uint64_t bytes;
    const uint8_t *desc;
    uint8_t *a, *b, *c, *d, *e; /* the call's arguments */
    uint64_t calls;             /* calls in one sample */
    double t[SAMPLES];          /* ns per call, one entry for each sample */
    int n;
} item;

static item *items;
static int nitems;

static uint64_t call(const item *it) {
    switch (it->fn) {
    case F_DE_SIZE: return ssz_deserialize_size(it->desc, it->a, it->b, it->c);
    case F_DE: return ssz_deserialize(it->desc, it->a, it->b, it->c);
    case F_SER_SIZE: return ssz_serialize_size(it->desc, it->a, it->b, it->c);
    case F_SER: return ssz_serialize(it->desc, it->a, it->b, it->c);
    case F_ROOT: return ssz_hash_tree_root(it->desc, it->a, it->b, it->c);
    case F_PROOF: return ssz_build_proof(it->desc, it->a, it->b, it->c, it->d);
    case F_GINDEX: return ssz_get_generalized_index(it->desc, it->a, it->b);
    default: return ssz_verify_merkle_proof(it->a, it->b, it->c, it->d, it->e);
    }
}

static int cmp_double(const void *x, const void *y) {
    double a = *(const double *)x, b = *(const double *)y;
    return (a > b) - (a < b);
}

/* Keep the timed thread on one fast core as far as the OS allows. */
static void settle(void) {
#if defined(__APPLE__)
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
#elif defined(_WIN32)
    SetThreadAffinityMask(GetCurrentThread(), (DWORD_PTR)1 << GetCurrentProcessorNumber());
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
#else
    cpu_set_t set;
    int cpu = sched_getcpu();
    CPU_ZERO(&set);
    CPU_SET(cpu < 0 ? 0 : cpu, &set);
    sched_setaffinity(0, sizeof set, &set);
#endif
}

static uint64_t refused;

/* Calls in one sample: double the batch until it runs an eighth of the target, then scale it. */
static void calibrate(item *it, double target) {
    uint64_t calls = 1;
    for (;;) {
        uint64_t start = now_ns();
        for (uint64_t k = 0; k < calls; k++) refused |= call(it);
        double took = (double)(now_ns() - start);
        if (took >= target / 8 || calls >= (1ull << 40)) {
            if (took > 0 && took < target) calls = (uint64_t)((double)calls * target / took) + 1;
            break;
        }
        calls *= 2;
    }
    it->calls = calls;
}

static void sample(item *it) {
    uint64_t start = now_ns();
    for (uint64_t k = 0; k < it->calls; k++) refused |= call(it);
    it->t[it->n++] = (double)(now_ns() - start) / (double)it->calls;
}

static void add_item(const item *it) {
    items = realloc(items, (size_t)(nitems + 1) * sizeof *items);
    if (!items) die("out of memory");
    items[nitems++] = *it;
}

static void check(int ok, const item *it, const char *what) {
    if (!ok) {
        fprintf(stderr, "bench: %s %s: %s\n", fn_name[it->fn], it->name, what);
        exit(1);
    }
}

/* Buffers for one decoded value of a descriptor. */
typedef struct {
    const uint8_t *desc;
    uint8_t *ser, *scratch, *value, *out;
    uint64_t value_size, out_size;
} decoded;

static void decode(decoded *d, const uint8_t *desc, const uint8_t *enc, uint64_t len) {
    const uint8_t *rn = root_node(desc);
    uint64_t scratch_size = rd64(rn + 64), ssize = 24 + len;
    d->desc = desc;
    d->ser = buffer(ssize);
    wr64(d->ser, ssize);
    wr64(d->ser + 8, 24);
    wr64(d->ser + 16, len);
    memcpy(d->ser + 24, enc, (size_t)len);
    d->scratch = buffer(scratch_size);
    wr64(d->scratch, scratch_size);
    if (ssz_deserialize_size(desc, d->ser, d->scratch, &d->value_size)) die("cannot size a workload value");
    d->value = buffer(d->value_size);
    if (rd64(rn + 24) == 0) wr64(d->value, d->value_size);
    if (ssz_deserialize(desc, d->ser, d->scratch, d->value)) die("cannot decode a workload value");
    if (ssz_serialize_size(desc, d->value, d->scratch, &d->out_size)) die("cannot size an encoding");
    d->out = buffer(d->out_size);
    wr64(d->out, d->out_size);
}

/* The static part: the largest case of each listed type. */
static void bench_static(const vecfile *v) {
    for (size_t k = 0; k < STATIC_TYPES; k++) {
        char needle[64];
        snprintf(needle, sizeof needle, "/ssz_static/%s/", static_types[k]);
        cursor c = {v->cases, v->data + v->len};
        const uint8_t *enc = NULL, *root = NULL, *desc = NULL;
        uint64_t len = 0;
        char name[256] = "";
        for (uint64_t i = 0; i < v->ncases; i++) {
            uint64_t nl = take64(&c);
            const char *cn = (const char *)take(&c, nl);
            uint64_t di = take64(&c), el = take64(&c);
            const uint8_t *e = take(&c, el), *r = take(&c, 32);
            char buf[256];
            snprintf(buf, sizeof buf, "%.*s", (int)(nl < 255 ? nl : 255), cn);
            if (strstr(buf, needle) && (!enc || el > len)) {
                enc = e, root = r, len = el, desc = v->desc[di];
                snprintf(name, sizeof name, "%s", buf);
            }
        }
        if (!enc) die("a workload type has no case");
        decoded d;
        decode(&d, desc, enc, len);
        uint64_t size = 0;
        uint8_t got[32];
        item it = {0};
        snprintf(it.name, sizeof it.name, "%s", name);
        it.bytes = len;
        it.desc = desc;

        it.fn = F_DE_SIZE, it.a = d.ser, it.b = d.scratch, it.c = (uint8_t *)&size;
        check(call(&it) == 0 && size == d.value_size, &it, "wrong size");
        add_item(&it);
        it.fn = F_DE, it.c = d.value;
        check(call(&it) == 0, &it, "refused");
        add_item(&it);
        it.fn = F_SER_SIZE, it.a = d.value, it.c = (uint8_t *)&size;
        check(call(&it) == 0 && size == 24 + len, &it, "wrong size");
        add_item(&it);
        it.fn = F_SER, it.c = d.out;
        check(call(&it) == 0 && !memcmp(d.out + 24, enc, (size_t)len), &it, "wrong encoding");
        add_item(&it);
        it.fn = F_ROOT, it.c = got;
        check(call(&it) == 0 && !memcmp(got, root, 32), &it, "wrong root");
        add_item(&it);
    }
}

/* Every proof case: build_proof on the decoded object. */
static void bench_proofs(const vecfile *v) {
    cursor c = {v->cases, v->data + v->len};
    for (uint64_t i = 0; i < v->ncases; i++) {
        uint64_t nl = take64(&c);
        const char *cn = (const char *)take(&c, nl);
        const uint8_t *desc = v->desc[take64(&c)];
        uint64_t el = take64(&c);
        const uint8_t *enc = take(&c, el);
        uint64_t gindex = take64(&c);
        take(&c, 32);
        uint64_t nodes = take64(&c);
        const uint8_t *branch = take(&c, 32 * nodes);
        decoded d;
        decode(&d, desc, enc, el);
        uint64_t bsize = 24 + 32 * nodes;
        uint8_t *out = buffer(bsize), *g = buffer(8);
        wr64(out, bsize);
        wr64(g, gindex);
        item it = {0};
        snprintf(it.name, sizeof it.name, "%.*s", (int)(nl < 255 ? nl : 255), cn);
        it.fn = F_PROOF, it.bytes = el, it.desc = desc;
        it.a = d.value, it.b = g, it.c = d.scratch, it.d = out;
        check(call(&it) == 0 && !memcmp(out + 24, branch, (size_t)(32 * nodes)), &it, "wrong branch");
        add_item(&it);
    }
}

/* The as-given verify cases: each must give valid = 1. */
static void bench_verify(const vecfile *v) {
    cursor c = {v->cases, v->data + v->len};
    for (uint64_t i = 0; i < v->ncases; i++) {
        uint64_t nl = take64(&c);
        const char *cn = (const char *)take(&c, nl);
        const uint8_t *leaf = take(&c, 32);
        uint64_t gindex = take64(&c);
        const uint8_t *root = take(&c, 32);
        uint64_t nodes = take64(&c);
        const uint8_t *branch = take(&c, 32 * nodes);
        uint64_t status = take64(&c), valid = take64(&c);
        char name[256];
        snprintf(name, sizeof name, "%.*s", (int)(nl < 255 ? nl : 255), cn);
        size_t n = strlen(name);
        if (n < 9 || strcmp(name + n - 9, "/as-given") || status || !valid) continue;
        uint64_t bsize = 24 + 32 * nodes;
        uint8_t *l = buffer(32), *r = buffer(32), *g = buffer(8), *b = buffer(bsize), *out = buffer(8);
        memcpy(l, leaf, 32);
        memcpy(r, root, 32);
        wr64(g, gindex);
        wr64(b, bsize);
        wr64(b + 8, 24);
        wr64(b + 16, nodes);
        memcpy(b + 24, branch, (size_t)(32 * nodes));
        item it = {0};
        snprintf(it.name, sizeof it.name, "%s", name);
        it.fn = F_VERIFY, it.bytes = 32 * nodes;
        it.a = l, it.b = b, it.c = g, it.d = r, it.e = out;
        check(call(&it) == 0 && rd64(out) == 1, &it, "not valid");
        add_item(&it);
    }
}

/* Every generalized index case from the spec tables. */
static void bench_gindex(const vecfile *v) {
    cursor c = {v->cases, v->data + v->len};
    for (uint64_t i = 0; i < v->ncases; i++) {
        uint64_t nl = take64(&c);
        const char *cn = (const char *)take(&c, nl);
        const uint8_t *desc = v->desc[take64(&c)];
        uint64_t count = take64(&c);
        const uint8_t *steps = take(&c, 8 * count);
        uint64_t status = take64(&c), expected = take64(&c);
        uint64_t psize = 24 + 8 * count;
        uint8_t *path = buffer(psize), *g = buffer(8);
        wr64(path, psize);
        wr64(path + 8, 24);
        wr64(path + 16, count);
        memcpy(path + 24, steps, (size_t)(8 * count));
        item it = {0};
        snprintf(it.name, sizeof it.name, "%.*s", (int)(nl < 255 ? nl : 255), cn);
        it.fn = F_GINDEX, it.desc = desc, it.a = path, it.b = g;
        check(status == 0 && call(&it) == 0 && rd64(g) == expected, &it, "wrong index");
        add_item(&it);
    }
}

static int run(const char *dir, int quick) {
    static vecfile st, pr, ve, gi;
    load(&st, dir, STATIC_FILE);
    load(&pr, dir, PROOF_FILE);
    load(&ve, dir, VERIFY_FILE);
    load(&gi, dir, GINDEX_FILE);
    char cpu[256];
    cpu_name(cpu, sizeof cpu);
    printf("asm-ssz bench\n");
    printf("os %s\nisa %s\ncpu %s\n", OS_NAME, ISA_NAME, cpu);
    printf("samples %d%s\n", quick ? QUICK_SAMPLES : SAMPLES, quick ? " quick" : "");
    printf("file %s %s\nfile %s %s\nfile %s %s\nfile %s %s\n", STATIC_FILE, st.sha256, PROOF_FILE, pr.sha256,
           VERIFY_FILE, ve.sha256, GINDEX_FILE, gi.sha256);
    printf("function case bytes calls p25_ns median_ns p75_ns\n");
    fflush(stdout);
    bench_static(&st);
    bench_proofs(&pr);
    bench_verify(&ve);
    bench_gindex(&gi);

    settle();
    for (int i = 0; i < nitems; i++) calibrate(&items[i], quick ? QUICK_SAMPLE_NS : SAMPLE_NS);
    int rounds = quick ? 1 : ROUNDS, per_round = quick ? QUICK_SAMPLES : SAMPLES_PER_ROUND;
    for (int r = 0; r < rounds; r++)
        for (int i = 0; i < nitems; i++)
            for (int k = 0; k < per_round; k++) sample(&items[i]);
    if (refused) die("a call returned a refusal while timed");
    for (int i = 0; i < nitems; i++) {
        item *it = &items[i];
        qsort(it->t, (size_t)it->n, sizeof it->t[0], cmp_double);
        printf("%s %s %llu %llu %.1f %.1f %.1f\n", fn_name[it->fn], it->name, (unsigned long long)it->bytes,
               (unsigned long long)it->calls, it->t[it->n / 4], it->t[it->n / 2], it->t[(3 * it->n) / 4]);
    }
    return 0;
}

/* ---------------------------------------------------------------- Compare */

typedef struct {
    char fn[64], name[256];
    double p25, median, p75;
} row;

typedef struct {
    char header[8][320]; /* os, isa, cpu, samples, then the workload files */
    int nheader;
    row *rows;
    int nrows;
} results;

static void read_results(results *r, const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) {
        fprintf(stderr, "bench: cannot read %s\n", path);
        exit(2);
    }
    char line[1024];
    int in_rows = 0;
    memset(r, 0, sizeof *r);
    r->rows = calloc(4096, sizeof *r->rows);
    while (fgets(line, sizeof line, f)) {
        line[strcspn(line, "\r\n")] = 0;
        if (!strncmp(line, "function ", 9)) {
            in_rows = 1;
            continue;
        }
        if (!in_rows) {
            if ((!strncmp(line, "os ", 3) || !strncmp(line, "isa ", 4) || !strncmp(line, "cpu ", 4)
                 || !strncmp(line, "samples ", 8) || !strncmp(line, "file ", 5)) && r->nheader < 8)
                snprintf(r->header[r->nheader++], sizeof r->header[0], "%s", line);
            continue;
        }
        row *w = &r->rows[r->nrows];
        unsigned long long bytes, calls;
        if (r->nrows < 4096 && sscanf(line, "%63s %255s %llu %llu %lf %lf %lf", w->fn, w->name, &bytes, &calls,
                                      &w->p25, &w->median, &w->p75) == 7)
            r->nrows++;
    }
    fclose(f);
    if (!in_rows) die("not a results file");
}

static int compare(const char *base_path, const char *new_path) {
    results a, b;
    read_results(&a, base_path);
    read_results(&b, new_path);
    if (a.nheader != b.nheader) die("the two results have different headers");
    for (int i = 0; i < a.nheader; i++) {
        if (!strncmp(a.header[i], "samples ", 8)) continue;
        if (strcmp(a.header[i], b.header[i])) {
            fprintf(stderr, "bench: the runs differ: \"%s\" and \"%s\"\n", a.header[i], b.header[i]);
            fprintf(stderr, "bench: compare runs from the same machine and workload only\n");
            return 2;
        }
    }
    int faster = 0, slower = 0, same = 0;
    printf("%-26s %-72s %12s %12s %7s  %s\n", "function", "case", "base_ns", "new_ns", "ratio", "result");
    for (int i = 0; i < a.nrows; i++) {
        const row *x = &a.rows[i], *y = NULL;
        for (int j = 0; j < b.nrows && !y; j++)
            if (!strcmp(x->fn, b.rows[j].fn) && !strcmp(x->name, b.rows[j].name)) y = &b.rows[j];
        if (!y) continue;
        const char *verdict = "within noise";
        if (y->p75 < x->p25 && x->median >= y->median * (1 + MIN_CHANGE)) verdict = "faster", faster++;
        else if (y->p25 > x->p75 && y->median >= x->median * (1 + MIN_CHANGE)) verdict = "slower", slower++;
        else same++;
        printf("%-26s %-72s %12.1f %12.1f %7.3f  %s\n", x->fn, x->name, x->median, y->median,
               x->median / y->median, verdict);
    }
    printf("faster %d, slower %d, within noise %d\n", faster, slower, same);
    return 0;
}

int main(int argc, char **argv) {
    if (argc >= 3 && !strcmp(argv[1], "run")) return run(argv[2], argc >= 4 && !strcmp(argv[3], "--quick"));
    if (argc == 4 && !strcmp(argv[1], "compare")) return compare(argv[2], argv[3]);
    fprintf(stderr, "usage: bench run VECTOR_DIR [--quick]\n       bench compare BASE NEW\n");
    return 2;
}
