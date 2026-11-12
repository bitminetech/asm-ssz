/*
 * asm-ssz for RISC-V (RISC-V ELF psABI, LP64D).
 * Requirements: docs/reference/serialization.md, merkleization.md and proofs.md.
 * Layouts: include/ssz.inc.
 *
 * v1: follows the ssz-specs v0.1.0 steps, one value at a time.
 * Every function follows the psABI: pointer arguments, status in a0.
 * Baseline RV64GC instructions only, so bit lengths are found with loops.
 * Trailing comments use #, which the RISC-V assembler requires after a register.
 */
.set ISA_RISCV64, 1
.include "ssz.inc"
.include "platform.inc"

/* ---------------------------------------------------------------- Macros */

/* Frame of a non-leaf function: locals at sp + 0, then ra and s1-s10. */
.macro ENTER locals
    addi    sp, sp, -(\locals + 96)
    UNWIND_ALLOC (\locals + 96)
    sd      ra, (\locals + 0)(sp)
    UNWIND_SAVE ra, (\locals + 0)
    sd      s1, (\locals + 8)(sp)
    UNWIND_SAVE s1, (\locals + 8)
    sd      s2, (\locals + 16)(sp)
    UNWIND_SAVE s2, (\locals + 16)
    sd      s3, (\locals + 24)(sp)
    UNWIND_SAVE s3, (\locals + 24)
    sd      s4, (\locals + 32)(sp)
    UNWIND_SAVE s4, (\locals + 32)
    sd      s5, (\locals + 40)(sp)
    UNWIND_SAVE s5, (\locals + 40)
    sd      s6, (\locals + 48)(sp)
    UNWIND_SAVE s6, (\locals + 48)
    sd      s7, (\locals + 56)(sp)
    UNWIND_SAVE s7, (\locals + 56)
    sd      s8, (\locals + 64)(sp)
    UNWIND_SAVE s8, (\locals + 64)
    sd      s9, (\locals + 72)(sp)
    UNWIND_SAVE s9, (\locals + 72)
    sd      s10, (\locals + 80)(sp)
    UNWIND_SAVE s10, (\locals + 80)
    UNWIND_END_PROLOGUE
.endm

.macro LEAVE locals
    UNWIND_BEGIN_EPILOGUE
    ld      ra, (\locals + 0)(sp)
    UNWIND_RESTORE ra
    ld      s1, (\locals + 8)(sp)
    UNWIND_RESTORE s1
    ld      s2, (\locals + 16)(sp)
    UNWIND_RESTORE s2
    ld      s3, (\locals + 24)(sp)
    UNWIND_RESTORE s3
    ld      s4, (\locals + 32)(sp)
    UNWIND_RESTORE s4
    ld      s5, (\locals + 40)(sp)
    UNWIND_RESTORE s5
    ld      s6, (\locals + 48)(sp)
    UNWIND_RESTORE s6
    ld      s7, (\locals + 56)(sp)
    UNWIND_RESTORE s7
    ld      s8, (\locals + 64)(sp)
    UNWIND_RESTORE s8
    ld      s9, (\locals + 72)(sp)
    UNWIND_RESTORE s9
    ld      s10, (\locals + 80)(sp)
    UNWIND_RESTORE s10
    addi    sp, sp, (\locals + 96)
    UNWIND_FREE (\locals + 96)
    UNWIND_END_EPILOGUE
    ret
.endm

/* dst = address of TypeNode number idx. Uses a6, a7. */
.macro NODE dst, idx, ctx
    ld      a6, SSZ_CTX_NODES(\ctx)
    li      a7, SSZ_NODE_STRIDE
    mul     \dst, \idx, a7
    add     \dst, \dst, a6
.endm

/* dst = 32 bytes at src. Uses a6, a7. */
.macro COPY32 dst, src
    ld      a6, 0(\src)
    ld      a7, 8(\src)
    sd      a6, 0(\dst)
    sd      a7, 8(\dst)
    ld      a6, 16(\src)
    ld      a7, 24(\src)
    sd      a6, 16(\dst)
    sd      a7, 24(\dst)
.endm

/* Serialize: append a2 bytes from a1 at cursor s3; write them when ctx s1 says so. Uses t0-t3. */
.macro COPY_OUT
    ld      t0, SSZ_CUR_OUT(s3)
    add     t1, t0, a2
    sd      t1, SSZ_CUR_OUT(s3)
    ld      t2, SSZ_CTX_WRITE(s1)
    beqz    t2, 98f
97: beqz    a2, 98f
    lbu     t3, 0(a1)
    sb      t3, 0(t0)
    addi    a1, a1, 1
    addi    t0, t0, 1
    addi    a2, a2, -1
    j       97b
98:
.endm

/* Deserialize: copy len bytes from src to dst when ctx s1 says to write. Uses t4-t6, a6. */
.macro COPY_IN dst, src, len
    ld      a6, SSZ_CTX_WRITE(s1)
    beqz    a6, 98f
    mv      t4, \dst
    mv      t5, \src
    mv      t6, \len
97: beqz    t6, 98f
    lbu     a6, 0(t5)
    sb      a6, 0(t4)
    addi    t4, t4, 1
    addi    t5, t5, 1
    addi    t6, t6, -1
    j       97b
98:
.endm

/* Deserialize: write the PartRef at s4 (value start s5) for a part at part with count entries. Uses a6. */
.macro WRITE_PARTREF part, count
    ld      a6, SSZ_CTX_WRITE(s1)
    beqz    a6, 98f
    sub     a6, \part, s5
    sd      a6, SSZ_PART_OFFSET(s4)
    sd      \count, SSZ_PART_COUNT(s4)
98:
.endm

/* reg = reg rounded up to a multiple of 8. */
.macro ROUND8 reg
    addi    \reg, \reg, 7
    andi    \reg, \reg, -8
.endm

/* Deserialize: decode one child into the slot at sp + 0; on failure go to 280. */
.macro DE_CHILD node, p, b, form, scope
    sd      \p, SSZ_SLOT_P(sp)
    sd      \b, SSZ_SLOT_B(sp)
    li      a7, \form
    sd      a7, SSZ_SLOT_FORM(sp)
    sd      \scope, SSZ_SLOT_SCOPE(sp)
    mv      a1, \node
    mv      a0, s1
    mv      a2, sp
    mv      a3, s3
    call    ssz_decode_value
    bnez    a0, 280f
.endm

/* Serialize: encode one child from the slot at sp + 0. */
.macro SER_CHILD node, p, b, form
    sd      \p, SSZ_SLOT_P(sp)
    sd      \b, SSZ_SLOT_B(sp)
    li      a7, \form
    sd      a7, SSZ_SLOT_FORM(sp)
    mv      a1, \node
    mv      a0, s1
    mv      a2, sp
    mv      a3, s3
    call    ssz_encode_value
.endm

/*
 * Deserialize, container: for the variable field at s10, set t0 to the next
 * variable field (0 when none) and t1 to where its body ends: the next
 * variable field's offset, or the scope s7. Reads the end of the fields at
 * sp + 88 and the start of the encoding at sp + 72. Uses t2-t4.
 */
.macro NEXT_END
    ld      t2, 88(sp)
    addi    t0, s10, SSZ_FIELD_STRIDE
93: bgeu    t0, t2, 95f
    ld      t3, SSZ_FIELD_FLAGS(t0)
    andi    t3, t3, 1
    bnez    t3, 94f
    addi    t0, t0, SSZ_FIELD_STRIDE
    j       93b
94: ld      t3, SSZ_FIELD_SSZ_OFFSET(t0)
    ld      t4, 72(sp)
    add     t4, t4, t3
    lwu     t1, 0(t4)
    j       96f
95: li      t0, 0
    mv      t1, s7
96:
.endm

/* L2 entry: s2 = root TypeNode of the descriptor in a0. Uses t0, t1. */
.macro ROOT_NODE
    ld      t0, SSZ_DESC_NODES_OFFSET(a0)
    add     t0, a0, t0
    ld      t1, SSZ_DESC_ROOT(a0)
    li      s2, SSZ_NODE_STRIDE
    mul     s2, t1, s2
    add     s2, s2, t0
.endm

/* L2 entry: fill the Ctx in the scratch at scr from the descriptor at desc; s1 = Ctx. Uses t0, t1. */
.macro SETUP_CTX desc, scr
    addi    s1, \scr, SSZ_SCR_CTX
    ld      t0, SSZ_DESC_NODES_OFFSET(\desc)
    add     t0, \desc, t0
    sd      t0, SSZ_CTX_NODES(s1)
    ld      t0, SSZ_DESC_FIELDS_OFFSET(\desc)
    add     t0, \desc, t0
    sd      t0, SSZ_CTX_FIELDS(s1)
    sd      zero, SSZ_CTX_WRITE(s1)
    sd      zero, SSZ_CTX_END(s1)
    addi    t0, \scr, SSZ_SCR_SHA
    sd      t0, SSZ_CTX_SHA(s1)
    li      t1, 88
    sd      t1, SSZ_BYTES_SIZE(t0)
    li      t1, SSZ_BYTES_FIXED
    sd      t1, SSZ_BYTES_OFFSET(t0)
    li      t1, 64
    sd      t1, SSZ_BYTES_COUNT(t0)
    lla     t0, 300f
    sd      t0, SSZ_CTX_ZERO(s1)
