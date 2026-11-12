/*
 * asm-ssz for x86-64 (System V AMD64 psABI). AT&T syntax.
 * Requirements: docs/reference/serialization.md, merkleization.md and proofs.md.
 * Layouts: include/ssz.inc.
 *
 * v1: follows the ssz-specs v0.1.0 steps, one value at a time.
 * Every function follows the System V ABI: pointer arguments, status in rax.
 * Baseline x86-64 instructions only.
 */
.set ISA_X86_64, 1
.include "ssz.inc"
.include "platform.inc"

/* ---------------------------------------------------------------- Macros */

/* Frame of a non-leaf function: rbx, rbp, r12-r15, then locals at rsp + 0 (a multiple of 16). */
.macro ENTER locals
    push    %rbx
    UNWIND_PUSH %rbx
    push    %rbp
    UNWIND_PUSH %rbp
    push    %r12
    UNWIND_PUSH %r12
    push    %r13
    UNWIND_PUSH %r13
    push    %r14
    UNWIND_PUSH %r14
    push    %r15
    UNWIND_PUSH %r15
    sub     $(\locals + 8), %rsp
    UNWIND_ALLOC (\locals + 8)
    UNWIND_END_PROLOGUE
.endm

.macro LEAVE locals
    UNWIND_BEGIN_EPILOGUE
    add     $(\locals + 8), %rsp
    UNWIND_FREE (\locals + 8)
    pop     %r15
    UNWIND_POP %r15
    pop     %r14
    UNWIND_POP %r14
    pop     %r13
    UNWIND_POP %r13
    pop     %r12
    UNWIND_POP %r12
    pop     %rbp
    UNWIND_POP %rbp
    pop     %rbx
    UNWIND_POP %rbx
    UNWIND_END_EPILOGUE
    ret
.endm

/* dst = address of TypeNode number idx. */
.macro NODE dst, idx, ctx=%rbx
    imul    $SSZ_NODE_STRIDE, \idx, \dst
    add     SSZ_CTX_NODES(\ctx), \dst
.endm

/* dst = 32 bytes at src. Uses r8-r11. */
.macro COPY32 dst, src
    mov     (\src), %r8
    mov     8(\src), %r9
    mov     16(\src), %r10
    mov     24(\src), %r11
    mov     %r8, (\dst)
    mov     %r9, 8(\dst)
    mov     %r10, 16(\dst)
    mov     %r11, 24(\dst)
.endm

/* Serialize: append rdx bytes from rsi at cursor r13; write them when ctx rbx says so. Uses rax, rcx, rdi. */
.macro COPY_OUT
    mov     SSZ_CUR_OUT(%r13), %rdi
    lea     (%rdi,%rdx), %rax
    mov     %rax, SSZ_CUR_OUT(%r13)
    cmpq    $(0), SSZ_CTX_WRITE(%rbx)
    je      98f
    mov     %rdx, %rcx
    rep movsb
98:
.endm

/* Deserialize: copy len bytes from src to dst when ctx rbx says to write. Uses rdi, rsi, rcx. */
.macro COPY_IN dst, src, len
    cmpq    $(0), SSZ_CTX_WRITE(%rbx)
    je      98f
    mov     \src, %rsi
    mov     \dst, %rdi
    mov     \len, %rcx
    rep movsb
98:
.endm

/* Deserialize: write the PartRef at r14 (value start r15) for a part at part with count entries. Uses rdx. */
.macro WRITE_PARTREF part, count
    cmpq    $(0), SSZ_CTX_WRITE(%rbx)
    je      98f
    mov     \part, %rdx
    sub     %r15, %rdx
    mov     %rdx, SSZ_PART_OFFSET(%r14)
    mov     \count, SSZ_PART_COUNT(%r14)
98:
.endm

/* Deserialize: decode one child into the slot at rsp + 0; on failure go to 280. */
.macro DE_CHILD node, p, b, form, scope
    mov     \p, SSZ_SLOT_P(%rsp)
    mov     \b, SSZ_SLOT_B(%rsp)
    movq    $\form, SSZ_SLOT_FORM(%rsp)
    mov     \scope, SSZ_SLOT_SCOPE(%rsp)
    mov     \node, %rsi
    mov     %rbx, %rdi
    mov     %rsp, %rdx
    mov     %r13, %rcx
    call    ssz_decode_value
    test    %rax, %rax
    jnz     280f
.endm

/*
 * Deserialize, container: for the variable field at rsp + 72, set r8 to the
 * next variable field (0 when none) and r9 to where its body ends: the next
 * variable field's offset, or the scope rbp. Reads the end of the fields at
 * rsp + 104 and the start of the encoding at rsp + 88.
 */
.macro NEXT_END
    mov     72(%rsp), %r8
93: add     $SSZ_FIELD_STRIDE, %r8
    cmp     104(%rsp), %r8
    jae     95f
    testq   $(1), SSZ_FIELD_FLAGS(%r8)
    jz      93b
    mov     SSZ_FIELD_SSZ_OFFSET(%r8), %r9
    add     88(%rsp), %r9
    mov     (%r9), %r9d
    jmp     96f
95: xor     %r8d, %r8d
    mov     %rbp, %r9
96:
.endm

/* Serialize: encode one child from the slot at rsp + 0. */
.macro SER_CALL node
    mov     \node, %rsi
    mov     %rbx, %rdi
    mov     %rsp, %rdx
    mov     %r13, %rcx
    call    ssz_encode_value
.endm

/* L2 entry: r12 = root TypeNode of the descriptor in rdi. */
.macro ROOT_NODE
    mov     SSZ_DESC_ROOT(%rdi), %r12
    imul    $SSZ_NODE_STRIDE, %r12, %r12
    add     SSZ_DESC_NODES_OFFSET(%rdi), %r12
    add     %rdi, %r12
.endm

/* L2 entry: fill the Ctx in the scratch at scr from the descriptor at desc; rbx = Ctx. Uses rax. */
.macro SETUP_CTX desc, scr
    lea     SSZ_SCR_CTX(\scr), %rbx
    mov     SSZ_DESC_NODES_OFFSET(\desc), %rax
    add     \desc, %rax
    mov     %rax, SSZ_CTX_NODES(%rbx)
    mov     SSZ_DESC_FIELDS_OFFSET(\desc), %rax
    add     \desc, %rax
    mov     %rax, SSZ_CTX_FIELDS(%rbx)
    movq    $(0), SSZ_CTX_WRITE(%rbx)
    movq    $(0), SSZ_CTX_END(%rbx)
    lea     SSZ_SCR_SHA(\scr), %rax
    mov     %rax, SSZ_CTX_SHA(%rbx)
    movq    $(88), SSZ_BYTES_SIZE(%rax)
    movq    $SSZ_BYTES_FIXED, SSZ_BYTES_OFFSET(%rax)
    movq    $(64), SSZ_BYTES_COUNT(%rax)
    lea     300f(%rip), %rax
    mov     %rax, SSZ_CTX_ZERO(%rbx)
.endm

/* L2 entry: slot at rsp + 0 for the caller's value in reg, of root type r12. Uses rax. */
.macro TOP_SLOT reg
    mov     \reg, SSZ_SLOT_P(%rsp)
    mov     \reg, SSZ_SLOT_B(%rsp)
    xor     %eax, %eax
    cmpq    $(0), SSZ_NODE_SSZ_SIZE(%r12)
    sete    %al
    shl     $(1), %eax
    mov     %rax, SSZ_SLOT_FORM(%rsp)
.endm

/* ---------------------------------------------------------------- Serialize */

/*
 * ssz_encode_value(ctx, node, slot, cursor): append the SSZ encoding of the value in
 * slot to cursor.out. rbx ctx, r12 node, r13 cursor, r14 p, r15 b, rbp element
 * or field. Locals: child slot 0, kind 32, count 40, base 48, index 56, start 64.
 */
LOCAL_FUNCTION ssz_encode_value
    ENTER   80
    mov     %rdi, %rbx
    mov     %rsi, %r12
    mov     %rcx, %r13
    mov     SSZ_SLOT_P(%rdx), %r14
    mov     SSZ_SLOT_B(%rdx), %r15
    mov     SSZ_SLOT_FORM(%rdx), %rax
    mov     SSZ_NODE_KIND(%r12), %rcx
    mov     %rcx, 32(%rsp)
    test    %rax, %rax
    jz      10f
    /* A value of a variable size type starts at p. */
    cmp     $SSZ_KIND_CONTAINER, %rcx
    je      40f
    mov     %r14, %r15
    add     $8, %r14
    jmp     30f
10: mov     SSZ_NODE_SSZ_SIZE(%r12), %rdx
    test    %rdx, %rdx
    jz      30f
    cmp     $SSZ_KIND_CONTAINER, %rcx
    je      40f
    cmp     $SSZ_KIND_VECTOR, %rcx
    je      20f
    /* uint, boolean, byte vector, bit vector: the bytes as they are */
    mov     %r14, %rsi
    COPY_OUT
    jmp     90f
20: /* fixed size vector: N entries in place */
    mov     SSZ_NODE_ELEMENT(%r12), %rax
    NODE    %rbp, %rax
    mov     SSZ_NODE_LENGTH(%r12), %rax
    mov     %rax, 40(%rsp)
    mov     %r14, 48(%rsp)
    jmp     60f
