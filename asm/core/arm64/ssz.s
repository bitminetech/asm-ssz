/*
 * asm-ssz for ARM64 (AAPCS64).
 * Requirements: docs/reference/serialization.md, merkleization.md and proofs.md.
 * Layouts: include/ssz.inc.
 *
 * v1: follows the ssz-specs v0.1.0 steps, one value at a time.
 * Every function follows AAPCS64: pointer arguments, status in x0.
 * x18 is never used. Every non-leaf function keeps an x29 frame record.
 */
.set ISA_ARM64, 1
.include "ssz.inc"
.include "platform.inc"

/* ---------------------------------------------------------------- Macros */

/* Frame of a non-leaf function: x29, x30, x19-x28, then locals at sp + 96. */
.macro ENTER locals
    stp     x29, x30, [sp, #-(96 + \locals)]!
    UNWIND_SAVE_FPLR_X (96 + \locals)
    mov     x29, sp
    UNWIND_SET_FP
    stp     x19, x20, [sp, #16]
    UNWIND_SAVE_REGP x19, x20, 16, (96 + \locals)
    stp     x21, x22, [sp, #32]
    UNWIND_SAVE_REGP x21, x22, 32, (96 + \locals)
    stp     x23, x24, [sp, #48]
    UNWIND_SAVE_REGP x23, x24, 48, (96 + \locals)
    stp     x25, x26, [sp, #64]
    UNWIND_SAVE_REGP x25, x26, 64, (96 + \locals)
    stp     x27, x28, [sp, #80]
    UNWIND_SAVE_REGP x27, x28, 80, (96 + \locals)
    UNWIND_END_PROLOGUE
.endm

.macro LEAVE locals
    UNWIND_BEGIN_EPILOGUE
    ldp     x27, x28, [sp, #80]
    UNWIND_RESTORE_REGP x27, x28, 80
    ldp     x25, x26, [sp, #64]
    UNWIND_RESTORE_REGP x25, x26, 64
    ldp     x23, x24, [sp, #48]
    UNWIND_RESTORE_REGP x23, x24, 48
    ldp     x21, x22, [sp, #32]
    UNWIND_RESTORE_REGP x21, x22, 32
    ldp     x19, x20, [sp, #16]
    UNWIND_RESTORE_REGP x19, x20, 16
    ldp     x29, x30, [sp], #(96 + \locals)
    UNWIND_RESTORE_FPLR_X (96 + \locals)
    UNWIND_END_EPILOGUE
    ret
.endm

/* dst = address of TypeNode number idx. Uses x16, x17. */
.macro NODE dst, idx, ctx
    ldr     x16, [\ctx, #SSZ_CTX_NODES]
    mov     x17, #SSZ_NODE_STRIDE
    madd    \dst, \idx, x17, x16
.endm

/* dst = 32 bytes at src. Uses x16, x17. */
.macro COPY32 dst, src
    ldp     x16, x17, [\src]
    stp     x16, x17, [\dst]
    ldp     x16, x17, [\src, #16]
    stp     x16, x17, [\dst, #16]
.endm

/* Serialize: append len (x2) bytes from src (x1) at cursor x21; write them when ctx x19 says so. */
.macro COPY_OUT
    ldr     x9, [x21, #SSZ_CUR_OUT]
    add     x10, x9, x2
    str     x10, [x21, #SSZ_CUR_OUT]
    ldr     x11, [x19, #SSZ_CTX_WRITE]
    cbz     x11, 98f
97: cbz     x2, 98f
    ldrb    w12, [x1], #1
    strb    w12, [x9], #1
    sub     x2, x2, #1
    b       97b
98:
.endm

/* Deserialize: copy len bytes from src to dst when ctx x19 says to write. Uses x14-x17. */
.macro COPY_IN dst, src, len
    ldr     x16, [x19, #SSZ_CTX_WRITE]
    cbz     x16, 98f
    mov     x15, \dst
    mov     x16, \src
    mov     x17, \len
97: cbz     x17, 98f
    ldrb    w14, [x16], #1
    strb    w14, [x15], #1
    sub     x17, x17, #1
    b       97b
98:
.endm

/* Deserialize: write the PartRef at x22 (value start x23) for a part at part with count entries. */
.macro WRITE_PARTREF part, count
    ldr     x16, [x19, #SSZ_CTX_WRITE]
    cbz     x16, 98f
    sub     x16, \part, x23
    str     x16, [x22, #SSZ_PART_OFFSET]
    str     \count, [x22, #SSZ_PART_COUNT]
98:
.endm

/* Deserialize: reg = reg rounded up to a multiple of 8. */
.macro ROUND8 reg
    add     \reg, \reg, #7
    and     \reg, \reg, #-8
.endm

/* Deserialize: decode one child into the slot at sp + 96; on failure go to 280. */
.macro DE_CHILD node, p, b, form, scope
    str     \p, [sp, #(96 + SSZ_SLOT_P)]
    str     \b, [sp, #(96 + SSZ_SLOT_B)]
    mov     x17, #\form
    str     x17, [sp, #(96 + SSZ_SLOT_FORM)]
    str     \scope, [sp, #(96 + SSZ_SLOT_SCOPE)]
    mov     x0, x19
    mov     x1, \node
    add     x2, sp, #96
    mov     x3, x21
    bl      ssz_decode_value
    cbnz    x0, 280f
.endm

/*
 * Deserialize, container: for the variable field at x28, set x9 to the next
 * variable field (0 when none) and x10 to where its body ends: the next
 * variable field's offset, or the scope x25. Reads the end of the fields at
 * sp + 184 and the start of the encoding at sp + 168. Uses x11-x13.
 */
.macro NEXT_END
    ldr     x11, [sp, #184]
    add     x9, x28, #SSZ_FIELD_STRIDE
93: cmp     x9, x11
    b.hs    95f
    ldr     x12, [x9, #SSZ_FIELD_FLAGS]
    tbnz    x12, #0, 94f
    add     x9, x9, #SSZ_FIELD_STRIDE
    b       93b
94: ldr     x12, [x9, #SSZ_FIELD_SSZ_OFFSET]
    ldr     x13, [sp, #168]
    ldr     w10, [x13, x12]
    b       96f
95: mov     x9, #0
    mov     x10, x25
96:
.endm

/* Serialize: encode one child from the slot at sp + 96. */
.macro SER_CHILD node, p, b, form
    str     \p, [sp, #(96 + SSZ_SLOT_P)]
    str     \b, [sp, #(96 + SSZ_SLOT_B)]
    mov     x17, #\form
    str     x17, [sp, #(96 + SSZ_SLOT_FORM)]
    mov     x0, x19
    mov     x1, \node
    add     x2, sp, #96
    mov     x3, x21
    bl      ssz_encode_value
.endm

/* L2 entry: x20 = root TypeNode of the descriptor in x0. Uses x9, x10. */
.macro ROOT_NODE
    ldr     x9, [x0, #SSZ_DESC_NODES_OFFSET]
    add     x9, x0, x9
    ldr     x10, [x0, #SSZ_DESC_ROOT]
    mov     x20, #SSZ_NODE_STRIDE
    madd    x20, x10, x20, x9
.endm

/* L2 entry: fill the Ctx in the scratch at scr from the descriptor at desc; x19 = Ctx. */
.macro SETUP_CTX desc, scr
    add     x19, \scr, #SSZ_SCR_CTX
    ldr     x9, [\desc, #SSZ_DESC_NODES_OFFSET]
    add     x9, \desc, x9
    str     x9, [x19, #SSZ_CTX_NODES]
    ldr     x9, [\desc, #SSZ_DESC_FIELDS_OFFSET]
    add     x9, \desc, x9
    str     x9, [x19, #SSZ_CTX_FIELDS]
    str     xzr, [x19, #SSZ_CTX_WRITE]
    str     xzr, [x19, #SSZ_CTX_END]
    add     x9, \scr, #SSZ_SCR_SHA
    str     x9, [x19, #SSZ_CTX_SHA]
    mov     x10, #88
    str     x10, [x9, #SSZ_BYTES_SIZE]
    mov     x10, #SSZ_BYTES_FIXED
    str     x10, [x9, #SSZ_BYTES_OFFSET]
    mov     x10, #64
    str     x10, [x9, #SSZ_BYTES_COUNT]
    adr     x9, 300f
    str     x9, [x19, #SSZ_CTX_ZERO]
.endm

/* ---------------------------------------------------------------- Serialize */

/*
 * ssz_encode_value(ctx, node, slot, cursor): append the SSZ encoding of the value in
 * slot to cursor.out. Locals: child slot at sp + 96.
 * x19 ctx, x20 node, x21 cursor, x22 p, x23 b, x24 kind.
 */
LOCAL_FUNCTION ssz_encode_value
    ENTER   48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x3
    ldr     x22, [x2, #SSZ_SLOT_P]
    ldr     x23, [x2, #SSZ_SLOT_B]
    ldr     x9, [x2, #SSZ_SLOT_FORM]
    ldr     x24, [x20, #SSZ_NODE_KIND]
    cbz     x9, 10f
    /* A value of a variable size type starts at p. */
    cmp     x24, #SSZ_KIND_CONTAINER
    b.eq    40f
    mov     x23, x22
    add     x22, x22, #8
    b       30f
10: ldr     x10, [x20, #SSZ_NODE_SSZ_SIZE]
    cbz     x10, 30f
    cmp     x24, #SSZ_KIND_CONTAINER
    b.eq    40f
    cmp     x24, #SSZ_KIND_VECTOR
    b.eq    20f
    /* uint, boolean, byte vector, bit vector: the bytes as they are. */
    mov     x1, x22
    mov     x2, x10
    COPY_OUT
    b       90f
20: /* fixed size vector: N entries in place */
    ldr     x11, [x20, #SSZ_NODE_ELEMENT]
    NODE    x25, x11, x19
    ldr     x26, [x20, #SSZ_NODE_LENGTH]
    mov     x27, x22
    b       60f
30: /* variable size: a PartRef at p, offsets from b */
    ldr     x11, [x22, #SSZ_PART_OFFSET]
    add     x27, x23, x11
    ldr     x26, [x22, #SSZ_PART_COUNT]
    cmp     x24, #SSZ_KIND_CONTAINER
    b.ne    31f
    mov     x22, x27
    b       40f
31: cmp     x24, #SSZ_KIND_BYTE_LIST
    b.ne    32f
    mov     x1, x27
    mov     x2, x26
    COPY_OUT
    b       90f
32: cmp     x24, #SSZ_KIND_BIT_LIST
    b.ne    33f
    add     x2, x26, #7
    lsr     x2, x2, #3
    mov     x1, x27
    COPY_OUT
    /* the delimiter bit sits at bit position count */
    ldr     x11, [x19, #SSZ_CTX_WRITE]
    ldr     x9, [x21, #SSZ_CUR_OUT]
    ands    x10, x26, #7
    b.ne    34f
    add     x12, x9, #1
    str     x12, [x21, #SSZ_CUR_OUT]
    cbz     x11, 90f
    mov     w12, #1
    strb    w12, [x9]
    b       90f
34: cbz     x11, 90f
    ldurb   w12, [x9, #-1]
    mov     w13, #1
    lsl     w13, w13, w10
    orr     w12, w12, w13
    sturb   w12, [x9, #-1]
    b       90f
33: /* vector or list in a part */
    ldr     x11, [x20, #SSZ_NODE_ELEMENT]
    NODE    x25, x11, x19
    b       60f

40: /* container at x22: the fixed part, then the variable fields */
    ldr     x10, [x20, #SSZ_NODE_ELEMENT]
    ldr     x11, [x19, #SSZ_CTX_FIELDS]
    add     x25, x11, x10, lsl #5
    ldr     x26, [x20, #SSZ_NODE_LENGTH]
    ldr     x27, [x21, #SSZ_CUR_OUT]
    mov     x28, #0
41: cmp     x28, x26
    b.hs    45f
    add     x24, x25, x28, lsl #5
    ldr     x10, [x24, #SSZ_FIELD_FLAGS]
    tbz     x10, #0, 42f
    ldr     x11, [x21, #SSZ_CUR_OUT]
    add     x11, x11, #SSZ_BYTES_PER_LENGTH_OFFSET
    str     x11, [x21, #SSZ_CUR_OUT]
    b       43f
42: ldr     x10, [x24, #SSZ_FIELD_MEM_OFFSET]
    add     x10, x22, x10
    ldr     x11, [x24, #SSZ_FIELD_NODE]
    NODE    x12, x11, x19
    SER_CHILD x12, x10, x22, SSZ_FORM_PLACE
43: add     x28, x28, #1
    b       41b
45: mov     x28, #0
46: cmp     x28, x26
    b.hs    90f
    add     x24, x25, x28, lsl #5
    ldr     x10, [x24, #SSZ_FIELD_FLAGS]
    tbz     x10, #0, 48f
    ldr     x11, [x19, #SSZ_CTX_WRITE]
    cbz     x11, 47f
    ldr     x12, [x21, #SSZ_CUR_OUT]
    sub     x12, x12, x27
    ldr     x13, [x24, #SSZ_FIELD_SSZ_OFFSET]
    str     w12, [x27, x13]
47: ldr     x10, [x24, #SSZ_FIELD_MEM_OFFSET]
    add     x10, x22, x10
    ldr     x11, [x24, #SSZ_FIELD_NODE]
    NODE    x12, x11, x19
    SER_CHILD x12, x10, x22, SSZ_FORM_PLACE
48: add     x28, x28, #1
    b       46b

60: /* x26 elements of type x25 from x27 */
    ldr     x10, [x25, #SSZ_NODE_SSZ_SIZE]
    cbz     x10, 70f
    ldr     x11, [x25, #SSZ_NODE_KIND]
    cmp     x11, #SSZ_KIND_BOOLEAN
    b.hi    65f
    /* basic elements: their bytes are already packed */
    mul     x2, x26, x10
    mov     x1, x27
    COPY_OUT
    b       90f
65: cbz     x26, 90f
    SER_CHILD x25, x27, x27, SSZ_FORM_PLACE
    ldr     x10, [x25, #SSZ_NODE_MEM_SIZE]
    add     x27, x27, x10
    sub     x26, x26, #1
    b       65b
70: /* variable size elements: the offset table, then each nested value */
    ldr     x28, [x21, #SSZ_CUR_OUT]
    add     x10, x28, x26, lsl #2
    str     x10, [x21, #SSZ_CUR_OUT]
    mov     x24, #0
71: cmp     x24, x26
    b.hs    90f
    ldr     x11, [x19, #SSZ_CTX_WRITE]
    cbz     x11, 72f
    ldr     x12, [x21, #SSZ_CUR_OUT]
    sub     x12, x12, x28
    str     w12, [x28, x24, lsl #2]
72: SER_CHILD x25, x27, x27, SSZ_FORM_NESTED
    ldr     x10, [x27, #SSZ_VALUE_SIZE]
    add     x27, x27, x10
    add     x24, x24, #1
    b       71b

90: mov     x0, #SSZ_OK
    LEAVE   48
END_FUNCTION ssz_encode_value

/* ssz_serialize_size(type, value, scratch, size). Locals: slot at sp + 96, cursor at sp + 128. */
FUNCTION ssz_serialize_size
    ENTER   48
    mov     x21, x1
    mov     x22, x3
    mov     x23, x2
    ROOT_NODE
    ldr     x9, [x23]
    ldr     x10, [x20, #SSZ_NODE_SCRATCH]
    cmp     x9, x10
    b.lo    80f
    SETUP_CTX x0, x23
    str     x21, [sp, #(96 + SSZ_SLOT_P)]
    str     x21, [sp, #(96 + SSZ_SLOT_B)]
    ldr     x10, [x20, #SSZ_NODE_SSZ_SIZE]
    cmp     x10, #0
    cset    x11, eq
    lsl     x11, x11, #1
    str     x11, [sp, #(96 + SSZ_SLOT_FORM)]
    str     xzr, [sp, #128]
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #96
    add     x3, sp, #128
    bl      ssz_encode_value
    ldr     x9, [sp, #128]
    add     x9, x9, #SSZ_BYTES_FIXED
    str     x9, [x22]
    mov     x0, #SSZ_OK
    b       90f
80: mov     x0, #SSZ_BUFFER_TOO_SMALL
90: LEAVE   48
END_FUNCTION ssz_serialize_size

/* ssz_serialize(type, value, scratch, serialized). Locals: slot at sp + 96, cursor at sp + 128. */
FUNCTION ssz_serialize
    ENTER   48
    mov     x21, x1
    mov     x22, x3
    mov     x23, x2
    ROOT_NODE
    ldr     x9, [x23]
    ldr     x10, [x20, #SSZ_NODE_SCRATCH]
    cmp     x9, x10
    b.lo    80f
    SETUP_CTX x0, x23
    str     x21, [sp, #(96 + SSZ_SLOT_P)]
    str     x21, [sp, #(96 + SSZ_SLOT_B)]
    ldr     x10, [x20, #SSZ_NODE_SSZ_SIZE]
    cmp     x10, #0
    cset    x11, eq
    lsl     x11, x11, #1
    str     x11, [sp, #(96 + SSZ_SLOT_FORM)]
    /* measure */
    str     xzr, [sp, #128]
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #96
    add     x3, sp, #128
    bl      ssz_encode_value
    ldr     x24, [sp, #128]
    ldr     x9, [x22, #SSZ_BYTES_SIZE]
    add     x10, x24, #SSZ_BYTES_FIXED
    cmp     x9, x10
    b.lo    80f
    mov     x10, #SSZ_BYTES_FIXED
    str     x10, [x22, #SSZ_BYTES_OFFSET]
    str     x24, [x22, #SSZ_BYTES_COUNT]
    /* write */
    mov     x10, #1
    str     x10, [x19, #SSZ_CTX_WRITE]
    add     x10, x22, #SSZ_BYTES_FIXED
    str     x10, [sp, #128]
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #96
    add     x3, sp, #128
    bl      ssz_encode_value
    mov     x0, #SSZ_OK
    b       90f
80: mov     x0, #SSZ_BUFFER_TOO_SMALL
90: LEAVE   48
END_FUNCTION ssz_serialize

/* ---------------------------------------------------------------- Deserialize */

/*
 * ssz_decode_value(ctx, node, slot, cursor): decode slot.scope bytes at cursor.pos into
 * the value in slot, as v0.1.0 deserialize does. On a refusal the cursor is
 * restored. Locals: child slot sp + 96, cursor at entry sp + 128, value start
 * sp + 144, form sp + 152, spare sp + 160 to sp + 192.
 * x19 ctx, x20 node, x21 cursor, x22 p, x23 b, x24 kind, x25 scope.
 */
LOCAL_FUNCTION ssz_decode_value
    ENTER   96
    mov     x19, x0
    mov     x20, x1
    mov     x21, x3
    ldp     x9, x10, [x3]
    stp     x9, x10, [sp, #128]
    ldr     x22, [x2, #SSZ_SLOT_P]
    ldr     x23, [x2, #SSZ_SLOT_B]
    ldr     x9, [x2, #SSZ_SLOT_FORM]
    ldr     x25, [x2, #SSZ_SLOT_SCOPE]
    str     x22, [sp, #144]
    str     x9, [sp, #152]
    ldr     x24, [x20, #SSZ_NODE_KIND]
    cbz     x9, 10f
    /* A value of a variable size type starts at p; its parts start at value_fixed. */
    ldr     x10, [x20, #SSZ_NODE_VALUE_FIXED]
    add     x10, x22, x10
    str     x10, [x21, #SSZ_CUR_NEXT]
    cmp     x24, #SSZ_KIND_CONTAINER
    b.eq    40f
    mov     x23, x22
    add     x22, x22, #8
    b       30f

10: ldr     x10, [x20, #SSZ_NODE_SSZ_SIZE]
    cbz     x10, 30f
    cmp     x24, #SSZ_KIND_CONTAINER
    b.eq    40f
    cmp     x24, #SSZ_KIND_VECTOR
    b.eq    20f
    /* uint, boolean, byte vector, bit vector */
    cmp     x25, x10
    b.ne    201f
    ldr     x11, [x21, #SSZ_CUR_POS]
    add     x12, x11, x10
    ldr     x13, [x19, #SSZ_CTX_END]
    cmp     x12, x13
    b.hi    202f
    cmp     x24, #SSZ_KIND_BOOLEAN
    b.ne    11f
    ldrb    w14, [x11]
    cmp     w14, #1
    b.hi    203f
    b       15f
11: cmp     x24, #SSZ_KIND_BIT_VECTOR
    b.ne    15f
    ldr     x14, [x20, #SSZ_NODE_LENGTH]
    ands    x14, x14, #7
    b.eq    15f
    ldurb   w15, [x12, #-1]
    lsr     w15, w15, w14
    cbnz    w15, 204f
15: str     x12, [x21, #SSZ_CUR_POS]
    COPY_IN x22, x11, x10
    b       288f

20: /* fixed size vector: the scope is the SSZ size, then each entry */
    cmp     x25, x10
    b.ne    201f
    ldr     x11, [x20, #SSZ_NODE_ELEMENT]
    NODE    x26, x11, x19
    ldr     x27, [x20, #SSZ_NODE_LENGTH]
    mov     x28, x22
21: cbz     x27, 288f
    ldr     x24, [x26, #SSZ_NODE_SSZ_SIZE]
    DE_CHILD x26, x28, x23, SSZ_FORM_PLACE, x24
    ldr     x10, [x26, #SSZ_NODE_MEM_SIZE]
    add     x28, x28, x10
    sub     x27, x27, #1
    b       21b

30: /* variable size in place: a PartRef at p, offsets from b */
    cmp     x24, #SSZ_KIND_CONTAINER
    b.ne    31f
    ldr     x26, [x21, #SSZ_CUR_NEXT]
    DE_CHILD x20, x26, x26, SSZ_FORM_NESTED, x25
    mov     x27, #1
    WRITE_PARTREF x26, x27
    b       288f
31: cmp     x24, #SSZ_KIND_BYTE_LIST
    b.ne    33f
    ldr     x10, [x20, #SSZ_NODE_LENGTH]
    cmp     x25, x10
    b.hi    205f
    ldr     x11, [x21, #SSZ_CUR_POS]
    add     x12, x11, x25
    ldr     x13, [x19, #SSZ_CTX_END]
    cmp     x12, x13
    b.hi    202f
    str     x12, [x21, #SSZ_CUR_POS]
    ldr     x26, [x21, #SSZ_CUR_NEXT]
    WRITE_PARTREF x26, x25
    COPY_IN x26, x11, x25
    mov     x10, x25
    ROUND8  x10
    add     x10, x26, x10
    str     x10, [x21, #SSZ_CUR_NEXT]
    b       288f
33: cmp     x24, #SSZ_KIND_BIT_LIST
    b.ne    50f
    ldr     x11, [x21, #SSZ_CUR_POS]
    add     x12, x11, x25
    ldr     x13, [x19, #SSZ_CTX_END]
    cmp     x12, x13
    b.hi    202f
    cbz     x25, 206f
    ldurb   w14, [x12, #-1]
    cbnz    w14, 35f
    /* the last byte is zero: zero bytes past the delimiter, or no delimiter */
    mov     x15, x11
34: cmp     x15, x12
    b.hs    207f
    ldrb    w16, [x15], #1
    cbz     w16, 34b
    b       208f
35: clz     w15, w14
    mov     w16, #31
    sub     w24, w16, w15                  /* delimiter bit in the last byte */
    sub     x16, x25, #1
    add     x26, x24, x16, lsl #3          /* bit count */
    ldr     x10, [x20, #SSZ_NODE_LENGTH]
    cmp     x26, x10
    b.hi    205f
    str     x12, [x21, #SSZ_CUR_POS]
    add     x27, x26, #7
    lsr     x27, x27, #3                   /* data bytes */
    ldr     x28, [x21, #SSZ_CUR_NEXT]
    WRITE_PARTREF x28, x26
    COPY_IN x28, x11, x27
    /* clear the delimiter when it shares the last data byte */
    cbz     x24, 36f
    ldr     x16, [x19, #SSZ_CTX_WRITE]
    cbz     x16, 36f
    add     x16, x28, x27
    ldurb   w17, [x16, #-1]
    mov     w14, #1
    lsl     w14, w14, w24
    bic     w17, w17, w14
    sturb   w17, [x16, #-1]
36: mov     x10, x27
    ROUND8  x10
    add     x10, x28, x10
    str     x10, [x21, #SSZ_CUR_NEXT]
    b       288f

40: /* container at x22 */
    ldr     x10, [x20, #SSZ_NODE_ELEMENT]
    ldr     x11, [x19, #SSZ_CTX_FIELDS]
    add     x26, x11, x10, lsl #5          /* first field */
    ldr     x27, [x20, #SSZ_NODE_LENGTH]
    add     x10, x26, x27, lsl #5
    str     x10, [sp, #184]                /* end of the fields */
    ldr     x12, [x21, #SSZ_CUR_POS]
    str     x12, [sp, #168]                /* start of the encoding */
    str     xzr, [sp, #176]                /* first variable field */
    mov     x28, x26
41: ldr     x10, [sp, #184]
    cmp     x28, x10
    b.hs    44f
    ldr     x10, [x28, #SSZ_FIELD_FLAGS]
    tbz     x10, #0, 42f
    ldr     x11, [sp, #176]
    cbnz    x11, 45f
    str     x28, [sp, #176]
45: ldr     x11, [x21, #SSZ_CUR_POS]
    add     x12, x11, #SSZ_BYTES_PER_LENGTH_OFFSET
    ldr     x13, [x19, #SSZ_CTX_END]
    cmp     x12, x13
    b.hi    202f
    str     x12, [x21, #SSZ_CUR_POS]
    b       43f
42: ldr     x10, [x28, #SSZ_FIELD_MEM_OFFSET]
    add     x10, x22, x10
    ldr     x11, [x28, #SSZ_FIELD_NODE]
    NODE    x24, x11, x19
    ldr     x27, [x24, #SSZ_NODE_SSZ_SIZE]
    DE_CHILD x24, x10, x22, SSZ_FORM_PLACE, x27
43: add     x28, x28, #SSZ_FIELD_STRIDE
    b       41b
44: ldr     x10, [x21, #SSZ_CUR_POS]
    ldr     x11, [sp, #168]
    sub     x12, x10, x11                  /* bytes read */
    ldr     x13, [sp, #176]
    cbnz    x13, 46f
    cmp     x25, x12
    b.ne    201f
    b       288f
46: ldr     x14, [x13, #SSZ_FIELD_SSZ_OFFSET]
    ldr     w15, [x11, x14]
    cmp     x15, x12
    b.ne    211f
    /* the spans of the variable fields */
    mov     x28, x13
47: NEXT_END
    ldr     x14, [x28, #SSZ_FIELD_SSZ_OFFSET]
    ldr     x11, [sp, #168]
    ldr     w15, [x11, x14]                /* start */
    cmp     x10, x15
    b.hs    48f
    cbz     x9, 214f
    b       215f
48: cbz     x9, 49f
    mov     x28, x9
    b       47b
49: /* the bodies of the variable fields */
    ldr     x28, [sp, #176]
491:
    NEXT_END
    str     x9, [sp, #160]                 /* next variable field */
    ldr     x14, [x28, #SSZ_FIELD_SSZ_OFFSET]
    ldr     x11, [sp, #168]
    ldr     w15, [x11, x14]
    sub     x27, x10, x15                  /* span */
    ldr     x10, [x28, #SSZ_FIELD_MEM_OFFSET]
    add     x10, x22, x10
    ldr     x11, [x28, #SSZ_FIELD_NODE]
    NODE    x24, x11, x19
    DE_CHILD x24, x10, x22, SSZ_FORM_PLACE, x27
    ldr     x28, [sp, #160]
    cbnz    x28, 491b
    b       288f

50: /* vector or list in a part */
    ldr     x11, [x20, #SSZ_NODE_ELEMENT]
    NODE    x26, x11, x19
    ldr     x10, [x26, #SSZ_NODE_SSZ_SIZE]
    cbz     x10, 60f
    /* list of fixed size elements */
    cbz     x25, 55f
    udiv    x27, x25, x10
    msub    x11, x27, x10, x25
    cbnz    x11, 209f
    ldr     x12, [x20, #SSZ_NODE_LENGTH]
    cmp     x27, x12
    b.hi    205f
    ldr     x28, [x21, #SSZ_CUR_NEXT]
    WRITE_PARTREF x28, x27
    ldr     x11, [x26, #SSZ_NODE_MEM_SIZE]
    mul     x11, x11, x27
    ROUND8  x11
    add     x11, x28, x11
    str     x11, [x21, #SSZ_CUR_NEXT]
52: cbz     x27, 288f
    ldr     x24, [x26, #SSZ_NODE_SSZ_SIZE]
    DE_CHILD x26, x28, x23, SSZ_FORM_PLACE, x24
    ldr     x10, [x26, #SSZ_NODE_MEM_SIZE]
    add     x28, x28, x10
    sub     x27, x27, #1
    b       52b
55: ldr     x28, [x21, #SSZ_CUR_NEXT]
    WRITE_PARTREF x28, xzr
    b       288f

60: /* variable size elements: the offset table */
    cmp     x24, #SSZ_KIND_VECTOR
    b.ne    62f
    ldr     x27, [x20, #SSZ_NODE_LENGTH]
    lsl     x10, x27, #2
    cmp     x25, x10
    b.lo    210f
    ldr     x11, [x21, #SSZ_CUR_POS]
    add     x12, x11, x10
    ldr     x13, [x19, #SSZ_CTX_END]
    cmp     x12, x13
    b.hi    202f
    ldr     w14, [x11]
    cmp     x14, x10
    b.ne    211f
    b       64f
62: cbz     x25, 55b
    cmp     x25, #SSZ_BYTES_PER_LENGTH_OFFSET
    b.lo    210f
    ldr     x11, [x21, #SSZ_CUR_POS]
    add     x12, x11, #SSZ_BYTES_PER_LENGTH_OFFSET
    ldr     x13, [x19, #SSZ_CTX_END]
    cmp     x12, x13
    b.hi    202f
    ldr     w14, [x11]
    cmp     x14, #SSZ_BYTES_PER_LENGTH_OFFSET
    b.lo    212f
    tst     x14, #3
    b.ne    213f
    cmp     x14, x25
    b.hi    214f
    lsr     x27, x14, #2
    ldr     x10, [x20, #SSZ_NODE_LENGTH]
    cmp     x27, x10
    b.hi    205f
    add     x12, x11, x14
    cmp     x12, x13
    b.hi    202f
64: /* x27 offsets at x11: check the spans */
    mov     x10, #0
65: cmp     x10, x27
    b.hs    67f
    ldr     w12, [x11, x10, lsl #2]
    add     x13, x10, #1
    cmp     x13, x27
    b.hs    66f
    ldr     w14, [x11, x13, lsl #2]
    cmp     x14, x12
    b.lo    215f
    mov     x10, x13
    b       65b
66: cmp     x25, x12
    b.lo    214f
67: /* the nested values */
    ldr     x28, [x21, #SSZ_CUR_NEXT]
    WRITE_PARTREF x28, x27
    add     x12, x11, x27, lsl #2
    str     x12, [x21, #SSZ_CUR_POS]
    str     x11, [sp, #168]                /* offset table */
    mov     x24, #0
68: cmp     x24, x27
    b.hs    288f
    ldr     x11, [sp, #168]
    ldr     w12, [x11, x24, lsl #2]
    add     x13, x24, #1
    mov     x14, x25
    cmp     x13, x27
    b.hs    69f
    ldr     w14, [x11, x13, lsl #2]
69: sub     x15, x14, x12                  /* span */
    ldr     x28, [x21, #SSZ_CUR_NEXT]
    DE_CHILD x26, x28, x28, SSZ_FORM_NESTED, x15
    add     x24, x24, #1
    b       68b

288: /* success: a nested value records its size */
    ldr     x9, [sp, #152]
    cmp     x9, #SSZ_FORM_NESTED
    b.ne    289f
    ldr     x10, [x19, #SSZ_CTX_WRITE]
    cbz     x10, 289f
    ldr     x11, [sp, #144]
    ldr     x12, [x21, #SSZ_CUR_NEXT]
    sub     x12, x12, x11
    str     x12, [x11, #SSZ_VALUE_SIZE]
289: mov    x0, #SSZ_OK
    b       299f
201: mov    x0, #SSZ_SCOPE
    b       280f
202: mov    x0, #SSZ_TRUNCATED
    b       280f
203: mov    x0, #SSZ_NOT_A_BIT
    b       280f
204: mov    x0, #SSZ_PADDING_BITS
    b       280f
205: mov    x0, #SSZ_LIMIT
    b       280f
206: mov    x0, #SSZ_EMPTY_ENCODING
    b       280f
207: mov    x0, #SSZ_NO_DELIMITER
    b       280f
208: mov    x0, #SSZ_TRAILING_ZEROS
    b       280f
209: mov    x0, #SSZ_SCOPE_UNDIVIDED
    b       280f
210: mov    x0, #SSZ_SCOPE_TOO_SMALL
    b       280f
211: mov    x0, #SSZ_FIRST_OFFSET
    b       280f
212: mov    x0, #SSZ_OFFSET_BELOW_TABLE
    b       280f
213: mov    x0, #SSZ_OFFSET_UNALIGNED
    b       280f
214: mov    x0, #SSZ_OFFSET_PAST_SCOPE
    b       280f
215: mov    x0, #SSZ_OFFSET_UNORDERED
280: /* refusal: restore the cursor */
    ldp     x9, x10, [sp, #128]
    stp     x9, x10, [x21]
299: LEAVE  96
END_FUNCTION ssz_decode_value

/*
 * L2 deserialize, decode_bytes rules for the top value. Uses x19 ctx, x20 root
 * TypeNode, x21 serialized ByteList, x25 value start (0 when only measuring),
 * the slot at sp + 96 and the cursor at sp + 128. Sets x0 to the status and x26
 * to the size of the value.
 */
.macro DE_TOP
    ldr     x9, [x21, #SSZ_BYTES_OFFSET]
    add     x9, x21, x9
    ldr     x10, [x21, #SSZ_BYTES_COUNT]
    add     x11, x9, x10
    str     x11, [x19, #SSZ_CTX_END]
    str     x9, [sp, #(128 + SSZ_CUR_POS)]
    str     x25, [sp, #(96 + SSZ_SLOT_P)]
    str     x25, [sp, #(96 + SSZ_SLOT_B)]
    str     x10, [sp, #(96 + SSZ_SLOT_SCOPE)]
    ldr     x24, [x20, #SSZ_NODE_KIND]
    ldr     x12, [x20, #SSZ_NODE_SSZ_SIZE]
    cbz     x12, 85f
    /* fixed size: a basic value or a byte or bit vector must be exactly its size */
    cmp     x24, #SSZ_KIND_CONTAINER
    b.eq    83f
    cmp     x24, #SSZ_KIND_VECTOR
    b.eq    83f
    cmp     x10, x12
    b.eq    83f
    mov     x0, #SSZ_TRUNCATED
    cmp     x24, #SSZ_KIND_BYTE_VECTOR
    b.ne    89f
    mov     x0, #SSZ_COUNT
    b       89f
83: str     xzr, [sp, #(96 + SSZ_SLOT_FORM)]
    ldr     x13, [x20, #SSZ_NODE_MEM_SIZE]
    add     x13, x25, x13
    str     x13, [sp, #(128 + SSZ_CUR_NEXT)]
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #96
    add     x3, sp, #128
    bl      ssz_decode_value
    cbnz    x0, 89f
    ldr     x26, [x20, #SSZ_NODE_MEM_SIZE]
    b       87f
85: mov     x13, #SSZ_FORM_TOP
    str     x13, [sp, #(96 + SSZ_SLOT_FORM)]
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #96
    add     x3, sp, #128
    bl      ssz_decode_value
    cbnz    x0, 89f
    ldr     x26, [sp, #(128 + SSZ_CUR_NEXT)]
    sub     x26, x26, x25
    cmp     x24, #SSZ_KIND_BYTE_LIST
    b.eq    88f
    cmp     x24, #SSZ_KIND_BIT_LIST
    b.eq    88f
87: ldr     x13, [sp, #(128 + SSZ_CUR_POS)]
    ldr     x14, [x19, #SSZ_CTX_END]
    cmp     x13, x14
    mov     x0, #SSZ_TRAILING_BYTES
    b.ne    89f
88: mov     x0, #SSZ_OK
89:
.endm

/* ssz_deserialize_size(type, serialized, scratch, size). Locals: slot sp + 96, cursor sp + 128. */
FUNCTION ssz_deserialize_size
    ENTER   64
    mov     x21, x1
    mov     x22, x3
    mov     x23, x2
    ROOT_NODE
    ldr     x9, [x23]
    ldr     x10, [x20, #SSZ_NODE_SCRATCH]
    cmp     x9, x10
    b.lo    80f
    SETUP_CTX x0, x23
    mov     x25, #0
    DE_TOP
    cbnz    x0, 90f
    str     x26, [x22]
    mov     x0, #SSZ_OK
    b       90f
80: mov     x0, #SSZ_BUFFER_TOO_SMALL
90: LEAVE   64
END_FUNCTION ssz_deserialize_size

/* ssz_deserialize(type, serialized, scratch, value). Locals: slot sp + 96, cursor sp + 128. */
FUNCTION ssz_deserialize
    ENTER   64
    mov     x21, x1
    mov     x22, x3
    mov     x23, x2
    ROOT_NODE
    ldr     x9, [x23]
    ldr     x10, [x20, #SSZ_NODE_SCRATCH]
    cmp     x9, x10
    b.lo    80f
    SETUP_CTX x0, x23
    /* check and measure */
    mov     x25, #0
    DE_TOP
    cbnz    x0, 90f
    ldr     x9, [x20, #SSZ_NODE_SSZ_SIZE]
    cbnz    x9, 70f
    ldr     x9, [x22, #SSZ_VALUE_SIZE]
    cmp     x9, x26
    b.lo    80f
70: /* write */
    mov     x10, #1
    str     x10, [x19, #SSZ_CTX_WRITE]
    mov     x25, x22
    DE_TOP
    b       90f
80: mov     x0, #SSZ_BUFFER_TOO_SMALL
90: LEAVE   64
END_FUNCTION ssz_deserialize

/* ---------------------------------------------------------------- Merkleization */

/* ssz_hash_pair(ctx, left, right, out): out = SHA-256(left || right), 32 bytes each. */
LOCAL_FUNCTION ssz_hash_pair
    ENTER   0
    ldr     x9, [x0, #SSZ_CTX_SHA]
    add     x10, x9, #SSZ_BYTES_FIXED
    COPY32  x10, x1
    add     x11, x10, #32
    COPY32  x11, x2
    mov     x0, x9
    mov     x1, x3
    CALL_EXTERN crypto_sha256
    mov     x0, #SSZ_OK
    LEAVE   0
END_FUNCTION ssz_hash_pair

/* ssz_value_level(ctx, node, slot, level): describe the leaves of the value in slot. */
LOCAL_FUNCTION ssz_value_level
    UNWIND_END_PROLOGUE
    ldr     x9, [x2, #SSZ_SLOT_P]
    ldr     x10, [x2, #SSZ_SLOT_B]
    ldr     x11, [x2, #SSZ_SLOT_FORM]
    ldr     x12, [x1, #SSZ_NODE_KIND]
    ldr     x13, [x1, #SSZ_NODE_CHUNKS]
    sub     x13, x13, #1
    clz     x13, x13
    mov     x14, #64
    sub     x13, x14, x13
    str     x13, [x3, #SSZ_LEVEL_DEPTH]
    str     xzr, [x3, #SSZ_LEVEL_MIXIN]
    str     xzr, [x3, #SSZ_LEVEL_LENGTH]
    str     xzr, [x3, #SSZ_LEVEL_C]
    str     xzr, [x3, #SSZ_LEVEL_WALK_I]
    str     xzr, [x3, #SSZ_LEVEL_WALK_V]
    cbz     x11, 10f
    /* a value of a variable size type at p */
    cmp     x12, #SSZ_KIND_CONTAINER
    b.eq    40f
    mov     x10, x9
    add     x9, x9, #8
    b       20f
10: ldr     x13, [x1, #SSZ_NODE_SSZ_SIZE]
    cbz     x13, 20f
    cmp     x12, #SSZ_KIND_CONTAINER
    b.eq    40f
    cmp     x12, #SSZ_KIND_VECTOR
    b.ne    50f
    ldr     x13, [x1, #SSZ_NODE_ELEMENT]
    NODE    x15, x13, x0
    ldr     x14, [x1, #SSZ_NODE_LENGTH]
    b       30f
20: /* a PartRef at x9, offsets from x10: x9 = part, x14 = count */
    ldr     x14, [x9, #SSZ_PART_OFFSET]
    add     x14, x10, x14
    ldr     x15, [x9, #SSZ_PART_COUNT]
    mov     x9, x14
    mov     x14, x15
    cmp     x12, #SSZ_KIND_CONTAINER
    b.eq    40f
    mov     x16, #1
    cmp     x12, #SSZ_KIND_BYTE_LIST
    b.ne    21f
    str     x14, [x3, #SSZ_LEVEL_LENGTH]
    str     x16, [x3, #SSZ_LEVEL_MIXIN]
    mov     x13, x14
    b       50f
21: cmp     x12, #SSZ_KIND_BIT_LIST
    b.ne    22f
    str     x14, [x3, #SSZ_LEVEL_LENGTH]
    str     x16, [x3, #SSZ_LEVEL_MIXIN]
    add     x13, x14, #7
    lsr     x13, x13, #3
    b       50f
22: cmp     x12, #SSZ_KIND_LIST
    b.ne    23f
    str     x14, [x3, #SSZ_LEVEL_LENGTH]
    str     x16, [x3, #SSZ_LEVEL_MIXIN]
23: ldr     x13, [x1, #SSZ_NODE_ELEMENT]
    NODE    x15, x13, x0
30: /* elements of type x15 from x9, count x14 */
    ldr     x13, [x15, #SSZ_NODE_SSZ_SIZE]
    cbz     x13, 35f
    ldr     x16, [x15, #SSZ_NODE_KIND]
    cmp     x16, #SSZ_KIND_BOOLEAN
    b.hi    32f
    mul     x13, x14, x13
    b       50f
32: mov     x16, #SSZ_MODE_FIXED
    str     x16, [x3, #SSZ_LEVEL_MODE]
    str     x14, [x3, #SSZ_LEVEL_COUNT]
    str     x15, [x3, #SSZ_LEVEL_A]
    str     x9, [x3, #SSZ_LEVEL_B]
    ldr     x16, [x15, #SSZ_NODE_MEM_SIZE]
    str     x16, [x3, #SSZ_LEVEL_C]
    b       90f
35: mov     x16, #SSZ_MODE_VARIABLE
    str     x16, [x3, #SSZ_LEVEL_MODE]
    str     x14, [x3, #SSZ_LEVEL_COUNT]
    str     x15, [x3, #SSZ_LEVEL_A]
    str     x9, [x3, #SSZ_LEVEL_B]
    str     x9, [x3, #SSZ_LEVEL_WALK_V]
    b       90f
40: /* container value at x9 */
    mov     x16, #SSZ_MODE_FIELDS
    str     x16, [x3, #SSZ_LEVEL_MODE]
    ldr     x16, [x1, #SSZ_NODE_LENGTH]
    str     x16, [x3, #SSZ_LEVEL_COUNT]
    str     x1, [x3, #SSZ_LEVEL_A]
    str     x9, [x3, #SSZ_LEVEL_B]
    b       90f
50: /* packed bytes at x9, length x13 */
    mov     x16, #SSZ_MODE_PACKED
    str     x16, [x3, #SSZ_LEVEL_MODE]
    str     x9, [x3, #SSZ_LEVEL_A]
    str     x13, [x3, #SSZ_LEVEL_B]
    add     x16, x13, #31
    lsr     x16, x16, #5
    str     x16, [x3, #SSZ_LEVEL_COUNT]
90: mov     x0, #SSZ_OK
    ret
END_FUNCTION ssz_value_level

/* ssz_child_level(ctx, level, index, child): describe the leaves of leaf index of level. */
LOCAL_FUNCTION ssz_child_level
    ENTER   32
    mov     x19, x0
    mov     x20, x1
    ldr     x21, [x2]
    mov     x22, x3
    ldr     x9, [x20, #SSZ_LEVEL_MODE]
    cmp     x9, #SSZ_MODE_FIXED
    b.ne    2f
    ldr     x10, [x20, #SSZ_LEVEL_B]
    ldr     x11, [x20, #SSZ_LEVEL_C]
    madd    x10, x21, x11, x10
    str     x10, [sp, #(96 + SSZ_SLOT_P)]
    str     x10, [sp, #(96 + SSZ_SLOT_B)]
    str     xzr, [sp, #(96 + SSZ_SLOT_FORM)]
    ldr     x1, [x20, #SSZ_LEVEL_A]
    b       9f
2:  cmp     x9, #SSZ_MODE_VARIABLE
    b.ne    5f
    ldr     x10, [x20, #SSZ_LEVEL_WALK_I]
    ldr     x11, [x20, #SSZ_LEVEL_WALK_V]
    cmp     x21, x10
    b.hs    3f
    mov     x10, #0
    ldr     x11, [x20, #SSZ_LEVEL_B]
3:  cmp     x10, x21
    b.hs    4f
    ldr     x12, [x11, #SSZ_VALUE_SIZE]
    add     x11, x11, x12
    add     x10, x10, #1
    b       3b
4:  str     x10, [x20, #SSZ_LEVEL_WALK_I]
    str     x11, [x20, #SSZ_LEVEL_WALK_V]
    str     x11, [sp, #(96 + SSZ_SLOT_P)]
    str     x11, [sp, #(96 + SSZ_SLOT_B)]
    mov     x12, #SSZ_FORM_NESTED
    str     x12, [sp, #(96 + SSZ_SLOT_FORM)]
    ldr     x1, [x20, #SSZ_LEVEL_A]
    b       9f
5:  /* container field number index */
    ldr     x13, [x20, #SSZ_LEVEL_A]
    ldr     x10, [x13, #SSZ_NODE_ELEMENT]
    add     x10, x10, x21
    ldr     x11, [x19, #SSZ_CTX_FIELDS]
    add     x10, x11, x10, lsl #5
    ldr     x12, [x20, #SSZ_LEVEL_B]
    ldr     x14, [x10, #SSZ_FIELD_MEM_OFFSET]
    add     x14, x12, x14
    str     x14, [sp, #(96 + SSZ_SLOT_P)]
    str     x12, [sp, #(96 + SSZ_SLOT_B)]
    str     xzr, [sp, #(96 + SSZ_SLOT_FORM)]
    ldr     x13, [x10, #SSZ_FIELD_NODE]
    NODE    x1, x13, x19
9:  mov     x0, x19
    add     x2, sp, #96
    mov     x3, x22
    bl      ssz_value_level
    mov     x0, #SSZ_OK
    LEAVE   32
END_FUNCTION ssz_child_level

/* ssz_level_leaf(ctx, level, index, work, out): out = leaf index of level. */
LOCAL_FUNCTION ssz_level_leaf
    ENTER   0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x9, [x20, #SSZ_LEVEL_MODE]
    cbnz    x9, 20f
    /* packed: the 32 bytes at 32 * index, zero padded */
    stp     xzr, xzr, [x23]
    stp     xzr, xzr, [x23, #16]
    ldr     x10, [x20, #SSZ_LEVEL_A]
    ldr     x11, [x20, #SSZ_LEVEL_B]
    ldr     x12, [x21]
    lsl     x12, x12, #5
    add     x10, x10, x12
    sub     x13, x11, x12
    mov     x14, #32
    cmp     x13, x14
    csel    x13, x13, x14, lo
    mov     x15, x23
1:  cbz     x13, 90f
    ldrb    w16, [x10], #1
    strb    w16, [x15], #1
    sub     x13, x13, #1
    b       1b
20: /* the root of the child value: child level at work + 8, child work after it */
    add     x24, x22, #8
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    mov     x3, x24
    bl      ssz_child_level
    add     x25, x24, #SSZ_LEVEL_SIZE
    ldr     x9, [x22]
    sub     x9, x9, #(8 + SSZ_LEVEL_SIZE)
    str     x9, [x25]
    mov     x0, x19
    mov     x1, x24
    mov     x2, x25
    mov     x3, x23
    bl      ssz_level_root
90: mov     x0, #SSZ_OK
    LEAVE   0
END_FUNCTION ssz_level_leaf

/* ssz_level_root(ctx, level, work, out): out = hash tree root of the value of level. */
LOCAL_FUNCTION ssz_level_root
    ENTER   48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    str     xzr, [sp, #(96 + SSZ_RANGE_LO)]
    ldr     x9, [x20, #SSZ_LEVEL_DEPTH]
    str     x9, [sp, #(96 + SSZ_RANGE_DEPTH)]
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #96
    mov     x3, x21
    mov     x4, x22
    bl      ssz_subtree_root
    ldr     x9, [x20, #SSZ_LEVEL_MIXIN]
    cbz     x9, 90f
    /* mix in the length as a 32-byte little-endian number */
    ldr     x10, [x20, #SSZ_LEVEL_LENGTH]
    str     x10, [sp, #112]
    str     xzr, [sp, #120]
    stp     xzr, xzr, [sp, #128]
    mov     x0, x19
    mov     x1, x22
    add     x2, sp, #112
    mov     x3, x22
    bl      ssz_hash_pair
90: mov     x0, #SSZ_OK
    LEAVE   48
END_FUNCTION ssz_level_root

/*
 * ssz_subtree_root(ctx, level, range, work, out): out = root of the subtree of
 * depth range.depth over leaves range.lo onward, padded with zero trees.
 * work: size, frontier of depth + 1 nodes, the node h, then the leaf work.
 * Locals: index sp + 96, a node is pending sp + 104, leaf work sp + 112, j sp + 120.
 */
LOCAL_FUNCTION ssz_subtree_root
    ENTER   32
    mov     x19, x0
    mov     x20, x1
    ldr     x21, [x2, #SSZ_RANGE_LO]
    ldr     x22, [x2, #SSZ_RANGE_DEPTH]
    mov     x23, x3
    mov     x24, x4
    ldr     x9, [x20, #SSZ_LEVEL_COUNT]
    cmp     x21, x9
    b.lo    10f
    /* no data in the range: a zero tree */
    ldr     x10, [x19, #SSZ_CTX_ZERO]
    add     x10, x10, x22, lsl #5
    COPY32  x24, x10
    b       90f
10: sub     x25, x9, x21                   /* leaves with data, m */
    cmp     x22, #63
    b.hs    11f
    mov     x10, #1
    lsl     x10, x10, x22
    cmp     x25, x10
    csel    x25, x25, x10, lo
11: add     x27, x23, #8                   /* frontier */
    add     x28, x22, #1
    add     x28, x27, x28, lsl #5          /* h */
    add     x10, x28, #32                  /* leaf work, only when leaves are child values */
    str     x10, [sp, #112]
    ldr     x13, [x20, #SSZ_LEVEL_MODE]
    cbz     x13, 12f
    sub     x11, x10, x23
    ldr     x12, [x23]
    sub     x12, x12, x11
    str     x12, [x10]
12:
    mov     x26, #0                        /* k */
20: cmp     x26, x25
    b.hs    40f
    add     x10, x21, x26
    str     x10, [sp, #96]
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #96
    ldr     x3, [sp, #112]
    mov     x4, x28
    bl      ssz_level_leaf
    str     xzr, [sp, #120]
21: ldr     x10, [sp, #120]
    lsr     x11, x26, x10
    tbz     x11, #0, 22f
    mov     x0, x19
    add     x1, x27, x10, lsl #5
    mov     x2, x28
    mov     x3, x28
    bl      ssz_hash_pair
    ldr     x10, [sp, #120]
    add     x10, x10, #1
    str     x10, [sp, #120]
    b       21b
22: ldr     x10, [sp, #120]
    add     x10, x27, x10, lsl #5
    COPY32  x10, x28
    add     x26, x26, #1
    b       20b
40: /* close the right edge with zero trees */
    str     xzr, [sp, #104]
    mov     x26, #0                        /* j */
41: cmp     x26, x22
    b.hs    50f
    lsr     x10, x25, x26
    tbz     x10, #0, 45f
    add     x1, x27, x26, lsl #5
    ldr     x11, [sp, #104]
    cbnz    x11, 42f
    ldr     x2, [x19, #SSZ_CTX_ZERO]
    add     x2, x2, x26, lsl #5
    mov     x11, #1
    str     x11, [sp, #104]
    b       43f
42: mov     x2, x28
43: mov     x0, x19
    mov     x3, x28
    bl      ssz_hash_pair
    b       46f
45: ldr     x11, [sp, #104]
    cbz     x11, 46f
    mov     x0, x19
    mov     x1, x28
    ldr     x2, [x19, #SSZ_CTX_ZERO]
    add     x2, x2, x26, lsl #5
    mov     x3, x28
    bl      ssz_hash_pair
46: add     x26, x26, #1
    b       41b
50: ldr     x11, [sp, #104]
    cbnz    x11, 51f
    add     x10, x27, x22, lsl #5
    COPY32  x24, x10
    b       90f
51: COPY32  x24, x28
90: mov     x0, #SSZ_OK
    LEAVE   32
END_FUNCTION ssz_subtree_root

/* ssz_hash_tree_root(type, value, scratch, root). Locals: slot at sp + 96. */
FUNCTION ssz_hash_tree_root
    ENTER   32
    mov     x21, x1
    mov     x22, x3
    mov     x23, x2
    ROOT_NODE
    ldr     x9, [x23]
    ldr     x10, [x20, #SSZ_NODE_SCRATCH]
    cmp     x9, x10
    b.lo    80f
    SETUP_CTX x0, x23
    str     x21, [sp, #(96 + SSZ_SLOT_P)]
    str     x21, [sp, #(96 + SSZ_SLOT_B)]
    ldr     x10, [x20, #SSZ_NODE_SSZ_SIZE]
    cmp     x10, #0
    cset    x11, eq
    lsl     x11, x11, #1
    str     x11, [sp, #(96 + SSZ_SLOT_FORM)]
    add     x24, x23, #SSZ_SCR_LEVEL
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #96
    mov     x3, x24
    bl      ssz_value_level
    add     x25, x23, #SSZ_SCR_WORK
    ldr     x9, [x23]
    sub     x9, x9, #SSZ_SCR_WORK
    str     x9, [x25]
    mov     x0, x19
    mov     x1, x24
    mov     x2, x25
    mov     x3, x22
    bl      ssz_level_root
    mov     x0, #SSZ_OK
    b       90f
80: mov     x0, #SSZ_BUFFER_TOO_SMALL
90: LEAVE   32
END_FUNCTION ssz_hash_tree_root

/* ---------------------------------------------------------------- Generalized indices and proofs */

/* ssz_get_generalized_index(type, path, gindex). A leaf: x0-x17 only. */
FUNCTION ssz_get_generalized_index
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #SSZ_DESC_NODES_OFFSET]
    add     x9, x0, x9                     /* nodes */
    ldr     x10, [x0, #SSZ_DESC_FIELDS_OFFSET]
    add     x10, x0, x10                   /* fields */
    ldr     x11, [x0, #SSZ_DESC_ROOT]
    mov     x12, #SSZ_NODE_STRIDE
    madd    x11, x11, x12, x9              /* current type */
    ldr     x12, [x1, #SSZ_BYTES_OFFSET]
    add     x12, x1, x12                   /* steps */
    ldr     x13, [x1, #SSZ_BYTES_COUNT]
    mov     x14, #0                        /* step number */
    mov     x15, #1                        /* index */
    mov     x3, #0                         /* 1 once the path is inside a basic value */
1:  cmp     x14, x13
    b.hs    90f
    ldr     x4, [x12, x14, lsl #3]
    cbnz    x3, 81f
    ldr     x5, [x11, #SSZ_NODE_KIND]
    cmp     x5, #SSZ_KIND_BOOLEAN
    b.ls    81f
    cmn     x4, #1
    b.ne    10f
    /* the length that a list mixes in: the right child, and the last step */
    cmp     x5, #SSZ_KIND_BYTE_LIST
    b.eq    2f
    cmp     x5, #SSZ_KIND_BIT_LIST
    b.eq    2f
    cmp     x5, #SSZ_KIND_LIST
    b.ne    82f
2:  add     x6, x14, #1
    cmp     x6, x13
    b.ne    83f
    tbnz    x15, #63, 86f
    lsl     x15, x15, #1
    add     x15, x15, #1
    b       90f
10: ldr     x6, [x11, #SSZ_NODE_CHUNKS]
    sub     x6, x6, #1
    clz     x6, x6
    mov     x7, #64
    sub     x6, x7, x6                     /* tree depth */
    ldr     x7, [x11, #SSZ_NODE_LENGTH]
    cmp     x5, #SSZ_KIND_CONTAINER
    b.ne    20f
    cmp     x4, x7
    b.hs    84f
    mov     x8, x4                         /* leaf */
    ldr     x16, [x11, #SSZ_NODE_ELEMENT]
    add     x16, x16, x4
    add     x16, x10, x16, lsl #5
    ldr     x16, [x16, #SSZ_FIELD_NODE]
    mov     x17, #SSZ_NODE_STRIDE
    madd    x16, x16, x17, x9              /* next type */
    b       50f
20: cmp     x4, x7
    b.hs    85f
    cmp     x5, #SSZ_KIND_BYTE_VECTOR
    b.eq    21f
    cmp     x5, #SSZ_KIND_BYTE_LIST
    b.ne    22f
21: lsr     x8, x4, #5
    mov     x3, #1
    mov     x16, x11
    b       50f
22: cmp     x5, #SSZ_KIND_BIT_VECTOR
    b.eq    23f
    cmp     x5, #SSZ_KIND_BIT_LIST
    b.ne    24f
23: lsr     x8, x4, #8
    mov     x3, #1
    mov     x16, x11
    b       50f
24: /* vector or list: basic elements pack into chunks */
    ldr     x16, [x11, #SSZ_NODE_ELEMENT]
    mov     x17, #SSZ_NODE_STRIDE
    madd    x16, x16, x17, x9
    ldr     x17, [x16, #SSZ_NODE_KIND]
    mov     x7, #32
    cmp     x17, #SSZ_KIND_BOOLEAN
    b.hi    25f
    ldr     x7, [x16, #SSZ_NODE_SSZ_SIZE]
25: mul     x8, x4, x7
    umulh   x17, x4, x7
    lsr     x8, x8, #5
    orr     x8, x8, x17, lsl #59
50: /* a list puts its data on the left of the length */
    cmp     x5, #SSZ_KIND_LIST
    b.eq    51f
    cmp     x5, #SSZ_KIND_BYTE_LIST
    b.eq    51f
    cmp     x5, #SSZ_KIND_BIT_LIST
    b.ne    52f
51: tbnz    x15, #63, 86f
    lsl     x15, x15, #1
52: cbz     x6, 53f
    mov     x7, #64
    sub     x7, x7, x6
    lsr     x17, x15, x7
    cbnz    x17, 86f
    lsl     x15, x15, x6
    orr     x15, x15, x8
53: mov     x11, x16
    add     x14, x14, #1
    b       1b
90: str     x15, [x2]
    mov     x0, #SSZ_OK
    ret
81: mov     x0, #SSZ_NO_PARTS
    ret
82: mov     x0, #SSZ_NO_MIXIN
    ret
83: mov     x0, #SSZ_NO_PARTS_MIXIN
    ret
84: mov     x0, #SSZ_NO_SUCH_FIELD
    ret
85: mov     x0, #SSZ_NO_SUCH_POSITION
    ret
86: mov     x0, #SSZ_GINDEX_TOO_LARGE
    ret
END_FUNCTION ssz_get_generalized_index

/*
 * ssz_build_proof(type, value, gindex, scratch, branch). Two passes over the
 * path: the first only checks it, the second writes the branch.
 * Locals: slot sp + 96, range sp + 128, index sp + 144, pass sp + 152,
 * q sp + 160, step sp + 168, bits left at this level sp + 176, tree depth sp + 184.
 * x19 ctx, x20 level, x21 value, x22 branch, x23 scratch, x24 gindex,
 * x25 root TypeNode, x26 branch length D, x27 bits used, x28 work.
 */
FUNCTION ssz_build_proof
    ENTER   96
    mov     x21, x1
    mov     x22, x4
    mov     x23, x3
    ldr     x24, [x2]
    ROOT_NODE
    mov     x25, x20
    cbz     x24, 82f
    ldr     x9, [x23]
    ldr     x10, [x25, #SSZ_NODE_SCRATCH]
    cmp     x9, x10
    b.lo    80f
    SETUP_CTX x0, x23
    clz     x9, x24
    mov     x10, #63
    sub     x26, x10, x9
    str     xzr, [sp, #152]
30: /* one pass from the root */
    str     x21, [sp, #(96 + SSZ_SLOT_P)]
    str     x21, [sp, #(96 + SSZ_SLOT_B)]
    ldr     x10, [x25, #SSZ_NODE_SSZ_SIZE]
    cmp     x10, #0
    cset    x11, eq
    lsl     x11, x11, #1
    str     x11, [sp, #(96 + SSZ_SLOT_FORM)]
    add     x20, x23, #SSZ_SCR_LEVEL
    mov     x0, x19
    mov     x1, x25
    add     x2, sp, #96
    mov     x3, x20
    bl      ssz_value_level
    add     x28, x23, #SSZ_SCR_WORK
    ldr     x9, [x23]
    sub     x9, x9, #SSZ_SCR_WORK
    str     x9, [x28]
    mov     x27, #0
31: sub     x9, x26, x27                   /* bits left */
    cbz     x9, 70f
    ldr     x10, [x20, #SSZ_LEVEL_MIXIN]
    cbz     x10, 35f
    /* the length mixin level */
    sub     x9, x9, #1
    lsr     x11, x24, x9
    add     x27, x27, #1
    sub     x12, x26, x27
    add     x12, x22, x12, lsl #5
    add     x12, x12, #SSZ_BYTES_FIXED     /* branch node for this depth */
    tbnz    x11, #0, 33f
    /* left: the data tree; its sibling is the length */
    ldr     x13, [sp, #152]
    cbz     x13, 35f
    ldr     x14, [x20, #SSZ_LEVEL_LENGTH]
    str     x14, [x12]
    str     xzr, [x12, #8]
    stp     xzr, xzr, [x12, #16]
    b       35f
33: /* right: the length itself, which must end the path; its sibling is the data root */
    cbnz    x9, 83f
    ldr     x13, [sp, #152]
    cbz     x13, 70f
    str     xzr, [sp, #(128 + SSZ_RANGE_LO)]
    ldr     x14, [x20, #SSZ_LEVEL_DEPTH]
    str     x14, [sp, #(128 + SSZ_RANGE_DEPTH)]
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #128
    mov     x3, x28
    mov     x4, x12
    bl      ssz_subtree_root
    b       70f
35: /* down this level's tree */
    sub     x9, x26, x27
    str     x9, [sp, #176]
    ldr     x10, [x20, #SSZ_LEVEL_DEPTH]
    str     x10, [sp, #184]
    str     xzr, [sp, #160]
    str     xzr, [sp, #168]
36: ldr     x11, [sp, #168]
    ldr     x9, [sp, #176]
    ldr     x10, [sp, #184]
    cmp     x11, x9
    b.hs    38f
    cmp     x11, x10
    b.hs    38f
    add     x11, x11, #1
    str     x11, [sp, #168]
    sub     x12, x9, x11
    lsr     x12, x24, x12
    and     x12, x12, #1
    ldr     x13, [sp, #160]
    orr     x13, x12, x13, lsl #1
    str     x13, [sp, #160]
    add     x27, x27, #1
    ldr     x14, [sp, #152]
    cbz     x14, 36b
    /* the sibling q ^ 1 covers 2^(depth - step) leaves */
    eor     x15, x13, #1
    sub     x16, x10, x11
    lsl     x15, x15, x16
    str     x15, [sp, #(128 + SSZ_RANGE_LO)]
    str     x16, [sp, #(128 + SSZ_RANGE_DEPTH)]
    sub     x12, x26, x27
    add     x12, x22, x12, lsl #5
    add     x4, x12, #SSZ_BYTES_FIXED
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #128
    mov     x3, x28
    bl      ssz_subtree_root
    b       36b
38: ldr     x9, [sp, #176]
    ldr     x10, [sp, #184]
    cmp     x9, x10
    b.ls    70f
    /* the path goes on into leaf q */
    ldr     x11, [x20, #SSZ_LEVEL_MODE]
    cbz     x11, 84f
    ldr     x13, [sp, #160]
    ldr     x12, [x20, #SSZ_LEVEL_COUNT]
    cmp     x13, x12
    b.hs    85f
    str     x13, [sp, #144]
    add     x14, x28, #8
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #144
    mov     x3, x14
    bl      ssz_child_level
    add     x20, x28, #8
    add     x9, x20, #SSZ_LEVEL_SIZE
    ldr     x10, [x28]
    sub     x10, x10, #(8 + SSZ_LEVEL_SIZE)
    str     x10, [x9]
    mov     x28, x9
    b       31b
70: /* end of a pass */
    ldr     x9, [sp, #152]
    cbnz    x9, 79f
    ldr     x10, [x22, #SSZ_BYTES_SIZE]
    lsl     x11, x26, #5
    add     x11, x11, #SSZ_BYTES_FIXED
    cmp     x10, x11
    b.lo    80f
    mov     x10, #SSZ_BYTES_FIXED
    str     x10, [x22, #SSZ_BYTES_OFFSET]
    str     x26, [x22, #SSZ_BYTES_COUNT]
    mov     x9, #1
    str     x9, [sp, #152]
    b       30b
79: mov     x0, #SSZ_OK
    b       90f
80: mov     x0, #SSZ_BUFFER_TOO_SMALL
    b       90f
82: mov     x0, #SSZ_NOT_A_GINDEX
    b       90f
83: mov     x0, #SSZ_PATH_INTO_MIXIN
    b       90f
84: mov     x0, #SSZ_PATH_INTO_PACKED
    b       90f
85: mov     x0, #SSZ_PATH_INTO_GAP
90: LEAVE   96
END_FUNCTION ssz_build_proof

/*
 * ssz_verify_merkle_proof(leaf, branch, gindex, root, valid). Rebuilds the root
 * from leaf and branch, as v0.1.0 calculate_merkle_root does, and compares it.
 * x19 next branch node, x20 node count, x21 gindex, x22 root, x23 valid,
 * x24 level. Locals: the SHA-256 input ByteList at sp + 96 (88 bytes), the
 * node at sp + 184.
 */
FUNCTION ssz_verify_merkle_proof
    ENTER   128
    ldr     x21, [x2]
    cbz     x21, 81f
    /* depth = the bit length of gindex - 1 */
    clz     x9, x21
    mov     x10, #63
    sub     x10, x10, x9
    cbz     x10, 82f
    ldr     x20, [x1, #SSZ_BYTES_COUNT]
    cmp     x20, x10
    b.ne    83f
    ldr     x9, [x1, #SSZ_BYTES_OFFSET]
    add     x19, x1, x9
    mov     x22, x3
    mov     x23, x4
    add     x9, sp, #184
    COPY32  x9, x0
    add     x9, sp, #96
    mov     x10, #88
    str     x10, [x9, #SSZ_BYTES_SIZE]
    mov     x10, #SSZ_BYTES_FIXED
    str     x10, [x9, #SSZ_BYTES_OFFSET]
    mov     x10, #64
    str     x10, [x9, #SSZ_BYTES_COUNT]
    mov     x24, #0
1:  cmp     x24, x20
    b.hs    5f
    add     x9, sp, #(96 + SSZ_BYTES_FIXED)
    add     x10, sp, #(96 + SSZ_BYTES_FIXED + 32)
    add     x11, sp, #184
    lsr     x12, x21, x24
    tbz     x12, #0, 2f
    /* bit set: the branch node is on the left */
    COPY32  x9, x19
    COPY32  x10, x11
    b       3f
2:  COPY32  x9, x11
    COPY32  x10, x19
3:  add     x0, sp, #96
    add     x1, sp, #184
    CALL_EXTERN crypto_sha256
    add     x19, x19, #32
    add     x24, x24, #1
    b       1b
5:  /* valid = 1 when the node equals root */
    ldp     x9, x10, [sp, #184]
    ldp     x11, x12, [x22]
    eor     x9, x9, x11
    eor     x10, x10, x12
    orr     x9, x9, x10
    ldp     x10, x11, [sp, #200]
    ldp     x12, x13, [x22, #16]
    eor     x10, x10, x12
    eor     x11, x11, x13
    orr     x10, x10, x11
    orr     x9, x9, x10
    cmp     x9, #0
    cset    x9, eq
    str     x9, [x23]
    mov     x0, #SSZ_OK
    b       90f
81: mov     x0, #SSZ_NOT_A_GINDEX
    b       90f
82: mov     x0, #SSZ_ROOT_HAS_NO_BRANCH
    b       90f
83: mov     x0, #SSZ_BRANCH_LENGTH
90: LEAVE   128
END_FUNCTION ssz_verify_merkle_proof

/* ---------------------------------------------------------------- Constants */

    .p2align 3
300:
.include "ssz_zero_hashes.inc"