.endm

/* L2 entry: slot at sp + 0 for the caller's value in reg, of root type s2. Uses t0. */
.macro TOP_SLOT reg
    sd      \reg, SSZ_SLOT_P(sp)
    sd      \reg, SSZ_SLOT_B(sp)
    ld      t0, SSZ_NODE_SSZ_SIZE(s2)
    seqz    t0, t0
    slli    t0, t0, 1
    sd      t0, SSZ_SLOT_FORM(sp)
.endm

/* ---------------------------------------------------------------- Serialize */

/*
 * ssz_encode_value(ctx, node, slot, cursor): append the SSZ encoding of the value in
 * slot to cursor.out. Locals: child slot at sp + 0.
 * s1 ctx, s2 node, s3 cursor, s4 p, s5 b, s6 kind.
 */
LOCAL_FUNCTION ssz_encode_value
    ENTER   48
    mv      s1, a0
    mv      s2, a1
    mv      s3, a3
    ld      s4, SSZ_SLOT_P(a2)
    ld      s5, SSZ_SLOT_B(a2)
    ld      t0, SSZ_SLOT_FORM(a2)
    ld      s6, SSZ_NODE_KIND(s2)
    li      t5, SSZ_KIND_CONTAINER
    beqz    t0, 10f
    /* A value of a variable size type starts at p. */
    beq     s6, t5, 40f
    mv      s5, s4
    addi    s4, s4, 8
    j       30f
10: ld      t1, SSZ_NODE_SSZ_SIZE(s2)
    beqz    t1, 30f
    beq     s6, t5, 40f
    li      t5, SSZ_KIND_VECTOR
    beq     s6, t5, 20f
    /* uint, boolean, byte vector, bit vector: the bytes as they are */
    mv      a1, s4
    mv      a2, t1
    COPY_OUT
    j       90f
20: /* fixed size vector: N entries in place */
    ld      t2, SSZ_NODE_ELEMENT(s2)
    NODE    s7, t2, s1
    ld      s8, SSZ_NODE_LENGTH(s2)
    mv      s9, s4
    j       60f
30: /* variable size: a PartRef at p, offsets from b */
    ld      t2, SSZ_PART_OFFSET(s4)
    add     s9, s5, t2
    ld      s8, SSZ_PART_COUNT(s4)
    li      t5, SSZ_KIND_CONTAINER
    bne     s6, t5, 31f
    mv      s4, s9
    j       40f
31: li      t5, SSZ_KIND_BYTE_LIST
    bne     s6, t5, 32f
    mv      a1, s9
    mv      a2, s8
    COPY_OUT
    j       90f
32: li      t5, SSZ_KIND_BIT_LIST
    bne     s6, t5, 33f
    addi    a2, s8, 7
    srli    a2, a2, 3
    mv      a1, s9
    COPY_OUT
    /* the delimiter bit sits at bit position count */
    ld      t2, SSZ_CTX_WRITE(s1)
    ld      t0, SSZ_CUR_OUT(s3)
    andi    t1, s8, 7
    bnez    t1, 34f
    addi    t3, t0, 1
    sd      t3, SSZ_CUR_OUT(s3)
    beqz    t2, 90f
    li      t3, 1
    sb      t3, 0(t0)
    j       90f
34: beqz    t2, 90f
    lbu     t3, -1(t0)
    li      t4, 1
    sll     t4, t4, t1
    or      t3, t3, t4
    sb      t3, -1(t0)
    j       90f
33: /* vector or list in a part */
    ld      t2, SSZ_NODE_ELEMENT(s2)
    NODE    s7, t2, s1
    j       60f

40: /* container at s4: the fixed part, then the variable fields */
    ld      t1, SSZ_NODE_ELEMENT(s2)
    ld      t2, SSZ_CTX_FIELDS(s1)
    slli    t1, t1, 5
    add     s7, t2, t1                     # first field
    ld      s8, SSZ_NODE_LENGTH(s2)
    ld      s9, SSZ_CUR_OUT(s3)            # start of this encoding
    li      s10, 0
41: bgeu    s10, s8, 45f
    slli    t0, s10, 5
    add     s6, s7, t0
    ld      t1, SSZ_FIELD_FLAGS(s6)
    andi    t1, t1, 1
    beqz    t1, 42f
    ld      t2, SSZ_CUR_OUT(s3)
    addi    t2, t2, SSZ_BYTES_PER_LENGTH_OFFSET
    sd      t2, SSZ_CUR_OUT(s3)
    j       43f
42: ld      t1, SSZ_FIELD_MEM_OFFSET(s6)
    add     t1, s4, t1
    ld      t2, SSZ_FIELD_NODE(s6)
    NODE    t3, t2, s1
    SER_CHILD t3, t1, s4, SSZ_FORM_PLACE
43: addi    s10, s10, 1
    j       41b
45: li      s10, 0
46: bgeu    s10, s8, 90f
    slli    t0, s10, 5
    add     s6, s7, t0
    ld      t1, SSZ_FIELD_FLAGS(s6)
    andi    t1, t1, 1
    beqz    t1, 48f
    ld      t2, SSZ_CTX_WRITE(s1)
    beqz    t2, 47f
    ld      t3, SSZ_CUR_OUT(s3)
    sub     t3, t3, s9
    ld      t4, SSZ_FIELD_SSZ_OFFSET(s6)
    add     t4, s9, t4
    sw      t3, 0(t4)
47: ld      t1, SSZ_FIELD_MEM_OFFSET(s6)
    add     t1, s4, t1
    ld      t2, SSZ_FIELD_NODE(s6)
    NODE    t3, t2, s1
    SER_CHILD t3, t1, s4, SSZ_FORM_PLACE
48: addi    s10, s10, 1
    j       46b

60: /* s8 elements of type s7 from s9 */
    ld      t1, SSZ_NODE_SSZ_SIZE(s7)
    beqz    t1, 70f
    ld      t2, SSZ_NODE_KIND(s7)
    li      t5, SSZ_KIND_BOOLEAN
    bgtu    t2, t5, 65f
    /* basic elements: their bytes are already packed */
    mul     a2, s8, t1
    mv      a1, s9
    COPY_OUT
    j       90f
65: beqz    s8, 90f
    SER_CHILD s7, s9, s9, SSZ_FORM_PLACE
    ld      t1, SSZ_NODE_MEM_SIZE(s7)
    add     s9, s9, t1
    addi    s8, s8, -1
    j       65b
70: /* variable size elements: the offset table, then each nested value */
    ld      s10, SSZ_CUR_OUT(s3)
    slli    t1, s8, 2
    add     t1, s10, t1
    sd      t1, SSZ_CUR_OUT(s3)
    li      s6, 0
71: bgeu    s6, s8, 90f
    ld      t2, SSZ_CTX_WRITE(s1)
    beqz    t2, 72f
    ld      t3, SSZ_CUR_OUT(s3)
    sub     t3, t3, s10
    slli    t4, s6, 2
    add     t4, s10, t4
    sw      t3, 0(t4)
72: SER_CHILD s7, s9, s9, SSZ_FORM_NESTED
    ld      t1, SSZ_VALUE_SIZE(s9)
    add     s9, s9, t1
    addi    s6, s6, 1
    j       71b

90: li      a0, SSZ_OK
    LEAVE   48
END_FUNCTION ssz_encode_value

/* ssz_serialize_size(type, value, scratch, size). Locals: slot 0, cursor 32. */
FUNCTION ssz_serialize_size
    ENTER   48
    mv      s3, a1
    mv      s4, a3
    mv      s5, a2
    ROOT_NODE
    ld      t0, 0(s5)
    ld      t1, SSZ_NODE_SCRATCH(s2)
    bltu    t0, t1, 80f
    SETUP_CTX a0, s5
    TOP_SLOT s3
    sd      zero, 32(sp)
    mv      a0, s1
    mv      a1, s2
    mv      a2, sp
    addi    a3, sp, 32
    call    ssz_encode_value
    ld      t0, 32(sp)
    addi    t0, t0, SSZ_BYTES_FIXED
    sd      t0, 0(s4)
    li      a0, SSZ_OK
    j       90f
80: li      a0, SSZ_BUFFER_TOO_SMALL
90: LEAVE   48
END_FUNCTION ssz_serialize_size

