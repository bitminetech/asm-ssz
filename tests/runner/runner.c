/*
 * asm-ssz vector runner. Test code: the library itself is assembly.
 *
 * Usage: runner VECTOR_DIR FILE ...
 *
 * Reads the case files that tests/generator/ writes (format in its README),
 * calls the library for every case and compares the results. It exits with
 * status 0 only when every case of every file passes.
 *
 * Every buffer is allocated at the exact size the library asks for, with guard
 * bytes after it, and output buffers start filled with 0xA5, so a write out of
 * bounds or a read of old output contents shows up as a failure.
 *
 * Every library call goes through abi_call (tests/runner/abi_<ISA>.s). The
 * runner prints the most stack each function used, and fails when a call uses
 * more than the README cap or changes state that the ABI says it must keep.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32) && defined(__x86_64__)
#define SSZ_ABI __attribute__((sysv_abi))
#else
#define SSZ_ABI
#endif

/* C view of include/ssz.inc and docs/reference/. */
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

#define GUARD 64
#define FILL 0xA5

/* The reason for a status mismatch, with both statuses. */
static char status_why[96];
static const char *status_differs(const char *function, uint64_t got, uint64_t want) {
    snprintf(status_why, sizeof status_why, "%s status %llu, expected %llu", function,
             (unsigned long long)got, (unsigned long long)want);
    return status_why;
}

/*
 * ABI and stack check. abi_call sets every register the callee must keep to a
 * known value and paints PAINT_BYTES of stack below the call. Afterwards it
 * reports the kept state that changed, and the bytes of stack the call used,
 * its return address included on x86-64.
 */
#define STACK_CAP 6144 /* README: stack per call */
#define PAINT_BYTES (STACK_CAP + 4096)

/* The record that abi_call reads and writes. The layout is in README.md. */
typedef struct {
    uint64_t fn, arg[5], paint, status, fault, stack, scratch[4];
} abi_ctx;
SSZ_ABI void abi_call(abi_ctx *ctx);

enum { F_SER_SIZE, F_SER, F_DE_SIZE, F_DE, F_ROOT, F_GINDEX, F_PROOF, F_VERIFY, F_COUNT };
static const char *const fn_name[F_COUNT] = {
    "ssz_serialize_size", "ssz_serialize", "ssz_deserialize_size", "ssz_deserialize",
    "ssz_hash_tree_root", "ssz_get_generalized_index", "ssz_build_proof", "ssz_verify_merkle_proof",
};
static uint64_t stack_peak[F_COUNT], stack_calls[F_COUNT], abi_fault[F_COUNT];

/* The functions that the cases of each file kind test, in enum order, and the files that tested each function. */
static const int kind_tests[7][F_COUNT] = {
    {0},
    {1, 1, 1, 1, 1, 0, 0, 0}, /* 1, static: decode, encode, root */
    {0, 0, 1, 1, 0, 0, 1, 0}, /* 2, proof: decode, build_proof */
    {0, 0, 0, 0, 0, 1, 0, 0}, /* 3, generalized index */
    {0, 0, 0, 0, 0, 0, 0, 1}, /* 4, verify */
    {0, 0, 1, 1, 0, 0, 0, 0}, /* 5, reject: both deserialize functions */
    {0, 0, 1, 1, 0, 0, 1, 0}, /* 6, proof outcome: decode, build_proof */
};
static uint64_t fn_files[F_COUNT], fn_failed_files[F_COUNT];

/* Call the library function f with its pointer arguments, through abi_call. */
static uint64_t checked_call(int fn, uint64_t f, const void *const *args, size_t n) {
    abi_ctx c;
    memset(&c, 0, sizeof c);
    c.fn = f;
    for (size_t i = 0; i < n; i++) c.arg[i] = (uint64_t)(uintptr_t)args[i];
    c.paint = PAINT_BYTES;
    abi_call(&c);
    if (c.stack > stack_peak[fn]) stack_peak[fn] = c.stack;
    stack_calls[fn]++;
    abi_fault[fn] |= c.fault;
    return c.status;
}

#define CALL(fn, f, ...)                                                                                       \
    checked_call(fn, (uint64_t)(uintptr_t)(f), (const void *const[]){__VA_ARGS__},                             \
                 sizeof((const void *const[]){__VA_ARGS__}) / sizeof(const void *))