30: /* variable size: a PartRef at p, offsets from b */
    mov     SSZ_PART_OFFSET(%r14), %rax
    add     %r15, %rax
    mov     SSZ_PART_COUNT(%r14), %rdx
    mov     %rax, 48(%rsp)
    mov     %rdx, 40(%rsp)
    mov     32(%rsp), %rcx
    cmp     $SSZ_KIND_CONTAINER, %rcx
    jne     31f
    mov     %rax, %r14
    jmp     40f
31: cmp     $SSZ_KIND_BYTE_LIST, %rcx
    jne     32f
    mov     %rax, %rsi
    COPY_OUT
    jmp     90f
32: cmp     $SSZ_KIND_BIT_LIST, %rcx
    jne     33f
    mov     %rax, %rsi
    add     $7, %rdx
    shr     $3, %rdx
    COPY_OUT
    /* the delimiter bit sits at bit position count */
    mov     40(%rsp), %rcx
    mov     SSZ_CUR_OUT(%r13), %rdi
    and     $7, %ecx
    jnz     34f
    lea     1(%rdi), %rax
    mov     %rax, SSZ_CUR_OUT(%r13)
    cmpq    $0, SSZ_CTX_WRITE(%rbx)
    je      90f
    movb    $1, (%rdi)
    jmp     90f
34: cmpq    $0, SSZ_CTX_WRITE(%rbx)
    je      90f
    mov     $1, %eax
    shl     %cl, %eax
    or      %al, -1(%rdi)
    jmp     90f
33: /* vector or list in a part */
    mov     SSZ_NODE_ELEMENT(%r12), %rax
    NODE    %rbp, %rax
    jmp     60f

40: /* container at r14: the fixed part, then the variable fields */
    mov     SSZ_NODE_ELEMENT(%r12), %rax
    shl     $5, %rax
    add     SSZ_CTX_FIELDS(%rbx), %rax
    mov     %rax, %rbp
    mov     SSZ_NODE_LENGTH(%r12), %rax
    mov     %rax, 40(%rsp)
    mov     SSZ_CUR_OUT(%r13), %rax
    mov     %rax, 64(%rsp)
    movq    $0, 56(%rsp)
41: mov     56(%rsp), %rax
    cmp     40(%rsp), %rax
    jae     45f
    shl     $5, %rax
    lea     (%rbp,%rax), %rcx
    testq   $1, SSZ_FIELD_FLAGS(%rcx)
    jz      42f
    addq    $SSZ_BYTES_PER_LENGTH_OFFSET, SSZ_CUR_OUT(%r13)
    jmp     43f
42: mov     SSZ_FIELD_MEM_OFFSET(%rcx), %rax
    add     %r14, %rax
    mov     %rax, SSZ_SLOT_P(%rsp)
    mov     %r14, SSZ_SLOT_B(%rsp)
    movq    $SSZ_FORM_PLACE, SSZ_SLOT_FORM(%rsp)
    mov     SSZ_FIELD_NODE(%rcx), %rax
    NODE    %rax, %rax
    SER_CALL %rax
43: incq    56(%rsp)
    jmp     41b
45: movq    $0, 56(%rsp)
46: mov     56(%rsp), %rax
    cmp     40(%rsp), %rax
    jae     90f
    shl     $5, %rax
    lea     (%rbp,%rax), %rcx
    testq   $1, SSZ_FIELD_FLAGS(%rcx)
    jz      48f
    cmpq    $0, SSZ_CTX_WRITE(%rbx)
    je      47f
    mov     SSZ_CUR_OUT(%r13), %rax
    mov     64(%rsp), %rdx
    sub     %rdx, %rax
    mov     SSZ_FIELD_SSZ_OFFSET(%rcx), %rsi
    mov     %eax, (%rdx,%rsi)
47: mov     SSZ_FIELD_MEM_OFFSET(%rcx), %rax
    add     %r14, %rax
    mov     %rax, SSZ_SLOT_P(%rsp)
    mov     %r14, SSZ_SLOT_B(%rsp)
    movq    $SSZ_FORM_PLACE, SSZ_SLOT_FORM(%rsp)
    mov     SSZ_FIELD_NODE(%rcx), %rax
    NODE    %rax, %rax
    SER_CALL %rax
48: incq    56(%rsp)
    jmp     46b

60: /* count (rsp + 40) elements of type rbp from base (rsp + 48) */
    mov     SSZ_NODE_SSZ_SIZE(%rbp), %rdx
    test    %rdx, %rdx
    jz      70f
    cmpq    $SSZ_KIND_BOOLEAN, SSZ_NODE_KIND(%rbp)
    ja      65f
    /* basic elements: their bytes are already packed */
    imul    40(%rsp), %rdx
    mov     48(%rsp), %rsi
    COPY_OUT
    jmp     90f
65: cmpq    $0, 40(%rsp)
    je      90f
    mov     48(%rsp), %rax
    mov     %rax, SSZ_SLOT_P(%rsp)
    mov     %rax, SSZ_SLOT_B(%rsp)
    movq    $SSZ_FORM_PLACE, SSZ_SLOT_FORM(%rsp)
    SER_CALL %rbp
    mov     SSZ_NODE_MEM_SIZE(%rbp), %rax
    add     %rax, 48(%rsp)
    decq    40(%rsp)
    jmp     65b
70: /* variable size elements: the offset table, then each nested value */
    mov     SSZ_CUR_OUT(%r13), %rax
    mov     %rax, 64(%rsp)
    mov     40(%rsp), %rcx
    lea     (%rax,%rcx,4), %rax
    mov     %rax, SSZ_CUR_OUT(%r13)
    movq    $0, 56(%rsp)
71: mov     56(%rsp), %rax
    cmp     40(%rsp), %rax
    jae     90f
    cmpq    $0, SSZ_CTX_WRITE(%rbx)
    je      72f
    mov     SSZ_CUR_OUT(%r13), %rcx
    mov     64(%rsp), %rdx
    sub     %rdx, %rcx
    mov     %ecx, (%rdx,%rax,4)
72: mov     48(%rsp), %rax
    mov     %rax, SSZ_SLOT_P(%rsp)
    mov     %rax, SSZ_SLOT_B(%rsp)
    movq    $SSZ_FORM_NESTED, SSZ_SLOT_FORM(%rsp)
    SER_CALL %rbp
    mov     48(%rsp), %rax
    mov     SSZ_VALUE_SIZE(%rax), %rcx
    add     %rcx, 48(%rsp)
    incq    56(%rsp)
    jmp     71b

90: xor     %eax, %eax
    LEAVE   80
END_FUNCTION ssz_encode_value

/* ssz_serialize_size(type, value, scratch, size). Locals: slot 0, cursor 32. */
FUNCTION ssz_serialize_size
    ENTER   48
    mov     %rsi, %r14
    mov     %rcx, %r15
    mov     %rdx, %rbp
    ROOT_NODE
    mov     (%rbp), %rax
    cmp     SSZ_NODE_SCRATCH(%r12), %rax
    jb      80f
    SETUP_CTX %rdi, %rbp
    TOP_SLOT %r14
    movq    $0, 32(%rsp)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     %rsp, %rdx
    lea     32(%rsp), %rcx
    call    ssz_encode_value
    mov     32(%rsp), %rax
    add     $SSZ_BYTES_FIXED, %rax
    mov     %rax, (%r15)
    xor     %eax, %eax
    jmp     90f
80: mov     $SSZ_BUFFER_TOO_SMALL, %eax
90: LEAVE   48
END_FUNCTION ssz_serialize_size

/* ssz_serialize(type, value, scratch, serialized). Locals: slot 0, cursor 32. */
FUNCTION ssz_serialize
    ENTER   48
    mov     %rsi, %r14
    mov     %rcx, %r15
    mov     %rdx, %rbp
    ROOT_NODE
    mov     (%rbp), %rax
    cmp     SSZ_NODE_SCRATCH(%r12), %rax
    jb      80f
    SETUP_CTX %rdi, %rbp
    TOP_SLOT %r14
    /* measure */
    movq    $0, 32(%rsp)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     %rsp, %rdx
    lea     32(%rsp), %rcx
    call    ssz_encode_value
    mov     32(%rsp), %r13
    lea     SSZ_BYTES_FIXED(%r13), %rax
    cmp     SSZ_BYTES_SIZE(%r15), %rax
    ja      80f
    movq    $SSZ_BYTES_FIXED, SSZ_BYTES_OFFSET(%r15)
    mov     %r13, SSZ_BYTES_COUNT(%r15)
    /* write */
    movq    $1, SSZ_CTX_WRITE(%rbx)
    lea     SSZ_BYTES_FIXED(%r15), %rax
    mov     %rax, 32(%rsp)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     %rsp, %rdx
    lea     32(%rsp), %rcx
    call    ssz_encode_value
    xor     %eax, %eax
    jmp     90f
80: mov     $SSZ_BUFFER_TOO_SMALL, %eax
90: LEAVE   48
END_FUNCTION ssz_serialize

/* ---------------------------------------------------------------- Deserialize */

/*
 * ssz_decode_value(ctx, node, slot, cursor): decode slot.scope bytes at cursor.pos into
 * the value in slot, as v0.1.0 deserialize does. On a refusal the cursor is
 * restored. rbx ctx, r12 node, r13 cursor, r14 p, r15 b, rbp scope.
 * Locals: child slot 0, cursor at entry 32 and 40, value start 48, form 56,
 * kind 64, then 72, 80, 88, 96, 104 for each case.
 */