/* ssz_serialize(type, value, scratch, serialized). Locals: slot 0, cursor 32. */
FUNCTION ssz_serialize
    ENTER   48
    mv      s3, a1
    mv      s4, a3
    mv      s5, a2
    ROOT_NODE
    ld      t0, 0(s5)
    ld      t1, SSZ_NODE_SCRATCH(s2)
    bltu    t0, t1, 80f
    SETUP_CTX a0, s5
    TOP_SLOT s3
    /* measure */
    sd      zero, 32(sp)
    mv      a0, s1
    mv      a1, s2
    mv      a2, sp
    addi    a3, sp, 32
    call    ssz_encode_value
    ld      s6, 32(sp)
    ld      t0, SSZ_BYTES_SIZE(s4)
    addi    t1, s6, SSZ_BYTES_FIXED
    bltu    t0, t1, 80f
    li      t1, SSZ_BYTES_FIXED
    sd      t1, SSZ_BYTES_OFFSET(s4)
    sd      s6, SSZ_BYTES_COUNT(s4)
    /* write */
    li      t1, 1
    sd      t1, SSZ_CTX_WRITE(s1)
    addi    t1, s4, SSZ_BYTES_FIXED
    sd      t1, 32(sp)
    mv      a0, s1
    mv      a1, s2
    mv      a2, sp
    addi    a3, sp, 32
    call    ssz_encode_value
    li      a0, SSZ_OK
    j       90f
80: li      a0, SSZ_BUFFER_TOO_SMALL
90: LEAVE   48
END_FUNCTION ssz_serialize

/* ---------------------------------------------------------------- Deserialize */

/*
 * ssz_decode_value(ctx, node, slot, cursor): decode slot.scope bytes at cursor.pos into
 * the value in slot, as v0.1.0 deserialize does. On a refusal the cursor is
 * restored. s1 ctx, s2 node, s3 cursor, s4 p, s5 b, s6 kind, s7 scope.
 * Locals: child slot 0, cursor at entry 32 and 40, value start 48, form 56,
 * next variable field 64, start of the encoding 72, first variable field 80,
 * end of the fields 88.
 */
LOCAL_FUNCTION ssz_decode_value
    ENTER   96
    mv      s1, a0
    mv      s2, a1
    mv      s3, a3
    ld      t0, SSZ_CUR_POS(a3)
    ld      t1, SSZ_CUR_NEXT(a3)
    sd      t0, 32(sp)
    sd      t1, 40(sp)
    ld      s4, SSZ_SLOT_P(a2)
    ld      s5, SSZ_SLOT_B(a2)
    ld      t0, SSZ_SLOT_FORM(a2)
    ld      s7, SSZ_SLOT_SCOPE(a2)
    sd      s4, 48(sp)
    sd      t0, 56(sp)
    ld      s6, SSZ_NODE_KIND(s2)
    beqz    t0, 10f
    /* A value of a variable size type starts at p; its parts start at value_fixed. */
    ld      t1, SSZ_NODE_VALUE_FIXED(s2)
    add     t1, s4, t1
    sd      t1, SSZ_CUR_NEXT(s3)
    li      t5, SSZ_KIND_CONTAINER
    beq     s6, t5, 40f
    mv      s5, s4
    addi    s4, s4, 8
    j       30f

10: ld      t1, SSZ_NODE_SSZ_SIZE(s2)
    beqz    t1, 30f
    li      t5, SSZ_KIND_CONTAINER
    beq     s6, t5, 40f
    li      t5, SSZ_KIND_VECTOR
    beq     s6, t5, 20f
    /* uint, boolean, byte vector, bit vector */
    bne     s7, t1, 201f
    ld      t2, SSZ_CUR_POS(s3)
    add     t3, t2, t1
    ld      t4, SSZ_CTX_END(s1)
    bgtu    t3, t4, 202f
    li      t5, SSZ_KIND_BOOLEAN
    bne     s6, t5, 11f
    lbu     t5, 0(t2)
    li      t6, 1
    bgtu    t5, t6, 203f
    j       15f
11: li      t5, SSZ_KIND_BIT_VECTOR
    bne     s6, t5, 15f
    ld      t5, SSZ_NODE_LENGTH(s2)
    andi    t5, t5, 7
    beqz    t5, 15f
    lbu     t6, -1(t3)
    srl     t6, t6, t5
    bnez    t6, 204f
15: sd      t3, SSZ_CUR_POS(s3)
    COPY_IN s4, t2, t1
    j       288f

20: /* fixed size vector: the scope is the SSZ size, then each entry */
    bne     s7, t1, 201f
    ld      t2, SSZ_NODE_ELEMENT(s2)
    NODE    s8, t2, s1
    ld      s9, SSZ_NODE_LENGTH(s2)
    mv      s10, s4
21: beqz    s9, 288f
    ld      s6, SSZ_NODE_SSZ_SIZE(s8)
    DE_CHILD s8, s10, s5, SSZ_FORM_PLACE, s6
    ld      t1, SSZ_NODE_MEM_SIZE(s8)
    add     s10, s10, t1
    addi    s9, s9, -1
    j       21b

30: /* variable size in place: a PartRef at p, offsets from b */
    li      t5, SSZ_KIND_CONTAINER
    bne     s6, t5, 31f
    ld      s8, SSZ_CUR_NEXT(s3)
    DE_CHILD s2, s8, s8, SSZ_FORM_NESTED, s7
    li      s9, 1
    WRITE_PARTREF s8, s9
    j       288f
31: li      t5, SSZ_KIND_BYTE_LIST
    bne     s6, t5, 33f
    ld      t1, SSZ_NODE_LENGTH(s2)
    bgtu    s7, t1, 205f
    ld      t2, SSZ_CUR_POS(s3)
    add     t3, t2, s7
    ld      t4, SSZ_CTX_END(s1)
    bgtu    t3, t4, 202f
    sd      t3, SSZ_CUR_POS(s3)
    ld      s8, SSZ_CUR_NEXT(s3)
    WRITE_PARTREF s8, s7
    COPY_IN s8, t2, s7
    mv      t1, s7
    ROUND8  t1
    add     t1, s8, t1
    sd      t1, SSZ_CUR_NEXT(s3)
    j       288f
33: li      t5, SSZ_KIND_BIT_LIST
    bne     s6, t5, 50f
    ld      t2, SSZ_CUR_POS(s3)
    add     t3, t2, s7
    ld      t4, SSZ_CTX_END(s1)
    bgtu    t3, t4, 202f
    beqz    s7, 206f
    lbu     t5, -1(t3)
    bnez    t5, 35f
    /* the last byte is zero: zero bytes past the delimiter, or no delimiter */
    mv      t6, t2
34: bgeu    t6, t3, 207f
    lbu     a6, 0(t6)
    addi    t6, t6, 1
    beqz    a6, 34b
    j       208f
35: /* the delimiter is the highest set bit of the last byte */
    li      s6, 0
351: srli   t5, t5, 1
    beqz    t5, 352f
    addi    s6, s6, 1
    j       351b
352: addi   t6, s7, -1
    slli    t6, t6, 3
    add     s8, s6, t6                     # bit count
    ld      t1, SSZ_NODE_LENGTH(s2)
    bgtu    s8, t1, 205f
    sd      t3, SSZ_CUR_POS(s3)
    addi    s9, s8, 7
    srli    s9, s9, 3                      # data bytes
    ld      s10, SSZ_CUR_NEXT(s3)
    WRITE_PARTREF s10, s8
    COPY_IN s10, t2, s9
    /* clear the delimiter when it shares the last data byte */
    beqz    s6, 36f
    ld      a6, SSZ_CTX_WRITE(s1)
    beqz    a6, 36f
    add     a6, s10, s9
    lbu     a7, -1(a6)
    li      t5, 1
    sll     t5, t5, s6
    not     t5, t5
    and     a7, a7, t5
    sb      a7, -1(a6)
36: mv      t1, s9
    ROUND8  t1
    add     t1, s10, t1
    sd      t1, SSZ_CUR_NEXT(s3)
    j       288f

40: /* container at s4 */
    ld      t1, SSZ_NODE_ELEMENT(s2)
    ld      t2, SSZ_CTX_FIELDS(s1)
    slli    t1, t1, 5
    add     s8, t2, t1                     # first field
    ld      s9, SSZ_NODE_LENGTH(s2)
    slli    t1, s9, 5
    add     t1, s8, t1
    sd      t1, 88(sp)                     # end of the fields
    ld      t3, SSZ_CUR_POS(s3)
    sd      t3, 72(sp)                     # start of the encoding
    sd      zero, 80(sp)                   # first variable field
    mv      s10, s8
41: ld      t1, 88(sp)
    bgeu    s10, t1, 44f
    ld      t1, SSZ_FIELD_FLAGS(s10)
    andi    t1, t1, 1
    beqz    t1, 42f
    ld      t2, 80(sp)
    bnez    t2, 45f
    sd      s10, 80(sp)
45: ld      t2, SSZ_CUR_POS(s3)
    addi    t3, t2, SSZ_BYTES_PER_LENGTH_OFFSET
    ld      t4, SSZ_CTX_END(s1)
    bgtu    t3, t4, 202f
    sd      t3, SSZ_CUR_POS(s3)
    j       43f
