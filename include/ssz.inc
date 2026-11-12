/*
 * asm-ssz shared definitions, in assembler syntax.
 * Every core file includes this file with .include.
 * Layouts are described in docs/reference/serialization.md.
 * Requirements for each function are in docs/reference/.
 */

/* ---------------------------------------------------------------- Status codes */

/* ARCHITECTURE.md section 6. */
.set SSZ_OK, 0
.set SSZ_BUFFER_TOO_SMALL, 1

/* Decode refusals. Each one is the ssz-specs v0.1.0 ValueFault of the same name. */
.set SSZ_SCOPE, 2
.set SSZ_SCOPE_TOO_SMALL, 3
.set SSZ_SCOPE_UNDIVIDED, 4
.set SSZ_TRUNCATED, 5
.set SSZ_TRAILING_BYTES, 6
.set SSZ_FIRST_OFFSET, 7
.set SSZ_OFFSET_UNORDERED, 8
.set SSZ_OFFSET_PAST_SCOPE, 9
.set SSZ_OFFSET_UNALIGNED, 10
.set SSZ_OFFSET_BELOW_TABLE, 11
.set SSZ_EMPTY_ENCODING, 12
.set SSZ_NO_DELIMITER, 13
.set SSZ_TRAILING_ZEROS, 14
.set SSZ_PADDING_BITS, 15
.set SSZ_NOT_A_BIT, 16
.set SSZ_LIMIT, 17

/* Path refusals. Codes 18 to 20 are v0.1.0 TypeFault names, 21 and 22 ValueFault names. */
.set SSZ_NO_PARTS, 18
.set SSZ_NO_MIXIN, 19
.set SSZ_NO_PARTS_MIXIN, 20
.set SSZ_NO_SUCH_FIELD, 21
.set SSZ_NO_SUCH_POSITION, 22
.set SSZ_GINDEX_TOO_LARGE, 23      /* asm-ssz: the index does not fit in 64 bits */

/* Proof refusals. Each one is the v0.1.0 ValueFault of the same name. */
.set SSZ_NOT_A_GINDEX, 24
.set SSZ_PATH_INTO_MIXIN, 25
.set SSZ_PATH_INTO_PACKED, 26
.set SSZ_PATH_INTO_GAP, 27

/* ---------------------------------------------------------------- Type descriptor */

/* Descriptor value: fixed fields. */
.set SSZ_DESC_SIZE, 0              /* total buffer size in bytes */
.set SSZ_DESC_NODES_OFFSET, 8      /* offset of the node part */
.set SSZ_DESC_NODES_COUNT, 16      /* number of nodes */
.set SSZ_DESC_FIELDS_OFFSET, 24    /* offset of the field part */
.set SSZ_DESC_FIELDS_COUNT, 32     /* number of field records */
.set SSZ_DESC_ROOT, 40             /* index of the node for the described type */
.set SSZ_DESC_FIXED, 48            /* end of the fixed fields */

/* Node record, 72 bytes. */
.set SSZ_NODE_KIND, 0
.set SSZ_NODE_LENGTH, 8            /* uint: byte width; vectors: N; lists: limit; container: field count */
.set SSZ_NODE_ELEMENT, 16          /* vector, list: element node; container: first field record */
.set SSZ_NODE_SSZ_SIZE, 24         /* SSZ encoding size of a fixed-size type, else 0 */
.set SSZ_NODE_MEM_SIZE, 32         /* bytes the type takes in place (16 for a variable-size type) */
.set SSZ_NODE_MEM_ALIGN, 40        /* alignment the type takes in place */
.set SSZ_NODE_VALUE_FIXED, 48      /* in a value of this type, where the parts start */
.set SSZ_NODE_CHUNKS, 56           /* Merkle leaf count at this type's own level */
.set SSZ_NODE_SCRATCH, 64          /* scratch bytes that every function needs for this type */
.set SSZ_NODE_STRIDE, 72

/* Node kinds. */
.set SSZ_KIND_UINT, 1
.set SSZ_KIND_BOOLEAN, 2
.set SSZ_KIND_BYTE_VECTOR, 3
.set SSZ_KIND_BYTE_LIST, 4
.set SSZ_KIND_BIT_VECTOR, 5
.set SSZ_KIND_BIT_LIST, 6
.set SSZ_KIND_VECTOR, 7
.set SSZ_KIND_LIST, 8
.set SSZ_KIND_CONTAINER, 9

/* Field record, 32 bytes. */
.set SSZ_FIELD_NODE, 0             /* node of the field type */
.set SSZ_FIELD_MEM_OFFSET, 8       /* offset of the field in the container value */
.set SSZ_FIELD_SSZ_OFFSET, 16      /* offset of the field, or of its 4-byte offset, in the SSZ fixed part */
.set SSZ_FIELD_FLAGS, 24           /* bit 0: the field type is variable-size */
.set SSZ_FIELD_STRIDE, 32
.set SSZ_FIELD_VARIABLE, 1

/* ---------------------------------------------------------------- Values */

/* A value with parts, and a part reference (ARCHITECTURE.md section 6). */
.set SSZ_VALUE_SIZE, 0             /* total buffer size, first 8 bytes of a value with parts */
.set SSZ_PART_OFFSET, 0            /* in a part reference: offset of the part from the value start */
.set SSZ_PART_COUNT, 8             /* in a part reference: entry count */
.set SSZ_PART_REF_SIZE, 16

/* Byte list value: a standalone list with one field. */
.set SSZ_BYTES_SIZE, 0
.set SSZ_BYTES_OFFSET, 8
.set SSZ_BYTES_COUNT, 16
.set SSZ_BYTES_FIXED, 24

/* Path step that names the length mixed into a list root ("__len__"). */
.set SSZ_STEP_LENGTH, 0xffffffffffffffff

/* SSZ constants. */
.set SSZ_BYTES_PER_CHUNK, 32
.set SSZ_BYTES_PER_LENGTH_OFFSET, 4

/*
 * Functions, roles and allowed calls (ARCHITECTURE.md sections 4 and 5).
 *
 * | Function                  | Role | Arguments, then outputs                  | Requirements      |
 * |---------------------------|------|------------------------------------------|-------------------|
 * | ssz_serialize             | L2   | type, value, scratch; serialized         | serialization.md  |
 * | ssz_serialize_size        | L2   | type, value, scratch; size               | serialization.md  |
 * | ssz_deserialize           | L2   | type, serialized, scratch; value         | serialization.md  |
 * | ssz_deserialize_size      | L2   | type, serialized, scratch; size          | serialization.md  |
 * | ssz_hash_tree_root        | L2   | type, value, scratch; root               | merkleization.md  |
 * | ssz_get_generalized_index | L2   | type, path; gindex                       | proofs.md         |
 * | ssz_build_proof           | L2   | type, value, gindex, scratch; branch     | proofs.md         |
 *
 * Allowed calls out of this repo: crypto_sha256 from asm-crypto (README, Dependencies),
 * from ssz_hash_tree_root and ssz_build_proof only.
 */