static uint64_t rd64(const uint8_t *p) {
    uint64_t v = 0;
    for (int i = 7; i >= 0; i--) v = (v << 8) | p[i];
    return v;
}

static void wr64(uint8_t *p, uint64_t v) {
    for (int i = 0; i < 8; i++) p[i] = (uint8_t)(v >> (8 * i));
}

typedef struct {
    const uint8_t *p, *end;
    const char *file;
} cursor;

static const uint8_t *take(cursor *c, uint64_t n) {
    if ((uint64_t)(c->end - c->p) < n) {
        fprintf(stderr, "%s: file ends early\n", c->file);
        exit(2);
    }
    const uint8_t *r = c->p;
    c->p += n;
    return r;
}

static uint64_t take64(cursor *c) { return rd64(take(c, 8)); }

/* A buffer of n bytes, 8-aligned, filled, with GUARD guard bytes after it. */
static uint8_t *buffer(uint64_t n) {
    uint8_t *b = malloc((size_t)(n + GUARD));
    if (!b) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    memset(b, FILL, (size_t)(n + GUARD));
    return b;
}

static int guard_ok(const uint8_t *b, uint64_t n) {
    for (uint64_t i = 0; i < GUARD; i++)
        if (b[n + i] != FILL) return 0;
    return 1;
}

/* TypeNode fields of the root type of a descriptor. */
static const uint8_t *root_node(const uint8_t *d) {
    return d + rd64(d + 8) + 72 * rd64(d + 40);
}

typedef struct {
    uint8_t *desc;
    uint64_t scratch_size, mem_size, ssz_size;
} type_t;

static uint8_t *scratch_for(const type_t *t) {
    uint8_t *s = buffer(t->scratch_size);
    wr64(s, t->scratch_size);
    return s;
}

/* Decode an encoding into a new value. Returns the value or NULL, with a reason. */
static uint8_t *decode(const type_t *t, const uint8_t *enc, uint64_t len, uint64_t *value_size,
                       const char **why) {
    uint64_t off = 32, room = 7, ssize = off + len + room;
    uint8_t *ser = buffer(ssize);
    wr64(ser, ssize);
    wr64(ser + 8, off);
    wr64(ser + 16, len);
    memcpy(ser + off, enc, (size_t)len);
    uint8_t *scr = scratch_for(t);
    uint64_t size = 0, st = CALL(F_DE_SIZE, ssz_deserialize_size, t->desc, ser, scr, &size);
    uint8_t *value = NULL;
    if (st != 0) {
        *why = "deserialize_size status";
    } else {
        value = buffer(size);
        if (t->ssz_size == 0) wr64(value, size);
        st = CALL(F_DE, ssz_deserialize, t->desc, ser, scr, value);
        if (st != 0) *why = "deserialize status";
        else if (!guard_ok(value, size) || !guard_ok(scr, t->scratch_size) || !guard_ok(ser, ssize))
            *why = "deserialize wrote out of bounds";
        else *value_size = size;
        if (*why) {
            free(value);
            value = NULL;
        }
    }
    free(ser);
    free(scr);
    return value;
}

static int run_static(const type_t *t, const uint8_t *enc, uint64_t len, const uint8_t *root,
                      const char **why) {
    uint64_t vsize = 0;
    uint8_t *value = decode(t, enc, len, &vsize, why);
    if (!value) return 0;
    uint8_t *scr = scratch_for(t);
    uint64_t need = 0;
    int ok = 0;
    if (CALL(F_SER_SIZE, ssz_serialize_size, t->desc, value, scr, &need) != 0) *why = "serialize_size status";
    else if (need != 24 + len) *why = "serialize_size value";
    else {
        uint8_t *out = buffer(need);
        wr64(out, need);
        uint8_t got[32 + GUARD];
        memset(got, FILL, sizeof got);
        if (CALL(F_SER, ssz_serialize, t->desc, value, scr, out) != 0) *why = "serialize status";
        else if (rd64(out + 8) != 24 || rd64(out + 16) != len || memcmp(out + 24, enc, (size_t)len))
            *why = "serialize bytes";
        else if (!guard_ok(out, need)) *why = "serialize wrote out of bounds";
        else if (CALL(F_ROOT, ssz_hash_tree_root, t->desc, value, scr, got) != 0) *why = "hash_tree_root status";
        else if (memcmp(got, root, 32)) *why = "hash_tree_root value";
        else if (!guard_ok(got, 32)) *why = "hash_tree_root wrote past root";
        else if (!guard_ok(scr, t->scratch_size)) *why = "wrote past scratch";
        else if (!guard_ok(value, vsize)) *why = "wrote past value";
        else ok = 1;
        free(out);
    }
    free(scr);
    free(value);
    return ok;
}