42: ld      t1, SSZ_FIELD_MEM_OFFSET(s10)
    add     t1, s4, t1
    ld      t2, SSZ_FIELD_NODE(s10)
    NODE    s6, t2, s1
    ld      s9, SSZ_NODE_SSZ_SIZE(s6)
    DE_CHILD s6, t1, s4, SSZ_FORM_PLACE, s9
43: addi    s10, s10, SSZ_FIELD_STRIDE
    j       41b
44: ld      t1, SSZ_CUR_POS(s3)
    ld      t2, 72(sp)
    sub     t3, t1, t2                     # bytes read
    ld      t4, 80(sp)
    bnez    t4, 46f
    bne     s7, t3, 201f
    j       288f
46: ld      t5, SSZ_FIELD_SSZ_OFFSET(t4)
    add     t5, t2, t5
    lwu     t6, 0(t5)
    bne     t6, t3, 211f
    /* the spans of the variable fields */
    mv      s10, t4
47: NEXT_END
    ld      t5, SSZ_FIELD_SSZ_OFFSET(s10)
    ld      t2, 72(sp)
    add     t5, t2, t5
    lwu     t6, 0(t5)                      # start
    bgeu    t1, t6, 48f
    beqz    t0, 214f
    j       215f
48: beqz    t0, 49f
    mv      s10, t0
    j       47b
49: /* the bodies of the variable fields */
    ld      s10, 80(sp)
491:
    NEXT_END
    sd      t0, 64(sp)                     # next variable field
    ld      t5, SSZ_FIELD_SSZ_OFFSET(s10)
    ld      t2, 72(sp)
    add     t5, t2, t5
    lwu     t6, 0(t5)
    sub     s9, t1, t6                     # span
    ld      t1, SSZ_FIELD_MEM_OFFSET(s10)
    add     t1, s4, t1
    ld      t2, SSZ_FIELD_NODE(s10)
    NODE    s6, t2, s1
    DE_CHILD s6, t1, s4, SSZ_FORM_PLACE, s9
    ld      s10, 64(sp)
    bnez    s10, 491b
    j       288f

50: /* vector or list in a part */
    ld      t2, SSZ_NODE_ELEMENT(s2)
    NODE    s8, t2, s1
    ld      t1, SSZ_NODE_SSZ_SIZE(s8)
    beqz    t1, 60f
    /* list of fixed size elements */
    beqz    s7, 55f
    divu    s9, s7, t1
    remu    t2, s7, t1
    bnez    t2, 209f
    ld      t3, SSZ_NODE_LENGTH(s2)
    bgtu    s9, t3, 205f
    ld      s10, SSZ_CUR_NEXT(s3)
    WRITE_PARTREF s10, s9
    ld      t2, SSZ_NODE_MEM_SIZE(s8)
    mul     t2, t2, s9
    ROUND8  t2
    add     t2, s10, t2
    sd      t2, SSZ_CUR_NEXT(s3)
52: beqz    s9, 288f
    ld      s6, SSZ_NODE_SSZ_SIZE(s8)
    DE_CHILD s8, s10, s5, SSZ_FORM_PLACE, s6
    ld      t1, SSZ_NODE_MEM_SIZE(s8)
    add     s10, s10, t1
    addi    s9, s9, -1
    j       52b
55: ld      s10, SSZ_CUR_NEXT(s3)
    WRITE_PARTREF s10, zero
    j       288f

60: /* variable size elements: the offset table */
    li      t5, SSZ_KIND_VECTOR
    bne     s6, t5, 62f
    ld      s9, SSZ_NODE_LENGTH(s2)
    slli    t1, s9, 2
    bltu    s7, t1, 210f
    ld      t2, SSZ_CUR_POS(s3)
    add     t3, t2, t1
    ld      t4, SSZ_CTX_END(s1)
    bgtu    t3, t4, 202f
    lwu     t5, 0(t2)
    bne     t5, t1, 211f
    j       64f
62: beqz    s7, 55b
    li      t5, SSZ_BYTES_PER_LENGTH_OFFSET
    bltu    s7, t5, 210f
    ld      t2, SSZ_CUR_POS(s3)
    addi    t3, t2, SSZ_BYTES_PER_LENGTH_OFFSET
    ld      t4, SSZ_CTX_END(s1)
    bgtu    t3, t4, 202f
    lwu     t5, 0(t2)
    li      t6, SSZ_BYTES_PER_LENGTH_OFFSET
    bltu    t5, t6, 212f
    andi    t6, t5, 3
    bnez    t6, 213f
    bgtu    t5, s7, 214f
    srli    s9, t5, 2
    ld      t1, SSZ_NODE_LENGTH(s2)
    bgtu    s9, t1, 205f
    add     t3, t2, t5
    bgtu    t3, t4, 202f
64: /* s9 offsets at t2: check the spans */
    li      t1, 0
65: bgeu    t1, s9, 67f
    slli    t3, t1, 2
    add     t3, t2, t3
    lwu     t3, 0(t3)                      # start
    addi    t4, t1, 1
    bgeu    t4, s9, 66f
    slli    t5, t4, 2
    add     t5, t2, t5
    lwu     t5, 0(t5)
    bltu    t5, t3, 215f
    mv      t1, t4
    j       65b
66: bltu    s7, t3, 214f
67: /* the nested values */
    ld      s10, SSZ_CUR_NEXT(s3)
    WRITE_PARTREF s10, s9
    slli    t3, s9, 2
    add     t3, t2, t3
    sd      t3, SSZ_CUR_POS(s3)
    sd      t2, 72(sp)                     # offset table
    li      s6, 0
68: bgeu    s6, s9, 288f
    ld      t2, 72(sp)
    slli    t3, s6, 2
    add     t3, t2, t3
    lwu     t4, 0(t3)                      # start
    addi    t5, s6, 1
    mv      t6, s7
    bgeu    t5, s9, 69f
    lwu     t6, 4(t3)
69: sub     a5, t6, t4                     # span
    ld      s10, SSZ_CUR_NEXT(s3)
    DE_CHILD s8, s10, s10, SSZ_FORM_NESTED, a5
    addi    s6, s6, 1
    j       68b

288: /* success: a nested value records its size */
    ld      t0, 56(sp)
    li      t1, SSZ_FORM_NESTED
    bne     t0, t1, 289f
    ld      t1, SSZ_CTX_WRITE(s1)
    beqz    t1, 289f
    ld      t2, 48(sp)
    ld      t3, SSZ_CUR_NEXT(s3)
    sub     t3, t3, t2
    sd      t3, SSZ_VALUE_SIZE(t2)
289: li     a0, SSZ_OK
    j       299f
201: li     a0, SSZ_SCOPE
    j       280f
202: li     a0, SSZ_TRUNCATED
    j       280f
203: li     a0, SSZ_NOT_A_BIT
    j       280f
204: li     a0, SSZ_PADDING_BITS
    j       280f
205: li     a0, SSZ_LIMIT
    j       280f
206: li     a0, SSZ_EMPTY_ENCODING
    j       280f
207: li     a0, SSZ_NO_DELIMITER
    j       280f
208: li     a0, SSZ_TRAILING_ZEROS
    j       280f
209: li     a0, SSZ_SCOPE_UNDIVIDED
    j       280f
210: li     a0, SSZ_SCOPE_TOO_SMALL
    j       280f
211: li     a0, SSZ_FIRST_OFFSET
    j       280f
212: li     a0, SSZ_OFFSET_BELOW_TABLE
    j       280f
213: li     a0, SSZ_OFFSET_UNALIGNED
    j       280f
214: li     a0, SSZ_OFFSET_PAST_SCOPE
    j       280f
215: li     a0, SSZ_OFFSET_UNORDERED
280: /* refusal: restore the cursor */
    ld      t0, 32(sp)
    sd      t0, SSZ_CUR_POS(s3)
    ld      t0, 40(sp)
    sd      t0, SSZ_CUR_NEXT(s3)
299: LEAVE  96
END_FUNCTION ssz_decode_value

/*
 * L2 deserialize, decode_bytes rules for the top value. Uses s1 ctx, s2 root
 * TypeNode, s3 serialized ByteList, s6 value start (0 when only measuring),
 * the slot at sp + 0 and the cursor at sp + 32. Sets a0 to the status and s7
 * to the size of the value.
 */
.macro DE_CALL
    mv      a0, s1
    mv      a1, s2
    mv      a2, sp
    addi    a3, sp, 32
    call    ssz_decode_value
.endm