LOCAL_FUNCTION ssz_decode_value
    ENTER   112
    mov     %rdi, %rbx
    mov     %rsi, %r12
    mov     %rcx, %r13
    mov     SSZ_CUR_POS(%rcx), %rax
    mov     %rax, 32(%rsp)
    mov     SSZ_CUR_NEXT(%rcx), %rax
    mov     %rax, 40(%rsp)
    mov     SSZ_SLOT_P(%rdx), %r14
    mov     SSZ_SLOT_B(%rdx), %r15
    mov     SSZ_SLOT_SCOPE(%rdx), %rbp
    mov     SSZ_SLOT_FORM(%rdx), %rax
    mov     %r14, 48(%rsp)
    mov     %rax, 56(%rsp)
    mov     SSZ_NODE_KIND(%r12), %rcx
    mov     %rcx, 64(%rsp)
    test    %rax, %rax
    jz      10f
    /* A value of a variable size type starts at p; its parts start at value_fixed. */
    mov     SSZ_NODE_VALUE_FIXED(%r12), %rax
    add     %r14, %rax
    mov     %rax, SSZ_CUR_NEXT(%r13)
    cmp     $SSZ_KIND_CONTAINER, %rcx
    je      40f
    mov     %r14, %r15
    add     $8, %r14
    jmp     30f

10: mov     SSZ_NODE_SSZ_SIZE(%r12), %rdx
    test    %rdx, %rdx
    jz      30f
    cmp     $SSZ_KIND_CONTAINER, %rcx
    je      40f
    cmp     $SSZ_KIND_VECTOR, %rcx
    je      20f
    /* uint, boolean, byte vector, bit vector */
    cmp     %rdx, %rbp
    jne     201f
    mov     SSZ_CUR_POS(%r13), %rsi
    lea     (%rsi,%rdx), %rdi
    cmp     SSZ_CTX_END(%rbx), %rdi
    ja      202f
    cmp     $SSZ_KIND_BOOLEAN, %rcx
    jne     11f
    cmpb    $1, (%rsi)
    ja      203f
    jmp     15f
11: cmp     $SSZ_KIND_BIT_VECTOR, %rcx
    jne     15f
    mov     SSZ_NODE_LENGTH(%r12), %rcx
    and     $7, %ecx
    jz      15f
    movzbl  -1(%rdi), %eax
    shr     %cl, %eax
    test    %eax, %eax
    jnz     204f
15: mov     %rdi, SSZ_CUR_POS(%r13)
    COPY_IN %r14, %rsi, %rdx
    jmp     288f

20: /* fixed size vector: the scope is the SSZ size, then each entry */
    cmp     %rdx, %rbp
    jne     201f
    mov     SSZ_NODE_ELEMENT(%r12), %rax
    NODE    %rax, %rax
    mov     %rax, 72(%rsp)
    mov     SSZ_NODE_LENGTH(%r12), %rax
    mov     %rax, 80(%rsp)
    mov     %r14, 88(%rsp)
21: cmpq    $0, 80(%rsp)
    je      288f
    mov     72(%rsp), %rsi
    mov     SSZ_NODE_SSZ_SIZE(%rsi), %r9
    mov     88(%rsp), %r8
    DE_CHILD %rsi, %r8, %r15, SSZ_FORM_PLACE, %r9
    mov     72(%rsp), %rsi
    mov     SSZ_NODE_MEM_SIZE(%rsi), %rax
    add     %rax, 88(%rsp)
    decq    80(%rsp)
    jmp     21b

30: /* variable size in place: a PartRef at p, offsets from b */
    mov     64(%rsp), %rcx
    cmp     $SSZ_KIND_CONTAINER, %rcx
    jne     31f
    mov     SSZ_CUR_NEXT(%r13), %r8
    mov     %r8, 72(%rsp)
    DE_CHILD %r12, %r8, %r8, SSZ_FORM_NESTED, %rbp
    mov     72(%rsp), %r8
    mov     $1, %r9d
    WRITE_PARTREF %r8, %r9
    jmp     288f
31: cmp     $SSZ_KIND_BYTE_LIST, %rcx
    jne     33f
    cmp     SSZ_NODE_LENGTH(%r12), %rbp
    ja      205f
    mov     SSZ_CUR_POS(%r13), %rsi
    lea     (%rsi,%rbp), %rax
    cmp     SSZ_CTX_END(%rbx), %rax
    ja      202f
    mov     %rax, SSZ_CUR_POS(%r13)
    mov     SSZ_CUR_NEXT(%r13), %r8
    WRITE_PARTREF %r8, %rbp
    COPY_IN %r8, %rsi, %rbp
    lea     7(%rbp), %rax
    and     $-8, %rax
    add     %r8, %rax
    mov     %rax, SSZ_CUR_NEXT(%r13)
    jmp     288f
33: cmp     $SSZ_KIND_BIT_LIST, %rcx
    jne     50f
    mov     SSZ_CUR_POS(%r13), %rsi
    lea     (%rsi,%rbp), %rdi
    cmp     SSZ_CTX_END(%rbx), %rdi
    ja      202f
    test    %rbp, %rbp
    jz      206f
    movzbl  -1(%rdi), %eax
    test    %eax, %eax
    jnz     35f
    /* the last byte is zero: zero bytes past the delimiter, or no delimiter */
    mov     %rsi, %rcx
34: cmp     %rdi, %rcx
    jae     207f
    movzbl  (%rcx), %edx
    inc     %rcx
    test    %edx, %edx
    jz      34b
    jmp     208f
35: bsr     %eax, %ecx                     /* delimiter bit in the last byte */
    mov     %rcx, 96(%rsp)
    lea     -1(%rbp), %rax
    lea     (%rcx,%rax,8), %rax            /* bit count */
    cmp     SSZ_NODE_LENGTH(%r12), %rax
    ja      205f
    mov     %rax, 72(%rsp)
    mov     %rdi, SSZ_CUR_POS(%r13)
    add     $7, %rax
    shr     $3, %rax
    mov     %rax, 80(%rsp)                 /* data bytes */
    mov     SSZ_CUR_NEXT(%r13), %r8
    mov     72(%rsp), %r9
    WRITE_PARTREF %r8, %r9
    mov     80(%rsp), %r9
    COPY_IN %r8, %rsi, %r9
    /* clear the delimiter when it shares the last data byte */
    cmpq    $0, 96(%rsp)
    je      36f
    cmpq    $0, SSZ_CTX_WRITE(%rbx)
    je      36f
    mov     96(%rsp), %rcx
    mov     $1, %eax
    shl     %cl, %eax
    not     %eax
    mov     80(%rsp), %rdx
    and     %al, -1(%r8,%rdx)
36: mov     80(%rsp), %rax
    add     $7, %rax
    and     $-8, %rax
    add     %r8, %rax
    mov     %rax, SSZ_CUR_NEXT(%r13)
    jmp     288f

40: /* container at r14 */
    mov     SSZ_NODE_ELEMENT(%r12), %rax
    shl     $5, %rax
    add     SSZ_CTX_FIELDS(%rbx), %rax
    mov     %rax, 72(%rsp)                 /* field */
    mov     SSZ_NODE_LENGTH(%r12), %rcx
    shl     $5, %rcx
    add     %rax, %rcx
    mov     %rcx, 104(%rsp)                /* end of the fields */
    mov     SSZ_CUR_POS(%r13), %rax
    mov     %rax, 88(%rsp)                 /* start of the encoding */
    movq    $0, 96(%rsp)                   /* first variable field */
41: mov     72(%rsp), %rcx
    cmp     104(%rsp), %rcx
    jae     44f
    testq   $1, SSZ_FIELD_FLAGS(%rcx)
    jz      42f
    cmpq    $0, 96(%rsp)
    jne     45f
    mov     %rcx, 96(%rsp)
45: mov     SSZ_CUR_POS(%r13), %rax
    add     $SSZ_BYTES_PER_LENGTH_OFFSET, %rax
    cmp     SSZ_CTX_END(%rbx), %rax
    ja      202f
    mov     %rax, SSZ_CUR_POS(%r13)
    jmp     43f
42: mov     SSZ_FIELD_MEM_OFFSET(%rcx), %r8
    add     %r14, %r8
    mov     SSZ_FIELD_NODE(%rcx), %rsi
    NODE    %rsi, %rsi
    mov     SSZ_NODE_SSZ_SIZE(%rsi), %r9
    DE_CHILD %rsi, %r8, %r14, SSZ_FORM_PLACE, %r9
43: addq    $SSZ_FIELD_STRIDE, 72(%rsp)
    jmp     41b
44: mov     SSZ_CUR_POS(%r13), %rax
    sub     88(%rsp), %rax                 /* bytes read */
    mov     96(%rsp), %rcx
    test    %rcx, %rcx
    jnz     46f
    cmp     %rax, %rbp
    jne     201f
    jmp     288f
46: mov     SSZ_FIELD_SSZ_OFFSET(%rcx), %rdx
    add     88(%rsp), %rdx
    mov     (%rdx), %edx
    cmp     %rax, %rdx
    jne     211f
    /* the spans of the variable fields */
    mov     %rcx, 72(%rsp)
47: NEXT_END
    mov     72(%rsp), %rcx
    mov     SSZ_FIELD_SSZ_OFFSET(%rcx), %rdx
    add     88(%rsp), %rdx
    mov     (%rdx), %edx                   /* start */
    cmp     %rdx, %r9
    jae     48f
    test    %r8, %r8
    jz      214f
    jmp     215f