/* An encoding the spec rejects: both deserialize functions return the expected refusal. */
static int run_reject(const type_t *t, const uint8_t *enc, uint64_t len, uint64_t want, const char **why) {
    uint64_t off = 32, ssize = off + len + 7;
    uint8_t *ser = buffer(ssize);
    wr64(ser, ssize);
    wr64(ser + 8, off);
    wr64(ser + 16, len);
    memcpy(ser + off, enc, (size_t)len);
    uint8_t *scr = scratch_for(t);
    uint64_t vsize = t->ssz_size ? t->mem_size : 64;
    uint8_t *value = buffer(vsize);
    if (t->ssz_size == 0) wr64(value, vsize);
    uint64_t size = 0, st;
    int ok = 0;
    if ((st = CALL(F_DE_SIZE, ssz_deserialize_size, t->desc, ser, scr, &size)) != want)
        *why = status_differs("deserialize_size", st, want);
    else if ((st = CALL(F_DE, ssz_deserialize, t->desc, ser, scr, value)) != want)
        *why = status_differs("deserialize", st, want);
    else if (!guard_ok(value, vsize) || !guard_ok(scr, t->scratch_size) || !guard_ok(ser, ssize))
        *why = "out of bounds write";
    else ok = 1;
    free(ser);
    free(scr);
    free(value);
    return ok;
}

static int run_proof(const type_t *t, const uint8_t *enc, uint64_t len, uint64_t gindex,
                     const uint8_t *branch, uint64_t nodes, const char **why) {
    uint64_t vsize = 0;
    uint8_t *value = decode(t, enc, len, &vsize, why);
    if (!value) return 0;
    uint8_t *scr = scratch_for(t);
    uint64_t bsize = 24 + 32 * nodes;
    uint8_t *out = buffer(bsize);
    wr64(out, bsize);
    uint64_t g = gindex;
    int ok = 0;
    if (CALL(F_PROOF, ssz_build_proof, t->desc, value, &g, scr, out) != 0) *why = "build_proof status";
    else if (rd64(out + 8) != 24 || rd64(out + 16) != nodes) *why = "build_proof count";
    else if (memcmp(out + 24, branch, (size_t)(32 * nodes))) *why = "build_proof nodes";
    else if (!guard_ok(out, bsize) || !guard_ok(scr, t->scratch_size)) *why = "out of bounds write";
    else ok = 1;
    free(out);
    free(scr);
    free(value);
    return ok;
}

/* A generated proof case: build_proof returns the expected status, and on status 0 the branch. */
static int run_proof_outcome(const type_t *t, const uint8_t *enc, uint64_t len, uint64_t gindex,
                             uint64_t want_status, const uint8_t *branch, uint64_t nodes, const char **why) {
    uint64_t vsize = 0;
    uint8_t *value = decode(t, enc, len, &vsize, why);
    if (!value) return 0;
    uint8_t *scr = scratch_for(t);
    uint64_t room = want_status ? 64 : nodes;
    uint64_t bsize = 24 + 32 * room;
    uint8_t *out = buffer(bsize);
    wr64(out, bsize);
    uint64_t g = gindex;
    int ok = 0;
    uint64_t st = CALL(F_PROOF, ssz_build_proof, t->desc, value, &g, scr, out);
    if (st != want_status) *why = status_differs("build_proof", st, want_status);
    else if (st == 0 && (rd64(out + 8) != 24 || rd64(out + 16) != nodes)) *why = "build_proof count";
    else if (st == 0 && memcmp(out + 24, branch, (size_t)(32 * nodes))) *why = "build_proof nodes";
    else if (!guard_ok(out, bsize) || !guard_ok(scr, t->scratch_size)) *why = "out of bounds write";
    else ok = 1;
    free(out);
    free(scr);
    free(value);
    return ok;
}