.macro DE_TOP
    ld      t0, SSZ_BYTES_OFFSET(s3)
    add     t0, s3, t0
    ld      t1, SSZ_BYTES_COUNT(s3)
    add     t2, t0, t1
    sd      t2, SSZ_CTX_END(s1)
    sd      t0, (32 + SSZ_CUR_POS)(sp)
    sd      s6, SSZ_SLOT_P(sp)
    sd      s6, SSZ_SLOT_B(sp)
    sd      t1, SSZ_SLOT_SCOPE(sp)
    ld      t3, SSZ_NODE_KIND(s2)
    ld      t4, SSZ_NODE_SSZ_SIZE(s2)
    beqz    t4, 85f
    /* fixed size: a basic value or a byte or bit vector must be exactly its size */
    li      t5, SSZ_KIND_CONTAINER
    beq     t3, t5, 83f
    li      t5, SSZ_KIND_VECTOR
    beq     t3, t5, 83f
    beq     t1, t4, 83f
    li      a0, SSZ_TRUNCATED
    li      t5, SSZ_KIND_BYTE_VECTOR
    bne     t3, t5, 89f
    li      a0, SSZ_COUNT
    j       89f
83: sd      zero, SSZ_SLOT_FORM(sp)
    ld      t5, SSZ_NODE_MEM_SIZE(s2)
    add     t5, s6, t5
    sd      t5, (32 + SSZ_CUR_NEXT)(sp)
    DE_CALL
    bnez    a0, 89f
    ld      s7, SSZ_NODE_MEM_SIZE(s2)
    j       87f
85: li      t5, SSZ_FORM_TOP
    sd      t5, SSZ_SLOT_FORM(sp)
    DE_CALL
    bnez    a0, 89f
    ld      s7, (32 + SSZ_CUR_NEXT)(sp)
    sub     s7, s7, s6
    ld      t3, SSZ_NODE_KIND(s2)
    li      t5, SSZ_KIND_BYTE_LIST
    beq     t3, t5, 88f
    li      t5, SSZ_KIND_BIT_LIST
    beq     t3, t5, 88f
87: ld      t0, (32 + SSZ_CUR_POS)(sp)
    ld      t1, SSZ_CTX_END(s1)
    li      a0, SSZ_TRAILING_BYTES
    bne     t0, t1, 89f
88: li      a0, SSZ_OK
89:
.endm

/* ssz_deserialize_size(type, serialized, scratch, size). Locals: slot 0, cursor 32. */
FUNCTION ssz_deserialize_size
    ENTER   64
    mv      s3, a1
    mv      s4, a3
    mv      s5, a2
    ROOT_NODE
    ld      t0, 0(s5)
    ld      t1, SSZ_NODE_SCRATCH(s2)
    bltu    t0, t1, 80f
    SETUP_CTX a0, s5
    li      s6, 0
    DE_TOP
    bnez    a0, 90f
    sd      s7, 0(s4)
    li      a0, SSZ_OK
    j       90f
80: li      a0, SSZ_BUFFER_TOO_SMALL
90: LEAVE   64
END_FUNCTION ssz_deserialize_size

/* ssz_deserialize(type, serialized, scratch, value). Locals: slot 0, cursor 32. */
FUNCTION ssz_deserialize
    ENTER   64
    mv      s3, a1
    mv      s4, a3
    mv      s5, a2
    ROOT_NODE
    ld      t0, 0(s5)
    ld      t1, SSZ_NODE_SCRATCH(s2)
    bltu    t0, t1, 80f
    SETUP_CTX a0, s5
    /* check and measure */
    li      s6, 0
    DE_TOP
    bnez    a0, 90f
    ld      t0, SSZ_NODE_SSZ_SIZE(s2)
    bnez    t0, 70f
    ld      t0, SSZ_VALUE_SIZE(s4)
    bltu    t0, s7, 80f
70: /* write */
    li      t0, 1
    sd      t0, SSZ_CTX_WRITE(s1)
    mv      s6, s4
    DE_TOP
    j       90f
80: li      a0, SSZ_BUFFER_TOO_SMALL
90: LEAVE   64
END_FUNCTION ssz_deserialize

/* ---------------------------------------------------------------- Merkleization */

/* ssz_hash_pair(ctx, left, right, out): out = SHA-256(left || right), 32 bytes each. */
LOCAL_FUNCTION ssz_hash_pair
    ENTER   0
    ld      t0, SSZ_CTX_SHA(a0)
    addi    t1, t0, SSZ_BYTES_FIXED
    COPY32  t1, a1
    addi    t2, t1, 32
    COPY32  t2, a2
    mv      a0, t0
    mv      a1, a3
    CALL_EXTERN crypto_sha256
    li      a0, SSZ_OK
    LEAVE   0
END_FUNCTION ssz_hash_pair

/* ssz_value_level(ctx, node, slot, level): describe the leaves of the value in slot. A leaf. */
LOCAL_FUNCTION ssz_value_level
    UNWIND_END_PROLOGUE
    ld      t0, SSZ_SLOT_P(a2)
    ld      t1, SSZ_SLOT_B(a2)
    ld      t2, SSZ_SLOT_FORM(a2)
    ld      t3, SSZ_NODE_KIND(a1)
    /* tree depth: the bit length of chunks - 1 */
    ld      t4, SSZ_NODE_CHUNKS(a1)
    addi    t4, t4, -1
    li      t5, 0
1:  beqz    t4, 2f
    srli    t4, t4, 1
    addi    t5, t5, 1
    j       1b
2:  sd      t5, SSZ_LEVEL_DEPTH(a3)
    sd      zero, SSZ_LEVEL_MIXIN(a3)
    sd      zero, SSZ_LEVEL_LENGTH(a3)
    sd      zero, SSZ_LEVEL_C(a3)
    sd      zero, SSZ_LEVEL_WALK_I(a3)
    sd      zero, SSZ_LEVEL_WALK_V(a3)
    beqz    t2, 10f
    /* a value of a variable size type at p */
    li      t6, SSZ_KIND_CONTAINER
    beq     t3, t6, 40f
    mv      t1, t0
    addi    t0, t0, 8
    j       20f
10: ld      t4, SSZ_NODE_SSZ_SIZE(a1)
    beqz    t4, 20f
    li      t6, SSZ_KIND_CONTAINER
    beq     t3, t6, 40f
    li      t6, SSZ_KIND_VECTOR
    bne     t3, t6, 50f
    ld      t4, SSZ_NODE_ELEMENT(a1)
    NODE    a5, t4, a0
    ld      a4, SSZ_NODE_LENGTH(a1)
    j       30f
20: /* a PartRef at t0, offsets from t1: t0 = part, a4 = count */
    ld      t4, SSZ_PART_OFFSET(t0)
    add     t4, t1, t4
    ld      a4, SSZ_PART_COUNT(t0)
    mv      t0, t4
    li      t6, SSZ_KIND_CONTAINER
    beq     t3, t6, 40f
    li      t5, 1
    li      t6, SSZ_KIND_BYTE_LIST
    bne     t3, t6, 21f
    sd      a4, SSZ_LEVEL_LENGTH(a3)
    sd      t5, SSZ_LEVEL_MIXIN(a3)
    mv      t4, a4
    j       50f
21: li      t6, SSZ_KIND_BIT_LIST
    bne     t3, t6, 22f
    sd      a4, SSZ_LEVEL_LENGTH(a3)
    sd      t5, SSZ_LEVEL_MIXIN(a3)
    addi    t4, a4, 7
    srli    t4, t4, 3
    j       50f
22: li      t6, SSZ_KIND_LIST
    bne     t3, t6, 23f
    sd      a4, SSZ_LEVEL_LENGTH(a3)
    sd      t5, SSZ_LEVEL_MIXIN(a3)
23: ld      t4, SSZ_NODE_ELEMENT(a1)
    NODE    a5, t4, a0
30: /* elements of type a5 from t0, count a4 */
    ld      t4, SSZ_NODE_SSZ_SIZE(a5)
    beqz    t4, 35f
    ld      t6, SSZ_NODE_KIND(a5)
    li      t5, SSZ_KIND_BOOLEAN
    bgtu    t6, t5, 32f
    mul     t4, a4, t4
    j       50f
32: li      t6, SSZ_MODE_FIXED
    sd      t6, SSZ_LEVEL_MODE(a3)
    sd      a4, SSZ_LEVEL_COUNT(a3)
    sd      a5, SSZ_LEVEL_A(a3)
    sd      t0, SSZ_LEVEL_B(a3)
    ld      t6, SSZ_NODE_MEM_SIZE(a5)
    sd      t6, SSZ_LEVEL_C(a3)
    j       90f
35: li      t6, SSZ_MODE_VARIABLE
    sd      t6, SSZ_LEVEL_MODE(a3)
    sd      a4, SSZ_LEVEL_COUNT(a3)
    sd      a5, SSZ_LEVEL_A(a3)
    sd      t0, SSZ_LEVEL_B(a3)
    sd      t0, SSZ_LEVEL_WALK_V(a3)
    j       90f
40: /* container value at t0 */
    li      t6, SSZ_MODE_FIELDS
    sd      t6, SSZ_LEVEL_MODE(a3)
    ld      t6, SSZ_NODE_LENGTH(a1)
    sd      t6, SSZ_LEVEL_COUNT(a3)
    sd      a1, SSZ_LEVEL_A(a3)
    sd      t0, SSZ_LEVEL_B(a3)
    j       90f