48: test    %r8, %r8
    jz      49f
    mov     %r8, 72(%rsp)
    jmp     47b
49: /* the bodies of the variable fields */
    mov     96(%rsp), %rax
    mov     %rax, 72(%rsp)
491:
    NEXT_END
    mov     %r8, 80(%rsp)                  /* next variable field */
    mov     72(%rsp), %rcx
    mov     SSZ_FIELD_SSZ_OFFSET(%rcx), %rdx
    add     88(%rsp), %rdx
    mov     (%rdx), %edx
    sub     %rdx, %r9                      /* span */
    mov     SSZ_FIELD_MEM_OFFSET(%rcx), %r8
    add     %r14, %r8
    mov     SSZ_FIELD_NODE(%rcx), %rsi
    NODE    %rsi, %rsi
    DE_CHILD %rsi, %r8, %r14, SSZ_FORM_PLACE, %r9
    mov     80(%rsp), %rax
    mov     %rax, 72(%rsp)
    test    %rax, %rax
    jnz     491b
    jmp     288f

50: /* vector or list in a part */
    mov     SSZ_NODE_ELEMENT(%r12), %rax
    NODE    %rax, %rax
    mov     %rax, 72(%rsp)                 /* element */
    mov     SSZ_NODE_SSZ_SIZE(%rax), %rcx
    test    %rcx, %rcx
    jz      60f
    /* list of fixed size elements */
    test    %rbp, %rbp
    jz      55f
    mov     %rbp, %rax
    xor     %edx, %edx
    div     %rcx
    test    %rdx, %rdx
    jnz     209f
    cmp     SSZ_NODE_LENGTH(%r12), %rax
    ja      205f
    mov     %rax, 80(%rsp)                 /* count */
    mov     SSZ_CUR_NEXT(%r13), %r8
    mov     %r8, 88(%rsp)                  /* entry */
    WRITE_PARTREF %r8, %rax
    mov     72(%rsp), %rcx
    mov     SSZ_NODE_MEM_SIZE(%rcx), %rax
    imul    80(%rsp), %rax
    add     $7, %rax
    and     $-8, %rax
    add     %r8, %rax
    mov     %rax, SSZ_CUR_NEXT(%r13)
52: cmpq    $0, 80(%rsp)
    je      288f
    mov     72(%rsp), %rsi
    mov     SSZ_NODE_SSZ_SIZE(%rsi), %r9
    mov     88(%rsp), %r8
    DE_CHILD %rsi, %r8, %r15, SSZ_FORM_PLACE, %r9
    mov     72(%rsp), %rsi
    mov     SSZ_NODE_MEM_SIZE(%rsi), %rax
    add     %rax, 88(%rsp)
    decq    80(%rsp)
    jmp     52b
55: mov     SSZ_CUR_NEXT(%r13), %r8
    xor     %r9d, %r9d
    WRITE_PARTREF %r8, %r9
    jmp     288f

60: /* variable size elements: the offset table */
    mov     64(%rsp), %rcx
    cmp     $SSZ_KIND_VECTOR, %rcx
    jne     62f
    mov     SSZ_NODE_LENGTH(%r12), %rax
    mov     %rax, 80(%rsp)
    shl     $2, %rax
    cmp     %rax, %rbp
    jb      210f
    mov     SSZ_CUR_POS(%r13), %rsi
    lea     (%rsi,%rax), %rdx
    cmp     SSZ_CTX_END(%rbx), %rdx
    ja      202f
    mov     (%rsi), %edx
    cmp     %rax, %rdx
    jne     211f
    jmp     64f
62: test    %rbp, %rbp
    jz      55b
    cmp     $SSZ_BYTES_PER_LENGTH_OFFSET, %rbp
    jb      210f
    mov     SSZ_CUR_POS(%r13), %rsi
    lea     SSZ_BYTES_PER_LENGTH_OFFSET(%rsi), %rdx
    cmp     SSZ_CTX_END(%rbx), %rdx
    ja      202f
    mov     (%rsi), %eax
    cmp     $SSZ_BYTES_PER_LENGTH_OFFSET, %rax
    jb      212f
    test    $3, %al
    jnz     213f
    cmp     %rbp, %rax
    ja      214f
    mov     %rax, %rdx
    shr     $2, %rdx
    cmp     SSZ_NODE_LENGTH(%r12), %rdx
    ja      205f
    mov     %rdx, 80(%rsp)
    add     %rsi, %rax
    cmp     SSZ_CTX_END(%rbx), %rax
    ja      202f
64: /* count (rsp + 80) offsets at rsi: check the spans */
    mov     80(%rsp), %r8
    xor     %ecx, %ecx
65: cmp     %r8, %rcx
    jae     67f
    mov     (%rsi,%rcx,4), %eax
    lea     1(%rcx), %rdx
    cmp     %r8, %rdx
    jae     66f
    mov     (%rsi,%rdx,4), %r9d
    cmp     %rax, %r9
    jb      215f
    mov     %rdx, %rcx
    jmp     65b
66: cmp     %rax, %rbp
    jb      214f
67: /* the nested values */
    mov     %rsi, 88(%rsp)                 /* offset table */
    mov     SSZ_CUR_NEXT(%r13), %rax
    WRITE_PARTREF %rax, %r8
    lea     (%rsi,%r8,4), %rax
    mov     %rax, SSZ_CUR_POS(%r13)
    movq    $0, 96(%rsp)
68: mov     96(%rsp), %rcx
    cmp     80(%rsp), %rcx
    jae     288f
    mov     88(%rsp), %rsi
    mov     (%rsi,%rcx,4), %eax
    lea     1(%rcx), %rdx
    mov     %rbp, %r9
    cmp     80(%rsp), %rdx
    jae     69f
    mov     (%rsi,%rdx,4), %r9d
69: sub     %rax, %r9                      /* span */
    mov     SSZ_CUR_NEXT(%r13), %r8
    mov     72(%rsp), %rsi
    DE_CHILD %rsi, %r8, %r8, SSZ_FORM_NESTED, %r9
    incq    96(%rsp)
    jmp     68b

288: /* success: a nested value records its size */
    cmpq    $SSZ_FORM_NESTED, 56(%rsp)
    jne     289f
    cmpq    $0, SSZ_CTX_WRITE(%rbx)
    je      289f
    mov     48(%rsp), %rax
    mov     SSZ_CUR_NEXT(%r13), %rcx
    sub     %rax, %rcx
    mov     %rcx, SSZ_VALUE_SIZE(%rax)
289: xor    %eax, %eax
    jmp     299f
201: mov    $SSZ_SCOPE, %eax
    jmp     280f
202: mov    $SSZ_TRUNCATED, %eax
    jmp     280f
203: mov    $SSZ_NOT_A_BIT, %eax
    jmp     280f
204: mov    $SSZ_PADDING_BITS, %eax
    jmp     280f
205: mov    $SSZ_LIMIT, %eax
    jmp     280f
206: mov    $SSZ_EMPTY_ENCODING, %eax
    jmp     280f
207: mov    $SSZ_NO_DELIMITER, %eax
    jmp     280f
208: mov    $SSZ_TRAILING_ZEROS, %eax
    jmp     280f
209: mov    $SSZ_SCOPE_UNDIVIDED, %eax
    jmp     280f
210: mov    $SSZ_SCOPE_TOO_SMALL, %eax
    jmp     280f
211: mov    $SSZ_FIRST_OFFSET, %eax
    jmp     280f
212: mov    $SSZ_OFFSET_BELOW_TABLE, %eax
    jmp     280f
213: mov    $SSZ_OFFSET_UNALIGNED, %eax
    jmp     280f
214: mov    $SSZ_OFFSET_PAST_SCOPE, %eax
    jmp     280f
215: mov    $SSZ_OFFSET_UNORDERED, %eax
280: /* refusal: restore the cursor */
    mov     32(%rsp), %rcx
    mov     %rcx, SSZ_CUR_POS(%r13)
    mov     40(%rsp), %rcx
    mov     %rcx, SSZ_CUR_NEXT(%r13)
299: LEAVE  112
END_FUNCTION ssz_decode_value

/*
 * L2 deserialize, decode_bytes rules for the top value. Uses rbx ctx, r12 root
 * TypeNode, r13 serialized ByteList, r15 value start (0 when only measuring),
 * the slot at rsp + 0 and the cursor at rsp + 32. Sets rax to the status and
 * rsp + 48 to the size of the value.
 */
.macro DE_CALL
    mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     %rsp, %rdx
    lea     32(%rsp), %rcx
    call    ssz_decode_value
.endm

.macro DE_TOP
    mov     SSZ_BYTES_OFFSET(%r13), %rsi
    add     %r13, %rsi
    mov     SSZ_BYTES_COUNT(%r13), %rdx
    lea     (%rsi,%rdx), %rax
    mov     %rax, SSZ_CTX_END(%rbx)
    mov     %rsi, (32 + SSZ_CUR_POS)(%rsp)
    mov     %r15, SSZ_SLOT_P(%rsp)
    mov     %r15, SSZ_SLOT_B(%rsp)
    mov     %rdx, SSZ_SLOT_SCOPE(%rsp)
    mov     SSZ_NODE_KIND(%r12), %rcx
    mov     SSZ_NODE_SSZ_SIZE(%r12), %rax
    test    %rax, %rax
    jz      85f
    /* fixed size: a basic value or a byte or bit vector must be exactly its size */
    cmp     $SSZ_KIND_CONTAINER, %rcx
    je      83f
    cmp     $SSZ_KIND_VECTOR, %rcx
    je      83f
    cmp     %rax, %rdx
    je      83f
    mov     $SSZ_TRUNCATED, %eax
    cmp     $SSZ_KIND_BYTE_VECTOR, %rcx
    jne     89f
    mov     $SSZ_COUNT, %eax
    jmp     89f
