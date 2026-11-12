# Types

Spec: [ssz-specs@v0.1.0](https://github.com/ethereum/ssz-specs/tree/7bce07ff7d51b1a3c66ff4e2bd3233ac248ede70/src/ssz): `uint.py`, `boolean.py`, `byte_arrays.py`, `bitfields.py`, `collections.py` and `container.py`.

asm-ssz supports only the SSZ kinds that consensus-specs uses on the live mainnet forks, phase0 to fulu: `Uint8`, `Uint32`, `Uint64`, `Uint256`, `Boolean`, `Byte`, `ByteVector`, `ByteList`, `BitVector`, `BitList`, `Vector`, `List` and `Container`. `Byte` is `Uint8`. The layouts below are layout revision 1.

### `TypeDescriptor`

A `TypeDescriptor` describes one SSZ type and every type inside it. A build-time tool, the descriptor builder, writes it. The builder also computes where each field sits in memory, so the assembly only reads these numbers. Every function requires a well-formed descriptor and does not validate it.

- `size` This unsigned 8-byte number gives the total buffer size in bytes.
- `nodes` This part reference gives the offset and the count of the node records.
- `fields` This part reference gives the offset and the count of the field records.
- `root` This unsigned 8-byte number gives the index of the node for the described type.

The fixed fields use 48 bytes. The node part comes first and the field part follows it. Both start at multiples of 8.

### `TypeNode`

A node record uses 72 bytes. Every field is an unsigned 8-byte number.

- `kind` This number gives the SSZ kind: 1 uint, 2 boolean, 3 byte vector, 4 byte list, 5 bit vector, 6 bit list, 7 vector, 8 list, 9 container.
- `length` This number gives the byte width of a uint, the length N of a vector, the limit of a list, or the field count of a container.
- `element` This number gives the element node of a vector or a list, or the first field record of a container.
- `ssz_size` This number gives the SSZ encoding size of a fixed-size type, and it is 0 for a variable-size type.
- `mem_size` This number gives the bytes that the type takes in place inside another value, and it is 16 for a variable-size type.
- `mem_align` This number gives the alignment that the type takes in place inside another value.
- `value_fixed` This number gives the offset where the parts start in a standalone or nested value of this type.
- `chunks` This number gives the Merkle leaf count at the type's own level, which is `chunk_count` of the spec.
- `scratch` This number gives the scratch bytes that every function needs for a value of this type.

A descriptor is well formed when every node index and field index is in range, every nested type has a higher node index than the type that holds it, and every number above follows the layout rules below. The rule that fills `scratch` is recorded with the v1 assembly.

### `TypeField`

A field record uses 32 bytes. Every field is an unsigned 8-byte number.

- `node` This number gives the node of the field type.
- `mem_offset` This number gives the offset of the field from the start of the container value.
- `ssz_offset` This number gives the offset of the field, or of its 4-byte offset, in the SSZ fixed part.
- `flags` This number holds bit 0, which is 1 when the field type is variable-size.

## Value layout

Every value that asm-ssz reads or writes follows ARCHITECTURE.md section 6. All numbers are little-endian.

| SSZ type | Fixed size | In place |
|---|---|---|
| `Uint8`, `Uint32`, `Uint64` | yes | 1, 4 or 8 bytes, aligned to their width |
| `Uint256` | yes | 32 bytes, aligned to 8 |
| `Boolean` | yes | 1 byte that holds 0 or 1 |
| `ByteVector[N]` | yes | N bytes, aligned to 1 |
| `BitVector[N]` | yes | ceil(N / 8) bytes in SSZ bit order, aligned to 1; the padding bits are 0 |
| `Vector[T, N]`, T fixed-size | yes | N entries of T, with a stride of T's `mem_size` |
| `Container`, all fields fixed-size | yes | the fields in spec order, each at its own alignment; the size is rounded up to the largest field alignment |
| `ByteList[N]` | no | a part reference; the part holds `count` bytes |
| `BitList[N]` | no | a part reference; `count` is the number of bits; the part holds ceil(count / 8) bytes in SSZ bit order, with no delimiter bit |
| `List[T, N]`, T fixed-size | no | a part reference; the part holds `count` entries with a stride of T's `mem_size` |
| `List[T, N]` or `Vector[T, N]`, T variable-size | no | a part reference; the part holds `count` nested values of T one after the other, each starting at a multiple of 8 |
| `Container` with a variable-size field | no | a part reference with `count` 1; the part holds one nested value |

A part reference uses 16 bytes, aligned to 8: the offset of the part from the start of the value that holds it, then the entry count.

A value whose type is variable-size starts with its total size as an unsigned 8-byte number. A container value then holds its fields at their `mem_offset`. A list, byte list, bit list or variable-size vector value is a standalone list: the size, then one part reference at byte 8. The parts follow the fixed fields, start at `value_fixed`, and keep field order. Each part ends where the next part starts, or at the end of the value. A nested value inside a part is laid out by the same rules, with offsets measured from its own start, and its size says where the next one starts.

A value whose type is fixed-size has no size header. It is the in-place bytes above.

A value is well formed when it follows these rules, every count is at most the type limit, every `Boolean` is 0 or 1, and every unused padding bit of a bit field is 0.