50: /* packed bytes at t0, length t4 */
    li      t6, SSZ_MODE_PACKED
    sd      t6, SSZ_LEVEL_MODE(a3)
    sd      t0, SSZ_LEVEL_A(a3)
    sd      t4, SSZ_LEVEL_B(a3)
    addi    t6, t4, 31
    srli    t6, t6, 5
    sd      t6, SSZ_LEVEL_COUNT(a3)
90: li      a0, SSZ_OK
    ret
END_FUNCTION ssz_value_level

/* ssz_child_level(ctx, level, index, child): describe the leaves of leaf index of level. */
LOCAL_FUNCTION ssz_child_level
    ENTER   32
    mv      s1, a0
    mv      s2, a1
    ld      s3, 0(a2)
    mv      s4, a3
    ld      t0, SSZ_LEVEL_MODE(s2)
    li      t1, SSZ_MODE_FIXED
    bne     t0, t1, 2f
    ld      t1, SSZ_LEVEL_B(s2)
    ld      t2, SSZ_LEVEL_C(s2)
    mul     t2, s3, t2
    add     t1, t1, t2
    sd      t1, SSZ_SLOT_P(sp)
    sd      t1, SSZ_SLOT_B(sp)
    sd      zero, SSZ_SLOT_FORM(sp)
    ld      a1, SSZ_LEVEL_A(s2)
    j       9f
2:  li      t1, SSZ_MODE_VARIABLE
    bne     t0, t1, 5f
    ld      t1, SSZ_LEVEL_WALK_I(s2)
    ld      t2, SSZ_LEVEL_WALK_V(s2)
    bgeu    s3, t1, 3f
    li      t1, 0
    ld      t2, SSZ_LEVEL_B(s2)
3:  bgeu    t1, s3, 4f
    ld      t3, SSZ_VALUE_SIZE(t2)
    add     t2, t2, t3
    addi    t1, t1, 1
    j       3b
4:  sd      t1, SSZ_LEVEL_WALK_I(s2)
    sd      t2, SSZ_LEVEL_WALK_V(s2)
    sd      t2, SSZ_SLOT_P(sp)
    sd      t2, SSZ_SLOT_B(sp)
    li      t3, SSZ_FORM_NESTED
    sd      t3, SSZ_SLOT_FORM(sp)
    ld      a1, SSZ_LEVEL_A(s2)
    j       9f
5:  /* container field number index */
    ld      t4, SSZ_LEVEL_A(s2)
    ld      t1, SSZ_NODE_ELEMENT(t4)
    add     t1, t1, s3
    ld      t2, SSZ_CTX_FIELDS(s1)
    slli    t1, t1, 5
    add     t1, t2, t1
    ld      t3, SSZ_LEVEL_B(s2)
    ld      t5, SSZ_FIELD_MEM_OFFSET(t1)
    add     t5, t3, t5
    sd      t5, SSZ_SLOT_P(sp)
    sd      t3, SSZ_SLOT_B(sp)
    sd      zero, SSZ_SLOT_FORM(sp)
    ld      t4, SSZ_FIELD_NODE(t1)
    NODE    a1, t4, s1
9:  mv      a0, s1
    mv      a2, sp
    mv      a3, s4
    call    ssz_value_level
    li      a0, SSZ_OK
    LEAVE   32
END_FUNCTION ssz_child_level

/* ssz_level_leaf(ctx, level, index, work, out): out = leaf index of level. */
LOCAL_FUNCTION ssz_level_leaf
    ENTER   0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      t0, SSZ_LEVEL_MODE(s2)
    bnez    t0, 20f
    /* packed: the 32 bytes at 32 * index, zero padded */
    sd      zero, 0(s5)
    sd      zero, 8(s5)
    sd      zero, 16(s5)
    sd      zero, 24(s5)
    ld      t1, SSZ_LEVEL_A(s2)
    ld      t2, SSZ_LEVEL_B(s2)
    ld      t3, 0(s3)
    slli    t3, t3, 5
    add     t1, t1, t3
    sub     t4, t2, t3
    li      t5, 32
    bltu    t4, t5, 1f
    mv      t4, t5
1:  mv      t6, s5
2:  beqz    t4, 90f
    lbu     t5, 0(t1)
    sb      t5, 0(t6)
    addi    t1, t1, 1
    addi    t6, t6, 1
    addi    t4, t4, -1
    j       2b
20: /* the root of the child value: child level at work + 8, child work after it */
    addi    s6, s4, 8
    mv      a0, s1
    mv      a1, s2
    mv      a2, s3
    mv      a3, s6
    call    ssz_child_level
    addi    s7, s6, SSZ_LEVEL_SIZE
    ld      t0, 0(s4)
    addi    t0, t0, -(8 + SSZ_LEVEL_SIZE)
    sd      t0, 0(s7)
    mv      a0, s1
    mv      a1, s6
    mv      a2, s7
    mv      a3, s5
    call    ssz_level_root
90: li      a0, SSZ_OK
    LEAVE   0
END_FUNCTION ssz_level_leaf

/* ssz_level_root(ctx, level, work, out): out = hash tree root of the value of level. Locals: range 0, length 16. */
LOCAL_FUNCTION ssz_level_root
    ENTER   48
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    sd      zero, SSZ_RANGE_LO(sp)
    ld      t0, SSZ_LEVEL_DEPTH(s2)
    sd      t0, SSZ_RANGE_DEPTH(sp)
    mv      a0, s1
    mv      a1, s2
    mv      a2, sp
    mv      a3, s3
    mv      a4, s4
    call    ssz_subtree_root
    ld      t0, SSZ_LEVEL_MIXIN(s2)
    beqz    t0, 90f
    /* mix in the length as a 32-byte little-endian number */
    ld      t1, SSZ_LEVEL_LENGTH(s2)
    sd      t1, 16(sp)
    sd      zero, 24(sp)
    sd      zero, 32(sp)
    sd      zero, 40(sp)
    mv      a0, s1
    mv      a1, s4
    addi    a2, sp, 16
    mv      a3, s4
    call    ssz_hash_pair
90: li      a0, SSZ_OK
    LEAVE   48
END_FUNCTION ssz_level_root

/*
 * ssz_subtree_root(ctx, level, range, work, out): out = root of the subtree of
 * depth range.depth over leaves range.lo onward, padded with zero trees.
 * work: size, frontier of depth + 1 nodes, the node h, then the leaf work.
 * s1 ctx, s2 level, s3 lo, s4 depth, s5 work, s6 out, s7 m, s8 k or j,
 * s9 frontier, s10 h. Locals: index 0, a node is pending 8, leaf work 16, j 24.
 */
LOCAL_FUNCTION ssz_subtree_root
    ENTER   32
    mv      s1, a0
    mv      s2, a1
    ld      s3, SSZ_RANGE_LO(a2)
    ld      s4, SSZ_RANGE_DEPTH(a2)
    mv      s5, a3
    mv      s6, a4
    ld      t0, SSZ_LEVEL_COUNT(s2)
    bltu    s3, t0, 10f
    /* no data in the range: a zero tree */
    ld      t1, SSZ_CTX_ZERO(s1)
    slli    t2, s4, 5
    add     t1, t1, t2
    COPY32  s6, t1
    j       90f
10: sub     s7, t0, s3                     # leaves with data, m
    li      t1, 63
    bgeu    s4, t1, 11f
    li      t1, 1
    sll     t1, t1, s4
    bleu    s7, t1, 11f
    mv      s7, t1
11: addi    s9, s5, 8                      # frontier
    addi    s10, s4, 1
    slli    s10, s10, 5
    add     s10, s9, s10                   # h
    addi    t1, s10, 32                    # leaf work, only when leaves are child values
    sd      t1, 16(sp)
    ld      t3, SSZ_LEVEL_MODE(s2)
    beqz    t3, 12f
    sub     t2, t1, s5
    ld      t3, 0(s5)
    sub     t3, t3, t2
    sd      t3, 0(t1)
12: li      s8, 0                          # k
20: bgeu    s8, s7, 40f
    add     t1, s3, s8
    sd      t1, 0(sp)
    mv      a0, s1
    mv      a1, s2
    mv      a2, sp
    ld      a3, 16(sp)
    mv      a4, s10
    call    ssz_level_leaf
    sd      zero, 24(sp)
21: ld      t1, 24(sp)
    srl     t2, s8, t1
    andi    t2, t2, 1
    beqz    t2, 22f
    mv      a0, s1
    slli    t3, t1, 5
    add     a1, s9, t3
    mv      a2, s10
    mv      a3, s10
    call    ssz_hash_pair
    ld      t1, 24(sp)
    addi    t1, t1, 1
    sd      t1, 24(sp)
    j       21b