static int run_gindex(const type_t *t, const uint8_t *steps, uint64_t count, uint64_t want_status,
                      uint64_t expected, const char **why) {
    uint64_t psize = 24 + 8 * count;
    uint8_t *path = buffer(psize);
    wr64(path, psize);
    wr64(path + 8, 24);
    wr64(path + 16, count);
    memcpy(path + 24, steps, (size_t)(8 * count));
    uint8_t got[8 + GUARD];
    memset(got, FILL, sizeof got);
    int ok = 0;
    uint64_t st = CALL(F_GINDEX, ssz_get_generalized_index, t->desc, path, got);
    if (st != want_status) *why = status_differs("get_generalized_index", st, want_status);
    else if (st == 0 && rd64(got) != expected) *why = "get_generalized_index value";
    else if (!guard_ok(got, 8)) *why = "out of bounds write";
    else ok = 1;
    free(path);
    return ok;
}

static int run_verify(const uint8_t *leaf, uint64_t gindex, const uint8_t *root, const uint8_t *nodes,
                      uint64_t count, uint64_t want_status, uint64_t want_valid, const char **why) {
    uint8_t *l = buffer(32), *r = buffer(32), *g = buffer(8), *valid = buffer(8);
    uint64_t bsize = 24 + 32 * count;
    uint8_t *branch = buffer(bsize);
    memcpy(l, leaf, 32);
    memcpy(r, root, 32);
    wr64(g, gindex);
    wr64(branch, bsize);
    wr64(branch + 8, 24);
    wr64(branch + 16, count);
    memcpy(branch + 24, nodes, (size_t)(32 * count));
    int ok = 0;
    uint64_t st = CALL(F_VERIFY, ssz_verify_merkle_proof, l, branch, g, r, valid);
    if (st != want_status) *why = status_differs("verify_merkle_proof", st, want_status);
    else if (st == 0 && rd64(valid) != want_valid) *why = "verify_merkle_proof valid";
    else if (!guard_ok(valid, 8)) *why = "out of bounds write";
    else ok = 1;
    free(l);
    free(r);
    free(g);
    free(valid);
    free(branch);
    return ok;
}

static uint8_t *read_file(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *data = malloc(n > 0 ? (size_t)n : 1);
    if (!data || fread(data, 1, (size_t)n, f) != (size_t)n) {
        fclose(f);
        free(data);
        return NULL;
    }
    fclose(f);
    *len = (size_t)n;
    return data;
}