83: movq    $SSZ_FORM_PLACE, SSZ_SLOT_FORM(%rsp)
    mov     SSZ_NODE_MEM_SIZE(%r12), %rax
    add     %r15, %rax
    mov     %rax, (32 + SSZ_CUR_NEXT)(%rsp)
    DE_CALL
    test    %rax, %rax
    jnz     89f
    mov     SSZ_NODE_MEM_SIZE(%r12), %rax
    mov     %rax, 48(%rsp)
    jmp     87f
85: movq    $SSZ_FORM_TOP, SSZ_SLOT_FORM(%rsp)
    DE_CALL
    test    %rax, %rax
    jnz     89f
    mov     (32 + SSZ_CUR_NEXT)(%rsp), %rax
    sub     %r15, %rax
    mov     %rax, 48(%rsp)
    mov     SSZ_NODE_KIND(%r12), %rcx
    cmp     $SSZ_KIND_BYTE_LIST, %rcx
    je      88f
    cmp     $SSZ_KIND_BIT_LIST, %rcx
    je      88f
87: mov     (32 + SSZ_CUR_POS)(%rsp), %rcx
    mov     $SSZ_TRAILING_BYTES, %eax
    cmp     SSZ_CTX_END(%rbx), %rcx
    jne     89f
88: xor     %eax, %eax
89:
.endm

/* ssz_deserialize_size(type, serialized, scratch, size). Locals: slot 0, cursor 32, size 48. */
FUNCTION ssz_deserialize_size
    ENTER   64
    mov     %rsi, %r13
    mov     %rcx, %r14
    mov     %rdx, %rbp
    ROOT_NODE
    mov     (%rbp), %rax
    cmp     SSZ_NODE_SCRATCH(%r12), %rax
    jb      80f
    SETUP_CTX %rdi, %rbp
    xor     %r15d, %r15d
    DE_TOP
    test    %rax, %rax
    jnz     90f
    mov     48(%rsp), %rcx
    mov     %rcx, (%r14)
    xor     %eax, %eax
    jmp     90f
80: mov     $SSZ_BUFFER_TOO_SMALL, %eax
90: LEAVE   64
END_FUNCTION ssz_deserialize_size

/* ssz_deserialize(type, serialized, scratch, value). Locals: slot 0, cursor 32, size 48. */
FUNCTION ssz_deserialize
    ENTER   64
    mov     %rsi, %r13
    mov     %rcx, %r14
    mov     %rdx, %rbp
    ROOT_NODE
    mov     (%rbp), %rax
    cmp     SSZ_NODE_SCRATCH(%r12), %rax
    jb      80f
    SETUP_CTX %rdi, %rbp
    /* check and measure */
    xor     %r15d, %r15d
    DE_TOP
    test    %rax, %rax
    jnz     90f
    cmpq    $0, SSZ_NODE_SSZ_SIZE(%r12)
    jne     70f
    mov     SSZ_VALUE_SIZE(%r14), %rax
    cmp     48(%rsp), %rax
    jb      80f
70: /* write */
    movq    $1, SSZ_CTX_WRITE(%rbx)
    mov     %r14, %r15
    DE_TOP
    jmp     90f
80: mov     $SSZ_BUFFER_TOO_SMALL, %eax
90: LEAVE   64
END_FUNCTION ssz_deserialize

/* ---------------------------------------------------------------- Merkleization */

/* ssz_hash_pair(ctx, left, right, out): out = SHA-256(left || right), 32 bytes each. */
LOCAL_FUNCTION ssz_hash_pair
    ENTER   0
    mov     SSZ_CTX_SHA(%rdi), %rbx
    lea     SSZ_BYTES_FIXED(%rbx), %rax
    COPY32  %rax, %rsi
    lea     32(%rax), %rax
    COPY32  %rax, %rdx
    mov     %rbx, %rdi
    mov     %rcx, %rsi
    CALL_EXTERN crypto_sha256
    xor     %eax, %eax
    LEAVE   0
END_FUNCTION ssz_hash_pair

/* ssz_value_level(ctx, node, slot, level): describe the leaves of the value in slot. A leaf. */
LOCAL_FUNCTION ssz_value_level
    UNWIND_END_PROLOGUE
    mov     SSZ_SLOT_P(%rdx), %r8
    mov     SSZ_SLOT_B(%rdx), %r9
    mov     SSZ_SLOT_FORM(%rdx), %r10
    mov     SSZ_NODE_KIND(%rsi), %r11
    mov     SSZ_NODE_CHUNKS(%rsi), %rax
    dec     %rax
    xor     %edx, %edx
    test    %rax, %rax
    jz      1f
    bsr     %rax, %rdx
    inc     %rdx
1:  mov     %rdx, SSZ_LEVEL_DEPTH(%rcx)
    movq    $0, SSZ_LEVEL_MIXIN(%rcx)
    movq    $0, SSZ_LEVEL_LENGTH(%rcx)
    movq    $0, SSZ_LEVEL_C(%rcx)
    movq    $0, SSZ_LEVEL_WALK_I(%rcx)
    movq    $0, SSZ_LEVEL_WALK_V(%rcx)
    test    %r10, %r10
    jz      10f
    /* a value of a variable size type at p */
    cmp     $SSZ_KIND_CONTAINER, %r11
    je      40f
    mov     %r8, %r9
    add     $8, %r8
    jmp     20f
10: mov     SSZ_NODE_SSZ_SIZE(%rsi), %rax
    test    %rax, %rax
    jz      20f
    cmp     $SSZ_KIND_CONTAINER, %r11
    je      40f
    cmp     $SSZ_KIND_VECTOR, %r11
    jne     50f
    mov     SSZ_NODE_ELEMENT(%rsi), %rdx
    NODE    %rdx, %rdx, %rdi
    mov     SSZ_NODE_LENGTH(%rsi), %r10
    jmp     30f
20: /* a PartRef at r8, offsets from r9: r8 = part, r10 = count */
    mov     SSZ_PART_OFFSET(%r8), %rax
    add     %r9, %rax
    mov     SSZ_PART_COUNT(%r8), %r10
    mov     %rax, %r8
    cmp     $SSZ_KIND_CONTAINER, %r11
    je      40f
    cmp     $SSZ_KIND_BYTE_LIST, %r11
    jne     21f
    mov     %r10, SSZ_LEVEL_LENGTH(%rcx)
    movq    $1, SSZ_LEVEL_MIXIN(%rcx)
    mov     %r10, %rax
    jmp     50f
21: cmp     $SSZ_KIND_BIT_LIST, %r11
    jne     22f
    mov     %r10, SSZ_LEVEL_LENGTH(%rcx)
    movq    $1, SSZ_LEVEL_MIXIN(%rcx)
    lea     7(%r10), %rax
    shr     $3, %rax
    jmp     50f
22: cmp     $SSZ_KIND_LIST, %r11
    jne     23f
    mov     %r10, SSZ_LEVEL_LENGTH(%rcx)
    movq    $1, SSZ_LEVEL_MIXIN(%rcx)
23: mov     SSZ_NODE_ELEMENT(%rsi), %rdx
    NODE    %rdx, %rdx, %rdi
30: /* elements of type rdx from r8, count r10 */
    mov     SSZ_NODE_SSZ_SIZE(%rdx), %rax
    test    %rax, %rax
    jz      35f
    cmpq    $SSZ_KIND_BOOLEAN, SSZ_NODE_KIND(%rdx)
    ja      32f
    imul    %r10, %rax
    jmp     50f
32: movq    $SSZ_MODE_FIXED, SSZ_LEVEL_MODE(%rcx)
    mov     %r10, SSZ_LEVEL_COUNT(%rcx)
    mov     %rdx, SSZ_LEVEL_A(%rcx)
    mov     %r8, SSZ_LEVEL_B(%rcx)
    mov     SSZ_NODE_MEM_SIZE(%rdx), %rax
    mov     %rax, SSZ_LEVEL_C(%rcx)
    jmp     90f
35: movq    $SSZ_MODE_VARIABLE, SSZ_LEVEL_MODE(%rcx)
    mov     %r10, SSZ_LEVEL_COUNT(%rcx)
    mov     %rdx, SSZ_LEVEL_A(%rcx)
    mov     %r8, SSZ_LEVEL_B(%rcx)
    mov     %r8, SSZ_LEVEL_WALK_V(%rcx)
    jmp     90f
40: /* container value at r8 */
    movq    $SSZ_MODE_FIELDS, SSZ_LEVEL_MODE(%rcx)
    mov     SSZ_NODE_LENGTH(%rsi), %rax
    mov     %rax, SSZ_LEVEL_COUNT(%rcx)
    mov     %rsi, SSZ_LEVEL_A(%rcx)
    mov     %r8, SSZ_LEVEL_B(%rcx)
    jmp     90f
50: /* packed bytes at r8, length rax */
    movq    $SSZ_MODE_PACKED, SSZ_LEVEL_MODE(%rcx)
    mov     %r8, SSZ_LEVEL_A(%rcx)
    mov     %rax, SSZ_LEVEL_B(%rcx)
    add     $31, %rax
    shr     $5, %rax
    mov     %rax, SSZ_LEVEL_COUNT(%rcx)