22: ld      t1, 24(sp)
    slli    t1, t1, 5
    add     t1, s9, t1
    COPY32  t1, s10
    addi    s8, s8, 1
    j       20b
40: /* close the right edge with zero trees */
    sd      zero, 8(sp)
    li      s8, 0                          # j
41: bgeu    s8, s4, 50f
    srl     t1, s7, s8
    andi    t1, t1, 1
    beqz    t1, 45f
    slli    t2, s8, 5
    add     a1, s9, t2
    ld      t3, 8(sp)
    bnez    t3, 42f
    ld      a2, SSZ_CTX_ZERO(s1)
    add     a2, a2, t2
    li      t3, 1
    sd      t3, 8(sp)
    j       43f
42: mv      a2, s10
43: mv      a0, s1
    mv      a3, s10
    call    ssz_hash_pair
    j       46f
45: ld      t3, 8(sp)
    beqz    t3, 46f
    mv      a0, s1
    mv      a1, s10
    ld      a2, SSZ_CTX_ZERO(s1)
    slli    t2, s8, 5
    add     a2, a2, t2
    mv      a3, s10
    call    ssz_hash_pair
46: addi    s8, s8, 1
    j       41b
50: ld      t3, 8(sp)
    bnez    t3, 51f
    slli    t1, s4, 5
    add     t1, s9, t1
    COPY32  s6, t1
    j       90f
51: COPY32  s6, s10
90: li      a0, SSZ_OK
    LEAVE   32
END_FUNCTION ssz_subtree_root

/* ssz_hash_tree_root(type, value, scratch, root). Locals: slot 0. */
FUNCTION ssz_hash_tree_root
    ENTER   32
    mv      s3, a1
    mv      s4, a3
    mv      s5, a2
    ROOT_NODE
    ld      t0, 0(s5)
    ld      t1, SSZ_NODE_SCRATCH(s2)
    bltu    t0, t1, 80f
    SETUP_CTX a0, s5
    TOP_SLOT s3
    addi    s6, s5, SSZ_SCR_LEVEL
    mv      a0, s1
    mv      a1, s2
    mv      a2, sp
    mv      a3, s6
    call    ssz_value_level
    addi    s7, s5, SSZ_SCR_WORK
    ld      t0, 0(s5)
    addi    t0, t0, -SSZ_SCR_WORK
    sd      t0, 0(s7)
    mv      a0, s1
    mv      a1, s6
    mv      a2, s7
    mv      a3, s4
    call    ssz_level_root
    li      a0, SSZ_OK
    j       90f
80: li      a0, SSZ_BUFFER_TOO_SMALL
90: LEAVE   32
END_FUNCTION ssz_hash_tree_root

/* ---------------------------------------------------------------- Generalized indices and proofs */

/*
 * ssz_get_generalized_index(type, path, gindex). t0 nodes, t1 fields,
 * t2 current type, t3 steps, t4 step count, t5 step number, a0 index,
 * a3 1 once the path is inside a basic value, a4 step, a5 kind, a6 tree depth,
 * a7 length or element width, t6 leaf, a1 next type, s1 temporary.
 */
FUNCTION ssz_get_generalized_index
    ENTER   0
    ld      t0, SSZ_DESC_NODES_OFFSET(a0)
    add     t0, a0, t0
    ld      t1, SSZ_DESC_FIELDS_OFFSET(a0)
    add     t1, a0, t1
    ld      t2, SSZ_DESC_ROOT(a0)
    li      s1, SSZ_NODE_STRIDE
    mul     t2, t2, s1
    add     t2, t2, t0
    ld      t3, SSZ_BYTES_OFFSET(a1)
    add     t3, a1, t3
    ld      t4, SSZ_BYTES_COUNT(a1)
    li      t5, 0
    li      a0, 1
    li      a3, 0
1:  bgeu    t5, t4, 90f
    slli    s1, t5, 3
    add     s1, t3, s1
    ld      a4, 0(s1)
    bnez    a3, 81f
    ld      a5, SSZ_NODE_KIND(t2)
    li      s1, SSZ_KIND_BOOLEAN
    bleu    a5, s1, 81f
    li      s1, -1
    bne     a4, s1, 10f
    /* the length that a list mixes in: the right child, and the last step */
    li      s1, SSZ_KIND_BYTE_LIST
    beq     a5, s1, 2f
    li      s1, SSZ_KIND_BIT_LIST
    beq     a5, s1, 2f
    li      s1, SSZ_KIND_LIST
    bne     a5, s1, 82f
2:  addi    s1, t5, 1
    bne     s1, t4, 83f
    bltz    a0, 86f
    slli    a0, a0, 1
    addi    a0, a0, 1
    j       90f
10: ld      a6, SSZ_NODE_CHUNKS(t2)
    addi    a6, a6, -1
    li      s1, 0
11: beqz    a6, 12f
    srli    a6, a6, 1
    addi    s1, s1, 1
    j       11b
12: mv      a6, s1                         # tree depth
    ld      a7, SSZ_NODE_LENGTH(t2)
    li      s1, SSZ_KIND_CONTAINER
    bne     a5, s1, 20f
    bgeu    a4, a7, 84f
    mv      t6, a4                         # leaf
    ld      a1, SSZ_NODE_ELEMENT(t2)
    add     a1, a1, a4
    slli    a1, a1, 5
    add     a1, t1, a1
    ld      a1, SSZ_FIELD_NODE(a1)
    li      s1, SSZ_NODE_STRIDE
    mul     a1, a1, s1
    add     a1, a1, t0                     # next type
    j       50f
20: bgeu    a4, a7, 85f
    li      s1, SSZ_KIND_BYTE_VECTOR
    beq     a5, s1, 21f
    li      s1, SSZ_KIND_BYTE_LIST
    bne     a5, s1, 22f
21: srli    t6, a4, 5
    li      a3, 1
    mv      a1, t2
    j       50f
22: li      s1, SSZ_KIND_BIT_VECTOR
    beq     a5, s1, 23f
    li      s1, SSZ_KIND_BIT_LIST
    bne     a5, s1, 24f
23: srli    t6, a4, 8
    li      a3, 1
    mv      a1, t2
    j       50f
24: /* vector or list: basic elements pack into chunks */
    ld      a1, SSZ_NODE_ELEMENT(t2)
    li      s1, SSZ_NODE_STRIDE
    mul     a1, a1, s1
    add     a1, a1, t0
    li      a7, 32
    ld      s1, SSZ_NODE_KIND(a1)
    addi    s1, s1, -(SSZ_KIND_BOOLEAN + 1)
    bgez    s1, 25f
    ld      a7, SSZ_NODE_SSZ_SIZE(a1)
25: mul     t6, a4, a7
    mulhu   s1, a4, a7
    srli    t6, t6, 5
    slli    s1, s1, 59
    or      t6, t6, s1
50: /* a list puts its data on the left of the length */
    li      s1, SSZ_KIND_LIST
    beq     a5, s1, 51f
    li      s1, SSZ_KIND_BYTE_LIST
    beq     a5, s1, 51f
    li      s1, SSZ_KIND_BIT_LIST
    bne     a5, s1, 52f
51: bltz    a0, 86f
    slli    a0, a0, 1
52: beqz    a6, 53f
    li      s1, 64
    sub     s1, s1, a6
    srl     s1, a0, s1
    bnez    s1, 86f
    sll     a0, a0, a6
    or      a0, a0, t6
53: mv      t2, a1
    addi    t5, t5, 1
    j       1b
90: sd      a0, 0(a2)
    li      a0, SSZ_OK
    j       99f
81: li      a0, SSZ_NO_PARTS
    j       99f
82: li      a0, SSZ_NO_MIXIN
    j       99f
83: li      a0, SSZ_NO_PARTS_MIXIN
    j       99f
84: li      a0, SSZ_NO_SUCH_FIELD
    j       99f
85: li      a0, SSZ_NO_SUCH_POSITION
    j       99f
86: li      a0, SSZ_GINDEX_TOO_LARGE
99: LEAVE   0
END_FUNCTION ssz_get_generalized_index

/*
 * ssz_build_proof(type, value, gindex, scratch, branch). Two passes over the
 * path: the first only checks it, the second writes the branch.
 * s1 ctx, s2 level, s3 value, s4 branch, s5 scratch, s6 gindex, s7 root
 * TypeNode, s8 branch length D, s9 bits used, s10 work.
 * Locals: slot 0, range 32, index 48, pass 56, q 64, step 72, bits left at
 * this level 80, tree depth 88.
 */
FUNCTION ssz_build_proof
    ENTER   96
    mv      s3, a1
    mv      s4, a4
    mv      s5, a3
    ld      s6, 0(a2)
    ROOT_NODE
    mv      s7, s2
    beqz    s6, 82f
    ld      t0, 0(s5)
    ld      t1, SSZ_NODE_SCRATCH(s7)
    bltu    t0, t1, 80f
    SETUP_CTX a0, s5
    /* D = the bit length of gindex - 1 */
    mv      t0, s6
    li      s8, -1