static int run_file(const char *dir, const char *name) {
    char path[4096];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    size_t len = 0;
    uint8_t *data = read_file(path, &len);
    if (!data) {
        fprintf(stderr, "%s: cannot read\n", path);
        return 1;
    }
    cursor c = {data, data + len, name};
    if (memcmp(take(&c, 8), "SSZVEC01", 8) != 0) {
        fprintf(stderr, "%s: wrong magic\n", name);
        exit(2);
    }
    uint64_t kind = take64(&c), ntypes = take64(&c);
    if (kind < 1 || kind > 6) {
        fprintf(stderr, "%s: unknown kind\n", name);
        exit(2);
    }
    type_t *types = calloc((size_t)ntypes, sizeof *types);
    for (uint64_t i = 0; i < ntypes; i++) {
        uint64_t n = take64(&c);
        types[i].desc = buffer(n);
        memcpy(types[i].desc, take(&c, n), (size_t)n);
        const uint8_t *root = root_node(types[i].desc);
        types[i].ssz_size = rd64(root + 24);
        types[i].mem_size = rd64(root + 32);
        types[i].scratch_size = rd64(root + 64);
    }
    uint64_t ncases = take64(&c), bad = 0;
    for (uint64_t k = 0; k < ncases; k++) {
        uint64_t nlen = take64(&c);
        const char *cname = (const char *)take(&c, nlen);
        const type_t *t = kind == 4 ? NULL : &types[take64(&c)];
        const char *why = NULL;
        int ok;
        if (kind == 1) {
            uint64_t elen = take64(&c);
            const uint8_t *enc = take(&c, elen);
            ok = run_static(t, enc, elen, take(&c, 32), &why);
        } else if (kind == 2) {
            uint64_t elen = take64(&c);
            const uint8_t *enc = take(&c, elen);
            uint64_t gindex = take64(&c);
            take(&c, 32); /* the leaf */
            uint64_t nodes = take64(&c);
            ok = run_proof(t, enc, elen, gindex, take(&c, 32 * nodes), nodes, &why);
        } else if (kind == 3) {
            uint64_t count = take64(&c);
            const uint8_t *steps = take(&c, 8 * count);
            uint64_t want_status = take64(&c);
            ok = run_gindex(t, steps, count, want_status, take64(&c), &why);
        } else if (kind == 6) {
            uint64_t elen = take64(&c);
            const uint8_t *enc = take(&c, elen);
            uint64_t gindex = take64(&c);
            uint64_t want_status = take64(&c);
            uint64_t nodes = take64(&c);
            ok = run_proof_outcome(t, enc, elen, gindex, want_status, take(&c, 32 * nodes), nodes, &why);
        } else if (kind == 5) {
            uint64_t elen = take64(&c);
            const uint8_t *enc = take(&c, elen);
            ok = run_reject(t, enc, elen, take64(&c), &why);
        } else if (kind == 4) {
            const uint8_t *leaf = take(&c, 32);
            uint64_t gindex = take64(&c);
            const uint8_t *root = take(&c, 32);
            uint64_t count = take64(&c);
            const uint8_t *nodes = take(&c, 32 * count);
            uint64_t want_status = take64(&c);
            ok = run_verify(leaf, gindex, root, nodes, count, want_status, take64(&c), &why);
        } else {
            fprintf(stderr, "%s: unknown kind\n", name);
            exit(2);
        }
        if (!ok) {
            if (bad < 10) fprintf(stderr, "%s: %.*s: %s\n", name, (int)nlen, cname, why);
            bad++;
        }
    }
    if (c.p != c.end) {
        fprintf(stderr, "%s: bytes left after the last case\n", name);
        exit(2);
    }
    printf("%s %s: %llu cases, %llu failed\n", bad ? "FAIL" : "PASS", name,
           (unsigned long long)ncases, (unsigned long long)bad);
    for (int fn = 0; fn < F_COUNT; fn++) {
        if (!kind_tests[kind][fn]) continue;
        fn_files[fn]++;
        if (bad) fn_failed_files[fn]++;
    }
    for (uint64_t i = 0; i < ntypes; i++) free(types[i].desc);
    free(types);
    free(data);
    return bad != 0;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: runner VECTOR_DIR FILE ...\n");
        return 2;
    }
    int failed = 0;
    for (int i = 2; i < argc; i++) failed |= run_file(argv[1], argv[i]);
    for (int fn = 0; fn < F_COUNT; fn++) {
        if (!stack_calls[fn]) continue;
        int over = stack_peak[fn] > STACK_CAP;
        printf("%s stack %s: %llu bytes, cap %d\n", over ? "FAIL" : "PASS", fn_name[fn],
               (unsigned long long)stack_peak[fn], STACK_CAP);
        failed |= over;
        if (over) fn_failed_files[fn]++;
    }
    for (int fn = 0; fn < F_COUNT; fn++) {
        if (!stack_calls[fn]) continue;
        if (abi_fault[fn])
            printf("FAIL abi %s: kept state changed, mask 0x%016llx\n", fn_name[fn], (unsigned long long)abi_fault[fn]);
        else
            printf("PASS abi %s: kept registers, stack pointer and flags\n", fn_name[fn]);
        failed |= abi_fault[fn] != 0;
        if (abi_fault[fn]) fn_failed_files[fn]++;
    }
    /* One verdict for each function: every file that tests it passed, within the stack cap and the ABI. */
    for (int fn = 0; fn < F_COUNT; fn++)
        printf("FUNCTION %s %s\n", fn_name[fn], fn_files[fn] && !fn_failed_files[fn] ? "PASS" : "FAIL");
    return failed;
}