90: xor     %eax, %eax
    ret
END_FUNCTION ssz_value_level

/* ssz_child_level(ctx, level, index, child): describe the leaves of leaf index of level. */
LOCAL_FUNCTION ssz_child_level
    ENTER   32
    mov     %rdi, %rbx
    mov     %rsi, %r12
    mov     (%rdx), %r13
    mov     %rcx, %r14
    mov     SSZ_LEVEL_MODE(%r12), %rax
    cmp     $SSZ_MODE_FIXED, %rax
    jne     2f
    mov     SSZ_LEVEL_C(%r12), %rax
    imul    %r13, %rax
    add     SSZ_LEVEL_B(%r12), %rax
    mov     %rax, SSZ_SLOT_P(%rsp)
    mov     %rax, SSZ_SLOT_B(%rsp)
    movq    $SSZ_FORM_PLACE, SSZ_SLOT_FORM(%rsp)
    mov     SSZ_LEVEL_A(%r12), %rsi
    jmp     9f
2:  cmp     $SSZ_MODE_VARIABLE, %rax
    jne     5f
    mov     SSZ_LEVEL_WALK_I(%r12), %rcx
    mov     SSZ_LEVEL_WALK_V(%r12), %rdx
    cmp     %rcx, %r13
    jae     3f
    xor     %ecx, %ecx
    mov     SSZ_LEVEL_B(%r12), %rdx
3:  cmp     %r13, %rcx
    jae     4f
    add     SSZ_VALUE_SIZE(%rdx), %rdx
    inc     %rcx
    jmp     3b
4:  mov     %rcx, SSZ_LEVEL_WALK_I(%r12)
    mov     %rdx, SSZ_LEVEL_WALK_V(%r12)
    mov     %rdx, SSZ_SLOT_P(%rsp)
    mov     %rdx, SSZ_SLOT_B(%rsp)
    movq    $SSZ_FORM_NESTED, SSZ_SLOT_FORM(%rsp)
    mov     SSZ_LEVEL_A(%r12), %rsi
    jmp     9f
5:  /* container field number index */
    mov     SSZ_LEVEL_A(%r12), %rax
    mov     SSZ_NODE_ELEMENT(%rax), %rax
    add     %r13, %rax
    shl     $5, %rax
    add     SSZ_CTX_FIELDS(%rbx), %rax
    mov     SSZ_LEVEL_B(%r12), %rcx
    mov     SSZ_FIELD_MEM_OFFSET(%rax), %rdx
    add     %rcx, %rdx
    mov     %rdx, SSZ_SLOT_P(%rsp)
    mov     %rcx, SSZ_SLOT_B(%rsp)
    movq    $SSZ_FORM_PLACE, SSZ_SLOT_FORM(%rsp)
    mov     SSZ_FIELD_NODE(%rax), %rsi
    NODE    %rsi, %rsi
9:  mov     %rbx, %rdi
    mov     %rsp, %rdx
    mov     %r14, %rcx
    call    ssz_value_level
    xor     %eax, %eax
    LEAVE   32
END_FUNCTION ssz_child_level

/* ssz_level_leaf(ctx, level, index, work, out): out = leaf index of level. */
LOCAL_FUNCTION ssz_level_leaf
    ENTER   0
    mov     %rdi, %rbx
    mov     %rsi, %r12
    mov     %rdx, %r13
    mov     %rcx, %r14
    mov     %r8, %r15
    cmpq    $SSZ_MODE_PACKED, SSZ_LEVEL_MODE(%r12)
    jne     20f
    /* packed: the 32 bytes at 32 * index, zero padded */
    movq    $0, (%r15)
    movq    $0, 8(%r15)
    movq    $0, 16(%r15)
    movq    $0, 24(%r15)
    mov     SSZ_LEVEL_A(%r12), %rsi
    mov     SSZ_LEVEL_B(%r12), %rax
    mov     (%r13), %rdx
    shl     $5, %rdx
    add     %rdx, %rsi
    sub     %rdx, %rax
    mov     $32, %ecx
    cmp     %rcx, %rax
    cmovb   %rax, %rcx
    mov     %r15, %rdi
    rep movsb
    jmp     90f
20: /* the root of the child value: child level at work + 8, child work after it */
    lea     8(%r14), %rbp
    mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     %r13, %rdx
    mov     %rbp, %rcx
    call    ssz_child_level
    lea     SSZ_LEVEL_SIZE(%rbp), %rdx
    mov     (%r14), %rax
    sub     $(8 + SSZ_LEVEL_SIZE), %rax
    mov     %rax, (%rdx)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r15, %rcx
    call    ssz_level_root
90: xor     %eax, %eax
    LEAVE   0
END_FUNCTION ssz_level_leaf

/* ssz_level_root(ctx, level, work, out): out = hash tree root of the value of level. Locals: range 0, length 16. */
LOCAL_FUNCTION ssz_level_root
    ENTER   48
    mov     %rdi, %rbx
    mov     %rsi, %r12
    mov     %rdx, %r13
    mov     %rcx, %r14
    movq    $0, SSZ_RANGE_LO(%rsp)
    mov     SSZ_LEVEL_DEPTH(%r12), %rax
    mov     %rax, SSZ_RANGE_DEPTH(%rsp)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     %rsp, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    call    ssz_subtree_root
    cmpq    $0, SSZ_LEVEL_MIXIN(%r12)
    je      90f
    /* mix in the length as a 32-byte little-endian number */
    mov     SSZ_LEVEL_LENGTH(%r12), %rax
    mov     %rax, 16(%rsp)
    movq    $0, 24(%rsp)
    movq    $0, 32(%rsp)
    movq    $0, 40(%rsp)
    mov     %rbx, %rdi
    mov     %r14, %rsi
    lea     16(%rsp), %rdx
    mov     %r14, %rcx
    call    ssz_hash_pair
90: xor     %eax, %eax
    LEAVE   48
END_FUNCTION ssz_level_root

/*
 * ssz_subtree_root(ctx, level, range, work, out): out = root of the subtree of
 * depth range.depth over leaves range.lo onward, padded with zero trees.
 * work: size, frontier of depth + 1 nodes, the node h, then the leaf work.
 * rbx ctx, r12 level, r13 work, r14 frontier, r15 h, rbp k or j.
 * Locals: lo 0, depth 8, out 16, m 24, index 32, a node is pending 40, leaf work 48, j 56.
 */
LOCAL_FUNCTION ssz_subtree_root
    ENTER   64
    mov     %rdi, %rbx
    mov     %rsi, %r12
    mov     SSZ_RANGE_LO(%rdx), %rax
    mov     %rax, 0(%rsp)
    mov     SSZ_RANGE_DEPTH(%rdx), %rax
    mov     %rax, 8(%rsp)
    mov     %rcx, %r13
    mov     %r8, 16(%rsp)
    mov     SSZ_LEVEL_COUNT(%r12), %rax
    mov     0(%rsp), %rcx
    cmp     %rax, %rcx
    jb      10f
    /* no data in the range: a zero tree */
    mov     8(%rsp), %rcx
    shl     $5, %rcx
    add     SSZ_CTX_ZERO(%rbx), %rcx
    mov     16(%rsp), %rdx
    COPY32  %rdx, %rcx
    jmp     90f
10: sub     %rcx, %rax                     /* leaves with data, m */
    mov     8(%rsp), %rcx
    cmp     $63, %rcx
    jae     11f
    mov     $1, %edx
    shl     %cl, %rdx
    cmp     %rdx, %rax
    cmova   %rdx, %rax
11: mov     %rax, 24(%rsp)
    lea     8(%r13), %r14                  /* frontier */
    mov     8(%rsp), %rax
    inc     %rax
    shl     $5, %rax
    lea     (%r14,%rax), %r15              /* h */
    lea     32(%r15), %rax                 /* leaf work, only when leaves are child values */
    mov     %rax, 48(%rsp)
    cmpq    $SSZ_MODE_PACKED, SSZ_LEVEL_MODE(%r12)
    je      12f
    mov     %rax, %rdx
    sub     %r13, %rdx
    mov     (%r13), %rcx
    sub     %rdx, %rcx
    mov     %rcx, (%rax)
12: xor     %ebp, %ebp                     /* k */
20: cmp     24(%rsp), %rbp
    jae     40f
    mov     0(%rsp), %rax
    add     %rbp, %rax
    mov     %rax, 32(%rsp)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     32(%rsp), %rdx
    mov     48(%rsp), %rcx
    mov     %r15, %r8
    call    ssz_level_leaf
    movq    $0, 56(%rsp)
21: mov     56(%rsp), %rcx
    mov     %rbp, %rax
    shr     %cl, %rax
    test    $1, %al
    jz      22f
    mov     %rbx, %rdi
    shl     $5, %rcx
    lea     (%r14,%rcx), %rsi
    mov     %r15, %rdx
    mov     %r15, %rcx
    call    ssz_hash_pair
    incq    56(%rsp)
    jmp     21b
22: mov     56(%rsp), %rcx
    shl     $5, %rcx
    lea     (%r14,%rcx), %rdx
    COPY32  %rdx, %r15
    inc     %rbp
    jmp     20b
40: /* close the right edge with zero trees */
    movq    $0, 40(%rsp)
    xor     %ebp, %ebp                     /* j */