1:  beqz    t0, 2f
    srli    t0, t0, 1
    addi    s8, s8, 1
    j       1b
2:  sd      zero, 56(sp)
30: /* one pass from the root */
    sd      s3, SSZ_SLOT_P(sp)
    sd      s3, SSZ_SLOT_B(sp)
    ld      t1, SSZ_NODE_SSZ_SIZE(s7)
    seqz    t1, t1
    slli    t1, t1, 1
    sd      t1, SSZ_SLOT_FORM(sp)
    addi    s2, s5, SSZ_SCR_LEVEL
    mv      a0, s1
    mv      a1, s7
    mv      a2, sp
    mv      a3, s2
    call    ssz_value_level
    addi    s10, s5, SSZ_SCR_WORK
    ld      t0, 0(s5)
    addi    t0, t0, -SSZ_SCR_WORK
    sd      t0, 0(s10)
    li      s9, 0
31: sub     t0, s8, s9                     # bits left
    beqz    t0, 70f
    ld      t1, SSZ_LEVEL_MIXIN(s2)
    beqz    t1, 35f
    /* the length mixin level */
    addi    t0, t0, -1
    srl     t2, s6, t0
    addi    s9, s9, 1
    sub     t3, s8, s9
    slli    t3, t3, 5
    add     t3, s4, t3
    addi    t3, t3, SSZ_BYTES_FIXED        # branch node for this depth
    andi    t2, t2, 1
    bnez    t2, 33f
    /* left: the data tree; its sibling is the length */
    ld      t4, 56(sp)
    beqz    t4, 35f
    ld      t5, SSZ_LEVEL_LENGTH(s2)
    sd      t5, 0(t3)
    sd      zero, 8(t3)
    sd      zero, 16(t3)
    sd      zero, 24(t3)
    j       35f
33: /* right: the length itself, which must end the path; its sibling is the data root */
    bnez    t0, 83f
    ld      t4, 56(sp)
    beqz    t4, 70f
    sd      zero, (32 + SSZ_RANGE_LO)(sp)
    ld      t5, SSZ_LEVEL_DEPTH(s2)
    sd      t5, (32 + SSZ_RANGE_DEPTH)(sp)
    mv      a0, s1
    mv      a1, s2
    addi    a2, sp, 32
    mv      a3, s10
    mv      a4, t3
    call    ssz_subtree_root
    j       70f
35: /* down this level's tree */
    sub     t0, s8, s9
    sd      t0, 80(sp)
    ld      t1, SSZ_LEVEL_DEPTH(s2)
    sd      t1, 88(sp)
    sd      zero, 64(sp)
    sd      zero, 72(sp)
36: ld      t2, 72(sp)
    ld      t0, 80(sp)
    ld      t1, 88(sp)
    bgeu    t2, t0, 38f
    bgeu    t2, t1, 38f
    addi    t2, t2, 1
    sd      t2, 72(sp)
    sub     t3, t0, t2
    srl     t3, s6, t3
    andi    t3, t3, 1
    ld      t4, 64(sp)
    slli    t4, t4, 1
    or      t4, t4, t3
    sd      t4, 64(sp)
    addi    s9, s9, 1
    ld      t5, 56(sp)
    beqz    t5, 36b
    /* the sibling q ^ 1 covers 2^(depth - step) leaves */
    xori    t5, t4, 1
    sub     t6, t1, t2
    sll     t5, t5, t6
    sd      t5, (32 + SSZ_RANGE_LO)(sp)
    sd      t6, (32 + SSZ_RANGE_DEPTH)(sp)
    sub     a4, s8, s9
    slli    a4, a4, 5
    add     a4, s4, a4
    addi    a4, a4, SSZ_BYTES_FIXED
    mv      a0, s1
    mv      a1, s2
    addi    a2, sp, 32
    mv      a3, s10
    call    ssz_subtree_root
    j       36b
38: ld      t0, 80(sp)
    ld      t1, 88(sp)
    bleu    t0, t1, 70f
    /* the path goes on into leaf q */
    ld      t2, SSZ_LEVEL_MODE(s2)
    beqz    t2, 84f
    ld      t3, 64(sp)
    ld      t4, SSZ_LEVEL_COUNT(s2)
    bgeu    t3, t4, 85f
    sd      t3, 48(sp)
    mv      a0, s1
    mv      a1, s2
    addi    a2, sp, 48
    addi    a3, s10, 8
    call    ssz_child_level
    addi    s2, s10, 8
    addi    t0, s2, SSZ_LEVEL_SIZE
    ld      t1, 0(s10)
    addi    t1, t1, -(8 + SSZ_LEVEL_SIZE)
    sd      t1, 0(t0)
    mv      s10, t0
    j       31b
70: /* end of a pass */
    ld      t0, 56(sp)
    bnez    t0, 79f
    ld      t1, SSZ_BYTES_SIZE(s4)
    slli    t2, s8, 5
    addi    t2, t2, SSZ_BYTES_FIXED
    bltu    t1, t2, 80f
    li      t3, SSZ_BYTES_FIXED
    sd      t3, SSZ_BYTES_OFFSET(s4)
    sd      s8, SSZ_BYTES_COUNT(s4)
    li      t0, 1
    sd      t0, 56(sp)
    j       30b
79: li      a0, SSZ_OK
    j       90f
80: li      a0, SSZ_BUFFER_TOO_SMALL
    j       90f
82: li      a0, SSZ_NOT_A_GINDEX
    j       90f
83: li      a0, SSZ_PATH_INTO_MIXIN
    j       90f
84: li      a0, SSZ_PATH_INTO_PACKED
    j       90f
85: li      a0, SSZ_PATH_INTO_GAP
90: LEAVE   96
END_FUNCTION ssz_build_proof

/*
 * ssz_verify_merkle_proof(leaf, branch, gindex, root, valid). Rebuilds the root
 * from leaf and branch, as v0.1.0 calculate_merkle_root does, and compares it.
 * s1 next branch node, s2 node count, s3 gindex, s4 root, s5 valid, s6 level.
 * Locals: the SHA-256 input ByteList at sp + 0 (88 bytes), the node at sp + 88.
 */
FUNCTION ssz_verify_merkle_proof
    ENTER   128
    ld      s3, 0(a2)
    beqz    s3, 81f
    /* depth = the bit length of gindex - 1 */
    mv      t0, s3
    li      t1, -1
1:  beqz    t0, 2f
    srli    t0, t0, 1
    addi    t1, t1, 1
    j       1b
2:  beqz    t1, 82f
    ld      s2, SSZ_BYTES_COUNT(a1)
    bne     s2, t1, 83f
    ld      t0, SSZ_BYTES_OFFSET(a1)
    add     s1, a1, t0
    mv      s4, a3
    mv      s5, a4
    addi    t0, sp, 88
    COPY32  t0, a0
    li      t0, 88
    sd      t0, SSZ_BYTES_SIZE(sp)
    li      t0, SSZ_BYTES_FIXED
    sd      t0, SSZ_BYTES_OFFSET(sp)
    li      t0, 64
    sd      t0, SSZ_BYTES_COUNT(sp)
    li      s6, 0
3:  bgeu    s6, s2, 6f
    addi    t0, sp, SSZ_BYTES_FIXED
    addi    t1, sp, (SSZ_BYTES_FIXED + 32)
    addi    t2, sp, 88
    srl     t3, s3, s6
    andi    t3, t3, 1
    beqz    t3, 4f
    /* bit set: the branch node is on the left */
    COPY32  t0, s1
    COPY32  t1, t2
    j       5f
4:  COPY32  t0, t2
    COPY32  t1, s1
5:  mv      a0, sp
    addi    a1, sp, 88
    CALL_EXTERN crypto_sha256
    addi    s1, s1, 32
    addi    s6, s6, 1
    j       3b
6:  /* valid = 1 when the node equals root */
    ld      t0, 88(sp)
    ld      t1, 0(s4)
    xor     t0, t0, t1
    ld      t1, 96(sp)
    ld      t2, 8(s4)
    xor     t1, t1, t2
    or      t0, t0, t1
    ld      t1, 104(sp)
    ld      t2, 16(s4)
    xor     t1, t1, t2
    or      t0, t0, t1
    ld      t1, 112(sp)
    ld      t2, 24(s4)
    xor     t1, t1, t2
    or      t0, t0, t1
    seqz    t0, t0
    sd      t0, 0(s5)
    li      a0, SSZ_OK
    j       90f
81: li      a0, SSZ_NOT_A_GINDEX
    j       90f
82: li      a0, SSZ_ROOT_HAS_NO_BRANCH
    j       90f
83: li      a0, SSZ_BRANCH_LENGTH
90: LEAVE   128
END_FUNCTION ssz_verify_merkle_proof

/* ---------------------------------------------------------------- Constants */

    .p2align 3
300:
.include "ssz_zero_hashes.inc"