41: cmp     8(%rsp), %rbp
    jae     50f
    mov     24(%rsp), %rax
    mov     %ebp, %ecx
    shr     %cl, %rax
    test    $1, %al
    jz      45f
    mov     %rbp, %rsi
    shl     $5, %rsi
    add     %r14, %rsi
    cmpq    $0, 40(%rsp)
    jne     42f
    mov     %rbp, %rdx
    shl     $5, %rdx
    add     SSZ_CTX_ZERO(%rbx), %rdx
    movq    $1, 40(%rsp)
    jmp     43f
42: mov     %r15, %rdx
43: mov     %rbx, %rdi
    mov     %r15, %rcx
    call    ssz_hash_pair
    jmp     46f
45: cmpq    $0, 40(%rsp)
    je      46f
    mov     %rbx, %rdi
    mov     %r15, %rsi
    mov     %rbp, %rdx
    shl     $5, %rdx
    add     SSZ_CTX_ZERO(%rbx), %rdx
    mov     %r15, %rcx
    call    ssz_hash_pair
46: inc     %rbp
    jmp     41b
50: mov     16(%rsp), %rdx
    cmpq    $0, 40(%rsp)
    jne     51f
    mov     8(%rsp), %rcx
    shl     $5, %rcx
    add     %r14, %rcx
    COPY32  %rdx, %rcx
    jmp     90f
51: COPY32  %rdx, %r15
90: xor     %eax, %eax
    LEAVE   64
END_FUNCTION ssz_subtree_root

/* ssz_hash_tree_root(type, value, scratch, root). Locals: slot 0. */
FUNCTION ssz_hash_tree_root
    ENTER   32
    mov     %rsi, %r14
    mov     %rcx, %r15
    mov     %rdx, %rbp
    ROOT_NODE
    mov     (%rbp), %rax
    cmp     SSZ_NODE_SCRATCH(%r12), %rax
    jb      80f
    SETUP_CTX %rdi, %rbp
    TOP_SLOT %r14
    lea     SSZ_SCR_LEVEL(%rbp), %r13
    mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     %rsp, %rdx
    mov     %r13, %rcx
    call    ssz_value_level
    lea     SSZ_SCR_WORK(%rbp), %rdx
    mov     (%rbp), %rax
    sub     $SSZ_SCR_WORK, %rax
    mov     %rax, (%rdx)
    mov     %rbx, %rdi
    mov     %r13, %rsi
    mov     %r15, %rcx
    call    ssz_level_root
    xor     %eax, %eax
    jmp     90f
80: mov     $SSZ_BUFFER_TOO_SMALL, %eax
90: LEAVE   32
END_FUNCTION ssz_hash_tree_root

/* ---------------------------------------------------------------- Generalized indices and proofs */

/*
 * ssz_get_generalized_index(type, path, gindex). r12 nodes, r13 fields,
 * r14 current type, r15 steps, rbx step count, rbp step number, r8 index,
 * r9 1 once the path is inside a basic value. Locals: gindex 0, depth 8.
 */
FUNCTION ssz_get_generalized_index
    ENTER   32
    mov     %rdx, 0(%rsp)
    mov     SSZ_DESC_NODES_OFFSET(%rdi), %r12
    add     %rdi, %r12
    mov     SSZ_DESC_FIELDS_OFFSET(%rdi), %r13
    add     %rdi, %r13
    mov     SSZ_DESC_ROOT(%rdi), %r14
    imul    $SSZ_NODE_STRIDE, %r14, %r14
    add     %r12, %r14
    mov     SSZ_BYTES_OFFSET(%rsi), %r15
    add     %rsi, %r15
    mov     SSZ_BYTES_COUNT(%rsi), %rbx
    xor     %ebp, %ebp
    mov     $1, %r8d
    xor     %r9d, %r9d
    movq    $(0), 16(%rsp)                 /* 1 once the index needs more than 64 bits */
1:  cmp     %rbx, %rbp
    jae     90f
    mov     (%r15,%rbp,8), %r10
    test    %r9, %r9
    jnz     81f
    mov     SSZ_NODE_KIND(%r14), %r11
    cmp     $SSZ_KIND_BOOLEAN, %r11
    jbe     81f
    cmp     $-1, %r10
    jne     10f
    /* the length that a list mixes in: the right child, and the last step */
    cmp     $SSZ_KIND_BYTE_LIST, %r11
    je      2f
    cmp     $SSZ_KIND_BIT_LIST, %r11
    je      2f
    cmp     $SSZ_KIND_LIST, %r11
    jne     82f
2:  lea     1(%rbp), %rax
    cmp     %rbx, %rax
    jne     83f
    mov     %r8, %rax
    shr     $(63), %rax
    or      %rax, 16(%rsp)
    lea     1(%r8,%r8), %r8
    jmp     90f
10: mov     SSZ_NODE_CHUNKS(%r14), %rax
    dec     %rax
    xor     %ecx, %ecx
    test    %rax, %rax
    jz      11f
    bsr     %rax, %rcx
    inc     %rcx
11: mov     %rcx, 8(%rsp)                  /* tree depth */
    mov     SSZ_NODE_LENGTH(%r14), %rax
    cmp     $SSZ_KIND_CONTAINER, %r11
    jne     20f
    cmp     %rax, %r10
    jae     84f
    mov     SSZ_NODE_ELEMENT(%r14), %rax
    add     %r10, %rax
    shl     $5, %rax
    add     %r13, %rax
    mov     SSZ_FIELD_NODE(%rax), %rdi
    imul    $SSZ_NODE_STRIDE, %rdi, %rdi
    add     %r12, %rdi                     /* next type */
    mov     %r10, %rsi                     /* leaf */
    jmp     50f
20: cmp     %rax, %r10
    jae     85f
    cmp     $SSZ_KIND_BYTE_VECTOR, %r11
    je      21f
    cmp     $SSZ_KIND_BYTE_LIST, %r11
    jne     22f
21: mov     %r10, %rsi
    shr     $5, %rsi
    mov     $1, %r9d
    mov     %r14, %rdi
    jmp     50f
22: cmp     $SSZ_KIND_BIT_VECTOR, %r11
    je      23f
    cmp     $SSZ_KIND_BIT_LIST, %r11
    jne     24f
23: mov     %r10, %rsi
    shr     $8, %rsi
    mov     $1, %r9d
    mov     %r14, %rdi
    jmp     50f
24: /* vector or list: basic elements pack into chunks */
    mov     SSZ_NODE_ELEMENT(%r14), %rdi
    imul    $SSZ_NODE_STRIDE, %rdi, %rdi
    add     %r12, %rdi
    mov     $32, %eax
    cmpq    $SSZ_KIND_BOOLEAN, SSZ_NODE_KIND(%rdi)
    ja      25f
    mov     SSZ_NODE_SSZ_SIZE(%rdi), %rax
25: mul     %r10
    shrd    $5, %rdx, %rax
    mov     %rax, %rsi
50: /* a list puts its data on the left of the length */
    cmp     $SSZ_KIND_LIST, %r11
    je      51f
    cmp     $SSZ_KIND_BYTE_LIST, %r11
    je      51f
    cmp     $SSZ_KIND_BIT_LIST, %r11
    jne     52f
51: mov     %r8, %rax
    shr     $(63), %rax
    or      %rax, 16(%rsp)
    shl     $1, %r8
52: mov     8(%rsp), %r11
    test    %r11, %r11
    jz      53f
    mov     $64, %ecx
    sub     %r11d, %ecx
    mov     %r8, %rax
    shr     %cl, %rax
    test    %rax, %rax
    setnz   %al
    movzbl  %al, %eax
    or      %rax, 16(%rsp)
    mov     %r11d, %ecx
    shl     %cl, %r8
    or      %rsi, %r8
53: mov     %rdi, %r14
    inc     %rbp
    jmp     1b
90: /* the 64 bit limit applies only to a path that is otherwise valid */
    cmpq    $(0), 16(%rsp)
    jne     86f
    mov     0(%rsp), %rdx
    mov     %r8, (%rdx)
    xor     %eax, %eax
    jmp     99f
81: mov     $SSZ_NO_PARTS, %eax
    jmp     99f
82: mov     $SSZ_NO_MIXIN, %eax
    jmp     99f
83: mov     $SSZ_NO_PARTS_MIXIN, %eax
    jmp     99f
84: mov     $SSZ_NO_SUCH_FIELD, %eax
    jmp     99f
85: mov     $SSZ_NO_SUCH_POSITION, %eax
    jmp     99f
86: mov     $SSZ_GINDEX_TOO_LARGE, %eax
99: LEAVE   32
END_FUNCTION ssz_get_generalized_index

/*
 * ssz_build_proof(type, value, gindex, scratch, branch). Two passes over the
 * path: the first only checks it, the second writes the branch.
 * rbx ctx, r12 level, r13 work, r14 bits used, r15 gindex, rbp branch length D.
 * Locals: slot 0, range 32, index 48, pass 56, q 64, step 72, bits left at
 * this level 80, tree depth 88, value 96, branch 104, scratch 112, root 120.
 */
FUNCTION ssz_build_proof
    ENTER   128
    mov     %rsi, 96(%rsp)
    mov     %r8, 104(%rsp)
    mov     %rcx, 112(%rsp)
    mov     (%rdx), %r15
    ROOT_NODE
    mov     %r12, 120(%rsp)
    test    %r15, %r15
    jz      82f
    cmp     $(1), %r15
    je      81f
    mov     (%rcx), %rax
    cmp     SSZ_NODE_SCRATCH(%r12), %rax
    jb      80f
    SETUP_CTX %rdi, %rcx
    bsr     %r15, %rbp
    movq    $0, 56(%rsp)
30: /* one pass from the root */
    mov     96(%rsp), %rax
    mov     %rax, SSZ_SLOT_P(%rsp)
    mov     %rax, SSZ_SLOT_B(%rsp)
    mov     120(%rsp), %rsi
    xor     %eax, %eax
    cmpq    $0, SSZ_NODE_SSZ_SIZE(%rsi)
    sete    %al
    shl     $1, %eax
    mov     %rax, SSZ_SLOT_FORM(%rsp)
    mov     112(%rsp), %rax
    lea     SSZ_SCR_LEVEL(%rax), %r12
    mov     %rbx, %rdi
    mov     %rsp, %rdx
    mov     %r12, %rcx
    call    ssz_value_level
    mov     112(%rsp), %rax
    lea     SSZ_SCR_WORK(%rax), %r13
    mov     (%rax), %rcx
    sub     $SSZ_SCR_WORK, %rcx
    mov     %rcx, (%r13)
    xor     %r14d, %r14d
31: mov     %rbp, %rcx
    sub     %r14, %rcx                     /* bits left */
    jz      70f
    cmpq    $0, SSZ_LEVEL_MIXIN(%r12)
    je      35f
    /* the length mixin level */
    dec     %rcx
    mov     %r15, %rax
    shr     %cl, %rax
    inc     %r14
    mov     %rbp, %rdx
    sub     %r14, %rdx
    shl     $5, %rdx
    add     104(%rsp), %rdx
    add     $SSZ_BYTES_FIXED, %rdx         /* branch node for this depth */
    test    $1, %al
    jnz     33f
    /* left: the data tree; its sibling is the length */
    cmpq    $0, 56(%rsp)
    je      35f
    mov     SSZ_LEVEL_LENGTH(%r12), %rax
    mov     %rax, (%rdx)
    movq    $0, 8(%rdx)
    movq    $0, 16(%rdx)
    movq    $0, 24(%rdx)
    jmp     35f
33: /* right: the length itself, which must end the path; its sibling is the data root */
    test    %rcx, %rcx
    jnz     83f
    cmpq    $0, 56(%rsp)
    je      70f
    movq    $0, (32 + SSZ_RANGE_LO)(%rsp)
    mov     SSZ_LEVEL_DEPTH(%r12), %rax
    mov     %rax, (32 + SSZ_RANGE_DEPTH)(%rsp)
    mov     %rdx, %r8
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     32(%rsp), %rdx
    mov     %r13, %rcx
    call    ssz_subtree_root
    jmp     70f
35: /* down this level's tree */
    mov     %rbp, %rax
    sub     %r14, %rax
    mov     %rax, 80(%rsp)
    mov     SSZ_LEVEL_DEPTH(%r12), %rax
    mov     %rax, 88(%rsp)
    movq    $0, 64(%rsp)
    movq    $0, 72(%rsp)
36: mov     72(%rsp), %rax
    cmp     80(%rsp), %rax
    jae     38f
    cmp     88(%rsp), %rax
    jae     38f
    inc     %rax
    mov     %rax, 72(%rsp)
    mov     80(%rsp), %rcx
    sub     %rax, %rcx
    mov     %r15, %rdx
    shr     %cl, %rdx
    and     $1, %edx
    mov     64(%rsp), %rax
    lea     (%rdx,%rax,2), %rax
    mov     %rax, 64(%rsp)
    inc     %r14
    cmpq    $0, 56(%rsp)
    je      36b
    /* the sibling q ^ 1 covers 2^(depth - step) leaves */
    xor     $1, %rax
    mov     88(%rsp), %rcx
    sub     72(%rsp), %rcx
    shl     %cl, %rax
    mov     %rax, (32 + SSZ_RANGE_LO)(%rsp)
    mov     %rcx, (32 + SSZ_RANGE_DEPTH)(%rsp)
    mov     %rbp, %r8
    sub     %r14, %r8
    shl     $5, %r8
    add     104(%rsp), %r8
    add     $SSZ_BYTES_FIXED, %r8
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     32(%rsp), %rdx
    mov     %r13, %rcx
    call    ssz_subtree_root
    jmp     36b
38: mov     80(%rsp), %rax
    cmp     88(%rsp), %rax
    jbe     70f
    /* the path goes on into leaf q */
    cmpq    $SSZ_MODE_PACKED, SSZ_LEVEL_MODE(%r12)
    je      84f
    mov     64(%rsp), %rax
    cmp     SSZ_LEVEL_COUNT(%r12), %rax
    jae     85f
    mov     %rax, 48(%rsp)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     48(%rsp), %rdx
    lea     8(%r13), %rcx
    call    ssz_child_level
    lea     8(%r13), %r12
    lea     SSZ_LEVEL_SIZE(%r12), %rax
    mov     (%r13), %rcx
    sub     $(8 + SSZ_LEVEL_SIZE), %rcx
    mov     %rcx, (%rax)
    mov     %rax, %r13
    jmp     31b
70: /* end of a pass */
    cmpq    $0, 56(%rsp)
    jne     79f
    mov     104(%rsp), %rdx
    mov     %rbp, %rax
    shl     $5, %rax
    add     $SSZ_BYTES_FIXED, %rax
    cmp     SSZ_BYTES_SIZE(%rdx), %rax
    ja      80f
    movq    $SSZ_BYTES_FIXED, SSZ_BYTES_OFFSET(%rdx)
    mov     %rbp, SSZ_BYTES_COUNT(%rdx)
    movq    $1, 56(%rsp)
    jmp     30b
79: xor     %eax, %eax
    jmp     99f
80: mov     $SSZ_BUFFER_TOO_SMALL, %eax
    jmp     99f
81: mov     $SSZ_ROOT_HAS_NO_BRANCH, %eax
    jmp     99f
82: mov     $SSZ_NOT_A_GINDEX, %eax
    jmp     99f
83: mov     $SSZ_PATH_INTO_MIXIN, %eax
    jmp     99f
84: mov     $SSZ_PATH_INTO_PACKED, %eax
    jmp     99f
85: mov     $SSZ_PATH_INTO_GAP, %eax
99: LEAVE   128
END_FUNCTION ssz_build_proof

/*
 * ssz_verify_merkle_proof(leaf, branch, gindex, root, valid). Rebuilds the root
 * from leaf and branch, as v0.1.0 calculate_merkle_root does, and compares it.
 * rbx next branch node, rbp node count, r12 gindex, r13 root, r14 valid,
 * r15 level. Locals: the SHA-256 input ByteList at rsp + 0 (88 bytes), the
 * node at rsp + 88.
 */
FUNCTION ssz_verify_merkle_proof
    ENTER   128
    mov     (%rdx), %r12
    test    %r12, %r12
    jz      81f
    /* depth = the bit length of gindex - 1 */
    bsr     %r12, %rax
    test    %rax, %rax
    jz      82f
    mov     SSZ_BYTES_COUNT(%rsi), %rbp
    cmp     %rax, %rbp
    jne     83f
    mov     SSZ_BYTES_OFFSET(%rsi), %rbx
    add     %rsi, %rbx
    mov     %rcx, %r13
    mov     %r8, %r14
    lea     88(%rsp), %rax
    COPY32  %rax, %rdi
    movq    $(88), SSZ_BYTES_SIZE(%rsp)
    movq    $(SSZ_BYTES_FIXED), SSZ_BYTES_OFFSET(%rsp)
    movq    $(64), SSZ_BYTES_COUNT(%rsp)
    xor     %r15d, %r15d
1:  cmp     %rbp, %r15
    jae     5f
    lea     SSZ_BYTES_FIXED(%rsp), %rax
    lea     (SSZ_BYTES_FIXED + 32)(%rsp), %rdx
    lea     88(%rsp), %rsi
    bt      %r15, %r12
    jnc     2f
    /* bit set: the branch node is on the left */
    COPY32  %rax, %rbx
    COPY32  %rdx, %rsi
    jmp     3f
2:  COPY32  %rax, %rsi
    COPY32  %rdx, %rbx
3:  mov     %rsp, %rdi
    lea     88(%rsp), %rsi
    CALL_EXTERN crypto_sha256
    add     $(32), %rbx
    inc     %r15
    jmp     1b
5:  /* valid = 1 when the node equals root */
    mov     88(%rsp), %rax
    xor     (%r13), %rax
    mov     96(%rsp), %rcx
    xor     8(%r13), %rcx
    or      %rcx, %rax
    mov     104(%rsp), %rcx
    xor     16(%r13), %rcx
    or      %rcx, %rax
    mov     112(%rsp), %rcx
    xor     24(%r13), %rcx
    or      %rcx, %rax
    setz    %al
    movzbl  %al, %eax
    mov     %rax, (%r14)
    xor     %eax, %eax
    jmp     90f
81: mov     $(SSZ_NOT_A_GINDEX), %eax
    jmp     90f
82: mov     $(SSZ_ROOT_HAS_NO_BRANCH), %eax
    jmp     90f
83: mov     $(SSZ_BRANCH_LENGTH), %eax
90: LEAVE   128
END_FUNCTION ssz_verify_merkle_proof

/* ---------------------------------------------------------------- Constants */

    .p2align 3
300:
.include "ssz_zero_hashes.inc"
